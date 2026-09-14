import '../../models/lyrics.dart';
import '../../utils/app_log.dart';
import 'lyrics_cache.dart';
import 'lyrics_provider.dart';

/// Ordina la catena e sceglie il risultato.
///
/// Regola: vince il primo testo sincronizzato incontrato. Un testo non
/// sincronizzato viene tenuto da parte e usato solo se la catena finisce
/// senza trovarne uno migliore. La cache (fuori dal caso sincronizzato, che
/// scrive subito) si aggiorna solo se la catena e' arrivata in fondo senza
/// che nessuna fonte cadesse: un esito ottenuto con una caduta di mezzo non
/// e' una risposta definitiva e non va congelato ne' come positivo ne' come
/// negativo.
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
        // Una fonte che non rispetta il contratto non deve poter avvelenare
        // la cache ne' la schermata: vale come "non ce l'ho".
        if (!result.isUsable) continue;
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

    // La catena e' "completa" solo se nessuna fonte e' caduta lungo la
    // strada: con una caduta di mezzo l'esito non e' una risposta definitiva
    // ("nessuna fonte ha il testo"), e' "non lo so per almeno una fonte". Un
    // esito del genere si puo' restituire, ma non scrivere in cache: altrimenti
    // un fallback degradato diventa un positivo permanente, o un buco di rete
    // diventa un negativo di sette giorni per un brano che il testo ce l'ha.
    final chainCompleted = failures == 0;

    final chosen = bestUnsynced ?? instrumental;
    if (chosen != null) {
      if (chainCompleted) await cache?.writeFound(query.trackId, chosen);
      return chosen;
    }

    // Tutte cadute significa "non lo so": non va confuso con "non esiste",
    // o l'utente non vedrebbe il pulsante per riprovare.
    if (providers.isNotEmpty && failures == providers.length) {
      throw const LyricsProviderException('Nessuna fonte raggiungibile');
    }

    if (chainCompleted) await cache?.writeMissing(query.trackId);
    return null;
  }
}
