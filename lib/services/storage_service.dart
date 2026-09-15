import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/spotify_tokens.dart';
import '../utils/app_log.dart';

class TokenStorage {
  /// Una chiave sola per tutti e tre i valori, non tre chiavi separate: tre
  /// scritture indipendenti possono riuscirne due, lasciando un access token
  /// nuovo accanto a un refresh token e a una scadenza vecchi. Quella terna
  /// mista e' indistinguibile da una buona in lettura, e porta a rinnovare
  /// con un refresh token che Spotify ha gia' ruotato.
  static const _tokensKey = 'spotify_tokens';

  /// Chiavi dell'archivio in chiaro usato dalle versioni precedenti.
  static const _legacyAccessTokenKey = 'access_token';
  static const _legacyRefreshTokenKey = 'refresh_token';
  static const _legacyExpiryDateKey = 'expiry_date';

  /// Le opzioni di default cifrano con una chiave avvolta nel Keystore. Niente
  /// biometria: metterebbe un'impronta davanti all'avvio di un'app che deve
  /// partire con il telefono nel supporto.
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  /// Restituisce `false` se non si e' riusciti a persistere. Chi chiama
  /// decide cosa farne: i token restano validi in memoria, quindi una
  /// sessione che per il resto funziona non deve morire per questo.
  Future<bool> save(SpotifyTokens tokens) async {
    try {
      await _secure.write(
        key: _tokensKey,
        value: jsonEncode({
          'access': tokens.accessToken,
          'refresh': tokens.refreshToken,
          'expiry': tokens.expiresAt.millisecondsSinceEpoch,
        }),
      );
      return true;
    } catch (error, stackTrace) {
      logError('Salvataggio dei token fallito', error, stackTrace);
      return false;
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

  /// Restituisce `false` se la credenziale potrebbe essere ancora sul
  /// dispositivo. Chi chiama non deve annunciare un logout che non e'
  /// avvenuto: al riavvio la sessione ripartirebbe da sola.
  Future<bool> clear() async {
    var cleared = true;

    try {
      await _secure.delete(key: _tokensKey);
    } catch (error, stackTrace) {
      logError('Cancellazione dei token fallita', error, stackTrace);
      cleared = false;
    }

    // In un try suo: svuotare il vecchio archivio in chiaro e' proprio la
    // cosa che non deve dipendere dalla salute di quello nuovo.
    try {
      await _clearPreferences();
    } catch (error, stackTrace) {
      logError('Pulizia del vecchio archivio fallita', error, stackTrace);
      cleared = false;
    }

    return cleared;
  }

  Future<SpotifyTokens?> _readSecure() async {
    final raw = await _secure.read(key: _tokensKey);
    if (raw == null) return null;

    final json = jsonDecode(raw) as Map<String, dynamic>;
    final accessToken = json['access'] as String?;
    final refreshToken = json['refresh'] as String?;
    final expiryDate = (json['expiry'] as num?)?.toInt();
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
  /// primo avvio in cui l'archivio sicuro e' vuoto.
  ///
  /// L'ordine conta: si scrive per prima cosa, e si svuota il vecchio
  /// archivio solo a scrittura confermata. Cancellare per primi significa,
  /// su un dispositivo dove il Keystore legge ma non scrive, restare senza
  /// nessuna delle due copie: la sessione dura fino alla chiusura e poi
  /// l'utente rifa' il login ad ogni avvio, per sempre e senza un errore.
  Future<SpotifyTokens?> _migrateFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_legacyAccessTokenKey);
    final refreshToken = prefs.getString(_legacyRefreshTokenKey);
    final expiryDate = prefs.getInt(_legacyExpiryDateKey);

    if (accessToken == null || refreshToken == null || expiryDate == null) {
      // Un residuo incompleto e' inutilizzabile e va buttato comunque, o
      // resterebbe in chiaro per sempre.
      await _clearPreferences();
      return null;
    }

    final tokens = SpotifyTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiryDate),
    );
    // Se la scrittura non riesce, il vecchio archivio resta dov'e': la
    // sessione funziona lo stesso e al prossimo avvio si ritenta.
    if (await save(tokens)) await _clearPreferences();
    return tokens;
  }

  Future<void> _clearPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyAccessTokenKey);
    await prefs.remove(_legacyRefreshTokenKey);
    await prefs.remove(_legacyExpiryDateKey);
  }
}
