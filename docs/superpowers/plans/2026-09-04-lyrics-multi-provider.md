# Sistema multi-provider per i lyrics — Piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sostituire l'unica fonte di testi con una catena di provider ordinata, con cache persistente, in modo che la morte di una fonte non spenga la funzione centrale dell'app.

**Architecture:** Un'interfaccia `LyricsProvider` con due implementazioni (proxy Spotify e LRCLIB), orchestrate da un `LyricsRepository` che consulta prima una cache su file, poi scorre i provider preferendo il primo testo sincronizzato. `PlayerProvider` parla solo con il repository.

**Tech Stack:** Flutter/Dart 3.9, `http` (con `package:http/testing.dart` per i test), `path_provider` (nuova), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-04-lyrics-multi-provider-design.md`

## Global Constraints

- Dart SDK `^3.9.0`; nessuna dipendenza nuova oltre a `path_provider`.
- `dart format` a 80 colonne; `flutter analyze` deve uscire pulito.
- Commenti in italiano, stringhe visibili all'utente in inglese.
- Mai `print`: solo `logInfo` / `logError` da `lib/utils/app_log.dart`.
- Un errore il cui esito e' *ignoto* non deve mai sovrascrivere uno stato buono con uno vuoto.
- Timeout per provider: 5 secondi. Tetto cache: 200 tracce. TTL voci negative: 7 giorni.
- Endpoint LRCLIB: `https://lrclib.net/api/get`.
- Messaggi di commit secondo le convenzioni del repo: `[tipo] Oggetto`, italiano, nessuna attribuzione.

**Nota sui test.** Il piano include test solo per la logica pura e per gli adattatori HTTP (via `MockClient`, che non aggiunge dipendenze). Non ci sono widget test. In questo repository non esiste ancora `test/`: la prima task lo crea.

## Struttura dei file

| File | Responsabilita' |
|---|---|
| `lib/services/lyrics/lrc_parser.dart` | Conversione del formato LRC in `LyricLine` |
| `lib/services/lyrics/lyrics_provider.dart` | Interfaccia, `LyricsQuery`, eccezione comune |
| `lib/services/lyrics/spotify_proxy_provider.dart` | Adattatore per `spotify-lyrics-api` |
| `lib/services/lyrics/lrclib_provider.dart` | Adattatore per LRCLIB |
| `lib/services/lyrics/lyrics_cache.dart` | Persistenza su file e sfratto |
| `lib/services/lyrics/lyrics_repository.dart` | Ordine della catena e scelta del risultato |
| `lib/services/lyrics_service.dart` | **Eliminato** alla task 8 |

Rispetto alla spec il parser LRC sta in un file suo invece che dentro l'adattatore: e' l'unita' piu' densa di casi limite del sottosistema e isolarla la rende testabile senza rete.

---

### Task 1: Parser LRC

**Files:**
- Create: `lib/services/lyrics/lrc_parser.dart`
- Test: `test/services/lyrics/lrc_parser_test.dart`

**Interfaces:**
- Consumes: `LyricLine` da `lib/models/lyrics.dart` (esistente).
- Produces: `List<LyricLine> parseLrc(String body)` — righe ordinate per tempo crescente; lista vuota se il corpo non contiene timestamp.

- [x] **Step 1: Scrivere il test che fallisce**

```dart
// test/services/lyrics/lrc_parser_test.dart
import 'package:car_play/services/lyrics/lrc_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converte i timestamp in millisecondi', () {
    final lines = parseLrc('[00:05.15] Prima riga\n[01:02.40] Seconda riga');

    expect(lines.length, 2);
    expect(lines[0].startTime, 5150);
    expect(lines[0].words, 'Prima riga');
    expect(lines[1].startTime, 62400);
  });

  test('salta i tag di metadati', () {
    final lines = parseLrc('[ar:Adele]\n[length:03:48]\n[00:01.00] Testo');

    expect(lines.length, 1);
    expect(lines[0].words, 'Testo');
  });

  test('espande le righe con piu timestamp e le riordina', () {
    final lines = parseLrc('[00:30.00][00:10.00] Ritornello');

    expect(lines.map((l) => l.startTime).toList(), [10000, 30000]);
    expect(lines.every((l) => l.words == 'Ritornello'), isTrue);
  });

  test('gestisce i centesimi assenti o a tre cifre', () {
    final lines = parseLrc('[00:02] A\n[00:03.7] B\n[00:04.125] C');

    expect(lines.map((l) => l.startTime).toList(), [2000, 3700, 4125]);
  });

  test('restituisce vuoto su un corpo senza timestamp', () {
    expect(parseLrc('solo testo\nsenza tempi'), isEmpty);
  });
}
```

- [x] **Step 2: Eseguire il test e verificare che fallisca**

Run: `flutter test test/services/lyrics/lrc_parser_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'car_play' ... lrc_parser.dart` (il file non esiste ancora).

- [x] **Step 3: Scrivere l'implementazione minima**

```dart
// lib/services/lyrics/lrc_parser.dart
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

  result.sort((a, b) => a.startTime.compareTo(b.startTime));
  return result;
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
```

