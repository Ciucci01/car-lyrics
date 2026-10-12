import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/player_provider.dart';

/// Rifa' il giro delle fonti per la traccia in corso.
///
/// Serve quando il testo c'e' ma e' quello sbagliato — una fonte migliore era
/// irraggiungibile al primo tentativo, e senza questo pulsante l'unico modo
/// per tornarci sarebbe svuotare i dati dell'app. Resta visibile anche a
/// testo caricato, perche' e' proprio li' che la schermata non offre nessun
/// altro appiglio: il Retry compare solo quando il caricamento e' fallito.
///
/// Widget suo, come [LyricsTextSizeButton], per poterlo provare senza montare
/// l'intera `PlayerScreen`.
class ReloadLyricsButton extends StatelessWidget {
  const ReloadLyricsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    if (player.playback == null) return const SizedBox.shrink();

    return IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: 'Reload lyrics',
      onPressed: player.retryLyrics,
    );
  }
}
