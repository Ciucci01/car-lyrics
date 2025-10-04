import 'package:car_play/screens/lyrics_list_view.dart';
import 'package:car_play/screens/player_controls.dart';
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
              Expanded(child: LyricsListView()),
              PlayerControls(player: player),
            ],
          );
        },
      ),
    );
  }
}
