import 'package:car_lyrics/models/lyrics_text_size.dart';
import 'package:car_lyrics/providers/player_provider.dart';
import 'package:car_lyrics/providers/settings_provider.dart';
import 'package:car_lyrics/screens/lyrics_list_view.dart';
import 'package:car_lyrics/screens/lyrics_text_size_button.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

void main() {
  setUp(() {
    seedTokens();
    SharedPreferences.setMockInitialValues({});
  });

  /// Il provider si registra qui e viene chiuso in un `finally`: i suoi due
  /// timer, se restassero accesi, seppellirebbero il fallimento vero sotto un
  /// "A Timer is still pending".
  final creati = <PlayerProvider>[];

  Future<SettingsProvider> pumpSchermata(WidgetTester tester) async {
    final player = buildPlayerProvider(FakeSpotifyApi());
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
    // Il centraggio iniziale dura 400ms, e mentre scorre la lista tiene due
    // viewport vive: ogni riga risulterebbe presente due volte.
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
    testWidgets(
      descrizione,
      (tester) => withClock(Clock.fixed(DateTime.utc(2026)), () async {
        try {
          await corpo(tester);
        } finally {
          for (final player in creati) {
            player.dispose();
          }
          creati.clear();
        }
      }),
    );
  }

  testSchermata('senza scelta parte dal livello medio', (tester) async {
    await pumpSchermata(tester);

    // Non e' piu' la misura storica: quella ora e' `small`. Chi non tocca il
    // menu vede il testo un gradino piu' grande di com'era, che e' il motivo
    // per cui la scala e' stata spostata.
    expect(sizeOf(tester, 'riga uno'), LyricsTextSize.medium.currentLineSize);
    expect(sizeOf(tester, 'riga due'), LyricsTextSize.medium.otherLineSize);
    expect(sizeOf(tester, 'riga uno'), greaterThan(20));
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
    SharedPreferences.setMockInitialValues({'lyrics_text_size': 'small'});

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
          home: Scaffold(body: Center(child: LyricsTextSizeButton())),
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
