// test/services/lyrics/lyrics_repository_test.dart
import 'package:car_play/models/lyrics.dart';
import 'package:car_play/services/lyrics/lyrics_provider.dart';
import 'package:car_play/services/lyrics/lyrics_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _query = LyricsQuery(
  trackId: 'abc123',
  title: 'Rolling in the Deep',
  primaryArtist: 'Adele',
  albumName: '21',
  durationMs: 228000,
);

const _synced = Lyrics(
  error: false,
  syncType: 'LINE_SYNCED',
  lines: [
    LyricLine(startTimeMs: '900', words: 'Sincronizzato', endTimeMs: '0'),
  ],
);

const _unsynced = Lyrics(
  error: false,
  syncType: 'UNSYNCED',
  lines: [LyricLine(startTimeMs: '0', words: 'Semplice', endTimeMs: '0')],
);

class _FakeProvider implements LyricsProvider {
  final Lyrics? result;
  final Object? error;
  int calls = 0;

  _FakeProvider({this.result, this.error});

  @override
  String get name => 'fake';

  @override
  Future<Lyrics?> fetch(LyricsQuery query) async {
    calls++;
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  test('si ferma alla prima fonte sincronizzata', () async {
    final second = _FakeProvider(result: _synced);
    final repository = LyricsRepository(
      providers: [
        _FakeProvider(result: _synced),
        second,
      ],
    );

    final lyrics = await repository.lyricsFor(_query);

    expect(lyrics!.isSynced, isTrue);
    expect(second.calls, 0);
  });

  test(
    'preferisce il sincronizzato che viene dopo un non sincronizzato',
    () async {
      final repository = LyricsRepository(
        providers: [
          _FakeProvider(result: _unsynced),
          _FakeProvider(result: _synced),
        ],
      );

      final lyrics = await repository.lyricsFor(_query);

      expect(lyrics!.lines.single.words, 'Sincronizzato');
    },
  );

  test('ripiega sul non sincronizzato se nessuno ha di meglio', () async {
    final repository = LyricsRepository(
      providers: [
        _FakeProvider(result: _unsynced),
        _FakeProvider(),
      ],
    );

    final lyrics = await repository.lyricsFor(_query);

    expect(lyrics!.lines.single.words, 'Semplice');
  });

  test('un provider rotto non ferma la catena', () async {
    final repository = LyricsRepository(
      providers: [
        _FakeProvider(error: const LyricsProviderException('giu')),
        _FakeProvider(result: _synced),
      ],
    );

    expect((await repository.lyricsFor(_query))!.isSynced, isTrue);
  });

  test('restituisce null se le fonti rispondono di non averlo', () async {
    final repository = LyricsRepository(
      providers: [_FakeProvider(), _FakeProvider()],
    );

    expect(await repository.lyricsFor(_query), isNull);
  });

  test('solleva se ogni fonte e caduta', () async {
    final repository = LyricsRepository(
      providers: [
        _FakeProvider(error: const LyricsProviderException('giu')),
        _FakeProvider(error: const LyricsProviderException('anche')),
      ],
    );

    expect(
      () => repository.lyricsFor(_query),
      throwsA(isA<LyricsProviderException>()),
    );
  });
}
