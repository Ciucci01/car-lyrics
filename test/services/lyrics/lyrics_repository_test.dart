// test/services/lyrics/lyrics_repository_test.dart
import 'dart:io';

import 'package:car_play/models/lyrics.dart';
import 'package:car_play/services/lyrics/lyrics_cache.dart';
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

const _instrumental = Lyrics(
  error: false,
  syncType: 'LINE_SYNCED',
  lines: [],
  instrumental: true,
);

const _badWithError = Lyrics(
  error: true,
  syncType: 'LINE_SYNCED',
  lines: [LyricLine(startTimeMs: '900', words: 'Testo', endTimeMs: '0')],
);

const _badWithoutLines = Lyrics(
  error: false,
  syncType: 'LINE_SYNCED',
  lines: [],
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

class _FakeCache implements LyricsCache {
  final Map<String, CacheHit?> storage = {};
  final List<String> writeFoundCalls = [];
  final List<String> writeMissingCalls = [];

  @override
  Directory get directory => throw UnimplementedError();

  @override
  int get maxEntries => throw UnimplementedError();

  @override
  Future<CacheHit?> read(String trackId) async => storage[trackId];

  @override
  Future<void> writeFound(String trackId, Lyrics lyrics) async {
    writeFoundCalls.add(trackId);
    storage[trackId] = CacheHit(lyrics);
  }

  @override
  Future<void> writeMissing(String trackId) async {
    writeMissingCalls.add(trackId);
    storage[trackId] = const CacheHit(null);
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

  test('un hit positivo dalla cache non consulta i provider', () async {
    final cache = _FakeCache();
    cache.storage[_query.trackId] = const CacheHit(_synced);
    final provider = _FakeProvider(result: _synced);

    final repository = LyricsRepository(providers: [provider], cache: cache);

    final lyrics = await repository.lyricsFor(_query);

    expect(lyrics, _synced);
    expect(provider.calls, 0);
  });

  test(
    'un hit negativo dalla cache restituisce null senza consultare',
    () async {
      final cache = _FakeCache();
      cache.storage[_query.trackId] = const CacheHit(null);
      final provider = _FakeProvider(result: _synced);

      final repository = LyricsRepository(providers: [provider], cache: cache);

      final lyrics = await repository.lyricsFor(_query);

      expect(lyrics, isNull);
      expect(provider.calls, 0);
    },
  );

  test('un risultato sincronizzato viene scritto in cache', () async {
    final cache = _FakeCache();
    final repository = LyricsRepository(
      providers: [_FakeProvider(result: _synced)],
      cache: cache,
    );

    await repository.lyricsFor(_query);

    expect(cache.writeFoundCalls, [_query.trackId]);
  });

  test('nessun risultato dalla catena viene scritto come mancante', () async {
    final cache = _FakeCache();
    final repository = LyricsRepository(
      providers: [_FakeProvider(), _FakeProvider()],
      cache: cache,
    );

    await repository.lyricsFor(_query);

    expect(cache.writeMissingCalls, [_query.trackId]);
  });

  test('un brano strumentale viene restituito', () async {
    final repository = LyricsRepository(
      providers: [_FakeProvider(result: _instrumental)],
    );

    final lyrics = await repository.lyricsFor(_query);

    expect(lyrics?.instrumental, isTrue);
  });

  test('il non sincronizzato vince su uno strumentale', () async {
    final repository = LyricsRepository(
      providers: [
        _FakeProvider(result: _unsynced),
        _FakeProvider(result: _instrumental),
      ],
    );

    final lyrics = await repository.lyricsFor(_query);

    expect(lyrics!.lines.single.words, 'Semplice');
    expect(lyrics.instrumental, isFalse);
  });

  test('uno strumentale viene scritto in cache nel fallback', () async {
    final cache = _FakeCache();
    final repository = LyricsRepository(
      providers: [_FakeProvider(result: _instrumental)],
      cache: cache,
    );

    await repository.lyricsFor(_query);

    expect(cache.writeFoundCalls, [_query.trackId]);
  });

  test(
    'un testo con error: true viene ignorato e non avvelena la cache',
    () async {
      final cache = _FakeCache();
      final repository = LyricsRepository(
        providers: [
          _FakeProvider(result: _badWithError),
          _FakeProvider(result: _synced),
        ],
        cache: cache,
      );

      final lyrics = await repository.lyricsFor(_query);

      expect(lyrics, _synced);
      expect(cache.writeFoundCalls, [_query.trackId]);
    },
  );

  test('un testo senza righe viene ignorato come inutilizzabile', () async {
    final repository = LyricsRepository(
      providers: [
        _FakeProvider(result: _badWithoutLines),
        _FakeProvider(result: _synced),
      ],
    );

    final lyrics = await repository.lyricsFor(_query);

    expect(lyrics, _synced);
  });
}
