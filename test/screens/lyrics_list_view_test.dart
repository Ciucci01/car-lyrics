import 'package:car_lyrics/providers/player_provider.dart';
import 'package:car_lyrics/providers/settings_provider.dart';
import 'package:car_lyrics/screens/lyrics_list_view.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

void main() {
  setUp(() {
    loadTestEnv();
    seedTokens();
    SharedPreferences.setMockInitialValues({});
  });

  /// Monta la lista su un provider vero: `PlayerProvider` ha il costruttore
  /// privato, quindi non e' sostituibile con una finta, e comunque cio' che
  /// si vuole vedere qui e' proprio come i due reagiscono insieme.
  ///
  /// Il provider si registra qui e `testLista` lo chiude in un `finally`.
  /// `addTearDown` non va bene: gira *dopo* il controllo dei timer pendenti
  /// di `flutter_test`, quindi arriverebbe a fallimento gia' avvenuto.
  final creati = <PlayerProvider>[];

  Future<PlayerProvider> pumpLista(
    WidgetTester tester,
    FakeSpotifyApi api, {
    FakeLyricsProvider? lyrics,
  }) async {
    final provider = buildPlayerProvider(api, lyrics: lyrics);
    creati.add(provider);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<PlayerProvider>.value(value: provider),
            ChangeNotifierProvider<SettingsProvider>(
              create: (_) => SettingsProvider(),
            ),
          ],
          child: const Scaffold(body: LyricsListView()),
        ),
      ),
    );

    // Ripresa della sessione, primo poll e caricamento del testo sono una
    // catena di future: si pompa finche' non si e' fermata, invece di
    // contare quanti salti servono oggi.
    for (var i = 0; i < 20; i++) {
      if (provider.status == ConnectionStatus.connected &&
          provider.lyricsStatus != LyricsStatus.loading) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Il centraggio iniziale e' rimandato al frame dopo l'aggancio, e dura
    // 400ms: mentre scorre, ScrollablePositionedList tiene due viewport vive
    // e ogni riga risulta presente due volte.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return provider;
  }

  TextStyle styleOf(WidgetTester tester, String words) {
    return tester.widget<Text>(find.text(words)).style!;
  }

  /// `flutter_test` finge i timer ma non l'orologio, e `estimatedProgressMs`
  /// e' ancora + tempo trascorso: senza fissarlo, asserire su quale riga sia
  /// evidenziata dipende da quanto e' veloce la macchina. Con un orologio
  /// fermo il trascorso e' sempre zero e a muovere la riga resta solo il
  /// `progress_ms` che arriva dal server.
  void testLista(
    String descrizione,
    Future<void> Function(WidgetTester) corpo,
  ) {
    testWidgets(
      descrizione,
      (tester) => withClock(Clock.fixed(DateTime.utc(2026)), () async {
        try {
          await corpo(tester);
        } finally {
          // Anche quando un expect e' appena fallito: i due timer del
          // provider seppellirebbero il fallimento vero sotto un "A Timer is
          // still pending" e continuerebbero a interrogare la finta nei test
          // successivi.
          for (final provider in creati) {
            provider.dispose();
          }
          creati.clear();
        }
      }),
    );
  }

  testLista('senza testo non disegna niente', (tester) async {
    final provider = await pumpLista(
      tester,
      FakeSpotifyApi(),
      lyrics: FakeLyricsProvider((_) async => null),
    );

    expect(provider.lyricsStatus, LyricsStatus.unavailable);
    expect(find.byType(ScrollablePositionedList), findsNothing);
  });

  testLista('mostra le righe fra due spaziatori', (tester) async {
    await pumpLista(tester, FakeSpotifyApi());

    expect(find.text('riga uno'), findsOneWidget);
    expect(find.text('riga due'), findsOneWidget);

    // itemCount e' lines.length + 2: gli spaziatori in testa e in coda sono
    // il motivo per cui l'indice della lista e' quello della riga piu' uno.
    final lista = tester.widget<ScrollablePositionedList>(
      find.byType(ScrollablePositionedList),
    );
    expect(lista.itemCount, syncedLyrics.lines.length + 2);
  });

  testLista('evidenzia solo la riga corrente', (tester) async {
    final provider = await pumpLista(tester, FakeSpotifyApi());

    expect(provider.currentLineIndex, 0);
    expect(styleOf(tester, 'riga uno').fontWeight, FontWeight.bold);
    expect(styleOf(tester, 'riga uno').color, const Color(0xFF1DB954));
    expect(styleOf(tester, 'riga due').fontWeight, FontWeight.normal);
    expect(styleOf(tester, 'riga due').color, Colors.white70);
  });

  testLista('la riga evidenziata segue la posizione', (tester) async {
    // Il secondo poll riporta la riproduzione oltre l'attacco della riga due.
    final api = FakeSpotifyApi()
      ..onPlayback = (call) =>
          http.Response(playingBody(progressMs: call == 1 ? 0 : 3500), 200);

    final provider = await pumpLista(tester, api);
    expect(provider.currentLineIndex, 0);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));

    expect(provider.currentLineIndex, 1);
    expect(styleOf(tester, 'riga due').fontWeight, FontWeight.bold);
    expect(styleOf(tester, 'riga uno').fontWeight, FontWeight.normal);
  });

  testLista('un trascinamento sgancia lo scorrimento e mostra il pulsante', (
    tester,
  ) async {
    await pumpLista(tester, FakeSpotifyApi());
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -120),
    );
    await tester.pump();

    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testLista('il pulsante riaggancia lo scorrimento', (tester) async {
    await pumpLista(tester, FakeSpotifyApi());

    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -120),
    );
    await tester.pump();
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testLista('il cambio traccia riaggancia da solo', (tester) async {
    final api = FakeSpotifyApi()
      ..onPlayback = (call) => http.Response(
        playingBody(id: call == 1 ? 'traccia-1' : 'traccia-2'),
        200,
      );

    final provider = await pumpLista(tester, api);

    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -120),
    );
    await tester.pump();
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // Lo sganciamento vale per la canzone che si stava sfogliando, non per
    // quella dopo: al cambio traccia il pulsante deve sparire da solo.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));

    expect(provider.playback?.trackId, 'traccia-2');
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
