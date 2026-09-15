import 'package:car_play/providers/player_provider.dart';
import 'package:car_play/screens/lyrics_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../support/fakes.dart';

void main() {
  setUp(() {
    loadTestEnv();
    seedTokens();
  });

  /// Monta la lista su un provider vero: `PlayerProvider` ha il costruttore
  /// privato, quindi non e' sostituibile con una finta, e comunque cio' che
  /// si vuole vedere qui e' proprio come i due reagiscono insieme.
  Future<PlayerProvider> pumpLista(
    WidgetTester tester,
    FakeSpotifyApi api, {
    FakeLyricsProvider? lyrics,
  }) async {
    final provider = buildPlayerProvider(api, lyrics: lyrics);
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<PlayerProvider>.value(
          value: provider,
          child: const Scaffold(body: LyricsListView()),
        ),
      ),
    );
    // Ripresa della sessione, primo poll, caricamento del testo e centraggio
    // rimandato al frame successivo.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return provider;
  }

  TextStyle styleOf(WidgetTester tester, String words) {
    return tester.widget<Text>(find.text(words)).style!;
  }

  testWidgets('senza testo non disegna niente', (tester) async {
    final provider = await pumpLista(
      tester,
      FakeSpotifyApi(),
      lyrics: FakeLyricsProvider((_) async => null),
    );

    expect(provider.lyricsStatus, LyricsStatus.unavailable);
    expect(find.byType(ScrollablePositionedList), findsNothing);

    provider.dispose();
  });

  testWidgets('mostra le righe fra due spaziatori', (tester) async {
    final provider = await pumpLista(tester, FakeSpotifyApi());

    expect(find.text('riga uno'), findsOneWidget);
    expect(find.text('riga due'), findsOneWidget);

    // itemCount e' lines.length + 2: gli spaziatori in testa e in coda sono
    // il motivo per cui l'indice della lista e' quello della riga piu' uno.
    final lista = tester.widget<ScrollablePositionedList>(
      find.byType(ScrollablePositionedList),
    );
    expect(lista.itemCount, syncedLyrics.lines.length + 2);

    provider.dispose();
  });

  testWidgets('evidenzia solo la riga corrente', (tester) async {
    final provider = await pumpLista(tester, FakeSpotifyApi());

    expect(provider.currentLineIndex, 0);
    expect(styleOf(tester, 'riga uno').fontWeight, FontWeight.bold);
    expect(styleOf(tester, 'riga uno').color, const Color(0xFF1DB954));
    expect(styleOf(tester, 'riga due').fontWeight, FontWeight.normal);
    expect(styleOf(tester, 'riga due').color, Colors.white70);

    provider.dispose();
  });

  testWidgets('la riga evidenziata segue la posizione', (tester) async {
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

    provider.dispose();
  });

  testWidgets('un trascinamento sgancia lo scorrimento e mostra il pulsante', (
    tester,
  ) async {
    final provider = await pumpLista(tester, FakeSpotifyApi());
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -120),
    );
    await tester.pump();

    expect(find.byType(FloatingActionButton), findsOneWidget);

    provider.dispose();
  });

  testWidgets('il pulsante riaggancia lo scorrimento', (tester) async {
    final provider = await pumpLista(tester, FakeSpotifyApi());

    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -120),
    );
    await tester.pump();
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(FloatingActionButton), findsNothing);

    provider.dispose();
  });

  testWidgets('il cambio traccia riaggancia da solo', (tester) async {
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

    provider.dispose();
  });
}
