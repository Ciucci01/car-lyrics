import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lyrics_text_size.dart';
import '../models/proxy_auth.dart';
import '../utils/app_log.dart';

/// Le preferenze di resa, tenute fuori da `PlayerProvider`: li' dentro tutto
/// arriva da Spotify, mentre questa e' una scelta dell'utente sulla propria
/// schermata e ha una persistenza sua.
class SettingsProvider with ChangeNotifier {
  static const _textSizeKey = 'lyrics_text_size';
  static const _proxyUrlKey = 'lyrics_proxy_url';
  static const _proxyAuthKey = 'lyrics_proxy_auth';

  /// Le credenziali del proxy sono un segreto e stanno nel Keystore come i
  /// token Spotify, non in chiaro accanto all'indirizzo.
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  LyricsTextSize _lyricsTextSize = LyricsTextSize.medium;
  String _lyricsProxyUrl = '';
  ProxyAuth _lyricsProxyAuth = const ProxyAuth.none();

  /// Il ripristino parte non atteso, come in `PlayerProvider`: il costruttore
  /// deve restare sincrono per `ChangeNotifierProvider`. Fino a quel momento
  /// vale il valore di default, che e' quello che l'app ha sempre usato.
  SettingsProvider() {
    unawaited(_restore());
  }

  LyricsTextSize get lyricsTextSize => _lyricsTextSize;

  /// Indirizzo di un'istanza di spotify-lyrics-api, provata prima di LRCLIB.
  ///
  /// Vuoto di default, e vuoto significa "nessun proxy": la catena resta il
  /// solo LRCLIB. Non c'e' un indirizzo predefinito perche' quel servizio se
  /// lo ospita ciascuno per conto suo, e cablarne uno nel codice vorrebbe
  /// dire spedire il server di qualcuno dentro l'app di tutti.
  String get lyricsProxyUrl => _lyricsProxyUrl;

  Future<void> setLyricsProxyUrl(String url) async {
    final pulito = url.trim();
    if (pulito == _lyricsProxyUrl) return;

    _lyricsProxyUrl = pulito;
    notifyListeners();
    await _persist(_proxyUrlKey, pulito);
  }

  ProxyAuth get lyricsProxyAuth => _lyricsProxyAuth;

  /// Come per le altre preferenze, un salvataggio fallito vale comunque per
  /// questa sessione.
  Future<void> setLyricsProxyAuth(ProxyAuth auth) async {
    _lyricsProxyAuth = auth;
    notifyListeners();
    try {
      if (auth.type == ProxyAuthType.none) {
        await _secure.delete(key: _proxyAuthKey);
      } else {
        await _secure.write(key: _proxyAuthKey, value: auth.toJson());
      }
    } catch (error, stackTrace) {
      logError(
        'Salvataggio delle credenziali del proxy fallito',
        error,
        stackTrace,
      );
    }
  }

  Future<void> setLyricsTextSize(LyricsTextSize size) async {
    // Riscegliere la taglia gia' attiva non e' un cambiamento visibile, e
    // ridisegnerebbe la lista per niente.
    if (size == _lyricsTextSize) return;

    _lyricsTextSize = size;
    notifyListeners();
    await _persist(_textSizeKey, size.name);
  }

  /// La scelta vale comunque per questa sessione: non farla vedere sarebbe
  /// peggio che perderla alla chiusura.
  Future<void> _persist(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (error, stackTrace) {
      logError('Salvataggio della preferenza $key fallito', error, stackTrace);
    }
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final size = LyricsTextSize.fromName(prefs.getString(_textSizeKey));
      final proxy = prefs.getString(_proxyUrlKey)?.trim() ?? '';
      if (size != _lyricsTextSize || proxy != _lyricsProxyUrl) {
        _lyricsTextSize = size;
        _lyricsProxyUrl = proxy;
        notifyListeners();
      }
    } catch (error, stackTrace) {
      logError('Lettura delle preferenze fallita', error, stackTrace);
    }

    // In un try suo: un Keystore illeggibile non deve costare le preferenze
    // in chiaro, e vale come "nessuna autenticazione".
    try {
      final raw = await _secure.read(key: _proxyAuthKey);
      if (raw == null) return;
      _lyricsProxyAuth = ProxyAuth.fromJson(raw);
      notifyListeners();
    } catch (error, stackTrace) {
      logError(
        'Lettura delle credenziali del proxy fallita',
        error,
        stackTrace,
      );
    }
  }
}
