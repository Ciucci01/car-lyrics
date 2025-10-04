import 'package:car_play/providers/player_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class LyricsListView extends StatefulWidget {
  LyricsListView({Key? key}) : super(key: key);

  @override
  State<LyricsListView> createState() => _LyricsListViewState();
}

class _LyricsListViewState extends State<LyricsListView> {
  final ItemScrollController _scrollController = ItemScrollController();
  bool _autoScrollEnabled = true;
  int? _lastScrolledIndex;
  PlayerProvider? _player;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // rimuovo eventuale listener precedente
    _player?.removeListener(_onPlayerUpdate);

    // prendo il nuovo player e aggiungo il listener
    _player = Provider.of<PlayerProvider>(context);
    _player?.addListener(_onPlayerUpdate);
  }

  @override
  void dispose() {
    _player?.removeListener(
      _onPlayerUpdate,
    ); // uso la variabile, non Provider.of
    super.dispose();
  }

  void _onPlayerUpdate() {
    if (!mounted) return;
    if (_autoScrollEnabled && _player!.currentLineIndex != _lastScrolledIndex) {
      _lastScrolledIndex = _player!.currentLineIndex;
      _scrollToCurrentLine(
        _player!.currentLineIndex,
        _player!.lyrics!.lines.length,
      );
    }
  }

  void _scrollToCurrentLine(int index, int total) {
    if (_scrollController.isAttached) {
      _scrollController.scrollTo(
        index: index + 1, // +1 per la riga vuota in cima
        duration: const Duration(milliseconds: 400),
        alignment: 0.5, // sempre al centro
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = _player!;
    final lyrics = player.lyrics!.lines;

    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.direction != ScrollDirection.idle &&
                _autoScrollEnabled) {
              setState(() => _autoScrollEnabled = false);
            }
            return false;
          },
          child: ScrollablePositionedList.builder(
            itemCount: lyrics.length + 2,
            itemScrollController: _scrollController,
            itemBuilder: (context, index) {
              if (index == 0 || index == lyrics.length + 1) {
                return SizedBox(height: MediaQuery.of(context).size.height / 2);
              }

              final realIndex = index - 1;
              final line = lyrics[realIndex];
              final isCurrentLine = realIndex == player.currentLineIndex;

              return ListTile(
                title: Text(
                  line.words,
                  style: TextStyle(
                    color: isCurrentLine ? Colors.green : Colors.white70,
                    fontSize: isCurrentLine ? 20 : 16,
                    fontWeight: isCurrentLine
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
        ),

        if (!_autoScrollEnabled)
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              child: const Icon(Icons.my_location),
              onPressed: () {
                setState(() => _autoScrollEnabled = true);
                _scrollToCurrentLine(player.currentLineIndex, lyrics.length);
              },
            ),
          ),
      ],
    );
  }
}
