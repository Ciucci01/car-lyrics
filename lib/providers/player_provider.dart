import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/lyrics.dart';
import '../models/playback_state.dart';
import '../models/spotify_tokens.dart';
import '../screens/spotify_auth_webview.dart';
import '../services/auth_service.dart';
import '../services/lyrics_service.dart';
import '../services/spotify_service.dart';
import '../services/storage_service.dart';
import '../utils/app_log.dart';

enum ConnectionStatus { initializing, disconnected, connecting, connected }

enum LyricsStatus { idle, loading, ready, unavailable, failed }

class PlayerProvider with ChangeNotifier, WidgetsBindingObserver {
  static const _pollInterval = Duration(seconds: 5);

  static const _tickInterval = Duration(milliseconds: 100);

  static const _commandSettleDelay = Duration(milliseconds: 400);

  static const redirectUri = 'car-play://callback';
  static const _scopes = [
    'user-read-playback-state',
    'user-modify-playback-state',
    'user-read-currently-playing',
  ];

  final TokenStorage _storage;
  final SpotifyAuth _auth;
  final SpotifyService _spotify;
  final LyricsService _lyricsService;
  final http.Client _httpClient;

  ConnectionStatus _status = ConnectionStatus.initializing;
  LyricsStatus _lyricsStatus = LyricsStatus.idle;
  PlaybackState? _playback;
  Lyrics? _lyrics;
  String? _authError;
  int _currentLineIndex = -1;

  Timer? _pollTimer;
  Timer? _tickTimer;
  Future<void>? _inFlightSync;

  /// Fino a questo istante non si interroga Spotify: valorizzato da un 429.
  DateTime? _pollBlockedUntil;
  bool _disposed = false;

  int _anchorProgressMs = 0;
  DateTime? _anchorAt;
  bool _anchorIsPlaying = false;

  int _lyricsRequestId = 0;

  factory PlayerProvider({
    TokenStorage? storage,
    SpotifyAuth? auth,
    SpotifyService? spotify,
    LyricsService? lyricsService,
  }) {
    // Un solo client per tutta l'app: tre client sono tre pool di
    // connessioni separati per lo stesso identico traffico.
    final httpClient = http.Client();
    final resolvedStorage = storage ?? TokenStorage();
    final resolvedAuth = auth ?? SpotifyAuth(client: httpClient);
    return PlayerProvider._(
      storage: resolvedStorage,
      auth: resolvedAuth,
      spotify:
          spotify ??
          SpotifyService(
            auth: resolvedAuth,
            storage: resolvedStorage,
            client: httpClient,
          ),
      lyricsService: lyricsService ?? LyricsService(client: httpClient),
      httpClient: httpClient,
    );
  }

