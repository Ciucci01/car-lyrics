import 'package:flutter/material.dart';

import '../providers/player_provider.dart';

class PlayerControls extends StatelessWidget {
  final PlayerProvider player;

  const PlayerControls({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[900],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
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
        ],
      ),
    );
  }
}
