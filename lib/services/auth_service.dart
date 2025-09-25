import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:convert' show utf8, base64;

import 'storage_service.dart';

class SpotifyAuth {
  static const clientId = '1b41b88b438c4103a5cb6e75d3f6e004';
  static const clientSecret = '0fc0f0bac5244630b92c60f7651d5aad';

  static Future<String?> refreshAccessToken(String refreshToken) async {
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
      final expiresIn = json['expires_in'] ?? 3600;

      // aggiorna solo access token, refresh rimane lo stesso
      await TokenStorage.saveTokens(newAccessToken, refreshToken, expiresIn);

      return newAccessToken;
    } else {
      print("Errore refresh token: ${response.statusCode} ${response.body}");
      return null;
    }
  }
}
