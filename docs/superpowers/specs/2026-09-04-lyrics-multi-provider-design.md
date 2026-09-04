# Sistema multi-provider per i lyrics

Data: 2026-09-04

## Contesto

L'app prende i testi da un solo endpoint, `LYRICS_BASE_URL`, interrogato come
`GET {base}/?trackid={spotifyTrackId}`. Se quel servizio non risponde o non ha
il testo, la funzione centrale dell'app non funziona e non c'e' nessun piano B.

La forma di quelle risposte e' stata confrontata con la documentazione di
`akashrchandran/spotify-lyrics-api` e coincide campo per campo, incluso
`syllables` che l'app ignora:

```json
{"error": false, "syncType": "LINE_SYNCED",
 "lines": [{"startTimeMs": "960", "words": "...", "syllables": [], "endTimeMs": "0"}]}
```

Quel progetto risulta deprecato. Il successore indicato,
`libre-lyrics/librelyrics-spotify`, **non e' un servizio HTTP**: e' un pacchetto
Python plugin della CLI LibreLyrics, che autentica con TOTP contro l'API interna
di Spotify scaricando a runtime un dizionario di segreti da una repo di terzi.
Da un'app Flutter non e' chiamabile senza interporre un backend.

## Obiettivo

Rendere il recupero dei testi resistente alla morte di una singola fonte, senza
introdurre un servizio da ospitare e senza dipendere da credenziali che scadono.

## Decisioni

| Decisione | Scelta | Alternative scartate |
|---|---|---|
| Ambito | Solo fonti con API, tutto dentro l'app | Scraping dietro un backend proprio; scraping direttamente dall'app |
| Selezione | Cerca il sincronizzato lungo la catena, ripiega sul migliore non sincronizzato | Prima risposta utile e stop; interrogazione parallela di tutti |
| Cache | Persistente con tetto massimo | Solo in memoria; nessuna cache |
| Fonte portante | LRCLIB, con il proxy Spotify davanti finche' vive | Wrapper HTTP su librelyrics; solo LRCLIB |

Le otto fonti solo-web della lista iniziale (rentanadviser, megalobiz, lyricsify,
rclyricsband, songmeanings, songlyrics, versuri.ro, AZLyrics) sono escluse: non
hanno API pubbliche e richiederebbero parsing di HTML, fragile ad ogni restyling
e in conflitto con i loro termini d'uso. Musixmatch e Genius sono escluse perche'
le rispettive API ufficiali non restituiscono testi sincronizzati completi.

**Ridondanza di hosting contro ridondanza di fonte.** Piu' istanze di
`spotify-lyrics-api` proteggono dalla caduta di un host, non dal fatto che
Spotify chiuda l'API interna: cadrebbero tutte insieme. LRCLIB e' l'unica fonte
davvero indipendente ed e' per questo la base, non il ripiego.

## Architettura

```
PlayerProvider ──> LyricsRepository ──> cache
                                        ├─ SpotifyProxyProvider  (solo se LYRICS_BASE_URL e' valorizzato)
                                        └─ LrclibProvider         (sempre)
```

Nuovi file sotto `lib/services/lyrics/`:

- `lyrics_provider.dart` — interfaccia e `LyricsQuery`
- `spotify_proxy_provider.dart`
- `lrclib_provider.dart` — include il parser LRC
- `lyrics_cache.dart`
- `lyrics_repository.dart`

`lib/services/lyrics_service.dart` viene eliminato.

## Contratto dei provider

```dart
abstract class LyricsProvider {
  String get name;
  Future<Lyrics?> fetch(LyricsQuery query);
}

class LyricsQuery {
  final String trackId;
  final String title;
  final String primaryArtist;
  final String? albumName;
  final int durationMs;
}
```

`null` significa "questa fonte non ha il testo"; un'eccezione significa "non lo
so". E' la stessa distinzione che `SpotifyService` fa fra 204 e errore, gia'
registrata nelle convenzioni del progetto, e serve a scegliere lo stato finale.

Ogni provider ha un timeout proprio di 5 secondi, piu' corto dei 10 globali: una
fonte morta non deve ritardare di dieci secondi l'arrivo alla successiva.

## Algoritmo di risoluzione

1. Consulta la cache. Una voce positiva viene restituita; una voce negativa
   ancora entro i 7 giorni interrompe subito la ricerca e produce `null`, senza
   interrogare nessuna fonte.
2. Scorre i provider in ordine. Un'eccezione viene registrata e si passa oltre.
3. Al primo risultato utilizzabile **e sincronizzato**: lo scrive in cache e lo
   restituisce.
4. Un risultato utilizzabile ma non sincronizzato viene tenuto da parte e la
   catena prosegue.
5. Esaurita la catena, restituisce il migliore non sincronizzato trovato.
6. Se nessuna fonte ha risposto e **tutte** hanno sollevato eccezione, il
   repository rilancia: diventa `LyricsStatus.failed`, che in interfaccia ha il
   pulsante Retry. Se almeno una ha risposto "non ce l'ho", restituisce `null`:
   diventa `LyricsStatus.unavailable`.

## Adattatori

### SpotifyProxyProvider

`GET {base}/?trackid={trackId}`. Deserializza con `Lyrics.fromJson`, che gia'
gestisce questa forma. E' il codice attuale spostato dietro l'interfaccia, senza
logica nuova. Se `LYRICS_BASE_URL` e' vuoto il provider non entra in catena: il
giorno in cui la voce sparisce dal `.env` l'app continua a funzionare.

### LrclibProvider

