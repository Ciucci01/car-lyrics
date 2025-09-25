class Lyrics {
  final bool error;
  final String syncType;
  final List<LyricLine> lines;

  Lyrics({required this.error, required this.syncType, required this.lines});

  factory Lyrics.fromJson(Map<String, dynamic> json) {
    return Lyrics(
      error: json['error'] ?? true,
      syncType: json['syncType'] ?? '',
      lines: List<LyricLine>.from(
        (json['lines'] ?? []).map((line) => LyricLine.fromJson(line)),
      ),
    );
  }
}

class LyricLine {
  final String startTimeMs;
  final String words;
  final String endTimeMs;

  LyricLine({
    required this.startTimeMs,
    required this.words,
    required this.endTimeMs,
  });

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      startTimeMs: json['startTimeMs'] ?? '0',
      words: json['words'] ?? '',
      endTimeMs: json['endTimeMs'] ?? '0',
    );
  }

  int get startTime => int.tryParse(startTimeMs) ?? 0;
}
