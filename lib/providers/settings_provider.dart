import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lyrics_text_size.dart';
import '../utils/app_log.dart';

/// Le preferenze di resa, tenute fuori da `PlayerProvider`: li' dentro tutto
/// arriva da Spotify, mentre questa e' una scelta dell'utente sulla propria
/// schermata e ha una persistenza sua.
class SettingsProvider with ChangeNotifier {
  static const _textSizeKey = 'lyrics_text_size';

  LyricsTextSize _lyricsTextSize = LyricsTextSize.medium;

  /// Il ripristino parte non atteso, come in `PlayerProvider`: il costruttore
  /// deve restare sincrono per `ChangeNotifierProvider`. Fino a quel momento
  /// vale il valore di default, che e' quello che l'app ha sempre usato.
  SettingsProvider() {
    unawaited(_restore());
  }

  LyricsTextSize get lyricsTextSize => _lyricsTextSize;

  Future<void> setLyricsTextSize(LyricsTextSize size) async {
    // Riscegliere la taglia gia' attiva non e' un cambiamento visibile, e
    // ridisegnerebbe la lista per niente.
    if (size == _lyricsTextSize) return;

    _lyricsTextSize = size;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_textSizeKey, size.name);
    } catch (error, stackTrace) {
      // La scelta vale comunque per questa sessione: non farla vedere
      // sarebbe peggio che perderla alla chiusura.
      logError(
        'Salvataggio della dimensione del testo fallito',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final restored = LyricsTextSize.fromName(prefs.getString(_textSizeKey));
      if (restored == _lyricsTextSize) return;

      _lyricsTextSize = restored;
      notifyListeners();
    } catch (error, stackTrace) {
      logError('Lettura della dimensione del testo fallita', error, stackTrace);
    }
  }
}
