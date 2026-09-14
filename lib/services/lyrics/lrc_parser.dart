import '../../models/lyrics.dart';

/// Riconosce [mm:ss], [mm:ss.xx] e [mm:ss.xxx]. I tag di metadati come
/// [ar:...] non iniziano con cifre e quindi non entrano nel match.
final _timestamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');

/// Converte il corpo LRC di LRCLIB in righe ordinate per tempo crescente.
///
/// Una riga puo' portare piu' timestamp: in LRC e' il modo di riusare lo
/// stesso verso per un ritornello, e produce una LyricLine per timestamp.
List<LyricLine> parseLrc(String body) {
  final result = <LyricLine>[];

  for (final raw in body.split('\n')) {
    final matches = _timestamp.allMatches(raw).toList();
    if (matches.isEmpty) continue;

    final words = raw.substring(matches.last.end).trim();
    for (final match in matches) {
      result.add(
        LyricLine(
          startTimeMs: '${_millisecondsOf(match)}',
          words: words,
          endTimeMs: '0',
        ),
      );
    }
  }

  // Ordina stabilmente per tempo crescente: quando due righe hanno lo stesso
  // startTime (es. testo originale + traduzione), conserva l'ordine sorgente.
  // List.sort non e' stabile per liste grandi, quindi usiamo l'indice
  // originale come tiebreaker.
  final indexed = result.asMap().entries.toList();
  indexed.sort((a, b) {
    final cmp = a.value.startTime.compareTo(b.value.startTime);
    return cmp != 0 ? cmp : a.key.compareTo(b.key);
  });
  return indexed.map((e) => e.value).toList();
}

int _millisecondsOf(RegExpMatch match) {
  final minutes = int.parse(match.group(1)!);
  final seconds = int.parse(match.group(2)!);
  var total = (minutes * 60 + seconds) * 1000;

  final fraction = match.group(3);
  if (fraction != null) {
    // "15" sono centesimi, "125" millesimi: si normalizza a tre cifre.
    total += int.parse(fraction.padRight(3, '0').substring(0, 3));
  }
  return total;
}
