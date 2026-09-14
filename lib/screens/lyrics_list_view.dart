import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../providers/player_provider.dart';

class LyricsListView extends StatefulWidget {
  const LyricsListView({super.key});

  @override
  State<LyricsListView> createState() => _LyricsListViewState();
}

class _LyricsListViewState extends State<LyricsListView> {
  // Frazione dell'altezza a cui si ferma il bordo alto della riga corrente.
  // A 0.5 sarebbe centrata, e in orizzontale restano due righe passate e una
  // sola futura; tenendola nel primo quarto si vede piu' testo in arrivo.
  static const double _lineAlignment = 0.25;

  final ItemScrollController _scrollController = ItemScrollController();
  bool _autoScrollEnabled = true;
  int? _lastScrolledIndex;
  String? _lastTrackId;
  PlayerProvider? _player;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final player = Provider.of<PlayerProvider>(context, listen: false);
    if (identical(player, _player)) return;

    _player?.removeListener(_onPlayerUpdate);
    _player = player;
    _player?.addListener(_onPlayerUpdate);
  }

  @override
  void dispose() {
    _player?.removeListener(_onPlayerUpdate);
    super.dispose();
  }

  void _onPlayerUpdate() {
    if (!mounted) return;
    final player = _player;
    if (player == null) return;

    final trackId = player.playback?.trackId;
    if (trackId != _lastTrackId) {
      _lastTrackId = trackId;
      _lastScrolledIndex = null;
      // La disattivazione vale solo per la canzone che l'utente stava
      // sfogliando: sulla traccia nuova si riparte agganciati.
      if (!_autoScrollEnabled) setState(() => _autoScrollEnabled = true);
    }

    if (!_autoScrollEnabled) return;
    if (player.currentLineIndex == _lastScrolledIndex) return;

    // L'indice si segna solo se lo scroll e' avvenuto davvero: al primo frame
    // dopo il caricamento la lista non e' ancora agganciata, e darlo per fatto
    // lascerebbe il testo fermo in cima fino al cambio riga successivo.
    if (_scrollToLine(player.currentLineIndex)) {
      _lastScrolledIndex = player.currentLineIndex;
    }
  }

  bool _scrollToLine(int lineIndex) {
    if (!_scrollController.isAttached) return false;
    _scrollController.scrollTo(
      // +1 per lo spaziatore in testa alla lista.
      index: (lineIndex < 0 ? 0 : lineIndex) + 1,
      duration: const Duration(milliseconds: 400),
      alignment: _lineAlignment,
      curve: Curves.easeOut,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final lines = player.lyrics?.lines;
    if (lines == null || lines.isEmpty) return const SizedBox.shrink();

    // Il primo centraggio puo' avvenire solo a lista agganciata, cioe' dopo
    // questo frame.
    if (_lastScrolledIndex == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onPlayerUpdate());
    }

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
            itemCount: lines.length + 2,
            itemScrollController: _scrollController,
            itemBuilder: (context, index) {
              // Gli spaziatori seguono _lineAlignment: in testa ne serve
              // quanto basta a far salire la prima riga fino a quel punto, in
              // coda tutto il resto, altrimenti le ultime righe non
              // raggiungono la posizione e restano piu' in basso.
              if (index == 0 || index == lines.length + 1) {
                final height = MediaQuery.of(context).size.height;
                return SizedBox(
                  height: index == 0
                      ? height * _lineAlignment
                      : height * (1 - _lineAlignment),
                );
              }

              final lineIndex = index - 1;
              final isCurrent = lineIndex == player.currentLineIndex;

              return ListTile(
                title: Text(
                  lines[lineIndex].words,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isCurrent ? const Color(0xFF1DB954) : Colors.white70,
                    fontSize: isCurrent ? 20 : 16,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
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
              tooltip: 'Follow the lyrics again',
              onPressed: () {
                setState(() => _autoScrollEnabled = true);
                _scrollToLine(player.currentLineIndex);
              },
              child: const Icon(Icons.my_location),
            ),
          ),
      ],
    );
  }
}
