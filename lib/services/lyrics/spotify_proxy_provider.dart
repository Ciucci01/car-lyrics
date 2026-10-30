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

  /// Risolto ad ogni richiesta, non una volta sola alla costruzione:
  /// l'indirizzo e' un'impostazione dell'app e puo' comparire, cambiare o
  /// sparire mentre l'app e' aperta.
  final String Function() baseUrl;

  /// Valore dell'header `Authorization`, risolto anch'esso ad ogni richiesta;
  /// `null` se il proxy non chiede autenticazione.
  final String? Function() authorization;
  final http.Client _client;

  SpotifyProxyProvider({
    required this.baseUrl,
    String? Function()? authorization,
    http.Client? client,
  }) : authorization = authorization ?? (() => null),
       _client = client ?? http.Client();

  @override
  String get name => 'spotify-proxy';

  @override
  Future<Lyrics?> fetch(LyricsQuery query) async {
    final base = baseUrl().trim();
    // Senza indirizzo non c'e' niente da chiedere. Vale come "non ce l'ho" e
    // non come una caduta: la catena resta completa e puo' scrivere in
    // cache, esattamente come quando il proxy non era proprio in lista.
    if (base.isEmpty) return null;

    // Uri.replace normalizza lo slash tra host e query string e fa
    // l'URL-encoding del trackId: l'interpolazione diretta rompeva entrambe
    // le cose se l'indirizzo impostato aveva uno slash finale.
    final uri = Uri.parse(
      base,
    ).replace(queryParameters: {'trackid': query.trackId});
    final auth = authorization();
    final response = await _client
        .get(uri, headers: {if (auth != null) 'Authorization': auth})
        .timeout(_timeout);

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
