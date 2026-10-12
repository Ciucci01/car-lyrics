import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<SettingsProvider>().lyricsProxyUrl,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
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

  Future<void> _save() async {
    final value = _controller.text.trim();
    final error = _validate(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    final navigator = Navigator.of(context);
    await context.read<SettingsProvider>().setLyricsProxyUrl(value);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Lyrics source'),
      content: Column(
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
        ],
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
