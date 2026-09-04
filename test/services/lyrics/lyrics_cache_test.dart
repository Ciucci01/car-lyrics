import 'dart:io';

import 'package:car_play/models/lyrics.dart';
import 'package:car_play/services/lyrics/lyrics_cache.dart';
import 'package:flutter_test/flutter_test.dart';

const _lyrics = Lyrics(
  error: false,
  syncType: 'LINE_SYNCED',
  lines: [LyricLine(startTimeMs: '900', words: 'Ciao', endTimeMs: '0')],
);

void main() {
  late Directory directory;
  late LyricsCache cache;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('lyrics_cache_test');
    cache = LyricsCache(directory);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('restituisce null quando non sa niente della traccia', () async {
    expect(await cache.read('mai_visto'), isNull);
  });

  test('rilegge un testo salvato', () async {
    await cache.writeFound('t1', _lyrics);

    final hit = await cache.read('t1');

    expect(hit, isNotNull);
    expect(hit!.lyrics!.lines.single.words, 'Ciao');
  });

  test('ricorda un esito negativo ancora fresco', () async {
    await cache.writeMissing('t2');

    final hit = await cache.read('t2');

    expect(hit, isNotNull);
    expect(hit!.lyrics, isNull);
  });

  test('dimentica un esito negativo scaduto', () async {
    await cache.writeMissing('t3');
    final file = File('${directory.path}/t3.json');
    // La scadenza viaggia nel contenuto, non nel filesystem: si riscrive la
    // data di salvataggio a otto giorni fa.
    final stale = file.readAsStringSync().replaceFirst(
      RegExp(r'"cachedAt":\d+'),
      '"cachedAt":${DateTime.now().subtract(const Duration(days: 8)).millisecondsSinceEpoch}',
    );
    file.writeAsStringSync(stale);

    expect(await cache.read('t3'), isNull);
  });

  test('sfratta la voce piu vecchia oltre il tetto', () async {
    final small = LyricsCache(directory, maxEntries: 2);

    await small.writeFound('a', _lyrics);
    await Future.delayed(const Duration(milliseconds: 10));
    await small.writeFound('b', _lyrics);
    await Future.delayed(const Duration(milliseconds: 10));
    await small.writeFound('c', _lyrics);

    expect(await small.read('a'), isNull);
    expect(await small.read('c'), isNotNull);
  });
}
