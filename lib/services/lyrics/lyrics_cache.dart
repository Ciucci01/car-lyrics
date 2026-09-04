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
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;

      if (json['found'] != true) {
        final cachedAt = DateTime.fromMillisecondsSinceEpoch(
          json['cachedAt'] as int,
        );
        if (DateTime.now().difference(cachedAt) > _negativeTtl) {
          try {
            await file.delete();
          } catch (deleteError, deleteStackTrace) {
            // La cancellazione potrebbe fallire (permessi, file gia scomparso).
            logError(
              'Pulizia cache scaduta fallita per $trackId',
              deleteError,
              deleteStackTrace,
            );
          }
          return null;
        }
        return const CacheHit(null);
      }

      return CacheHit(Lyrics.fromJson(json['lyrics'] as Map<String, dynamic>));
    } catch (error, stackTrace) {
      // Voce corrotta: si butta e si riparte dalla rete.
      logError('Voce di cache illeggibile per $trackId', error, stackTrace);
      try {
        await file.delete();
      } catch (deleteError, deleteStackTrace) {
        // La cancellazione potrebbe fallire (permessi, file gia scomparso).
        // Una cache che non si ripulisce e' un peggioramento, non un guasto.
        logError(
          'Pulizia cache fallita per $trackId',
          deleteError,
          deleteStackTrace,
        );
      }
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
    final files = directory
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    if (files.length <= maxEntries) return;

    files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    for (final file in files.take(files.length - maxEntries)) {
      await file.delete();
    }
  }
}
