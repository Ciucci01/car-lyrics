import '../../models/lyrics.dart';

/// Quello che serve a una fonte per cercare un testo.
///
/// I proxy di Spotify usano il solo trackId; LRCLIB cerca per metadati, e la
/// durata e' la difesa contro l'abbinamento della versione sbagliata.
class LyricsQuery {
  final String trackId;
  final String title;
  final String primaryArtist;
  final String? albumName;
  final int durationMs;

  const LyricsQuery({
    required this.trackId,
    required this.title,
    required this.primaryArtist,
    required this.albumName,
    required this.durationMs,
  });
}

/// Una fonte di testi.
///
/// Contratto degli esiti, identico a quello di SpotifyService fra 204 ed
/// errore: `null` significa "questa fonte non ha il testo", un'eccezione
/// significa "non lo so". Il repository ne ha bisogno per distinguere
/// "non esiste" da "riprova".
abstract class LyricsProvider {
  String get name;

  Future<Lyrics?> fetch(LyricsQuery query);
}

class LyricsProviderException implements Exception {
  final String message;

  const LyricsProviderException(this.message);

  @override
  String toString() => 'LyricsProviderException: $message';
}
