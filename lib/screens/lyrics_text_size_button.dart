import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lyrics_text_size.dart';
import '../providers/settings_provider.dart';

/// Il menu con cui si sceglie quanto e' grande il testo.
///
/// Sta in un widget suo e non dentro la AppBar di `PlayerScreen` perche' li'
/// sarebbe verificabile solo montando l'intera schermata, che si porta dietro
/// il Marquee del titolo e il wakelock: due cose che con la dimensione del
/// testo non c'entrano niente.
class LyricsTextSizeButton extends StatelessWidget {
  const LyricsTextSizeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return PopupMenuButton<LyricsTextSize>(
      icon: const Icon(Icons.format_size),
      tooltip: 'Lyrics text size',
      initialValue: settings.lyricsTextSize,
      onSelected: settings.setLyricsTextSize,
      itemBuilder: (context) => [
        for (final size in LyricsTextSize.values)
          PopupMenuItem(value: size, child: Text(size.label)),
      ],
    );
  }
}
