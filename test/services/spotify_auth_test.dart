import 'package:car_play/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final auth = SpotifyAuth(clientId: 'id-di-prova');

  Uri buildUrl() => auth.authorizeUrl(
    redirectUri: 'car-play://callback',
    scopes: const ['user-read-playback-state', 'user-modify-playback-state'],
    codeChallenge: 'sfida',
    state: 'stato',
  );

  test('chiede sempre la conferma dell account', () {
    // Custom Tabs condivide i cookie con il browser: senza show_dialog la
    // pagina approverebbe da sola e il logout non permetterebbe di cambiare
    // account.
    expect(buildUrl().queryParameters['show_dialog'], 'true');
  });

  test('porta i parametri del flusso PKCE', () {
    final params = buildUrl().queryParameters;

    expect(params['response_type'], 'code');
    expect(params['client_id'], 'id-di-prova');
    expect(params['redirect_uri'], 'car-play://callback');
    expect(params['code_challenge_method'], 'S256');
    expect(params['code_challenge'], 'sfida');
    expect(params['state'], 'stato');
    expect(
      params['scope'],
      'user-read-playback-state user-modify-playback-state',
    );
  });
}
