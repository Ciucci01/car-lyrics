import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static Future<void> saveTokens(
    String accessToken,
    String refreshToken,
    int expiresIn,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final expiryDate =
        DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000);
    await prefs.setString('access_token', accessToken);
    await prefs.setString('refresh_token', refreshToken);
    await prefs.setInt('expiry_date', expiryDate);
  }

  static Future<Map<String, dynamic>?> loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    final refreshToken = prefs.getString('refresh_token');
    final expiryDate = prefs.getInt('expiry_date');
    if (accessToken == null || refreshToken == null || expiryDate == null) {
      return null;
    }
    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expiry_date': expiryDate,
    };
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
