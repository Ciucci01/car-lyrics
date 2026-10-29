import 'package:car_lyrics/providers/player_provider.dart';
import 'package:car_lyrics/providers/settings_provider.dart';
import 'package:car_lyrics/screens/player_menu_button.dart';
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

  final creati = <PlayerProvider>[];

  void testMenu(String descrizione, Future<void> Function(WidgetTester) corpo) {
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

  /// I provider stanno *sopra* MaterialApp, come in `main.dart`: il dialogo
  /// nasce appeso al Navigator, quindi da li' in giu' deve poterli trovare.
  Future<SettingsProvider> pumpMenu(WidgetTester tester) async {
    final player = buildPlayerProvider(FakeSpotifyApi());
    creati.add(player);
    final settings = SettingsProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerProvider>.value(value: player),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: PlayerMenuButton())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  Future<void> apriDialogo(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lyrics source'));
    await tester.pumpAndSettle();
  }

  testMenu('il menu raccoglie fonte dei testi e disconnessione', (
    tester,
  ) async {
    await pumpMenu(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Lyrics source'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
  });

  testMenu('l indirizzo inserito arriva alle impostazioni', (tester) async {
    final settings = await pumpMenu(tester);
    await apriDialogo(tester);

    await tester.enterText(
      find.byType(TextField),
      '  https://lyrics.example.com  ',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(settings.lyricsProxyUrl, 'https://lyrics.example.com');
    expect(find.byType(TextField), findsNothing);
  });

  testMenu('il dialogo riparte dall indirizzo gia impostato', (tester) async {
    final settings = await pumpMenu(tester);
    await settings.setLyricsProxyUrl('https://lyrics.example.com');

    await apriDialogo(tester);

    final campo = tester.widget<TextField>(find.byType(TextField));
    expect(campo.controller?.text, 'https://lyrics.example.com');
  });

  testMenu('un indirizzo scritto male non viene salvato', (tester) async {
    final settings = await pumpMenu(tester);
    await apriDialogo(tester);

    await tester.enterText(find.byType(TextField), 'lyrics.example.com');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // L'errore si vede qui e non una canzone dopo, sotto forma di testo che
    // non si carica: il dialogo resta aperto con il campo segnato.
    expect(find.textContaining('full address'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(settings.lyricsProxyUrl, '');
  });

  testMenu('svuotare il campo toglie il proxy dalla catena', (tester) async {
    final settings = await pumpMenu(tester);
    await settings.setLyricsProxyUrl('https://lyrics.example.com');

    await apriDialogo(tester);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(settings.lyricsProxyUrl, '');
  });
}
