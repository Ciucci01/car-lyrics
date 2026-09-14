import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/app_log.dart';

class SpotifyAuthResult {
  final String? code;
  final String? state;
  final String? error;

  const SpotifyAuthResult({this.code, this.state, this.error});
}

class SpotifyAuthWebView extends StatefulWidget {
  final Uri authorizeUrl;
  final String redirectUri;

  const SpotifyAuthWebView({
    super.key,
    required this.authorizeUrl,
    required this.redirectUri,
  });

  /// Prende il [NavigatorState] gia' risolto invece di un BuildContext: chi
  /// chiama cambia stato prima di aprire la rotta, e il widget da cui arriva
  /// il context puo' essere gia' stato smontato.
  ///
  /// Restituisce null se l'utente esce senza completare, con la X o con il
  /// gesto di indietro del sistema.
  static Future<SpotifyAuthResult?> show(
    NavigatorState navigator, {
    required Uri authorizeUrl,
    required String redirectUri,
  }) {
    return navigator.push<SpotifyAuthResult>(
      MaterialPageRoute(
        builder: (_) => SpotifyAuthWebView(
          authorizeUrl: authorizeUrl,
          redirectUri: redirectUri,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  /// Cancella i cookie della WebView: senza questo un logout seguito da un
  /// nuovo login rientrerebbe in automatico con lo stesso account.
  static Future<void> clearSession() async {
    try {
      await WebViewCookieManager().clearCookies();
    } catch (error, stackTrace) {
      logError('Pulizia dei cookie della WebView fallita', error, stackTrace);
    }
  }

  @override
  State<SpotifyAuthWebView> createState() => _SpotifyAuthWebViewState();
}

class _SpotifyAuthWebViewState extends State<SpotifyAuthWebView> {
  late final WebViewController _controller;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!request.url.startsWith(widget.redirectUri)) {
              return NavigationDecision.navigate;
            }
            final uri = Uri.parse(request.url);
            _finish(
              SpotifyAuthResult(
                code: uri.queryParameters['code'],
                state: uri.queryParameters['state'],
                error: uri.queryParameters['error'],
              ),
            );
            return NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            // Gli errori delle sottorisorse non devono far fallire il login:
            // conta solo il documento principale.
            if (error.isForMainFrame == false) return;
            _finish(SpotifyAuthResult(error: error.description));
          },
        ),
      )
      ..loadRequest(widget.authorizeUrl);
  }

  void _finish(SpotifyAuthResult result) {
    if (_finished || !mounted) return;
    _finished = true;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login with Spotify'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
