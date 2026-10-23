import 'package:car_play/screens/track_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/marquee.dart';

/// La decisione si prova da sola, senza montare Marquee: Marquee pianta nel
/// suo initState un timer che dispose non annulla, e il test lo segnalerebbe
/// come pendente. E' la stessa ragione per cui PlayerScreen non si monta.
void main() {
  group('serveMarquee', () {
    test('un titolo corto ci sta', () {
      expect(TrackTitle.serveMarquee('Numb', 300), isFalse);
    });

    test('un titolo lungo non ci sta', () {
      expect(
        TrackTitle.serveMarquee('Everything In Its Right Place', 60),
        isTrue,
      );
    });

    test('lo stesso titolo dipende dalla larghezza', () {
      const titolo = 'Bohemian Rhapsody';

      expect(TrackTitle.serveMarquee(titolo, 400), isFalse);
      expect(TrackTitle.serveMarquee(titolo, 80), isTrue);
    });

    test('testo vuoto non scorre: Marquee lo rifiuterebbe', () {
      expect(TrackTitle.serveMarquee('', 1), isFalse);
    });

    test('il testo ingrandito dal sistema puo far sforare un titolo corto', () {
      // "Numb" misura 64 punti con questo stile.
      const titolo = 'Numb';
      const stretta = 80.0;

      expect(TrackTitle.serveMarquee(titolo, stretta), isFalse);
      expect(
        TrackTitle.serveMarquee(titolo, stretta, const TextScaler.linear(2)),
        isTrue,
      );
    });
  });

  testWidgets('un titolo che ci sta rende un Text, non un Marquee', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 22,
              child: TrackTitle(text: 'Numb', trackId: 't1'),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Marquee), findsNothing);
    expect(find.text('Numb'), findsOneWidget);
  });
}
