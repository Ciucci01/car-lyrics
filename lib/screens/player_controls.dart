import 'package:flutter/material.dart';

import '../providers/player_provider.dart';

class PlayerControls extends StatelessWidget {
  final PlayerProvider player;

  /// Come sono disposti i tre comandi.
  ///
  /// In orizzontale la barra in fondo si mangiava una novantina di punti di
  /// altezza, che e' proprio la misura che li' manca e che serve alle righe
  /// del testo; la larghezza invece avanza. Gli stessi tre pulsanti, con le
  /// stesse dimensioni, diventano quindi una colonna sul bordo destro.
  final Axis axis;

  const PlayerControls({
    super.key,
    required this.player,
    this.axis = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = [
      IconButton(
        icon: const Icon(Icons.skip_previous, color: Colors.white),
        iconSize: 32,
        tooltip: 'Previous',
        onPressed: player.skipToPrevious,
      ),
      IconButton(
        icon: Icon(
          player.isPlaying ? Icons.pause : Icons.play_arrow,
          color: Colors.white,
        ),
        iconSize: 40,
        tooltip: player.isPlaying ? 'Pause' : 'Play',
        onPressed: player.togglePlayPause,
      ),
      IconButton(
        icon: const Icon(Icons.skip_next, color: Colors.white),
        iconSize: 32,
        tooltip: 'Next',
        onPressed: player.skipToNext,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[900],
      child: axis == Axis.horizontal
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: buttons,
            )
          // Raggruppati al centro invece che distribuiti su tutta l'altezza:
          // chi guida arriva a tutti e tre senza spostare la mano.
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 12,
              children: buttons,
            ),
    );
  }
}