- [x] **Step 4: Eseguire i test e verificare che passino**

Run: `flutter test test/services/lyrics/lrc_parser_test.dart`
Expected: PASS, 5 test.

- [x] **Step 5: Commit**

```bash
git add lib/services/lyrics/lrc_parser.dart test/services/lyrics/lrc_parser_test.dart
git commit -m "[feat] Parser del formato LRC"
```

---

### Task 2: Campi nuovi nei modelli

**Files:**
- Modify: `lib/models/lyrics.dart`
- Modify: `lib/models/playback_state.dart`
- Test: `test/models/lyrics_test.dart`

**Interfaces:**
- Produces: `Lyrics.instrumental` (`bool`, default `false`); `Lyrics.toJson()` → `Map<String, dynamic>`; `PlaybackState.primaryArtist` (`String`); `PlaybackState.albumName` (`String?`).

`instrumental` serve perche' LRCLIB distingue "brano strumentale" da "testo non trovato", e senza un campo dedicato quell'informazione si perderebbe nel `null` del contratto `Future<Lyrics?>`. `toJson` serve alla cache della task 6.

- [x] **Step 1: Scrivere il test che fallisce**

```dart
// test/models/lyrics_test.dart
import 'package:car_play/models/lyrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sopravvive al giro completo su JSON', () {
    const original = Lyrics(
      error: false,
      syncType: 'LINE_SYNCED',
      lines: [LyricLine(startTimeMs: '900', words: 'Ciao', endTimeMs: '0')],
    );

    final restored = Lyrics.fromJson(original.toJson());

    expect(restored.syncType, 'LINE_SYNCED');
    expect(restored.instrumental, isFalse);
    expect(restored.lines.single.startTime, 900);
    expect(restored.lines.single.words, 'Ciao');
  });

  test('conserva il flag strumentale', () {
    const original = Lyrics(
      error: false,
      syncType: 'UNSYNCED',
      lines: [],
      instrumental: true,
    );

    expect(Lyrics.fromJson(original.toJson()).instrumental, isTrue);
  });

  test('un brano strumentale non e utilizzabile come testo', () {
    const lyrics = Lyrics(
      error: false,
      syncType: 'UNSYNCED',
      lines: [],
      instrumental: true,
    );

    expect(lyrics.isUsable, isFalse);
  });
}
```

- [x] **Step 2: Eseguire il test e verificare che fallisca**

Run: `flutter test test/models/lyrics_test.dart`
Expected: FAIL — `No named parameter with the name 'instrumental'` e `The method 'toJson' isn't defined`.

- [x] **Step 3: Modificare `lib/models/lyrics.dart`**

Aggiungere il campo al costruttore e alla classe, leggerlo in `fromJson`, e aggiungere `toJson`:

```dart
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
```

Il resto della classe (`isUsable`, `isSynced`) resta invariato.

- [x] **Step 4: Modificare `lib/models/playback_state.dart`**

Aggiungere due campi. Nel costruttore, fra `artistName` e `albumImageUrl`:

```dart
  /// LRCLIB abbina su un artista singolo: artistName e' la lista unita con
  /// ", " e non combacerebbe.
  final String primaryArtist;
  final String? albumName;
```

Renderli `required` nel costruttore e in `copyWith` (che li ripropaga invariati). In `parse`, dopo il calcolo di `artists`:

```dart
    final album = item['album'] as Map<String, dynamic>?;

    return PlaybackState(
      trackId: id,
      trackName: item['name'] as String? ?? '',
      artistName: artists?.join(', ') ?? '',
      primaryArtist: (artists != null && artists.isNotEmpty) ? artists.first : '',
      albumName: album?['name'] as String?,
      albumImageUrl: ...,   // invariato
      ...
    );
```

Sostituire l'accesso esistente a `item['album']?['images']` con `album?['images']` per non leggerlo due volte.

- [x] **Step 5: Eseguire i test e l'analisi**

Run: `flutter test test/models/lyrics_test.dart && flutter analyze`
Expected: 3 test PASS; analyze pulito.

- [x] **Step 6: Commit**

```bash
git add lib/models test/models
git commit -m "[feat] Flag strumentale, serializzazione e metadati per la ricerca"
```

---

### Task 3: Interfaccia dei provider

**Files:**
- Create: `lib/services/lyrics/lyrics_provider.dart`

**Interfaces:**
- Consumes: `Lyrics` da `lib/models/lyrics.dart`.
- Produces: `abstract class LyricsProvider { String get name; Future<Lyrics?> fetch(LyricsQuery query); }`; `class LyricsQuery` con campi `trackId`, `title`, `primaryArtist`, `albumName`, `durationMs`; `class LyricsProviderException implements Exception` con campo `message`.

Questa task non ha test propri: e' sola dichiarazione, e viene esercitata dalle task 4, 5 e 7.

- [x] **Step 1: Creare il file**

```dart
// lib/services/lyrics/lyrics_provider.dart
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
```

- [x] **Step 2: Verificare che compili**

Run: `flutter analyze lib/services/lyrics/lyrics_provider.dart`
Expected: `No issues found`.

