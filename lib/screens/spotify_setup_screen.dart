import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';

/// Chiede il client id della registrazione Spotify di chi usa l'app.
///
/// E' la prima schermata finche' un client id non c'e', e si riapre dal menu
/// per cambiarlo: senza quella seconda strada un id sbagliato chiuderebbe
/// fuori dall'app, perche' il login fallisce e non resta modo di correggerlo.
///
/// Il client id non arriva da nessun file incluso nella build, e questa e' la
/// ragione per cui esiste la schermata: i termini di Spotify chiedono che un
/// Security Code stia dentro l'app in modo non accessibile a terzi, e un APK
/// pubblico non lo e'.
class SpotifySetupScreen extends StatefulWidget {
  /// Vero quando si arriva dal menu e non dall'avvio: compare l'indietro e,
  /// salvando, si torna da dove si e' venuti.
  final bool canGoBack;

  const SpotifySetupScreen({super.key, this.canGoBack = false});

  @override
  State<SpotifySetupScreen> createState() => _SpotifySetupScreenState();
}

class _SpotifySetupScreenState extends State<SpotifySetupScreen> {
  late final TextEditingController _controller;
  late final String _iniziale;

  @override
  void initState() {
    super.initState();
    _iniziale = context.read<SettingsProvider>().spotifyClientId;
    _controller = TextEditingController(text: _iniziale);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _salva() async {
    final pulito = _controller.text.trim();
    if (pulito.isEmpty || pulito == _iniziale) return;

    final navigator = Navigator.of(context);
    final settings = context.read<SettingsProvider>();

    // La sessione in corso e' stata aperta con l'altra registrazione: i suoi
    // token non valgono piu'. Si chiude prima di cambiare l'id, finche' il
    // PlayerProvider e' ancora quello giusto.
    //
    // Si arriva dal menu solo quando il player esiste gia', ed e' l'unico
    // caso in cui c'e' una sessione da chiudere: all'avvio non c'e' ancora
    // nessun PlayerProvider da cui leggere.
    if (widget.canGoBack) await context.read<PlayerProvider>().disconnect();

    await settings.setSpotifyClientId(pulito);
    if (widget.canGoBack && navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.canGoBack
          ? AppBar(title: const Text('Spotify client ID'))
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.canGoBack) ...[
                const Icon(Icons.key, size: 48, color: Colors.white54),
                const SizedBox(height: 16),
                const Text(
                  'One thing before you start',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                'Car Lyrics talks to Spotify with your own app '
                'registration, not with one built into the download. It '
                'takes a minute and it stays on this phone.',
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 20),
              const _Passo(
                numero: '1',
                testo:
                    'Open developer.spotify.com/dashboard and create an '
                    'app. Any name will do.',
              ),
              const _Passo(
                numero: '2',
                testo: 'Add this exact redirect URI to it:',
                codice: PlayerProvider.redirectUri,
              ),
              const _Passo(
                numero: '3',
                testo: 'Copy the client ID it gives you and paste it below.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Client ID',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _salva(),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _salva,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Passo extends StatelessWidget {
  final String numero;
  final String testo;
  final String? codice;

  const _Passo({required this.numero, required this.testo, this.codice});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$numero.',
            style: const TextStyle(color: Colors.white54, height: 1.4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  testo,
                  style: const TextStyle(color: Colors.white70, height: 1.4),
                ),
                if (codice != null) ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    codice!,
                    style: const TextStyle(
                      color: Color(0xFF1DB954),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