  PlayerProvider._({
    required TokenStorage storage,
    required SpotifyAuth auth,
    required SpotifyService spotify,
    required LyricsService lyricsService,
    required http.Client httpClient,
  }) : _storage = storage,
       _auth = auth,
       _spotify = spotify,
       _lyricsService = lyricsService,
       _httpClient = httpClient {
    _spotify.onAuthLost = _handleAuthLost;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreSession());
  }

  ConnectionStatus get status => _status;
  LyricsStatus get lyricsStatus => _lyricsStatus;
  PlaybackState? get playback => _playback;
  Lyrics? get lyrics => _lyrics;
  String? get authError => _authError;
  int get currentLineIndex => _currentLineIndex;

  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isBusy =>
      _status == ConnectionStatus.initializing ||
      _status == ConnectionStatus.connecting;
  bool get isPlaying => _playback?.isPlaying ?? false;

  /// Posizione stimata: l'ultima letta dal server piu' il tempo trascorso da
  /// allora. E' cio' che permette di evidenziare la riga giusta senza dover
  /// interrogare Spotify dieci volte al secondo.
  int get estimatedProgressMs {
    final anchorAt = _anchorAt;
    if (anchorAt == null) return 0;

    var value = _anchorProgressMs;
    if (_anchorIsPlaying) {
      value += DateTime.now().difference(anchorAt).inMilliseconds;
    }

    final duration = _playback?.durationMs ?? 0;
    if (duration > 0 && value > duration) value = duration;
    return value < 0 ? 0 : value;
  }

  Future<void> _restoreSession() async {
    try {
      final tokens = await _storage.load();
      if (tokens != null) {
        await _adoptTokens(tokens, persist: false);
        return;
      }
    } catch (error, stackTrace) {
      logError('Ripristino sessione fallito', error, stackTrace);
    }
    _status = ConnectionStatus.disconnected;
    notifyListeners();
  }

  Future<void> connect(BuildContext context) async {
    if (!_auth.isConfigured) {
      _authError = 'SPOTIFY_CLIENT_ID is missing from .env';
      notifyListeners();
      return;
    }

    // Il navigator va risolto adesso: la notifica qui sotto smonta il widget
    // da cui arriva questo context, e con esso la sua validita'.
    final navigator = Navigator.of(context);

    _status = ConnectionStatus.connecting;
    _authError = null;
    notifyListeners();

    try {
      final verifier = SpotifyAuth.createCodeVerifier();
      final expectedState = SpotifyAuth.createState();
      final result = await SpotifyAuthWebView.show(
        navigator,
        authorizeUrl: _auth.authorizeUrl(
          redirectUri: redirectUri,
          scopes: _scopes,
          codeChallenge: SpotifyAuth.codeChallengeFor(verifier),
          state: expectedState,
        ),
        redirectUri: redirectUri,
      );

      if (result == null) {
        // Login annullato: nessun errore da mostrare.
        _status = ConnectionStatus.disconnected;
        notifyListeners();
        return;
      }
      if (result.error != null || result.code == null) {
        _failConnect('Login failed: ${result.error ?? 'no code returned'}');
        return;
      }
      if (result.state != expectedState) {
        _failConnect('Invalid login response, please try again');
        return;
      }

      final tokens = await _auth.exchangeCode(
        code: result.code!,
        codeVerifier: verifier,
        redirectUri: redirectUri,
      );
      if (tokens == null) {
        _failConnect('Could not complete the login, please try again');
        return;
      }

      await _adoptTokens(tokens);
    } catch (error, stackTrace) {
      logError('Login Spotify fallito', error, stackTrace);
      _failConnect('Login failed, please try again');
    }
  }

  void _failConnect(String message) {
    _authError = message;
    _status = ConnectionStatus.disconnected;
    notifyListeners();
  }

  Future<void> _adoptTokens(SpotifyTokens tokens, {bool persist = true}) async {
    _spotify.adoptTokens(tokens);
    if (persist) await _storage.save(tokens);

    _status = ConnectionStatus.connected;
    _authError = null;
    notifyListeners();

    _startPolling();
    await _syncPlayback();
  }

  void _handleAuthLost() {
    _stopPolling();
    _resetPlaybackState();
    _status = ConnectionStatus.disconnected;
    _authError = 'Session expired, please sign in again';
    notifyListeners();
  }

  Future<void> disconnect() async {
    _stopPolling();
    _spotify.clearTokens();
    await _storage.clear();
    await SpotifyAuthWebView.clearSession();
    _resetPlaybackState();
    _status = ConnectionStatus.disconnected;
    _authError = null;
    notifyListeners();
  }

  void _resetPlaybackState() {
    // Invalida anche le richieste di lyrics in volo: cio' per cui erano state
    // fatte non esiste piu'.
    _lyricsRequestId++;
    _playback = null;
    _lyrics = null;
    _lyricsStatus = LyricsStatus.idle;
    _currentLineIndex = -1;
    _anchorAt = null;
    _anchorProgressMs = 0;
    _anchorIsPlaying = false;
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(_pollInterval, (_) => _syncPlayback());
    _tickTimer ??= Timer.periodic(_tickInterval, (_) => _tick());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  /// [force] serve ai comandi dell'utente: se un poll periodico e' gia' in
  /// volo, il refresh che segue uno skip o un play/pause non va perso, o la
  /// schermata resterebbe ferma fino al poll successivo.
  Future<void> _syncPlayback({bool force = false}) async {
    if (!_spotify.hasTokens) return;

    // Il backoff vale anche per i comandi dell'utente: un 429 ignorato
    // allunga la finestra di blocco invece di accorciarla.
    final blockedUntil = _pollBlockedUntil;
    if (blockedUntil != null) {
      if (DateTime.now().isBefore(blockedUntil)) return;
      _pollBlockedUntil = null;
    }

    final inFlight = _inFlightSync;
    if (inFlight != null) {
      // Su rete lenta un poll puo' durare piu' dell'intervallo: le richieste
      // non devono accavallarsi.
      if (!force) return;
      await inFlight;
    }

    final sync = _fetchPlayback();
    _inFlightSync = sync;
    try {
      await sync;
    } finally {
      if (identical(_inFlightSync, sync)) _inFlightSync = null;
    }
  }

  Future<void> _fetchPlayback() async {
    try {
      _applyPlayback(await _spotify.currentPlayback());
    } catch (error, stackTrace) {
      // Stato ignoto: si tiene quello che stiamo gia' mostrando, invece di
      // azzerare la schermata per un errore passeggero.
      _noteFailure('Poll della riproduzione fallito', error, stackTrace);
    }
  }

  /// Registra un errore e, se Spotify ha imposto un'attesa, la rispetta.
  void _noteFailure(String what, Object error, StackTrace stackTrace) {
    if (error is SpotifyApiException && error.retryAfter != null) {
      _pollBlockedUntil = DateTime.now().add(error.retryAfter!);
      logInfo('Polling sospeso per ${error.retryAfter!.inSeconds}s');
    }
    logError(what, error, stackTrace);
  }

  /// In background non c'e' niente da disegnare: il polling si ferma e
  /// l'ancora viene congelata, cosi' al rientro il tick non stima una
  /// posizione calcolata su minuti di assenza.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!isConnected) return;
      logInfo('App in primo piano: polling riavviato');
      _startPolling();
      unawaited(_syncPlayback(force: true));
      return;
    }
    // inactive e' transitorio (notifiche, app switcher): non vale fermarsi.
    if (state == AppLifecycleState.inactive) return;
    if (_pollTimer == null) return;
    logInfo('App in background: polling sospeso');
    _setAnchor(estimatedProgressMs, false);
    _stopPolling();
  }

  void _applyPlayback(PlaybackState? playback) {
    final previous = _playback;
    _playback = playback;

    if (playback == null) {
      if (previous != null) {
        _resetPlaybackState();
        notifyListeners();
      }
      return;
    }

    _setAnchor(playback.progressMs, playback.isPlaying);

    if (previous?.trackId != playback.trackId) {
      unawaited(_loadLyrics(playback.trackId));
      notifyListeners();
      return;
    }

    // progress_ms cambia ad ogni poll: notifichiamo solo se e' cambiato
    // qualcosa di visibile, altrimenti ridisegneremmo la schermata a vuoto.
    if (!playback.sameDisplayAs(previous)) notifyListeners();
    _updateCurrentLine(estimatedProgressMs);
  }

  void _setAnchor(int progressMs, bool isPlaying) {
    _anchorProgressMs = progressMs;
    _anchorIsPlaying = isPlaying;
    _anchorAt = DateTime.now();
  }

  void _tick() {
    if (!_anchorIsPlaying) return;
    _updateCurrentLine(estimatedProgressMs);
  }

  /// Indice dell'ultima riga gia' iniziata, oppure -1 prima della prima riga.
  void _updateCurrentLine(int positionMs) {
    final lyrics = _lyrics;
    // In un testo non sincronizzato ogni riga parte da zero: cercarci dentro
    // la riga corrente inchioderebbe l'evidenziazione sull'ultima, per tutta
    // la canzone. Meglio mostrarlo senza seguirlo.
    if (lyrics == null || !lyrics.isSynced) return;

    final lines = lyrics.lines;
    if (lines.isEmpty) return;

    var index = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startTime > positionMs) break;
      index = i;
    }

    if (index != _currentLineIndex) {
      _currentLineIndex = index;
      notifyListeners();
    }
  }

  Future<void> _loadLyrics(String trackId) async {
    final requestId = ++_lyricsRequestId;

    _lyrics = null;
    _currentLineIndex = -1;
    _lyricsStatus = LyricsStatus.loading;
    notifyListeners();

    try {
      final lyrics = await _lyricsService.getLyrics(trackId);
      // Risposta in ritardo di una traccia gia' cambiata: va ignorata, o
      // mostreremmo il testo della canzone precedente.
      if (requestId != _lyricsRequestId) return;

      if (lyrics.isUsable) {
        _lyrics = lyrics;
        _lyricsStatus = LyricsStatus.ready;
        _updateCurrentLine(estimatedProgressMs);
      } else {
        _lyricsStatus = LyricsStatus.unavailable;
      }
    } catch (error, stackTrace) {
      if (requestId != _lyricsRequestId) return;
      logError('Caricamento lyrics fallito', error, stackTrace);
      _lyricsStatus = LyricsStatus.failed;
    }

    notifyListeners();
  }

  Future<void> retryLyrics() async {
    final trackId = _playback?.trackId;
    if (trackId != null) await _loadLyrics(trackId);
  }

  Future<void> togglePlayPause() async {
    final playback = _playback;
    if (playback == null) return;

    final shouldPlay = !playback.isPlaying;
    // Aggiorniamo subito l'ancora con la posizione stimata finora, cosi' il
    // pulsante risponde immediatamente e il testo non salta.
    final progress = estimatedProgressMs;
    _playback = playback.copyWith(isPlaying: shouldPlay, progressMs: progress);
    _setAnchor(progress, shouldPlay);
    notifyListeners();

    await _runCommand(
      'Comando play/pause fallito',
      shouldPlay ? _spotify.resume : _spotify.pause,
    );
  }

  Future<void> skipToNext() =>
      _runCommand('Cambio traccia fallito', _spotify.next);

  Future<void> skipToPrevious() =>
      _runCommand('Cambio traccia fallito', _spotify.previous);

  /// Ogni comando passa di qui, perche' la Web API resta eventually
  /// consistent per qualche centinaio di millisecondi: risincronizzare subito
  /// rileggerebbe lo stato precedente e ribalterebbe l'aggiornamento
  /// ottimistico appena mostrato all'utente.
  Future<void> _runCommand(String what, Future<void> Function() command) async {
    try {
      await command();
    } catch (error, stackTrace) {
      _noteFailure(what, error, stackTrace);
    }
    // La rilettura serve anche dopo un errore: se il comando non e' passato,
    // l'aggiornamento ottimistico va corretto.
    await Future.delayed(_commandSettleDelay);
    await _syncPlayback(force: true);
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _spotify.onAuthLost = null;
    _stopPolling();
    _httpClient.close();
    super.dispose();
  }
}