- [x] **Step 3: Commit**

```bash
git add lib/services/lyrics/lyrics_provider.dart
git commit -m "[feat] Contratto comune delle fonti di testi"
```

---

### Task 4: Adattatore del proxy Spotify

**Files:**
- Create: `lib/services/lyrics/spotify_proxy_provider.dart`
- Test: `test/services/lyrics/spotify_proxy_provider_test.dart`

**Interfaces:**
- Consumes: `LyricsProvider`, `LyricsQuery`, `LyricsProviderException` (task 3); `Lyrics` (task 2).
- Produces: `SpotifyProxyProvider({required String baseUrl, http.Client? client})`, con `name == 'spotify-proxy'`.

- [x] **Step 1: Scrivere il test che fallisce**

```dart
// test/services/lyrics/spotify_proxy_provider_test.dart
import 'package:car_play/services/lyrics/lyrics_provider.dart';
import 'package:car_play/services/lyrics/spotify_proxy_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _query = LyricsQuery(
  trackId: 'abc123',
  title: 'Rolling in the Deep',
  primaryArtist: 'Adele',
  albumName: '21',
  durationMs: 228000,
);

void main() {
  test('interroga per trackId e converte la risposta', () async {
    late Uri requested;
    final provider = SpotifyProxyProvider(
      baseUrl: 'https://proxy.example',
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          '{"error":false,"syncType":"LINE_SYNCED",'
          '"lines":[{"startTimeMs":"960","words":"Uno","endTimeMs":"0"}]}',
          200,
        );
      }),
    );

    final lyrics = await provider.fetch(_query);

    expect(requested.queryParameters['trackid'], 'abc123');
    expect(lyrics!.lines.single.words, 'Uno');
    expect(lyrics.isSynced, isTrue);
  });

  test('restituisce null quando la fonte dichiara di non averlo', () async {
    final provider = SpotifyProxyProvider(
      baseUrl: 'https://proxy.example',
      client: MockClient(
        (_) async => http.Response('{"error":true,"lines":[]}', 200),
      ),
    );

    expect(await provider.fetch(_query), isNull);
  });

  test('solleva su errore del server', () async {
    final provider = SpotifyProxyProvider(
      baseUrl: 'https://proxy.example',
      client: MockClient((_) async => http.Response('boom', 500)),
    );

    expect(
      () => provider.fetch(_query),
      throwsA(isA<LyricsProviderException>()),
    );
  });
}
```

- [x] **Step 2: Eseguire il test e verificare che fallisca**

Run: `flutter test test/services/lyrics/spotify_proxy_provider_test.dart`
Expected: FAIL — il file `spotify_proxy_provider.dart` non esiste.

- [x] **Step 3: Scrivere l'implementazione**

```dart
// lib/services/lyrics/spotify_proxy_provider.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/lyrics.dart';
import 'lyrics_provider.dart';

/// Adattatore per i deployment di akashrchandran/spotify-lyrics-api.
///
/// Restituisce la forma interna di Spotify, la stessa che Lyrics.fromJson
/// gia' sa leggere: qui non c'e' conversione, solo trasporto.
class SpotifyProxyProvider implements LyricsProvider {
  static const _timeout = Duration(seconds: 5);

  final String baseUrl;
  final http.Client _client;

  SpotifyProxyProvider({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  @override
  String get name => 'spotify-proxy';

  @override
  Future<Lyrics?> fetch(LyricsQuery query) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/?trackid=${query.trackId}'))
        .timeout(_timeout);

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw LyricsProviderException('$name: HTTP ${response.statusCode}');
    }

    final lyrics = Lyrics.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    return lyrics.isUsable ? lyrics : null;
  }
}
```

- [x] **Step 4: Eseguire i test e verificare che passino**

Run: `flutter test test/services/lyrics/spotify_proxy_provider_test.dart`
Expected: PASS, 3 test.

- [x] **Step 5: Commit**

```bash
git add lib/services/lyrics/spotify_proxy_provider.dart test/services/lyrics/spotify_proxy_provider_test.dart
git commit -m "[feat] Adattatore per il proxy dei testi di Spotify"
```

---

### Task 5: Adattatore LRCLIB

**Files:**
- Create: `lib/services/lyrics/lrclib_provider.dart`
- Test: `test/services/lyrics/lrclib_provider_test.dart`

**Interfaces:**
- Consumes: `parseLrc` (task 1); `LyricsProvider`, `LyricsQuery`, `LyricsProviderException` (task 3); `Lyrics`, `LyricLine` (task 2).
- Produces: `LrclibProvider({http.Client? client, String host = 'lrclib.net'})`, con `name == 'lrclib'`.

- [x] **Step 1: Confermare il comportamento in assenza di corrispondenza**

Run:
```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  'https://lrclib.net/api/get?track_name=zzz_non_esiste_zzz&artist_name=zzz'
```
Expected: `404`. La regola resta quella della spec a prescindere — 404 o corpo senza testi produce `null`, ogni altro non-2xx solleva — quindi se il codice fosse 200 con corpo vuoto non cambia nulla dell'implementazione qui sotto, che copre entrambi i rami.

