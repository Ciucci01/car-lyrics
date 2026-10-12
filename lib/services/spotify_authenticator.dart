import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

/// Esito del ritorno dal browser: o un codice da scambiare, o l'errore che
/// Spotify ha messo nella query del redirect.
class SpotifyAuthResult {
  final String? code;
  final String? state;
  final String? error;

  const SpotifyAuthResult({this.code, this.state, this.error});
}

/// Apre la pagina di autorizzazione nel browser di sistema (Chrome Auth Tab
/// su Android, ASWebAuthenticationSession su iOS) e raccoglie il redirect.
///
/// La password non passa piu' per una vista che controlliamo noi, e i pulsanti
/// "Continue with Google/Apple" funzionano: dentro una WebView incorporata
/// vengono bloccati, lasciando fuori dall'app chi ha creato l'account cosi'.
class SpotifyAuthenticator {
  const SpotifyAuthenticator();

  /// Restituisce null se l'utente esce senza completare: l'annullamento non
  /// e' un errore da mostrare.
  Future<SpotifyAuthResult?> authenticate({
    required Uri authorizeUrl,
    required String redirectUri,
  }) async {
    try {
      final callback = await FlutterWebAuth2.authenticate(
        url: authorizeUrl.toString(),
        callbackUrlScheme: Uri.parse(redirectUri).scheme,
      );
      final uri = Uri.parse(callback);
      return SpotifyAuthResult(
        code: uri.queryParameters['code'],
        state: uri.queryParameters['state'],
        error: uri.queryParameters['error'],
      );
    } on PlatformException catch (error) {
      if (error.code == 'CANCELED') return null;
      return SpotifyAuthResult(error: error.message ?? error.code);
    }
  }
}
