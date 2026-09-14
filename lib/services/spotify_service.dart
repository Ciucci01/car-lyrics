import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/playback_state.dart';
import '../models/spotify_tokens.dart';
import '../utils/app_log.dart';
import 'auth_service.dart';
import 'storage_service.dart';

/// Errore per cui lo stato della riproduzione resta *ignoto*.
///
/// Va tenuto distinto dal 204 "non sta suonando niente": il primo non deve
/// toccare quello che stiamo gia' mostrando, il secondo si'.
class SpotifyApiException implements Exception {
  final String message;
  final int? statusCode;

  /// Valorizzato solo per il 429: quanto Spotify chiede di aspettare prima di
  /// ripresentarsi. Chi cattura deve rispettarlo, non solo registrarlo.
  final Duration? retryAfter;

  const SpotifyApiException(this.message, [this.statusCode, this.retryAfter]);

  @override
  String toString() => statusCode == null
      ? 'SpotifyApiException: $message'
      : 'SpotifyApiException($statusCode): $message';
}

/// Client della Web API di Spotify.
///
/// Non riproduce nulla in locale: pilota il dispositivo attivo sulla sessione
/// Spotify Connect dell'utente, quindi ogni comando richiede che qualcosa sia
/// gia' in riproduzione altrove.
class SpotifyService {
  static const _base = 'https://api.spotify.com/v1';

  /// Senza timeout una richiesta appesa bloccherebbe il polling a tempo
  /// indeterminato: il guard sul poll in corso non si sbloccherebbe mai.
  static const _requestTimeout = Duration(seconds: 10);

  final SpotifyAuth _auth;
  final TokenStorage _storage;
  final http.Client _client;

  SpotifyTokens? _tokens;
  Future<bool>? _pendingRefresh;

  /// Invocata quando il refresh fallisce in modo definitivo e serve un
  /// nuovo login.
  void Function()? onAuthLost;

  SpotifyService({
    required SpotifyAuth auth,
    required TokenStorage storage,
    http.Client? client,
  }) : _auth = auth,
       _storage = storage,
       _client = client ?? http.Client();

  bool get hasTokens => _tokens != null;

  void adoptTokens(SpotifyTokens tokens) {
    _tokens = tokens;
  }

  void clearTokens() {
    _tokens = null;
  }

  /// Un solo refresh alla volta: senza questo guard le richieste in volo
  /// scadute partirebbero tutte insieme a rinnovare, invalidandosi a vicenda
  /// perche' Spotify ruota il refresh token ad ogni scambio.
  Future<bool> _refreshTokens() {
    final pending = _pendingRefresh;
    if (pending != null) return pending;

    final refreshToken = _tokens?.refreshToken;
    if (refreshToken == null) return Future.value(false);

    final future = _auth
        .refresh(refreshToken)
        .then((tokens) async {
          if (tokens == null) {
            logError('Refresh non riuscito, sessione da rifare');
            _tokens = null;
            await _storage.clear();
            onAuthLost?.call();
            return false;
          }
          _tokens = tokens;
          await _storage.save(tokens);
          return true;
        })
        .whenComplete(() => _pendingRefresh = null);

    _pendingRefresh = future;
    return future;
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    if (_tokens == null) {
      throw const SpotifyApiException('Nessuna sessione attiva');
    }

    // Rinnovo proattivo: se il token e' gia' scaduto evitiamo del tutto il 401.
    if (_tokens!.isExpired()) {
      final refreshed = await _refreshTokens();
      if (!refreshed) {
        throw const SpotifyApiException('Rinnovo del token non riuscito');
      }
    }

    var response = await _dispatch(method, uri, body);
    if (response.statusCode == 401 && await _refreshTokens()) {
      response = await _dispatch(method, uri, body);
    }
    if (response.statusCode == 429) {
      // Continuare a bussare allunga la finestra di punizione: l'attesa
      // richiesta viaggia con l'eccezione perche' il chiamante la applichi.
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 5;
      throw SpotifyApiException(
        'Rate limit Spotify',
        429,
        Duration(seconds: seconds),
      );
    }
    return response;
  }

  Future<http.Response> _dispatch(
    String method,
    Uri uri,
    Map<String, dynamic>? body,
  ) {
    final headers = {
      'Authorization': 'Bearer ${_tokens!.accessToken}',
      'Content-Type': 'application/json',
    };
    final encoded = body != null ? jsonEncode(body) : null;

    final Future<http.Response> request = switch (method) {
      'GET' => _client.get(uri, headers: headers),
      'POST' => _client.post(uri, headers: headers, body: encoded),
      'PUT' => _client.put(uri, headers: headers, body: encoded),
      _ => throw ArgumentError('Metodo non supportato: $method'),
    };
    return request.timeout(_requestTimeout);
  }

  /// Restituisce null solo per il 204, cioe' "non c'e' niente da mostrare".
  /// Ogni altro esito diventa un'eccezione, perche' significa "non lo so".
  Future<Map<String, dynamic>?> _get(String path) async {
    final response = await _send('GET', Uri.parse('$_base$path'));
    if (response.statusCode == 204) return null;
    if (response.statusCode != 200) {
      throw SpotifyApiException(
        'GET $path fallita: ${response.body}',
        response.statusCode,
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _command(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final response = await _send(method, Uri.parse('$_base$path'), body: body);
    if (response.statusCode >= 300) {
      throw SpotifyApiException(
        '$method $path fallita: ${response.body}',
        response.statusCode,
      );
    }
  }

  /// Stato della riproduzione, o null quando non c'e' nulla in riproduzione.
  /// Solleva [SpotifyApiException] se lo stato non e' determinabile.
  Future<PlaybackState?> currentPlayback() async {
    final json = await _get('/me/player/currently-playing');
    if (json == null) return null;
    return PlaybackState.parse(json);
  }

  Future<void> next() => _command('POST', '/me/player/next');

  Future<void> previous() => _command('POST', '/me/player/previous');

  Future<void> pause() => _command('PUT', '/me/player/pause');

  Future<void> resume() => _command('PUT', '/me/player/play');
}
