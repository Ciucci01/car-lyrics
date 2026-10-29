import 'dart:convert';
import 'dart:async';

import 'package:car_lyrics/models/lyrics.dart';
import 'package:car_lyrics/providers/player_provider.dart';
import 'package:car_lyrics/services/lyrics/lyrics_provider.dart';
import 'package:car_lyrics/services/spotify_authenticator.dart';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    seedTokens();
  });

  /// Costruisce il provider a tempo finto e aspetta che la sessione ripresa
  /// dall'archivio abbia gia' fatto il suo primo poll.
  void withConnectedProvider(
    FakeSpotifyApi api,
    void Function(PlayerProvider provider, FakeAsync async) body, {
    LyricsProvider? lyrics,
    SpotifyAuthenticator? authenticator,
  }) {
    fakeAsync((async) {
      withClock(async.getClock(DateTime(2026, 1, 1)), () {
        final provider = buildPlayerProvider(
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
      final api = FakeSpotifyApi();

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
      final api = FakeSpotifyApi();

      withConnectedProvider(api, (provider, async) {
        async.elapse(const Duration(seconds: 12));

        // Il primo all'avvio, poi uno a 5s e uno a 10s. Il tick a 100ms
        // avrebbe battuto 120 volte senza toccare la rete.
        expect(api.playbackCalls, 3);
        expect(provider.currentLineIndex, 2);
      });
    });

    test('in background il polling si ferma e la stima si congela', () {
      final api = FakeSpotifyApi();

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
      final api = FakeSpotifyApi();

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
      final api = FakeSpotifyApi()
        ..onPlayback = (call) => call == 1
            ? http.Response(playingBody(), 200)
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
      final api = FakeSpotifyApi()
        ..onPlayback = (call) => call == 1
            ? http.Response(playingBody(), 200)
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
      final api = FakeSpotifyApi()
        ..onPlayback = (call) => call == 1
            ? http.Response(playingBody(), 200)
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
      final api = FakeSpotifyApi()..holdCommands = Completer<void>();

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
      final api = FakeSpotifyApi()
        ..onPlayback = (call) => call == 1
            ? http.Response(playingBody(), 200)
            : http.Response(playingBody(id: 'traccia-2'), 200);

      final lenta = FakeLyricsProvider((query) async {
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
        return syncedLyrics;
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
      final api = FakeSpotifyApi();
      final provider = buildPlayerProvider(
        api,
        authenticator: const FakeAuthenticator(wrongState: 'stato-inventato'),
      );
      addTearDown(provider.dispose);
      // _restoreSession() parte non atteso dal costruttore e finisce con
      // uno stato disconnected: se atterrasse dopo connect() lo
      // sovrascriverebbe. Oggi l'ordine di scheduling lo evita, ma nessuno
      // lo garantisce.
      await pumpEventQueue();

      await provider.connect();

      expect(provider.status, ConnectionStatus.disconnected);
      expect(provider.authError, 'Invalid login response, please try again');
      // Il codice non e' mai stato scambiato.
      expect(api.commands, isEmpty);
    });

    test('connect() annullato non e un errore da mostrare', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = FakeSpotifyApi();
      final provider = buildPlayerProvider(
        api,
        authenticator: const FakeAuthenticator(cancelled: true),
      );
      addTearDown(provider.dispose);
      // _restoreSession() parte non atteso dal costruttore e finisce con
      // uno stato disconnected: se atterrasse dopo connect() lo
      // sovrascriverebbe. Oggi l'ordine di scheduling lo evita, ma nessuno
      // lo garantisce.
      await pumpEventQueue();

      await provider.connect();

      expect(provider.status, ConnectionStatus.disconnected);
      expect(provider.authError, isNull);
    });

    test('connect() riuscito scambia il codice e collega', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = FakeSpotifyApi();
      final provider = buildPlayerProvider(api);
      addTearDown(provider.dispose);
      // _restoreSession() parte non atteso dal costruttore e finisce con
      // uno stato disconnected: se atterrasse dopo connect() lo
      // sovrascriverebbe. Oggi l'ordine di scheduling lo evita, ma nessuno
      // lo garantisce.
      await pumpEventQueue();

      await provider.connect();

      expect(api.commands, contains('TOKEN'));
      expect(provider.status, ConnectionStatus.connected);
      expect(provider.authError, isNull);
      // I token appena ottenuti sono finiti nell'archivio sicuro.
      final raw = await const FlutterSecureStorage().read(
        key: 'spotify_tokens',
      );
      expect(jsonDecode(raw!)['refresh'], 'rinnovo-nuovo');
    });
  });
}
