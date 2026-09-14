import 'dart:async';
import 'dart:convert';

import 'package:car_play/models/lyrics.dart';
import 'package:car_play/providers/player_provider.dart';
import 'package:car_play/services/auth_service.dart';
import 'package:car_play/services/lyrics/lyrics_provider.dart';
import 'package:car_play/services/lyrics/lyrics_repository.dart';
import 'package:car_play/services/spotify_authenticator.dart';
import 'package:car_play/services/spotify_service.dart';
import 'package:car_play/services/storage_service.dart';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Risposte della Web API sotto il nostro controllo, piu' il conto di quante
/// richieste sono davvero partite: e' cio' che i test sui timer misurano.
class _FakeSpotifyApi {
  int playbackCalls = 0;
  final List<String> commands = [];

  /// Riceve il numero della chiamata, a partire da 1. Di default la posizione
  /// avanza di 5s ad ogni poll, come farebbe una riproduzione vera.
  http.Response Function(int call) onPlayback = (call) =>
      http.Response(_playingBody(progressMs: (call - 1) * 5000), 200);

  /// Se valorizzato, i comandi restano appesi finche' non viene completato:
  /// serve a guardare la schermata mentre la rete e' ancora in volo.
  Completer<void>? holdCommands;

  late final http.Client client = MockClient((request) async {
    final path = request.url.path;

    if (path.endsWith('/currently-playing')) {
      playbackCalls++;
      return onPlayback(playbackCalls);
    }

    if (request.url.host == 'accounts.spotify.com') {
      commands.add('TOKEN');
      return http.Response(
        jsonEncode({
          'access_token': 'accesso-nuovo',
          'refresh_token': 'rinnovo-nuovo',
          'expires_in': 3600,
        }),
        200,
      );
    }

    commands.add('${request.method} $path');
    await holdCommands?.future;
    return http.Response('', 204);
  });
}

String _playingBody({
  String id = 'traccia-1',
  int progressMs = 0,
  bool isPlaying = true,
  int durationMs = 200000,
}) {
  return jsonEncode({
    'is_playing': isPlaying,
    'progress_ms': progressMs,
    'item': {
      'id': id,
      'name': 'Titolo di prova',
      'duration_ms': durationMs,
      'artists': [
        {'name': 'Artista di prova'},
      ],
      'album': {
        'name': 'Album di prova',
        'images': [
          {'url': 'https://esempio.invalid/copertina.jpg'},
        ],
      },
    },
  });
}

/// Testo inventato: al test interessano solo i tempi di attacco delle righe.
const _synced = Lyrics(
  error: false,
  syncType: 'LINE_SYNCED',
  lines: [
    LyricLine(startTimeMs: '0', words: 'riga uno', endTimeMs: '0'),
    LyricLine(startTimeMs: '3000', words: 'riga due', endTimeMs: '0'),
    LyricLine(startTimeMs: '6000', words: 'riga tre', endTimeMs: '0'),
  ],
);

class _FakeLyricsProvider implements LyricsProvider {
  _FakeLyricsProvider([Future<Lyrics?> Function(LyricsQuery query)? responder])
    : responder = responder ?? ((_) async => _synced);

  final Future<Lyrics?> Function(LyricsQuery query) responder;

  @override
  String get name => 'finto';

  @override
  Future<Lyrics?> fetch(LyricsQuery query) => responder(query);
}

/// Rimanda indietro lo `state` che ha ricevuto, come farebbe Spotify, a meno
/// che il test non voglia proprio vederlo sbagliato.
class _FakeAuthenticator extends SpotifyAuthenticator {
  const _FakeAuthenticator({this.wrongState, this.cancelled = false});

  final String? wrongState;

  /// L'utente esce dal browser senza completare.
  final bool cancelled;

  @override
  Future<SpotifyAuthResult?> authenticate({
    required Uri authorizeUrl,
    required String redirectUri,
  }) async {
    if (cancelled) return null;
    return SpotifyAuthResult(
      code: 'codice-di-prova',
      state: wrongState ?? authorizeUrl.queryParameters['state'],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.loadFromString(envString: 'SPOTIFY_CLIENT_ID=id-di-prova');
    seedTokens();
  });

