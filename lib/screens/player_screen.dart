import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';

class PlayerScreen extends StatefulWidget {
  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Spotify Lyrics'),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: Consumer<PlayerProvider>(
        builder: (context, player, child) {
          if (player.isLoading) {
            return Center(child: CircularProgressIndicator());
          }

          if (player.lyrics == null) {
            return Center(
              child: Column(
                children: [
                  Text(
                    'Connect to Spotify and play a song',
                    style: TextStyle(color: Colors.white),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Provider.of<PlayerProvider>(
                        context,
                        listen: false,
                      ).connectSpotify(context);
                    },
                    child: Text('Connect to Spotify'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 15,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Expanded(child: LyricsListView(player: player)),
              PlayerControls(player: player),
            ],
          );
        },
      ),
    );
  }
}

class LyricsListView extends StatelessWidget {
  final PlayerProvider player;

  LyricsListView({required this.player});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: player.lyrics!.lines.length,
      itemBuilder: (context, index) {
        final line = player.lyrics!.lines[index];
        final isCurrentLine = index == player.currentLineIndex;

        return ListTile(
          title: Text(
            line.words,
            style: TextStyle(
              color: isCurrentLine ? Colors.green : Colors.white70,
              fontSize: isCurrentLine ? 20 : 16,
              fontWeight: isCurrentLine ? FontWeight.bold : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }
}

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
