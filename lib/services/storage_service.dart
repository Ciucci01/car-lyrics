import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/spotify_tokens.dart';
import '../utils/app_log.dart';

class TokenStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _expiryDateKey = 'expiry_date';

  /// Le opzioni di default cifrano con una chiave avvolta nel Keystore. Niente
  /// biometria: metterebbe un'impronta davanti all'avvio di un'app che deve
  /// partire con il telefono nel supporto.
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  /// Un archivio che non scrive non deve far fallire una sessione che per il
  /// resto funziona: i token restano validi in memoria fino alla chiusura.
  Future<void> save(SpotifyTokens tokens) async {
    try {
      await _secure.write(key: _accessTokenKey, value: tokens.accessToken);
      await _secure.write(key: _refreshTokenKey, value: tokens.refreshToken);
      await _secure.write(
        key: _expiryDateKey,
        value: tokens.expiresAt.millisecondsSinceEpoch.toString(),
      );
    } catch (error, stackTrace) {
      logError('Salvataggio dei token fallito', error, stackTrace);
    }
  }

  Future<SpotifyTokens?> load() async {
    try {
      return await _readSecure() ?? await _migrateFromPreferences();
    } catch (error, stackTrace) {
      // Il Keystore puo' diventare illeggibile dopo un ripristino da backup o
      // un wipe delle credenziali del dispositivo: si riparte da un login.
      logError('Lettura dei token fallita', error, stackTrace);
      return null;
    }
  }

  Future<void> clear() async {
    try {
      await _secure.delete(key: _accessTokenKey);
      await _secure.delete(key: _refreshTokenKey);
      await _secure.delete(key: _expiryDateKey);
      await _clearPreferences();
    } catch (error, stackTrace) {
      logError('Cancellazione dei token fallita', error, stackTrace);
    }
  }

  Future<SpotifyTokens?> _readSecure() async {
    final accessToken = await _secure.read(key: _accessTokenKey);
    final refreshToken = await _secure.read(key: _refreshTokenKey);
    final expiryDate = int.tryParse(
      await _secure.read(key: _expiryDateKey) ?? '',
    );
    if (accessToken == null || refreshToken == null || expiryDate == null) {
      return null;
    }

    return SpotifyTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiryDate),
    );
  }

  /// Le installazioni precedenti tenevano i token in chiaro. Si spostano al
  /// primo avvio, cosi' chi aggiorna non deve rifare il login.
  Future<SpotifyTokens?> _migrateFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_accessTokenKey);
    final refreshToken = prefs.getString(_refreshTokenKey);
    final expiryDate = prefs.getInt(_expiryDateKey);

    // Il vecchio archivio si svuota comunque: un residuo incompleto e'
    // inutilizzabile, e resterebbe in chiaro per sempre.
    await _clearPreferences();

    if (accessToken == null || refreshToken == null || expiryDate == null) {
      return null;
    }

    final tokens = SpotifyTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiryDate),
    );
    await save(tokens);
    return tokens;
  }

  Future<void> _clearPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_expiryDateKey);
  }
}
