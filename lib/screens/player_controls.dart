import 'package:car_play/providers/player_provider.dart';
import 'package:flutter/material.dart';

class PlayerControls extends StatelessWidget {
  final PlayerProvider player;

  PlayerControls({required this.player});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      color: Colors.grey[900],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: Icon(Icons.skip_previous, color: Colors.white),
            onPressed: player.skipToPrevious,
          ),
          IconButton(
            icon: Icon(
              player.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 36,
            ),
            onPressed: player.togglePlayPause,
          ),
          IconButton(
            icon: Icon(Icons.skip_next, color: Colors.white),
            onPressed: player.skipToNext,
          ),
        ],
      ),
    );
  }
}
