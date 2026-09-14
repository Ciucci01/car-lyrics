class Lyrics {
  final bool error;
  final String syncType;
  final List<LyricLine> lines;

  /// LRCLIB segnala cosi' i brani senza parole: e' un esito diverso da
  /// "testo non trovato" e va mostrato in modo diverso.
  final bool instrumental;

  const Lyrics({
    required this.error,
    required this.syncType,
    required this.lines,
    this.instrumental = false,
  });

  factory Lyrics.fromJson(Map<String, dynamic> json) {
    return Lyrics(
      // Solo un error dichiarato conta: diverse risposte valide omettono del
      // tutto il campo, e un default a true spegnerebbe i lyrics ovunque.
      error: json['error'] == true,
      syncType: json['syncType'] ?? '',
      instrumental: json['instrumental'] == true,
      lines: List<LyricLine>.from(
        (json['lines'] ?? []).map((line) => LyricLine.fromJson(line)),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'error': error,
    'syncType': syncType,
    'instrumental': instrumental,
    'lines': [
      for (final line in lines)
        {
          'startTimeMs': line.startTimeMs,
          'words': line.words,
          'endTimeMs': line.endTimeMs,
        },
    ],
  };

  /// lines e' il segnale affidabile: se il servizio non ha righe da dare,
  /// non c'e' testo da mostrare, comunque abbia formulato la risposta.
  bool get isUsable => !error && lines.isNotEmpty && !instrumental;

  /// Solo un UNSYNCED dichiarato, o righe tutte a timestamp zero, escludono
  /// la sincronizzazione. Un syncType assente o sconosciuto resta trattato
  /// come sincronizzato: spegnere l'evidenziazione per un default sarebbe lo
  /// stesso errore gia' fatto con error.
  bool get isSynced =>
      syncType != 'UNSYNCED' && lines.any((line) => line.startTime > 0);
}

class LyricLine {
  final String startTimeMs;
  final String words;
  final String endTimeMs;

  const LyricLine({
    required this.startTimeMs,
    required this.words,
    required this.endTimeMs,
  });

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      // toString(): alcuni servizi mandano i timestamp come numeri, e un
      // cast diretto farebbe fallire l'intera traccia.
      startTimeMs: json['startTimeMs']?.toString() ?? '0',
      words: json['words']?.toString() ?? '',
      endTimeMs: json['endTimeMs']?.toString() ?? '0',
    );
  }

  int get startTime => int.tryParse(startTimeMs) ?? 0;
}
