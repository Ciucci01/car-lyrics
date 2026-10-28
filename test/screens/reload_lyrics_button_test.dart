import 'package:car_lyrics/models/lyrics.dart';
import 'package:car_lyrics/providers/player_provider.dart';
import 'package:car_lyrics/screens/reload_lyrics_button.dart';
import 'package:car_lyrics/services/lyrics/lyrics_provider.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../support/fakes.dart';

/// Conta le richieste: e' l'unica cosa che questi test devono vedere.
class _ContaRichieste implements LyricsProvider {
  int calls = 0;

  @override
  String get name => 'conta';

  @override
  Future<Lyrics?> fetch(LyricsQuery query) async {
    calls++;
    return syncedLyrics;
  }
}

void main() {
  setUp(() {
    loadTestEnv();
    seedTokens();
  });

  final creati = <PlayerProvider>[];

  void testPulsante(
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

  Future<void> pumpPulsante(
    WidgetTester tester, {
    required _ContaRichieste lyrics,
    bool conTraccia = true,
  }) async {
    final api = FakeSpotifyApi();
    if (!conTraccia) api.onPlayback = (_) => http.Response('', 204);
    final player = buildPlayerProvider(api, lyrics: lyrics);
    creati.add(player);

    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerProvider>.value(
        value: player,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: ReloadLyricsButton())),
        ),
      ),
    );

    for (var i = 0; i < 20; i++) {
      if (player.status == ConnectionStatus.connected &&
          player.lyricsStatus != LyricsStatus.loading) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testPulsante('ricarica il testo della traccia in corso', (tester) async {
    final lyrics = _ContaRichieste();
    await pumpPulsante(tester, lyrics: lyrics);
    expect(lyrics.calls, 1);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Il punto del pulsante: la fonte viene riconsultata anche se il testo e'
    // gia' a schermo. Senza, rimediare a un testo sbagliato vorrebbe dire
    // svuotare i dati dell'app.
    expect(lyrics.calls, 2);
  });

  testPulsante('senza niente in riproduzione non compare', (tester) async {
    await pumpPulsante(tester, lyrics: _ContaRichieste(), conTraccia: false);

    expect(find.byIcon(Icons.refresh), findsNothing);
  });
}
