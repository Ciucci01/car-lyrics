import 'package:car_play/screens/lyrics_list_view.dart';
import 'package:car_play/screens/player_controls.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:marquee/marquee.dart';
import '../providers/player_provider.dart';

class PlayerScreen extends StatefulWidget {
  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<PlayerProvider>(
          builder: (context, player, _) {
            if (player.trackName == null) {
              return const Text('Spotify Lyrics');
            }
            return _buildTrackHeader(player);
          },
        ),
        backgroundColor: Colors.black,
        centerTitle: false,
        titleSpacing: 16,
      ),
      backgroundColor: Colors.black,
      body: Consumer<PlayerProvider>(
        builder: (context, player, child) {
          if (player.isLoading) {
            return Center(child: CircularProgressIndicator());
          }

          if (!player.isConnected) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Connect to Spotify and play a song',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          if (!player.isPlaying) {
            return const Center(
              child: Text(
                'No song is playing',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          if (player.lyrics != null) {
            return Column(
              children: [
                Expanded(child: LyricsListView()),
                PlayerControls(player: player),
              ],
            );
          }
          return const Center(
            child: Text(
              'No lyrics found',
              style: TextStyle(color: Colors.white),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTrackHeader(PlayerProvider player) {
    return Row(
      children: [
        if (player.albumImageUrl != null)
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                player.albumImageUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 22,
                child: Marquee(
                  key: ValueKey(player.currentTrackId),
                  text: player.trackName ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  scrollAxis: Axis.horizontal,
                  blankSpace: 50.0,
                  velocity: 30.0,
                  pauseAfterRound: const Duration(seconds: 2),
                  startPadding: 0.0,
                  accelerationDuration: const Duration(seconds: 1),
                  accelerationCurve: Curves.linear,
                  decelerationDuration: const Duration(milliseconds: 500),
                  decelerationCurve: Curves.easeOut,
                ),
              ),
              Text(
                player.artistName ?? '',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
