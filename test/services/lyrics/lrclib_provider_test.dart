// test/services/lyrics/lrclib_provider_test.dart
import 'package:car_play/services/lyrics/lrclib_provider.dart';
import 'package:car_play/services/lyrics/lyrics_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _query = LyricsQuery(
  trackId: 'abc123',
  title: 'Rolling in the Deep',
  primaryArtist: 'Adele',
  albumName: '21',
  durationMs: 228400,
);

void main() {
  test('cerca per metadati con la durata in secondi', () async {
    late Uri requested;
    final provider = LrclibProvider(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          '{"instrumental":false,'
          '"syncedLyrics":"[00:05.15] Prima\\n[00:09.74] Seconda",'
          '"plainLyrics":"Prima\\nSeconda"}',
          200,
        );
      }),
    );

    final lyrics = await provider.fetch(_query);

    expect(requested.queryParameters['track_name'], 'Rolling in the Deep');
    expect(requested.queryParameters['artist_name'], 'Adele');
    expect(requested.queryParameters['album_name'], '21');
    expect(requested.queryParameters['duration'], '228');
    expect(lyrics!.isSynced, isTrue);
    expect(lyrics.lines.first.startTime, 5150);
  });

  test('ripiega sul testo semplice come non sincronizzato', () async {
    final provider = LrclibProvider(
      client: MockClient(
        (_) async => http.Response(
          '{"instrumental":false,"syncedLyrics":null,'
          '"plainLyrics":"Prima\\nSeconda"}',
          200,
        ),
      ),
    );

    final lyrics = await provider.fetch(_query);

    expect(lyrics!.syncType, 'UNSYNCED');
    expect(lyrics.isSynced, isFalse);
    expect(lyrics.lines.length, 2);
  });

  test('segnala i brani strumentali', () async {
    final provider = LrclibProvider(
      client: MockClient(
        (_) async => http.Response(
          '{"instrumental":true,"syncedLyrics":null,"plainLyrics":null}',
          200,
        ),
      ),
    );

    final lyrics = await provider.fetch(_query);

    expect(lyrics!.instrumental, isTrue);
    expect(lyrics.lines, isEmpty);
  });

  test('restituisce null su 404', () async {
    final provider = LrclibProvider(
      client: MockClient((_) async => http.Response('{}', 404)),
    );

    expect(await provider.fetch(_query), isNull);
  });

  test('solleva su errore del server', () async {
    final provider = LrclibProvider(
      client: MockClient((_) async => http.Response('boom', 503)),
    );

    expect(
      () => provider.fetch(_query),
      throwsA(isA<LyricsProviderException>()),
    );
  });
}
