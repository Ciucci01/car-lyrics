import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SpotifyService {
  static const String clientId = '1b41b88b438c4103a5cb6e75d3f6e004';
  static const String clientSecret = '0fc0f0bac5244630b92c60f7651d5aad';

  static String? _accessToken;
  static String? _refreshToken;

  static void initialize(String accessToken, String refreshToken) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  static Future<Map<String, dynamic>?> _get(String url) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {"Authorization": "Bearer $_accessToken"},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    if (response.statusCode == 204) {
      return null; // Nessun contenuto
    }
    throw Exception("GET $url failed: ${response.statusCode} ${response.body}");
  }

  static Future<void> _put(String url, [Map<String, dynamic>? body]) async {
    final response = await http.put(
      Uri.parse(url),
      headers: {
        "Authorization": "Bearer $_accessToken",
        "Content-Type": "application/json",
      },
      body: body != null ? jsonEncode(body) : null,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(
        "PUT $url failed: ${response.statusCode} ${response.body}",
      );
    }
  }

  static Future<void> _post(String url, [Map<String, dynamic>? body]) async {
    final response = await http.post(
      Uri.parse(url),
      headers: {
        "Authorization": "Bearer $_accessToken",
        "Content-Type": "application/json",
      },
      body: body != null ? jsonEncode(body) : null,
    );
    if (response.statusCode != 204 &&
        response.statusCode != 202 &&
        response.statusCode != 200) {
      throw Exception(
        "POST $url failed: ${response.statusCode} ${response.body}",
      );
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
