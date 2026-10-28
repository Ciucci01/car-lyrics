import 'package:car_lyrics/services/lyrics/lrc_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converte i timestamp in millisecondi', () {
    final lines = parseLrc('[00:05.15] Prima riga\n[01:02.40] Seconda riga');

    expect(lines.length, 2);
    expect(lines[0].startTime, 5150);
    expect(lines[0].words, 'Prima riga');
    expect(lines[1].startTime, 62400);
  });

  test('salta i tag di metadati', () {
    final lines = parseLrc('[ar:Adele]\n[length:03:48]\n[00:01.00] Testo');

    expect(lines.length, 1);
    expect(lines[0].words, 'Testo');
  });

  test('espande le righe con piu timestamp e le riordina', () {
    final lines = parseLrc('[00:30.00][00:10.00] Ritornello');

    expect(lines.map((l) => l.startTime).toList(), [10000, 30000]);
    expect(lines.every((l) => l.words == 'Ritornello'), isTrue);
  });

  test('gestisce i centesimi assenti o a tre cifre', () {
    final lines = parseLrc('[00:02] A\n[00:03.7] B\n[00:04.125] C');

    expect(lines.map((l) => l.startTime).toList(), [2000, 3700, 4125]);
  });

  test('restituisce vuoto su un corpo senza timestamp', () {
    expect(parseLrc('solo testo\nsenza tempi'), isEmpty);
  });

  test('conserva l\'ordine sorgente per righe con lo stesso timestamp', () {
    // Testo LRC con molte righe (40+) allo stesso timestamp, per superare
    // la soglia di stabilita' di List.sort in Dart. Verifica che l'ordine
    // sorgente sia preservato: senza stabilita', l'ordine relativo
    // entrerebbe casuale una volta superati ~32-64 elementi.
    final lines = parseLrc(
      '[00:00.00] Line 1\n'
      '[00:00.00] Line 2\n'
      '[00:00.00] Line 3\n'
      '[00:00.00] Line 4\n'
      '[00:00.00] Line 5\n'
      '[00:00.00] Line 6\n'
      '[00:00.00] Line 7\n'
      '[00:00.00] Line 8\n'
      '[00:00.00] Line 9\n'
      '[00:00.00] Line 10\n'
      '[00:00.00] Line 11\n'
      '[00:00.00] Line 12\n'
      '[00:00.00] Line 13\n'
      '[00:00.00] Line 14\n'
      '[00:00.00] Line 15\n'
      '[00:00.00] Line 16\n'
      '[00:00.00] Line 17\n'
      '[00:00.00] Line 18\n'
      '[00:00.00] Line 19\n'
      '[00:00.00] Line 20\n'
      '[00:00.00] Line 21\n'
      '[00:00.00] Line 22\n'
      '[00:00.00] Line 23\n'
      '[00:00.00] Line 24\n'
      '[00:00.00] Line 25\n'
      '[00:00.00] Line 26\n'
      '[00:00.00] Line 27\n'
      '[00:00.00] Line 28\n'
      '[00:00.00] Line 29\n'
      '[00:00.00] Line 30\n'
      '[00:00.00] Line 31\n'
      '[00:00.00] Line 32\n'
      '[00:00.00] Line 33\n'
      '[00:00.00] Line 34\n'
      '[00:00.00] Line 35\n'
      '[00:00.00] Line 36\n'
      '[00:00.00] Line 37\n'
      '[00:00.00] Line 38\n'
      '[00:00.00] Line 39\n'
      '[00:00.00] Line 40\n',
    );

    expect(lines.length, 40);
    expect(lines.every((l) => l.startTime == 0), isTrue);

    // Verifica che l'ordine sorgente sia preservato: ogni riga deve
    // corrispondere al suo numero di riga.
    for (int i = 0; i < 40; i++) {
      expect(lines[i].words, 'Line ${i + 1}');
    }
  });
}
