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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Risposte della Web API sotto il nostro controllo, piu' il conto di quante
/// richieste sono davvero partite: e' cio' che i test sui timer misurano.
class FakeSpotifyApi {
  int playbackCalls = 0;
  final List<String> commands = [];

  /// Riceve il numero della chiamata, a partire da 1. Di default la posizione
  /// avanza di 5s ad ogni poll, come farebbe una riproduzione vera.
  http.Response Function(int call) onPlayback = (call) =>
      http.Response(playingBody(progressMs: (call - 1) * 5000), 200);

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

String playingBody({
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
const syncedLyrics = Lyrics(
  error: false,
  syncType: 'LINE_SYNCED',
  lines: [
    LyricLine(startTimeMs: '0', words: 'riga uno', endTimeMs: '0'),
    LyricLine(startTimeMs: '3000', words: 'riga due', endTimeMs: '0'),
    LyricLine(startTimeMs: '6000', words: 'riga tre', endTimeMs: '0'),
  ],
);

class FakeLyricsProvider implements LyricsProvider {
  FakeLyricsProvider([Future<Lyrics?> Function(LyricsQuery query)? responder])
    : responder = responder ?? ((_) async => syncedLyrics);

  final Future<Lyrics?> Function(LyricsQuery query) responder;

  @override
  String get name => 'finto';

  @override
  Future<Lyrics?> fetch(LyricsQuery query) => responder(query);
}

/// Rimanda indietro lo `state` che ha ricevuto, come farebbe Spotify, a meno
/// che il test non voglia proprio vederlo sbagliato.
class FakeAuthenticator extends SpotifyAuthenticator {
  const FakeAuthenticator({this.wrongState, this.cancelled = false});

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

/// Una sessione gia' valida nell'archivio sicuro: il provider la ritrova da
/// solo alla costruzione e parte collegato.
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

void loadTestEnv() {
  dotenv.loadFromString(envString: 'SPOTIFY_CLIENT_ID=id-di-prova');
}

PlayerProvider buildPlayerProvider(
  FakeSpotifyApi api, {
  LyricsProvider? lyrics,
  SpotifyAuthenticator? authenticator,
}) {
  final storage = TokenStorage();
  final auth = SpotifyAuth(clientId: 'id-di-prova', client: api.client);
  return PlayerProvider(
    storage: storage,
    auth: auth,
    authenticator: authenticator ?? const FakeAuthenticator(),
    spotify: SpotifyService(auth: auth, storage: storage, client: api.client),
    lyricsRepository: LyricsRepository(
      providers: [lyrics ?? FakeLyricsProvider()],
    ),
  );
}
