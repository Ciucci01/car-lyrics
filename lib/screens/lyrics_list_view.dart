import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/lyrics_text_size.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';

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
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();
  bool _autoScrollEnabled = true;
  int? _lastScrolledIndex;
  String? _lastTrackId;
  LyricsTextSize? _lastTextSize;
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
    // isAttached diventa true appena la lista si registra, ma non dice che la
    // viewport sia stata misurata. Se non lo e', scrollTo non fallisce
    // subito: rimanda a una callback post-frame e li' esplode con
    // "ScrollController not attached to any scroll views", fuori dalla
    // portata di qualunque try. Le posizioni note sono il segnale che la
    // lista ha davvero un viewport sotto.
    if (_positionsListener.itemPositions.value.isEmpty) return false;

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
    final textSize = context.watch<SettingsProvider>().lyricsTextSize;
    final lines = player.lyrics?.lines;
    if (lines == null || lines.isEmpty) return const SizedBox.shrink();

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (_lastTextSize != textSize) {
      _lastTextSize = textSize;
      // Righe piu' alte o piu' basse spostano la riga corrente altrove nella
      // lista: senza rifare il centraggio il testo scivola via da solo sotto
      // gli occhi di chi guida. Stesso meccanismo del primo caricamento.
      _lastScrolledIndex = null;
    }

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
            itemPositionsListener: _positionsListener,
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
                    fontSize: isCurrent
                        ? textSize.currentLineSize
                        : textSize.otherLineSize,
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
            // In orizzontale i comandi occupano il bordo destro: lasciato in
            // basso a destra il pulsante ci finirebbe appiccicato, e due
            // bersagli adiacenti che fanno cose diverse sono un errore di
            // tocco in macchina.
            left: isLandscape ? 20 : null,
            right: isLandscape ? null : 20,
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
