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
        return Lyrics(error: false, syncType: 'LINE_SYNCED', lines: lines);
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
