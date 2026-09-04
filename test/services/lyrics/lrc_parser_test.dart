import 'package:car_play/services/lyrics/lrc_parser.dart';
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
}
