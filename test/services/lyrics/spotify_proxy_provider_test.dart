import 'package:car_lyrics/services/lyrics/lyrics_provider.dart';
import 'package:car_lyrics/services/lyrics/spotify_proxy_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _query = LyricsQuery(
  trackId: 'abc123',
  title: 'Rolling in the Deep',
  primaryArtist: 'Adele',
  albumName: '21',
  durationMs: 228000,
);

void main() {
  test('senza indirizzo non manda niente e vale come "non ce l\'ho"', () async {
    var chiamate = 0;
    final provider = SpotifyProxyProvider(
      baseUrl: () => '   ',
      client: MockClient((request) async {
        chiamate++;
        return http.Response('', 200);
      }),
    );

    // null e non un'eccezione: senza indirizzo la catena resta completa e
    // puo' scrivere in cache, come quando il proxy non era proprio in lista.
    expect(await provider.fetch(_query), isNull);
    expect(chiamate, 0);
  });

  test('un indirizzo che compare dopo viene usato subito', () async {
    var base = '';
    final provider = SpotifyProxyProvider(
      baseUrl: () => base,
      client: MockClient(
        (request) async => http.Response(
          '{"error":false,"syncType":"LINE_SYNCED",'
          '"lines":[{"startTimeMs":"0","words":"Uno","endTimeMs":"0"}]}',
          200,
        ),
      ),
    );
    expect(await provider.fetch(_query), isNull);

    base = 'https://proxy.example';

    expect((await provider.fetch(_query))?.lines.single.words, 'Uno');
  });

  test('interroga per trackId e converte la risposta', () async {
    late Uri requested;
    final provider = SpotifyProxyProvider(
      baseUrl: () => 'https://proxy.example',
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          '{"error":false,"syncType":"LINE_SYNCED",'
          '"lines":[{"startTimeMs":"960","words":"Uno","endTimeMs":"0"}]}',
          200,
        );
      }),
    );

    final lyrics = await provider.fetch(_query);

    expect(requested.queryParameters['trackid'], 'abc123');
    expect(lyrics!.lines.single.words, 'Uno');
    expect(lyrics.isSynced, isTrue);
  });

  test('restituisce null quando la fonte dichiara di non averlo', () async {
    final provider = SpotifyProxyProvider(
      baseUrl: () => 'https://proxy.example',
      client: MockClient(
        (_) async => http.Response('{"error":true,"lines":[]}', 200),
      ),
    );

    expect(await provider.fetch(_query), isNull);
  });

  test('restituisce null su 404 della fonte', () async {
    final provider = SpotifyProxyProvider(
      baseUrl: () => 'https://proxy.example',
      client: MockClient((_) async => http.Response('', 404)),
    );

    expect(await provider.fetch(_query), isNull);
  });

  test('solleva su errore del server', () async {
    final provider = SpotifyProxyProvider(
      baseUrl: () => 'https://proxy.example',
      client: MockClient((_) async => http.Response('boom', 500)),
    );

    expect(
      () => provider.fetch(_query),
      throwsA(isA<LyricsProviderException>()),
    );
  });
}