- [x] **Step 2: Scrivere il test che fallisce**

```dart
// test/services/lyrics/lrclib_provider_test.dart
import 'package:car_play/services/lyrics/lrclib_provider.dart';
import 'package:car_play/services/lyrics/lyrics_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _query = LyricsQuery(
  trackId: 'abc123',
  title: 'Rolling in the Deep',
  primaryArtist: 'Adele',
  albumName: '21',
  durationMs: 228400,
);

void main() {
  test('cerca per metadati con la durata in secondi', () async {
    late Uri requested;
    final provider = LrclibProvider(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          '{"instrumental":false,'
          '"syncedLyrics":"[00:05.15] Prima\\n[00:09.74] Seconda",'
          '"plainLyrics":"Prima\\nSeconda"}',
          200,
        );
      }),
    );

    final lyrics = await provider.fetch(_query);

    expect(requested.queryParameters['track_name'], 'Rolling in the Deep');
    expect(requested.queryParameters['artist_name'], 'Adele');
    expect(requested.queryParameters['album_name'], '21');
    expect(requested.queryParameters['duration'], '228');
    expect(lyrics!.isSynced, isTrue);
    expect(lyrics.lines.first.startTime, 5150);
  });

  test('ripiega sul testo semplice come non sincronizzato', () async {
    final provider = LrclibProvider(
      client: MockClient(
        (_) async => http.Response(
          '{"instrumental":false,"syncedLyrics":null,'
          '"plainLyrics":"Prima\\nSeconda"}',
          200,
        ),
      ),
    );

    final lyrics = await provider.fetch(_query);

    expect(lyrics!.syncType, 'UNSYNCED');
    expect(lyrics.isSynced, isFalse);
    expect(lyrics.lines.length, 2);
  });

  test('segnala i brani strumentali', () async {
    final provider = LrclibProvider(
      client: MockClient(
        (_) async => http.Response(
          '{"instrumental":true,"syncedLyrics":null,"plainLyrics":null}',
          200,
        ),
      ),
    );

    final lyrics = await provider.fetch(_query);

    expect(lyrics!.instrumental, isTrue);
    expect(lyrics.lines, isEmpty);
  });

  test('restituisce null su 404', () async {
    final provider = LrclibProvider(
      client: MockClient((_) async => http.Response('{}', 404)),
    );

    expect(await provider.fetch(_query), isNull);
  });

  test('solleva su errore del server', () async {
    final provider = LrclibProvider(
      client: MockClient((_) async => http.Response('boom', 503)),
    );

    expect(
      () => provider.fetch(_query),
      throwsA(isA<LyricsProviderException>()),
    );
  });
}
```

- [x] **Step 3: Eseguire il test e verificare che fallisca**

Run: `flutter test test/services/lyrics/lrclib_provider_test.dart`
Expected: FAIL — il file `lrclib_provider.dart` non esiste.

- [x] **Step 4: Scrivere l'implementazione**

```dart
// lib/services/lyrics/lrclib_provider.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/lyrics.dart';
import 'lrc_parser.dart';
import 'lyrics_provider.dart';

/// Adattatore per LRCLIB: testi contribuiti dalla comunita', senza chiavi
/// ne' cookie. E' l'unica fonte della catena che non passa da Spotify, quindi
/// l'unica che sopravvive alla chiusura dell'API interna.
class LrclibProvider implements LyricsProvider {
  static const _timeout = Duration(seconds: 5);

  final String host;
  final http.Client _client;

  LrclibProvider({http.Client? client, this.host = 'lrclib.net'})
    : _client = client ?? http.Client();

  @override
  String get name => 'lrclib';

  @override
  Future<Lyrics?> fetch(LyricsQuery query) async {
    final uri = Uri.https(host, '/api/get', {
      'track_name': query.title,
      'artist_name': query.primaryArtist,
      if (query.albumName != null) 'album_name': query.albumName!,
      'duration': '${(query.durationMs / 1000).round()}',
    });

    final response = await _client
        .get(uri, headers: {'User-Agent': 'car_play/0.1.0'})
        .timeout(_timeout);

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw LyricsProviderException('$name: HTTP ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    // Strumentale non e' "non trovato": va distinto in interfaccia.
    if (json['instrumental'] == true) {
      return const Lyrics(
        error: false,
        syncType: 'UNSYNCED',
        lines: [],
        instrumental: true,
      );
    }

    final synced = json['syncedLyrics'] as String?;
    if (synced != null && synced.trim().isNotEmpty) {
      final lines = parseLrc(synced);
      if (lines.isNotEmpty) {
        return Lyrics(
          error: false,
          syncType: 'LINE_SYNCED',
          lines: lines,
        );
      }
    }

    final plain = json['plainLyrics'] as String?;
    if (plain != null && plain.trim().isNotEmpty) {
      return Lyrics(
        error: false,
        syncType: 'UNSYNCED',
        lines: [
          for (final verse in plain.split('\n'))
            LyricLine(startTimeMs: '0', words: verse, endTimeMs: '0'),
        ],
      );
    }

    return null;
  }
}
```