  PlayerProvider build(
    _FakeSpotifyApi api, {
    LyricsProvider? lyrics,
    SpotifyAuthenticator? authenticator,
  }) {
    final storage = TokenStorage();
    final auth = SpotifyAuth(clientId: 'id-di-prova', client: api.client);
    return PlayerProvider(
      storage: storage,
      auth: auth,
      authenticator: authenticator ?? const _FakeAuthenticator(),
      spotify: SpotifyService(auth: auth, storage: storage, client: api.client),
      lyricsRepository: LyricsRepository(
        providers: [lyrics ?? _FakeLyricsProvider()],
      ),
    );
  }

  /// Costruisce il provider a tempo finto e aspetta che la sessione ripresa
  /// dall'archivio abbia gia' fatto il suo primo poll.
  void withConnectedProvider(
    _FakeSpotifyApi api,
    void Function(PlayerProvider provider, FakeAsync async) body, {
    LyricsProvider? lyrics,
    SpotifyAuthenticator? authenticator,
  }) {
    fakeAsync((async) {
      withClock(async.getClock(DateTime(2026, 1, 1)), () {
        final provider = build(
          api,
          lyrics: lyrics,
          authenticator: authenticator,
        );
        async.elapse(const Duration(milliseconds: 1));
        body(provider, async);
        provider.dispose();
      });
    });
  }

  group('i due timer', () {
    test('il tick muove la riga senza interrogare Spotify', () {
      final api = _FakeSpotifyApi();

      withConnectedProvider(api, (provider, async) {
        expect(provider.status, ConnectionStatus.connected);
        expect(provider.lyricsStatus, LyricsStatus.ready);
        expect(provider.currentLineIndex, 0);

        final dopoIlPrimoPoll = api.playbackCalls;
        async.elapse(const Duration(seconds: 3));

        // La riga e' avanzata da sola, per interpolazione dell'ancora.
        expect(provider.currentLineIndex, 1);
        expect(api.playbackCalls, dopoIlPrimoPoll);
      });
    });

    test('in dodici secondi partono tre poll, non centoventi', () {
      final api = _FakeSpotifyApi();

      withConnectedProvider(api, (provider, async) {
        async.elapse(const Duration(seconds: 12));

        // Il primo all'avvio, poi uno a 5s e uno a 10s. Il tick a 100ms
        // avrebbe battuto 120 volte senza toccare la rete.
        expect(api.playbackCalls, 3);
        expect(provider.currentLineIndex, 2);
      });
    });

    test('in background il polling si ferma e la stima si congela', () {
      final api = _FakeSpotifyApi();

      withConnectedProvider(api, (provider, async) {
        provider.didChangeAppLifecycleState(AppLifecycleState.paused);
        final congelata = provider.estimatedProgressMs;
        final pollFinora = api.playbackCalls;

        async.elapse(const Duration(seconds: 30));

        expect(api.playbackCalls, pollFinora);
        expect(provider.estimatedProgressMs, congelata);

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.elapse(const Duration(milliseconds: 1));

        // Il rientro risincronizza subito, senza aspettare il poll a 5s.
        expect(api.playbackCalls, pollFinora + 1);
      });
    });

    test('inactive non ferma niente: e\' transitorio', () {
      final api = _FakeSpotifyApi();

      withConnectedProvider(api, (provider, async) {
        provider.didChangeAppLifecycleState(AppLifecycleState.inactive);
        final pollFinora = api.playbackCalls;

        async.elapse(const Duration(seconds: 6));

        expect(api.playbackCalls, pollFinora + 1);
      });
    });
  });

  group('errori', () {
    test('un 500 passeggero non cancella quello che si sta mostrando', () {
      final api = _FakeSpotifyApi()
        ..onPlayback = (call) => call == 1
            ? http.Response(_playingBody(), 200)
            : http.Response('errore del server', 500);

      withConnectedProvider(api, (provider, async) {
        expect(provider.playback, isNotNull);

        async.elapse(const Duration(seconds: 12));

        expect(api.playbackCalls, greaterThan(1));
        expect(provider.playback?.trackId, 'traccia-1');
        expect(provider.lyricsStatus, LyricsStatus.ready);
      });
    });

    test('un 204 invece azzera: non sta suonando niente', () {
      final api = _FakeSpotifyApi()
        ..onPlayback = (call) => call == 1
            ? http.Response(_playingBody(), 200)
            : http.Response('', 204);

      withConnectedProvider(api, (provider, async) {
        expect(provider.playback, isNotNull);

        async.elapse(const Duration(seconds: 6));

        expect(provider.playback, isNull);
        expect(provider.lyrics, isNull);
        expect(provider.lyricsStatus, LyricsStatus.idle);
        expect(provider.currentLineIndex, -1);
      });
    });

    test('un 429 blocca anche i comandi dell utente', () {
      final api = _FakeSpotifyApi()
        ..onPlayback = (call) => call == 1
            ? http.Response(_playingBody(), 200)
            : http.Response('', 429, headers: {'retry-after': '30'});

      withConnectedProvider(api, (provider, async) {
        // Il poll a 5s incassa il 429 e parcheggia il blocco.
        async.elapse(const Duration(seconds: 6));
        final pollAlBlocco = api.playbackCalls;

        unawaited(provider.skipToNext());
        async.elapse(const Duration(seconds: 20));

        // Ne' il comando ne' i poll periodici sono partiti.
        expect(api.commands, isEmpty);
        expect(api.playbackCalls, pollAlBlocco);

        async.elapse(const Duration(seconds: 15));
        expect(api.playbackCalls, greaterThan(pollAlBlocco));
      });
    });
  });

