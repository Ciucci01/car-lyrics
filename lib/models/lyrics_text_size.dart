/// Quanto sono grandi le righe del testo a schermo.
///
/// I fattori si applicano alle due misure storiche — 20 per la riga corrente,
/// 16 per le altre — invece di elencare quattro coppie di numeri scelte a
/// mano. Cosi' il rapporto fra riga attiva e righe attorno, che e' quello che
/// rende leggibile il punto in cui si e', resta lo stesso a ogni livello.
enum LyricsTextSize {
  small('Small', 0.8),
  medium('Medium', 1),
  large('Large', 1.3),
  huge('Extra large', 1.6);

  const LyricsTextSize(this.label, this.scale);

  /// Mostrata nel menu, quindi in inglese come il resto dell'interfaccia.
  final String label;

  final double scale;

  static const _currentLineBase = 20.0;
  static const _otherLineBase = 16.0;

  double get currentLineSize => _currentLineBase * scale;
  double get otherLineSize => _otherLineBase * scale;

  /// Un valore salvato che non si riconosce piu' — una versione precedente,
  /// o preferenze manomesse — vale come "mai scelto", non come un errore.
  static LyricsTextSize fromName(String? name) {
    return values.firstWhere((size) => size.name == name, orElse: () => medium);
  }
}