- [x] **Step 5: Eseguire i test e verificare che passino**

Run: `flutter test test/services/lyrics/lrclib_provider_test.dart`
Expected: PASS, 5 test.

- [x] **Step 6: Commit**

```bash
git add lib/services/lyrics/lrclib_provider.dart test/services/lyrics/lrclib_provider_test.dart
git commit -m "[feat] Adattatore LRCLIB con ripiego sul testo non sincronizzato"
```

---

### Task 6: Cache su file

**Files:**
- Create: `lib/services/lyrics/lyrics_cache.dart`
- Modify: `pubspec.yaml` (aggiunta di `path_provider`)
- Test: `test/services/lyrics/lyrics_cache_test.dart`

**Interfaces:**
- Consumes: `Lyrics` con `toJson`/`fromJson` (task 2).
- Produces: `LyricsCache(Directory directory)`; `static Future<LyricsCache> open()`; `Future<CacheHit?> read(String trackId)`; `Future<void> writeFound(String trackId, Lyrics lyrics)`; `Future<void> writeMissing(String trackId)`. `class CacheHit { final Lyrics? lyrics; }` — `null` come ritorno di `read` significa "non so", un `CacheHit` con `lyrics` nullo significa "nessuna fonte ce l'ha, e la risposta e' ancora fresca".

- [x] **Step 1: Aggiungere la dipendenza**

In `pubspec.yaml`, fra `shared_preferences` e `scrollable_positioned_list`:

```yaml
  path_provider: ^2.1.4
```

Run: `flutter pub get`
Expected: risoluzione senza conflitti.

- [x] **Step 2: Scrivere il test che fallisce**

```dart
// test/services/lyrics/lyrics_cache_test.dart
import 'dart:io';

import 'package:car_play/models/lyrics.dart';
import 'package:car_play/services/lyrics/lyrics_cache.dart';
import 'package:flutter_test/flutter_test.dart';

const _lyrics = Lyrics(
  error: false,
  syncType: 'LINE_SYNCED',
  lines: [LyricLine(startTimeMs: '900', words: 'Ciao', endTimeMs: '0')],
);

void main() {
  late Directory directory;
  late LyricsCache cache;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('lyrics_cache_test');
    cache = LyricsCache(directory);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('restituisce null quando non sa niente della traccia', () async {
    expect(await cache.read('mai_visto'), isNull);
  });

  test('rilegge un testo salvato', () async {
    await cache.writeFound('t1', _lyrics);

    final hit = await cache.read('t1');

    expect(hit, isNotNull);
    expect(hit!.lyrics!.lines.single.words, 'Ciao');
  });

  test('ricorda un esito negativo ancora fresco', () async {
    await cache.writeMissing('t2');

    final hit = await cache.read('t2');

    expect(hit, isNotNull);
    expect(hit!.lyrics, isNull);
  });

  test('dimentica un esito negativo scaduto', () async {
    await cache.writeMissing('t3');
    final file = File('${directory.path}/t3.json');
    file.setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 8)),
    );
    // La scadenza viaggia nel contenuto, non nel filesystem: si riscrive la
    // data di salvataggio a otto giorni fa.
    final stale = file.readAsStringSync().replaceFirst(
      RegExp(r'"cachedAt":\d+'),
      '"cachedAt":${DateTime.now().subtract(const Duration(days: 8)).millisecondsSinceEpoch}',
    );
    file.writeAsStringSync(stale);

    expect(await cache.read('t3'), isNull);
  });

  test('sfratta la voce piu vecchia oltre il tetto', () async {
    final small = LyricsCache(directory, maxEntries: 2);

    await small.writeFound('a', _lyrics);
    await Future.delayed(const Duration(milliseconds: 10));
    await small.writeFound('b', _lyrics);
    await Future.delayed(const Duration(milliseconds: 10));
    await small.writeFound('c', _lyrics);

    expect(await small.read('a'), isNull);
    expect(await small.read('c'), isNotNull);
  });
}
```

- [x] **Step 3: Eseguire il test e verificare che fallisca**

Run: `flutter test test/services/lyrics/lyrics_cache_test.dart`
Expected: FAIL — il file `lyrics_cache.dart` non esiste.

- [x] **Step 4: Scrivere l'implementazione**

