import 'package:car_play/models/lyrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sopravvive al giro completo su JSON', () {
    const original = Lyrics(
      error: false,
      syncType: 'LINE_SYNCED',
      lines: [LyricLine(startTimeMs: '900', words: 'Ciao', endTimeMs: '0')],
    );

    final restored = Lyrics.fromJson(original.toJson());

    expect(restored.syncType, 'LINE_SYNCED');
    expect(restored.instrumental, isFalse);
    expect(restored.lines.single.startTime, 900);
    expect(restored.lines.single.words, 'Ciao');
  });

  test('conserva il flag strumentale', () {
    const original = Lyrics(
      error: false,
      syncType: 'UNSYNCED',
      lines: [],
      instrumental: true,
    );

    expect(Lyrics.fromJson(original.toJson()).instrumental, isTrue);
  });

  test('un brano strumentale non e utilizzabile come testo', () {
    const lyrics = Lyrics(
      error: false,
      syncType: 'UNSYNCED',
      lines: [],
      instrumental: true,
    );

    expect(lyrics.isUsable, isFalse);
  });
}
