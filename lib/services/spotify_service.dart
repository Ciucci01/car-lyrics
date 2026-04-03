import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class SpotifyService {
  static String? _accessToken;
  static String? _refreshToken;

  static void initialize(String accessToken, String refreshToken) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  static Future<http.Response> _request(
    String method,
    String url, {
    Map<String, dynamic>? body,
  }) async {
    Future<http.Response> send() async {
      final uri = Uri.parse(url);
      final headers = {
        "Authorization": "Bearer $_accessToken",
        "Content-Type": "application/json",
      };
      if (method == 'GET') {
        return http.get(uri, headers: headers);
      } else if (method == 'POST') {
        return http.post(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      } else if (method == 'PUT') {
        return http.put(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      }
      throw Exception("Unsupported method $method");
    }

    var response = await send();

    // Se otteniamo 401, proviamo a refreshare il token
    if (response.statusCode == 401 && _refreshToken != null) {
      print("Access token scaduto, provo il refresh...");
      final tokens = await SpotifyAuth.refreshTokens(_refreshToken!);
      if (tokens != null) {
        _accessToken = tokens['access_token'];
        _refreshToken = tokens['refresh_token'];
        // Riprova la richiesta originale con il nuovo token
        response = await send();
      }
    }

    return response;
  }

  static Future<Map<String, dynamic>?> _get(String url) async {
    final response = await _request('GET', url);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    if (response.statusCode == 204) {
      return null; // Nessun contenuto
    }
    print("GET $url failed: ${response.statusCode} ${response.body}");
    return null;
  }

  static Future<void> _put(String url, [Map<String, dynamic>? body]) async {
    final response = await _request('PUT', url, body: body);
    if (response.statusCode != 204 && response.statusCode != 200) {
      print("PUT $url failed: ${response.statusCode} ${response.body}");
    }
  }

  static Future<void> _post(String url, [Map<String, dynamic>? body]) async {
    final response = await _request('POST', url, body: body);
    if (response.statusCode != 204 &&
        response.statusCode != 202 &&
        response.statusCode != 200) {
      print("POST $url failed: ${response.statusCode} ${response.body}");
    }
  }

  /// Ottiene la traccia corrente
  static Future<String?> getCurrentTrackId() async {
    final playback = await _get(
      "https://api.spotify.com/v1/me/player/currently-playing",
    );
    return playback?["item"]?["id"];
  }

  /// Ottiene dettagli completi della riproduzione
  static Future<Map<String, dynamic>?> getCurrentPlayback() async {
    final playback = await _get(
      "https://api.spotify.com/v1/me/player/currently-playing",
    );
    if (playback == null) return null;

    return {
      'id': playback["item"]?["id"],
      'name': playback["item"]?["name"],
      'artists':
          (playback["item"]?["artists"] as List?)
              ?.map((a) => a["name"])
              .toList() ??
          [],
      'album_image': (playback["item"]?["album"]?["images"] as List?)?.isNotEmpty == true
          ? playback["item"]["album"]["images"][0]["url"]
          : null,
      'duration_ms': playback["item"]?["duration_ms"],
      'is_playing': playback["is_playing"],
      'progress_ms': playback["progress_ms"],
    };
  }

  /// Metti la prossima traccia
  static Future<void> next() async {
    await _post("https://api.spotify.com/v1/me/player/next");
  }

  /// Metti la traccia precedente
  static Future<void> previous() async {
    await _post("https://api.spotify.com/v1/me/player/previous");
  }

  /// Avvia la riproduzione di un brano specifico
  static Future<void> play(String trackId) async {
    await _put("https://api.spotify.com/v1/me/player/play", {
      "uris": ["spotify:track:$trackId"],
    });
  }

  /// Metti in pausa
  static Future<void> pause() async {
    await _put("https://api.spotify.com/v1/me/player/pause");
  }

  /// Riprendi la riproduzione
  static Future<void> resume() async {
    await _put("https://api.spotify.com/v1/me/player/play");
  }

  /// Ottieni la posizione corrente
  static Future<int?> getPosition() async {
    final playback = await _get(
      "https://api.spotify.com/v1/me/player/currently-playing",
    );
    return playback?["progress_ms"];
  }

  /// Verifica se sta suonando
  static Future<bool> getIsPlaying() async {
    final playback = await _get(
      "https://api.spotify.com/v1/me/player/currently-playing",
    );
    return playback?["is_playing"] ?? false;
  }

  /// Vai ad una posizione precisa
  static Future<void> seekToPosition(int positionMs) async {
    final url =
        "https://api.spotify.com/v1/me/player/seek?position_ms=$positionMs";
    await _put(url);
  }
}

