import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/lyrics.dart';
import 'lyrics_provider.dart';

/// Adattatore per i deployment di akashrchandran/spotify-lyrics-api.
///
/// Restituisce la forma interna di Spotify, la stessa che Lyrics.fromJson
/// gia' sa leggere: qui non c'e' conversione, solo trasporto.
class SpotifyProxyProvider implements LyricsProvider {
  static const _timeout = Duration(seconds: 5);

  final String baseUrl;
  final http.Client _client;

  SpotifyProxyProvider({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  @override
  String get name => 'spotify-proxy';

  @override
  Future<Lyrics?> fetch(LyricsQuery query) async {
    // Uri.replace normalizza lo slash tra host e query string e fa
    // l'URL-encoding del trackId: l'interpolazione diretta rompeva entrambe
    // le cose se LYRICS_BASE_URL aveva uno slash finale.
    final uri = Uri.parse(
      baseUrl,
    ).replace(queryParameters: {'trackid': query.trackId});
    final response = await _client.get(uri).timeout(_timeout);

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw LyricsProviderException('$name: HTTP ${response.statusCode}');
    }

    final lyrics = Lyrics.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    return lyrics.isUsable ? lyrics : null;
  }
}
