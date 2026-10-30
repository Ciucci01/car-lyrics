import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import 'lyrics_source_dialog.dart';
import 'spotify_setup_screen.dart';

enum _VoceMenu { lyricsSource, clientId, disconnect }

/// Le azioni che non servono mentre si guida.
///
/// Stanno sotto i tre puntini e non come icone a se': la barra ospita gia'
/// taglia e ricarica, e un Disconnect a portata di pollice accanto a quelli
/// e' un logout per sbaglio a un semaforo.
class PlayerMenuButton extends StatelessWidget {
  const PlayerMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_VoceMenu>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'More',
      onSelected: (voce) {
        switch (voce) {
          case _VoceMenu.lyricsSource:
            showDialog<void>(
              context: context,
              builder: (_) => ChangeNotifierProvider.value(
                // Il dialogo vive in un ramo suo dell'albero, appeso al
                // Navigator: riportarci il provider lo rende indipendente da
                // dove il pulsante e' montato.
                value: context.read<SettingsProvider>(),
                child: const LyricsSourceDialog(),
              ),
            );
          case _VoceMenu.clientId:
            // Come il dialogo sopra: la schermata vive appesa al Navigator,
            // quindi i due provider se li porta dietro.
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MultiProvider(
                  providers: [
                    ChangeNotifierProvider.value(
                      value: context.read<SettingsProvider>(),
                    ),
                    ChangeNotifierProvider.value(
                      value: context.read<PlayerProvider>(),
                    ),
                  ],
                  child: const SpotifySetupScreen(canGoBack: true),
                ),
              ),
            );
          case _VoceMenu.disconnect:
            context.read<PlayerProvider>().disconnect();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _VoceMenu.lyricsSource,
          child: ListTile(
            leading: Icon(Icons.travel_explore),
            title: Text('Lyrics source'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _VoceMenu.clientId,
          child: ListTile(
            leading: Icon(Icons.key),
            title: Text('Spotify client ID'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _VoceMenu.disconnect,
          child: ListTile(
            leading: Icon(Icons.logout),
            title: Text('Disconnect'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