```dart
// lib/services/lyrics/lyrics_cache.dart
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../models/lyrics.dart';
import '../../utils/app_log.dart';

/// Esito noto per una traccia. `lyrics` nullo significa che nessuna fonte
/// aveva il testo, e che la risposta e' ancora entro la scadenza.
class CacheHit {
  final Lyrics? lyrics;

  const CacheHit(this.lyrics);
}

/// Un file JSON per traccia, con il track id di Spotify come nome.
///
/// Lo sfratto si appoggia alla data di modifica dei file, cosi' non serve
/// nessun indice da tenere allineato.
class LyricsCache {
  static const _defaultMaxEntries = 200;

  /// Gli esiti negativi scadono: un testo aggiunto a LRCLIB nel frattempo
  /// deve poter essere ritrovato.
  static const _negativeTtl = Duration(days: 7);

  final Directory directory;
  final int maxEntries;

  LyricsCache(this.directory, {this.maxEntries = _defaultMaxEntries});

  static Future<LyricsCache> open() async {
    final base = await getApplicationDocumentsDirectory();
    final directory = Directory('${base.path}/lyrics_cache');
    if (!directory.existsSync()) directory.createSync(recursive: true);
    return LyricsCache(directory);
  }

  File _fileFor(String trackId) => File('${directory.path}/$trackId.json');

  Future<CacheHit?> read(String trackId) async {
    final file = _fileFor(trackId);
    if (!file.existsSync()) return null;

    try {
      final json = jsonDecode(await file.readAsString())
          as Map<String, dynamic>;

      if (json['found'] != true) {
        final cachedAt = DateTime.fromMillisecondsSinceEpoch(
          json['cachedAt'] as int,
        );
        if (DateTime.now().difference(cachedAt) > _negativeTtl) {
          await file.delete();
          return null;
        }
        return const CacheHit(null);
      }

      return CacheHit(
        Lyrics.fromJson(json['lyrics'] as Map<String, dynamic>),
      );
    } catch (error, stackTrace) {
      // Voce corrotta: si butta e si riparte dalla rete.
      logError('Voce di cache illeggibile per $trackId', error, stackTrace);
      await file.delete();
      return null;
    }
  }

  Future<void> writeFound(String trackId, Lyrics lyrics) {
    return _write(trackId, {
      'cachedAt': DateTime.now().millisecondsSinceEpoch,
      'found': true,
      'lyrics': lyrics.toJson(),
    });
  }

  Future<void> writeMissing(String trackId) {
    return _write(trackId, {
      'cachedAt': DateTime.now().millisecondsSinceEpoch,
      'found': false,
    });
  }

  Future<void> _write(String trackId, Map<String, dynamic> payload) async {
    try {
      await _fileFor(trackId).writeAsString(jsonEncode(payload));
      await _evict();
    } catch (error, stackTrace) {
      // Una cache che non scrive e' un peggioramento, non un guasto.
      logError('Scrittura in cache fallita per $trackId', error, stackTrace);
    }
  }

  Future<void> _evict() async {
    final files = directory.listSync().whereType<File>().toList();
    if (files.length <= maxEntries) return;

    files.sort(
      (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
    );
    for (final file in files.take(files.length - maxEntries)) {
      await file.delete();
    }
  }
}
```

- [x] **Step 5: Eseguire i test e verificare che passino**

Run: `flutter test test/services/lyrics/lyrics_cache_test.dart`
Expected: PASS, 5 test.

- [x] **Step 6: Commit**

```bash
git add lib/services/lyrics/lyrics_cache.dart test/services/lyrics/lyrics_cache_test.dart pubspec.yaml pubspec.lock
git commit -m "[feat] Cache su file dei testi con sfratto e scadenza dei negativi"
```

---

### Task 7: Repository

**Files:**
- Create: `lib/services/lyrics/lyrics_repository.dart`
- Test: `test/services/lyrics/lyrics_repository_test.dart`

**Interfaces:**
- Consumes: `LyricsProvider`, `LyricsQuery`, `LyricsProviderException` (task 3); `LyricsCache`, `CacheHit` (task 6).
- Produces: `LyricsRepository({required List<LyricsProvider> providers, LyricsCache? cache})`; `Future<Lyrics?> lyricsFor(LyricsQuery query)` — solleva `LyricsProviderException` se ogni provider ha sollevato.

- [x] **Step 1: Scrivere il test che fallisce**

```dart
// test/services/lyrics/lyrics_repository_test.dart
import 'package:car_play/models/lyrics.dart';
import 'package:car_play/services/lyrics/lyrics_provider.dart';
import 'package:car_play/services/lyrics/lyrics_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _query = LyricsQuery(
  trackId: 'abc123',
  title: 'Rolling in the Deep',
  primaryArtist: 'Adele',
  albumName: '21',
  durationMs: 228000,
);

const _synced = Lyrics(
  error: false,
  syncType: 'LINE_SYNCED',
  lines: [LyricLine(startTimeMs: '900', words: 'Sincronizzato', endTimeMs: '0')],
);

const _unsynced = Lyrics(
  error: false,
  syncType: 'UNSYNCED',
  lines: [LyricLine(startTimeMs: '0', words: 'Semplice', endTimeMs: '0')],
);

class _FakeProvider implements LyricsProvider {
  final Lyrics? result;
  final Object? error;
  int calls = 0;

  _FakeProvider({this.result, this.error});

  @override
  String get name => 'fake';

  @override
  Future<Lyrics?> fetch(LyricsQuery query) async {
    calls++;
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  test('si ferma alla prima fonte sincronizzata', () async {
    final second = _FakeProvider(result: _synced);
    final repository = LyricsRepository(
      providers: [_FakeProvider(result: _synced), second],
    );

    final lyrics = await repository.lyricsFor(_query);

    expect(lyrics!.isSynced, isTrue);
    expect(second.calls, 0);
  });

  test('preferisce il sincronizzato che viene dopo un non sincronizzato',
      () async {
    final repository = LyricsRepository(
      providers: [
        _FakeProvider(result: _unsynced),
        _FakeProvider(result: _synced),
      ],
    );

    final lyrics = await repository.lyricsFor(_query);

    expect(lyrics!.lines.single.words, 'Sincronizzato');
  });

  test('ripiega sul non sincronizzato se nessuno ha di meglio', () async {
    final repository = LyricsRepository(
      providers: [_FakeProvider(result: _unsynced), _FakeProvider()],
    );

    final lyrics = await repository.lyricsFor(_query);

    expect(lyrics!.lines.single.words, 'Semplice');
  });

  test('un provider rotto non ferma la catena', () async {
    final repository = LyricsRepository(
      providers: [
        _FakeProvider(error: const LyricsProviderException('giu')),
        _FakeProvider(result: _synced),
      ],
    );

    expect((await repository.lyricsFor(_query))!.isSynced, isTrue);
  });

  test('restituisce null se le fonti rispondono di non averlo', () async {
    final repository = LyricsRepository(
      providers: [_FakeProvider(), _FakeProvider()],
    );

    expect(await repository.lyricsFor(_query), isNull);
  });

  test('solleva se ogni fonte e caduta', () async {
    final repository = LyricsRepository(
      providers: [
        _FakeProvider(error: const LyricsProviderException('giu')),
        _FakeProvider(error: const LyricsProviderException('anche')),
      ],
    );

    expect(
      () => repository.lyricsFor(_query),
      throwsA(isA<LyricsProviderException>()),
    );
  });
}
```

