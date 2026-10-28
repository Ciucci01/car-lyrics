import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/proxy_auth.dart';
import '../providers/settings_provider.dart';

/// Dove sta l'istanza di spotify-lyrics-api da provare prima di LRCLIB.
///
/// Si imposta qui e non in un file di build perche' quel servizio se lo
/// ospita ciascuno per conto suo: cablare un indirizzo nel codice vorrebbe
/// dire spedire il server di qualcuno dentro l'app di tutti, e obbligherebbe
/// a ricostruire l'APK per cambiarlo.
class LyricsSourceDialog extends StatefulWidget {
  const LyricsSourceDialog({super.key});

  @override
  State<LyricsSourceDialog> createState() => _LyricsSourceDialogState();
}

class _LyricsSourceDialogState extends State<LyricsSourceDialog> {
  late final TextEditingController _controller;
  late final TextEditingController _token;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late ProxyAuthType _authType;
  String? _error;
  String? _authError;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    final auth = settings.lyricsProxyAuth;
    _controller = TextEditingController(text: settings.lyricsProxyUrl);
    _token = TextEditingController(text: auth.token);
    _username = TextEditingController(text: auth.username);
    _password = TextEditingController(text: auth.password);
    _authType = auth.type;
  }

  @override
  void dispose() {
    _controller.dispose();
    _token.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Vuoto e' valido e significa "nessun proxy". Un indirizzo c'e' solo se e'
  /// assoluto e parla http: senza questo controllo l'errore arriverebbe una
  /// canzone dopo, come un testo che non si carica.
  String? _validate(String value) {
    if (value.isEmpty) return null;

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.isAbsolute || !uri.hasAuthority) {
      return 'Enter a full address, like https://lyrics.example.com';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Only http and https are supported';
    }
    return null;
  }

  /// Il nome utente di Basic non puo' contenere i due punti (RFC 7617): il
  /// server lo leggerebbe come l'inizio della password.
  String? _validateAuth() {
    return switch (_authType) {
      ProxyAuthType.none => null,
      ProxyAuthType.bearer when _token.text.trim().isEmpty => 'Enter a token',
      ProxyAuthType.basic when _username.text.isEmpty => 'Enter a username',
      ProxyAuthType.basic when _username.text.contains(':') =>
        'The username cannot contain ":"',
      _ => null,
    };
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    final error = _validate(value);
    // Senza indirizzo le credenziali non servono a niente: si buttano invece
    // di lasciarle nel Keystore.
    final authError = value.isEmpty ? null : _validateAuth();
    if (error != null || authError != null) {
      setState(() {
        _error = error;
        _authError = authError;
      });
      return;
    }

    final auth = value.isEmpty
        ? const ProxyAuth.none()
        : switch (_authType) {
            ProxyAuthType.none => const ProxyAuth.none(),
            ProxyAuthType.bearer => ProxyAuth.bearer(_token.text.trim()),
            ProxyAuthType.basic => ProxyAuth.basic(
              _username.text,
              _password.text,
            ),
          };

    final navigator = Navigator.of(context);
    final settings = context.read<SettingsProvider>();
    await settings.setLyricsProxyAuth(auth);
    await settings.setLyricsProxyUrl(value);
    navigator.pop();
  }

  void _clearAuthError(String _) {
    if (_authError != null) setState(() => _authError = null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Lyrics source'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Optional. Address of a spotify-lyrics-api instance, asked '
              'before LRCLIB. Leave it empty to use LRCLIB alone.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Base address',
                hintText: 'https://lyrics.example.com',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ProxyAuthType>(
              initialValue: _authType,
              decoration: const InputDecoration(labelText: 'Authentication'),
              items: [
                for (final type in ProxyAuthType.values)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: (type) => setState(() {
                _authType = type!;
                _authError = null;
              }),
            ),
            if (_authType == ProxyAuthType.bearer)
              TextField(
                controller: _token,
                autocorrect: false,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Token',
                  errorText: _authError,
                ),
                onChanged: _clearAuthError,
              ),
            if (_authType == ProxyAuthType.basic) ...[
              TextField(
                controller: _username,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Username',
                  errorText: _authError,
                ),
                onChanged: _clearAuthError,
              ),
              TextField(
                controller: _password,
                autocorrect: false,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
