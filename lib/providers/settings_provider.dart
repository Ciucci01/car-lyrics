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
  static const _clientIdKey = 'spotify_client_id';
  static const _proxyAuthKey = 'lyrics_proxy_auth';

  /// Le credenziali del proxy sono un segreto e stanno nel Keystore come i
  /// token Spotify, non in chiaro accanto all'indirizzo.
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  LyricsTextSize _lyricsTextSize = LyricsTextSize.medium;
  String _lyricsProxyUrl = '';
  String _spotifyClientId = '';
  ProxyAuth _lyricsProxyAuth = const ProxyAuth.none();

  /// Si completa quando le preferenze salvate sono state lette.
  ///
  /// Serve a `main`, che deve sapere se un client id c'e' gia' prima di
  /// decidere quale schermata aprire: senza attenderlo, al primo frame il
  /// valore e' ancora vuoto e la configurazione lampeggerebbe a ogni avvio.
  late final Future<void> ready;

  /// Il costruttore resta sincrono per `ChangeNotifierProvider`; chi ha
  /// bisogno dei valori salvati attende [ready].
  SettingsProvider() {
    ready = _restore();
  }

  LyricsTextSize get lyricsTextSize => _lyricsTextSize;

  /// Client id della registrazione Spotify di chi usa l'app.
  ///
  /// Vuoto significa "non configurata", e l'app apre la schermata di
  /// impostazione invece del player. Non ha un valore predefinito e non
  /// viene letto da nessun file incluso nella build: i termini di Spotify
  /// chiedono che un Security Code stia dentro l'app "in a secure manner not
  /// accessible by third parties", e un APK pubblico non e' quel posto.
  String get spotifyClientId => _spotifyClientId;

  /// Chi cambia il client id deve anche chiudere la sessione in corso: i
  /// token sono stati emessi per un'altra registrazione e non valgono piu'.
  Future<void> setSpotifyClientId(String id) async {
    final pulito = id.trim();
    if (pulito == _spotifyClientId) return;

    _spotifyClientId = pulito;
    notifyListeners();
    await _persist(_clientIdKey, pulito);
  }

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
      final clientId = prefs.getString(_clientIdKey)?.trim() ?? '';
      if (size != _lyricsTextSize ||
          proxy != _lyricsProxyUrl ||
          clientId != _spotifyClientId) {
        _lyricsTextSize = size;
        _lyricsProxyUrl = proxy;
        _spotifyClientId = clientId;
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
