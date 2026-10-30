import 'package:car_lyrics/services/spotify_authenticator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_auth_2_platform_interface/flutter_web_auth_2_platform_interface.dart';

/// Sostituisce il canale nativo del plugin, come `_FlakySecureStorage` fa con
/// il Keystore. Serve a verificare l'accoppiamento con `flutter_web_auth_2`,
/// che altrimenti nessun test tocca: la finta usata altrove reimplementa il
/// percorso felice e non passa mai di qui.
class _FakeWebAuth extends FlutterWebAuth2Platform {
  _FakeWebAuth(this.risposta);

  final Future<String> Function() risposta;
  String? urlRicevuto;
  String? schemaRicevuto;

  @override
  Future<String> authenticate({
    required String url,
    required String callbackUrlScheme,
    required Map<String, dynamic> options,
  }) {
    urlRicevuto = url;
    schemaRicevuto = callbackUrlScheme;
    return risposta();
  }

  @override
  Future<void> clearAllDanglingCalls() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final authorizeUrl = Uri.parse(
    'https://accounts.spotify.com/authorize?client_id=abc&state=stato',
  );

  Future<SpotifyAuthResult?> autentica(_FakeWebAuth finta) {
    FlutterWebAuth2Platform.instance = finta;
    return const SpotifyAuthenticator().authenticate(
      authorizeUrl: authorizeUrl,
      redirectUri: 'car-lyrics://callback',
    );
  }

  test(
    'ricava lo schema dal redirect e passa l url di autorizzazione',
    () async {
      final finta = _FakeWebAuth(() async => 'car-lyrics://callback?code=xyz');

      await autentica(finta);

      // Lo schema arriva dal redirectUri, non da una seconda costante che puo'
      // andare fuori sincrono con quella del manifest.
      expect(finta.schemaRicevuto, 'car-lyrics');
      expect(finta.urlRicevuto, authorizeUrl.toString());
    },
  );

  test('estrae code e state dal redirect', () async {
    final result = await autentica(
      _FakeWebAuth(() async => 'car-lyrics://callback?code=xyz&state=stato'),
    );

    expect(result?.code, 'xyz');
    expect(result?.state, 'stato');
    expect(result?.error, isNull);
  });

  test('riporta l errore che Spotify mette nel redirect', () async {
    final result = await autentica(
      _FakeWebAuth(() async => 'car-lyrics://callback?error=access_denied'),
    );

    expect(result?.error, 'access_denied');
    expect(result?.code, isNull);
  });

  test('CANCELED diventa null, non un errore', () async {
    // Stringa accoppiata al plugin: se cambiasse a monte, ogni annullamento
    // diventerebbe un errore mostrato in faccia all'utente.
    final result = await autentica(
      _FakeWebAuth(
        () async => throw PlatformException(
          code: 'CANCELED',
          message: 'User canceled login',
        ),
      ),
    );

    expect(result, isNull);
  });

  test('un guasto del browser resta un errore', () async {
    final result = await autentica(
      _FakeWebAuth(
        () async => throw PlatformException(
          code: 'NO_BROWSER',
          message: 'No valid browser available for authentication.',
        ),
      ),
    );

    expect(result, isNotNull);
    expect(result?.error, isNotNull);
    expect(result?.code, isNull);
  });
}
