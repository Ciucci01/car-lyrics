import 'dart:convert';

import 'package:car_play/models/lyrics.dart';
import 'package:car_play/models/lyrics_text_size.dart';
import 'package:car_play/providers/player_provider.dart';
import 'package:car_play/providers/settings_provider.dart';
import 'package:car_play/screens/lyrics_list_view.dart';
import 'package:car_play/screens/lyrics_text_size_button.dart';
import 'package:car_play/services/auth_service.dart';
import 'package:car_play/services/lyrics/lyrics_provider.dart';
import 'package:car_play/services/lyrics/lyrics_repository.dart';
import 'package:car_play/services/spotify_service.dart';
import 'package:car_play/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Testo inventato: qui contano solo le dimensioni con cui viene reso.
const _lyrics = Lyrics(
  error: false,
  syncType: 'LINE_SYNCED',
  lines: [
    LyricLine(startTimeMs: '0', words: 'riga uno', endTimeMs: '0'),
    LyricLine(startTimeMs: '3000', words: 'riga due', endTimeMs: '0'),
  ],
);

class _FakeLyricsProvider implements LyricsProvider {
  @override
  String get name => 'finto';

  @override
  Future<Lyrics?> fetch(LyricsQuery query) async => _lyrics;
}

String _playingBody() => jsonEncode({
  'is_playing': true,
  'progress_ms': 0,
  'item': {
    'id': 'traccia-1',
    'name': 'Titolo di prova',
    'duration_ms': 200000,
    'artists': [
      {'name': 'Artista di prova'},
    ],
    'album': {'name': 'Album di prova', 'images': []},
  },
});

void main() {
  setUp(() {
    dotenv.loadFromString(envString: 'SPOTIFY_CLIENT_ID=id-di-prova');
    // Una sessione gia' valida: il provider la ritrova da solo e parte
    // collegato, senza passare dal login.
    SharedPreferences.setMockInitialValues({
      'access_token': 'accesso',
      'refresh_token': 'rinnovo',
      'expiry_date': DateTime.now()
          .add(const Duration(days: 1))
          .millisecondsSinceEpoch,
    });
  });

  /// Il provider si registra qui e viene chiuso in un `finally`: i suoi due
  /// timer, se restassero accesi, seppellirebbero il fallimento vero sotto un
  /// "A Timer is still pending".
  final creati = <PlayerProvider>[];

  Future<SettingsProvider> pumpSchermata(WidgetTester tester) async {
    final client = MockClient(
      (request) async => request.url.path.endsWith('/currently-playing')
          ? http.Response(_playingBody(), 200)
          : http.Response('', 204),
    );
    final storage = TokenStorage();
    final auth = SpotifyAuth(clientId: 'id-di-prova', client: client);
    final player = PlayerProvider(
      storage: storage,
      auth: auth,
      spotify: SpotifyService(auth: auth, storage: storage, client: client),
      lyricsRepository: LyricsRepository(providers: [_FakeLyricsProvider()]),
    );
    creati.add(player);
    final settings = SettingsProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerProvider>.value(value: player),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ],
        child: const MaterialApp(home: Scaffold(body: LyricsListView())),
      ),
    );

    for (var i = 0; i < 20; i++) {
      if (player.lyricsStatus == LyricsStatus.ready) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return settings;
  }

  double sizeOf(WidgetTester tester, String words) {
    return tester.widget<Text>(find.text(words)).style!.fontSize!;
  }

  void testSchermata(
    String descrizione,
    Future<void> Function(WidgetTester) corpo,
  ) {
    testWidgets(descrizione, (tester) async {
      try {
        await corpo(tester);
      } finally {
        for (final player in creati) {
          player.dispose();
        }
        creati.clear();
      }
    });
  }

  testSchermata('senza scelta rende le righe come ha sempre fatto', (
    tester,
  ) async {
    await pumpSchermata(tester);

    expect(sizeOf(tester, 'riga uno'), 20);
    expect(sizeOf(tester, 'riga due'), 16);
  });

  testSchermata('la taglia scelta arriva alle righe', (tester) async {
    final settings = await pumpSchermata(tester);

    await settings.setLyricsTextSize(LyricsTextSize.huge);
    await tester.pump();

    expect(sizeOf(tester, 'riga uno'), LyricsTextSize.huge.currentLineSize);
    expect(sizeOf(tester, 'riga due'), LyricsTextSize.huge.otherLineSize);
    // La riga corrente resta piu' grande delle altre a ogni taglia: e' quello
    // che fa capire a colpo d'occhio a che punto si e'.
    expect(sizeOf(tester, 'riga uno'), greaterThan(sizeOf(tester, 'riga due')));
  });

  testSchermata('una taglia salvata vale gia al primo disegno', (tester) async {
    SharedPreferences.setMockInitialValues({
      'access_token': 'accesso',
      'refresh_token': 'rinnovo',
      'expiry_date': DateTime.now()
          .add(const Duration(days: 1))
          .millisecondsSinceEpoch,
      'lyrics_text_size': 'small',
    });

    await pumpSchermata(tester);

    expect(sizeOf(tester, 'riga uno'), LyricsTextSize.small.currentLineSize);
  });

  testWidgets('il menu offre le quattro taglie e applica quella scelta', (
    tester,
  ) async {
    final settings = SettingsProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(
          home: Scaffold(
            appBar: null,
            body: Center(child: LyricsTextSizeButton()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.format_size));
    await tester.pumpAndSettle();

    for (final size in LyricsTextSize.values) {
      expect(find.text(size.label), findsOneWidget);
    }

    await tester.tap(find.text(LyricsTextSize.large.label));
    await tester.pumpAndSettle();

    expect(settings.lyricsTextSize, LyricsTextSize.large);
  });
}
