import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/playback_state.dart';
import '../providers/player_provider.dart';
import 'lyrics_list_view.dart';
import 'lyrics_text_size_button.dart';
import 'player_controls.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<PlayerProvider>(
          builder: (context, player, _) {
            final playback = player.playback;
            if (playback == null) return const Text('Spotify Lyrics');
            return _TrackHeader(playback: playback);
          },
        ),
        actions: [
          Consumer<PlayerProvider>(
            builder: (context, player, _) {
              if (!player.isConnected) return const SizedBox.shrink();
              return const LyricsTextSizeButton();
            },
          ),
          Consumer<PlayerProvider>(
            builder: (context, player, _) {
              if (!player.isConnected) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Disconnect',
                onPressed: player.disconnect,
              );
            },
          ),
        ],
      ),
      body: Consumer<PlayerProvider>(
        builder: (context, player, _) {
          if (player.isBusy) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!player.isConnected) {
            return _ConnectView(error: player.authError);
          }
          return PlaybackView(player: player);
        },
      ),
    );
  }
}

class _ConnectView extends StatelessWidget {
  final String? error;

  const _ConnectView({this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Connect to Spotify and play a song',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => context.read<PlayerProvider>().connect(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text('Connect to Spotify'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Il testo piu' i comandi, nell'unica disposizione che l'orientamento
/// permette. Pubblica solo perche' il passaggio fra le due disposizioni si
/// possa verificare senza montare l'intera schermata, che si porta dietro il
/// Marquee del titolo e il wakelock.
class PlaybackView extends StatelessWidget {
  final PlayerProvider player;

  const PlaybackView({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    if (player.playback == null) {
      return const _Message(
        icon: Icons.music_off,
        text: 'No song playing.\nStart playback on any Spotify device.',
      );
    }

    // In orizzontale l'altezza e' la cosa scarsa: i comandi si spostano sul
    // bordo destro, dove invece lo spazio avanza.
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      return Row(
        children: [
          Expanded(child: _buildLyricsArea()),
          PlayerControls(player: player, axis: Axis.vertical),
        ],
      );
    }

    return Column(
      children: [
        Expanded(child: _buildLyricsArea()),
        PlayerControls(player: player),
      ],
    );
  }

  Widget _buildLyricsArea() {
    return switch (player.lyricsStatus) {
      LyricsStatus.ready => const LyricsListView(),
      LyricsStatus.unavailable => const _Message(
        icon: Icons.lyrics_outlined,
        text: 'No lyrics for this track',
      ),
      LyricsStatus.instrumental => const _Message(
        icon: Icons.music_note,
        text: 'Instrumental track',
      ),
      LyricsStatus.failed => _Message(
        icon: Icons.cloud_off,
        text: 'Could not load the lyrics',
        action: TextButton(
          onPressed: player.retryLyrics,
          child: const Text('Retry'),
        ),
      ),
      LyricsStatus.loading ||
      LyricsStatus.idle => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.white38),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}

class _TrackHeader extends StatelessWidget {
  final PlaybackState playback;

  const _TrackHeader({required this.playback});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (playback.albumImageUrl != null)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                playback.albumImageUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox(width: 40, height: 40),
              ),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 22, child: _buildTitle()),
              Text(
                playback.artistName,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTitle() {
    const style = TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    );

    // Marquee non accetta testo vuoto.
    if (playback.trackName.isEmpty) {
      return const Text('', style: style);
    }

    return Marquee(
      key: ValueKey(playback.trackId),
      text: playback.trackName,
      style: style,
      scrollAxis: Axis.horizontal,
      blankSpace: 50,
      velocity: 30,
      pauseAfterRound: const Duration(seconds: 2),
      startPadding: 0,
      accelerationDuration: const Duration(seconds: 1),
      accelerationCurve: Curves.linear,
      decelerationDuration: const Duration(milliseconds: 500),
      decelerationCurve: Curves.easeOut,
    );
  }
}