`GET https://lrclib.net/api/get?track_name=&artist_name=&album_name=&duration=`,
senza chiavi ne' autenticazione. `duration` va passata in secondi e serve a
distinguere la versione in studio da live e remaster. Risposta verificata:

```json
{"id": 1213, "trackName": "Rolling In The Deep", "artistName": "Adele",
 "albumName": "21", "duration": 228, "instrumental": false,
 "plainLyrics": "There's a fire starting in my heart\n...",
 "syncedLyrics": "[00:05.15] There's a fire starting in my heart\n..."}
```

- `syncedLyrics` presente: parsing LRC verso `LyricLine`, `syncType` a
  `LINE_SYNCED`.
- solo `plainLyrics`: una riga per verso con `startTimeMs` a `0` e `syncType` a
  `UNSYNCED`, forma che l'app gia' mostra senza inseguire.
- `instrumental: true`: nessuna riga, ma non e' la stessa cosa di "non
  trovato". `Lyrics` guadagna un campo booleano `instrumental` (default
  `false`), l'unica modifica al modello: senza, l'informazione non avrebbe modo
  di uscire dal contratto `Future<Lyrics?>` e si perderebbe nel `null`. Il
  repository lo tratta come esito di ultima istanza, e `PlayerProvider` lo mappa
  su `LyricsStatus.instrumental`, che in interfaccia dice "Strumentale" invece
  di "No lyrics for this track".

Il parser LRC deve saltare i tag di metadati (`[ar:]`, `[ti:]`, `[al:]`,
`[length:]`), accettare piu' timestamp sulla stessa riga (legali in LRC,
producono piu' `LyricLine` con lo stesso testo) e ordinare l'esito per tempo
crescente. Formato del timestamp: `[mm:ss.xx]`, con i centesimi opzionali.

A parte il campo `instrumental`, il modello `Lyrics` non cambia: entrambi gli
adattatori costruiscono la forma esistente.

## Cache

Un file JSON per traccia nella directory documenti dell'app, con il track id di
Spotify come nome. Tetto a 200 tracce; alla scrittura, superato il tetto, viene
cancellato il file con data di modifica piu' vecchia. Non serve nessun indice: lo
sfratto si appoggia al filesystem.

Le voci negative ("nessuna fonte ha il testo") vengono memorizzate con scadenza a
7 giorni, cosi' un brano strumentale non ripaga l'intera catena ad ogni
riascolto, ma un testo aggiunto a LRCLIB nel frattempo viene comunque ritrovato.
Le voci positive non scadono.

Richiede la dipendenza `path_provider`. L'alternativa senza nuove dipendenze e'
SharedPreferences, scartata perche' su Android viene caricata interamente in
memoria all'avvio.

## Impatti sul codice esistente

- `PlaybackState` espone `primaryArtist` (oggi `artistName` e' la lista unita con
  `", "`, che LRCLIB non abbina) e `albumName`, gia' presente nella risposta di
  Spotify come `item.album.name` ma non conservato.
- `PlayerProvider._loadLyrics` riceve il `PlaybackState` invece del solo id e
  costruisce la `LyricsQuery`. La guardia `_lyricsRequestId` resta invariata.
- La factory di `PlayerProvider` inietta il repository al posto di
  `LyricsService`, con lo stesso client HTTP condiviso.
- `LyricsStatus` guadagna il valore `instrumental`; `PlayerScreen` gestisce il
  caso nuovo nel suo switch, che e' esaustivo e quindi lo segnalera' da solo.
- `.env`: `LYRICS_BASE_URL` diventa facoltativo. `main()` non deve piu'
  considerarlo mancante un errore di configurazione bloccante.

## Fuori scope

- Circuit breaker sui provider che falliscono ripetutamente. Con due fonti e un
  timeout di 5 secondi non paga la complessita'. E' la prima cosa da aggiungere
  se il proxy Spotify diventasse lento invece che morto.
- Scraping, backend proprio, implementazione del TOTP lato client.
- Scelta manuale della fonte da parte dell'utente.

## Stato della verifica

Verificato dal vivo durante la progettazione:

- LRCLIB risponde, non richiede autenticazione, e restituisce i campi elencati
  sopra. Esempio interrogato: `Rolling in the Deep` / `Adele`.
- La forma di risposta di `spotify-lyrics-api` corrisponde a quella attesa dal
  codice attuale.
- `librelyrics-spotify` e' un pacchetto Python senza interfaccia HTTP.

**Non** verificato:

- Che il `LYRICS_BASE_URL` attualmente in uso sia davvero un deployment di
  `spotify-lyrics-api`: il file `.env` non e' nel repository. La coincidenza di
  rotta e schema lo rende molto probabile ma non e' una prova.
- La copertura reale di LRCLIB sul repertorio che ascolti.
- Il comportamento di `/api/get` in assenza di corrispondenza: se risponda 404
  o 200 con corpo vuoto. La regola non dipende dalla risposta ed e' fissata qui:
  **404 o corpo privo di testi produce `null`, ogni altro esito non-2xx produce
  un'eccezione**. La verifica serve solo a confermare quale ramo si attiva.
- Nulla di questo codice e' mai stato compilato: in questo ambiente non c'e' un
  SDK Flutter.

## Rischi noti

- **Abbinamento sbagliato su LRCLIB.** La ricerca per metadati puo' restituire
  una versione diversa dello stesso brano. Il filtro sulla durata e' la difesa
  principale e va tenuto stretto.
- **Il proxy Spotify e' in fine vita.** Il design lo tratta come rimovibile: sta
  in coda alla configurazione, non nella struttura.
- **LRCLIB e' un servizio comunitario gratuito.** Non offre garanzie di
  disponibilita'. La cache persistente e' anche la mitigazione di questo.
