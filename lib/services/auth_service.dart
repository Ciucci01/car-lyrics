import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'storage_service.dart';

class SpotifyAuth {
  static String get clientId => dotenv.env['SPOTIFY_CLIENT_ID'] ?? '';
  static String get clientSecret => dotenv.env['SPOTIFY_CLIENT_SECRET'] ?? '';

  static Future<Map<String, String>?> refreshTokens(String refreshToken) async {
    final basicAuth = base64.encode(utf8.encode('$clientId:$clientSecret'));

    final response = await http.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: {
        'Authorization': 'Basic $basicAuth',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final newAccessToken = json['access_token'];
      // Spotify potrebbe restituire un nuovo refresh_token
      final newRefreshToken = json['refresh_token'] ?? refreshToken;
      final expiresIn = json['expires_in'] ?? 3600;

      // salva i nuovi token
      await TokenStorage.saveTokens(newAccessToken, newRefreshToken, expiresIn);

      return {
        'access_token': newAccessToken,
        'refresh_token': newRefreshToken,
      };
    } else {
      print("Errore refresh token: ${response.statusCode} ${response.body}");
      return null;
    }
  }
}
