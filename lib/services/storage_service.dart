import 'package:shared_preferences/shared_preferences.dart';

import '../models/spotify_tokens.dart';

class TokenStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _expiryDateKey = 'expiry_date';

  Future<void> save(SpotifyTokens tokens) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, tokens.accessToken);
    await prefs.setString(_refreshTokenKey, tokens.refreshToken);
    await prefs.setInt(_expiryDateKey, tokens.expiresAt.millisecondsSinceEpoch);
  }

  Future<SpotifyTokens?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_accessTokenKey);
    final refreshToken = prefs.getString(_refreshTokenKey);
    final expiryDate = prefs.getInt(_expiryDateKey);
    if (accessToken == null || refreshToken == null || expiryDate == null) {
      return null;
    }

    return SpotifyTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiryDate),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_expiryDateKey);
  }
}