- [x] **Step 2: Eseguire il test e verificare che fallisca**

Run: `flutter test test/services/lyrics/lyrics_repository_test.dart`
Expected: FAIL — il file `lyrics_repository.dart` non esiste.

- [x] **Step 3: Scrivere l'implementazione**

```dart
// lib/services/lyrics/lyrics_repository.dart
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
  final LyricsCache? cache;

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
```

- [x] **Step 4: Eseguire i test e verificare che passino**

Run: `flutter test test/services/lyrics/lyrics_repository_test.dart`
Expected: PASS, 6 test.

- [x] **Step 5: Commit**

```bash
git add lib/services/lyrics/lyrics_repository.dart test/services/lyrics/lyrics_repository_test.dart
git commit -m "[feat] Repository che ordina le fonti e preferisce il sincronizzato"
```

---

### Task 8: Innesto nell'app

**Files:**
- Delete: `lib/services/lyrics_service.dart`
- Modify: `lib/providers/player_provider.dart`
- Modify: `lib/screens/player_screen.dart`
- Modify: `lib/main.dart`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: `LyricsRepository`, `LyricsQuery`, `LyricsProviderException`, `LyricsCache`, `SpotifyProxyProvider`, `LrclibProvider` (task 3-7); `PlaybackState.primaryArtist` e `albumName` (task 2).
- Produces: `LyricsStatus.instrumental`.

- [x] **Step 1: Sostituire il servizio nel provider**

In `lib/providers/player_provider.dart`:

1. Sostituire l'import di `../services/lyrics_service.dart` con:
```dart
import '../services/lyrics/lrclib_provider.dart';
import '../services/lyrics/lyrics_cache.dart';
import '../services/lyrics/lyrics_provider.dart';
import '../services/lyrics/lyrics_repository.dart';
import '../services/lyrics/spotify_proxy_provider.dart';
```
2. Aggiungere `instrumental` all'enum `LyricsStatus`:
```dart
enum LyricsStatus { idle, loading, ready, unavailable, instrumental, failed }
```
3. Rinominare il campo `_lyricsService` in `_lyricsRepository`, di tipo `LyricsRepository`, e rinominare il parametro omonimo della factory e del costruttore privato in `lyricsRepository`. Nella factory, al posto di `lyricsService ?? LyricsService()`, costruire la catena:

```dart
    final proxyBaseUrl = dotenv.env['LYRICS_BASE_URL'] ?? '';
    final providers = <LyricsProvider>[
      // Il proxy Spotify entra in catena solo se configurato: il giorno che
      // smette di esistere basta togliere la voce dal .env.
      if (proxyBaseUrl.isNotEmpty)
        SpotifyProxyProvider(baseUrl: proxyBaseUrl, client: httpClient),
      LrclibProvider(client: httpClient),
    ];
```
La factory diventa `async`? No: `LyricsCache.open()` e' asincrona, quindi la cache si aggancia dopo. Aggiungere al costruttore privato:
```dart
    unawaited(_attachCache());
```
e il metodo:
```dart
  /// La cache si apre dopo la costruzione: finche' non e' pronta la catena
  /// funziona lo stesso, solo senza risparmiare richieste.
  Future<void> _attachCache() async {
    try {
      _lyricsRepository.cache = await LyricsCache.open();
    } catch (error, stackTrace) {
      logError('Cache dei testi non disponibile', error, stackTrace);
    }
  }
```
che richiede di rendere `cache` un campo non-`final` in `LyricsRepository` (`LyricsCache? cache;`).

Serve anche l'import di `package:flutter_dotenv/flutter_dotenv.dart` nel provider.