  group('comandi e login', () {
    test('il pulsante risponde prima che la rete abbia risposto', () {
      final api = _FakeSpotifyApi()..holdCommands = Completer<void>();

      withConnectedProvider(api, (provider, async) {
        expect(provider.isPlaying, isTrue);

        unawaited(provider.togglePlayPause());
        async.flushMicrotasks();

        // La PUT e' ancora appesa, ma la schermata si e' gia' aggiornata.
        expect(api.commands, ['PUT /v1/me/player/pause']);
        expect(provider.isPlaying, isFalse);

        api.holdCommands!.complete();
        async.elapse(const Duration(seconds: 1));
      });
    });

    test('una risposta lyrics in ritardo non copre la traccia nuova', () {
      final api = _FakeSpotifyApi()
        ..onPlayback = (call) => call == 1
            ? http.Response(_playingBody(), 200)
            : http.Response(_playingBody(id: 'traccia-2'), 200);

      final lenta = _FakeLyricsProvider((query) async {
        if (query.trackId == 'traccia-1') {
          await Future<void>.delayed(const Duration(seconds: 8));
          return const Lyrics(
            error: false,
            syncType: 'LINE_SYNCED',
            lines: [
              LyricLine(
                startTimeMs: '0',
                words: 'testo della traccia vecchia',
                endTimeMs: '0',
              ),
            ],
          );
        }
        return _synced;
      });

      withConnectedProvider(api, (provider, async) {
        // Alla traccia 1 il testo e' ancora in volo.
        expect(provider.lyricsStatus, LyricsStatus.loading);

        // A 5s arriva la traccia 2, a 8s atterra la risposta della traccia 1.
        async.elapse(const Duration(seconds: 12));

        expect(provider.playback?.trackId, 'traccia-2');
        expect(provider.lyricsStatus, LyricsStatus.ready);
        expect(provider.lyrics?.lines.first.words, 'riga uno');
      }, lyrics: lenta);
    });

    test('connect() rifiuta uno state che non corrisponde', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = _FakeSpotifyApi();
      final provider = build(
        api,
        authenticator: const _FakeAuthenticator(wrongState: 'stato-inventato'),
      );
      addTearDown(provider.dispose);

      await provider.connect();

      expect(provider.status, ConnectionStatus.disconnected);
      expect(provider.authError, 'Invalid login response, please try again');
      // Il codice non e' mai stato scambiato.
      expect(api.commands, isEmpty);
    });

    test('connect() annullato non e un errore da mostrare', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = _FakeSpotifyApi();
      final provider = build(
        api,
        authenticator: const _FakeAuthenticator(cancelled: true),
      );
      addTearDown(provider.dispose);

      await provider.connect();

      expect(provider.status, ConnectionStatus.disconnected);
      expect(provider.authError, isNull);
    });

    test('connect() riuscito scambia il codice e collega', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = _FakeSpotifyApi();
      final provider = build(api);
      addTearDown(provider.dispose);

      await provider.connect();

      expect(api.commands, contains('TOKEN'));
      expect(provider.status, ConnectionStatus.connected);
      expect(provider.authError, isNull);
      // I token appena ottenuti sono finiti nell'archivio sicuro.
      expect(
        await const FlutterSecureStorage().read(key: 'refresh_token'),
        'rinnovo-nuovo',
      );
    });
  });
}

void seedTokens() {
  FlutterSecureStorage.setMockInitialValues({
    'access_token': 'accesso',
    'refresh_token': 'rinnovo',
    'expiry_date': DateTime.now()
        .add(const Duration(days: 1))
        .millisecondsSinceEpoch
        .toString(),
  });
}
