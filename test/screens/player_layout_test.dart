import 'package:car_play/providers/player_provider.dart';
import 'package:car_play/providers/settings_provider.dart';
import 'package:car_play/screens/lyrics_list_view.dart';
import 'package:car_play/screens/player_controls.dart';
import 'package:car_play/screens/player_screen.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

void main() {
  const orizzontale = Size(800, 400);
  const verticale = Size(400, 800);

  setUp(() {
    loadTestEnv();
    seedTokens();
    SharedPreferences.setMockInitialValues({});
  });

  /// I due timer del provider, lasciati accesi, seppellirebbero il fallimento
  /// vero sotto un "A Timer is still pending": vanno chiusi dentro il corpo
  /// del test, perche' `addTearDown` gira *dopo* il controllo di
  /// `flutter_test`.
  final creati = <PlayerProvider>[];

  Future<void> pumpSchermata(WidgetTester tester, Size dimensioni) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = dimensioni;
    addTearDown(tester.view.reset);

    final player = buildPlayerProvider(FakeSpotifyApi());
    creati.add(player);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerProvider>.value(value: player),
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: PlaybackView(player: player)),
        ),
      ),
    );

    for (var i = 0; i < 20; i++) {
      if (player.lyricsStatus == LyricsStatus.ready) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
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

  testSchermata('in verticale i comandi restano una barra in fondo', (
    tester,
  ) async {
    await pumpSchermata(tester, verticale);

    final comandi = tester.getRect(find.byType(PlayerControls));
    expect(comandi.left, 0);
    expect(comandi.width, verticale.width);
    expect(comandi.bottom, verticale.height);
    // Il testo paga la barra in altezza, che in verticale e' il lato lungo.
    expect(
      tester.getRect(find.byType(LyricsListView)).height,
      verticale.height - comandi.height,
    );
  });

  testSchermata('in orizzontale i comandi stanno sul bordo destro', (
    tester,
  ) async {
    await pumpSchermata(tester, orizzontale);

    final comandi = tester.getRect(find.byType(PlayerControls));
    expect(comandi.right, orizzontale.width);
    expect(comandi.height, orizzontale.height);
    // Il motivo di tutto: in orizzontale il testo tiene l'altezza intera.
    final testo = tester.getRect(find.byType(LyricsListView));
    expect(testo.height, orizzontale.height);
    expect(testo.right, comandi.left);
  });

  testSchermata('i tre comandi restano grandi uguale nelle due disposizioni', (
    tester,
  ) async {
    await pumpSchermata(tester, orizzontale);

    final misure = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .map((button) => button.iconSize)
        .toList();

    expect(misure, [32.0, 40.0, 32.0]);
  });

  testSchermata('in orizzontale il ricentraggio non finisce sotto i comandi', (
    tester,
  ) async {
    await pumpSchermata(tester, orizzontale);

    // Trascinare disattiva l'inseguimento e fa comparire il pulsante.
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -40),
    );
    await tester.pump();

    final ricentra = tester.getRect(find.byType(FloatingActionButton));
    final comandi = tester.getRect(find.byType(PlayerControls));
    expect(ricentra.right, lessThan(comandi.left));
    expect(ricentra.left, lessThan(orizzontale.width / 2));
  });
}
