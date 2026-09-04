import '../../models/lyrics.dart';
import '../../utils/app_log.dart';
import 'lyrics_cache.dart';
import 'lyrics_provider.dart';

/// Ordina la catena e sceglie il risultato.
///
/// Regola: vince il primo testo sincronizzato incontrato. Un testo non
/// sincronizzato viene tenuto da parte e usato solo se la catena finisce
/// senza trovarne uno migliore.
class LyricsRepository {
  final List<LyricsProvider> providers;

  /// Non è final: la cache si apre in modo asincrono e viene agganciata
  /// dopo la costruzione, perché PlayerProvider si costruisce in modo
  /// sincrono dentro ChangeNotifierProvider.
  LyricsCache? cache;

  LyricsRepository({required this.providers, this.cache});

  Future<Lyrics?> lyricsFor(LyricsQuery query) async {
    final hit = await cache?.read(query.trackId);
    if (hit != null) return hit.lyrics;

    Lyrics? bestUnsynced;
    Lyrics? instrumental;
    var failures = 0;

    for (final provider in providers) {
      try {
        final result = await provider.fetch(query);
        if (result == null) continue;

        if (result.instrumental) {
          instrumental ??= result;
          continue;
        }
        if (result.isSynced) {
          await cache?.writeFound(query.trackId, result);
          return result;
        }
        bestUnsynced ??= result;
      } catch (error, stackTrace) {
        failures++;
        logError('Fonte ${provider.name} non raggiungibile', error, stackTrace);
      }
    }

    final chosen = bestUnsynced ?? instrumental;
    if (chosen != null) {
      await cache?.writeFound(query.trackId, chosen);
      return chosen;
    }

    // Tutte cadute significa "non lo so": non va confuso con "non esiste",
    // o l'utente non vedrebbe il pulsante per riprovare.
    if (providers.isNotEmpty && failures == providers.length) {
      throw const LyricsProviderException('Nessuna fonte raggiungibile');
    }

    await cache?.writeMissing(query.trackId);
    return null;
  }
}