- [x] **Step 2: Aggiornare `_loadLyrics`**

Sostituire la firma e il corpo:

```dart
  Future<void> _loadLyrics(PlaybackState playback) async {
    final requestId = ++_lyricsRequestId;

    _lyrics = null;
    _currentLineIndex = -1;
    _lyricsStatus = LyricsStatus.loading;
    notifyListeners();

    try {
      final lyrics = await _lyricsRepository.lyricsFor(
        LyricsQuery(
          trackId: playback.trackId,
          title: playback.trackName,
          primaryArtist: playback.primaryArtist,
          albumName: playback.albumName,
          durationMs: playback.durationMs,
        ),
      );
      if (requestId != _lyricsRequestId) return;

      if (lyrics == null) {
        _lyricsStatus = LyricsStatus.unavailable;
      } else if (lyrics.instrumental) {
        _lyricsStatus = LyricsStatus.instrumental;
      } else if (lyrics.isUsable) {
        _lyrics = lyrics;
        _lyricsStatus = LyricsStatus.ready;
        _updateCurrentLine(estimatedProgressMs);
      } else {
        _lyricsStatus = LyricsStatus.unavailable;
      }
    } catch (error, stackTrace) {
      if (requestId != _lyricsRequestId) return;
      logError('Caricamento lyrics fallito', error, stackTrace);
      _lyricsStatus = LyricsStatus.failed;
    }

    notifyListeners();
  }
```

Aggiornare i due chiamanti: in `_applyPlayback` `unawaited(_loadLyrics(playback));` e in `retryLyrics` `if (playback != null) await _loadLyrics(playback);` (con `final playback = _playback;`).

- [x] **Step 3: Aggiungere il caso in interfaccia**

In `lib/screens/player_screen.dart`, dentro `_buildLyricsArea`, aggiungere un ramo allo switch:

```dart
      LyricsStatus.instrumental => const _Message(
        icon: Icons.music_note,
        text: 'Instrumental track',
      ),
```

- [x] **Step 4: Rendere `LYRICS_BASE_URL` facoltativo**

In `lib/main.dart`, in `_describeMissingConfig`, sostituire la lista con:

```dart
  final missing = ['SPOTIFY_CLIENT_ID']
```

- [x] **Step 5: Eliminare il servizio vecchio**

```bash
git rm lib/services/lyrics_service.dart
```

- [x] **Step 6: Verificare che tutto stia in piedi**

Run: `flutter analyze && flutter test && dart format --set-exit-if-changed lib test`
Expected: analyze pulito, tutti i test verdi, nessun file da riformattare.

- [x] **Step 7: Aggiornare CLAUDE.md**

Nella sezione `### Lyrics`, sostituire il paragrafo che descrive `LyricsService` con la descrizione della catena: ordine dei provider, contratto `null` contro eccezione, regola del "primo sincronizzato vince", cache su file con tetto 200 e negativi a 7 giorni, e il fatto che `LYRICS_BASE_URL` sia ora facoltativo. Aggiornare anche la sezione `## Setup`, dove quella chiave e' descritta come necessaria.

- [x] **Step 8: Commit**

```bash
git add -A lib test CLAUDE.md
git commit -m "[feat] Innesta la catena multi-provider al posto del servizio unico"
```

- [x] **Step 9: Verifica manuale sul dispositivo**

Con `.env` presente e un brano in riproduzione su Spotify:

1. Brano con testo sincronizzato: il testo scorre e si evidenzia come prima.
2. Svuotare `LYRICS_BASE_URL` nel `.env` e riavviare: l'app parte lo stesso e i testi arrivano da LRCLIB.
3. Brano strumentale noto: compare "Instrumental track", non "No lyrics for this track".
4. Riascoltare un brano gia' visto in modalita' aereo: il testo compare comunque, dalla cache.

Annotare gli esiti; se il punto 4 fallisce, controllare che `_attachCache` non abbia loggato un errore all'avvio.

---

## Self-review

**Copertura della spec.** Ogni sezione della spec ha una task: catena e ordine (7, 8), contratto dei provider (3), algoritmo di risoluzione (7), adattatore Spotify (4), adattatore LRCLIB e parser (1, 5), stato strumentale (2, 5, 8), cache con tetto e TTL (6), impatti su `PlaybackState`, `PlayerProvider`, interfaccia e `.env` (2, 8), eliminazione di `lyrics_service.dart` (8). Il fuori scope della spec resta fuori.

**Coerenza dei nomi.** `parseLrc`, `LyricsQuery`, `LyricsProvider.fetch`, `LyricsProviderException`, `CacheHit`, `LyricsCache.read/writeFound/writeMissing`, `LyricsRepository.lyricsFor` sono usati con la stessa firma in tutte le task che li nominano.

**Punto aperto segnalato all'esecutore.** La task 8 rende `LyricsRepository.cache` mutabile per poterla agganciare dopo la costruzione asincrona. E' l'unica concessione di questo tipo del piano; l'alternativa sarebbe rendere asincrona la costruzione di `PlayerProvider`, che ricadrebbe su `main()` e su `ChangeNotifierProvider`.
