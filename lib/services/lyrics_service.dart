import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/lyrics.dart';

class LyricsService {
  static const _requestTimeout = Duration(seconds: 10);

  final String baseUrl;
  final http.Client _client;

  LyricsService({String? endpoint, http.Client? client})
    : baseUrl = endpoint ?? dotenv.env['LYRICS_BASE_URL'] ?? '',
      _client = client ?? http.Client();

  Future<Lyrics> getLyrics(String trackId) async {
    if (baseUrl.isEmpty) {
      throw StateError('LYRICS_BASE_URL non configurato');
    }

    final response = await _client
        .get(
          Uri.parse('$baseUrl/?trackid=$trackId'),
          headers: {'Content-Type': 'application/json'},
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw LyricsHttpException(
        'Lyrics non disponibili (${response.statusCode})',
      );
    }

    return Lyrics.fromJson(json.decode(response.body) as Map<String, dynamic>);
  }
}

/// Nome proprio per non collidere con HttpException di dart:io in chi
/// dovesse importare entrambi.
class LyricsHttpException implements Exception {
  final String message;

  const LyricsHttpException(this.message);

  @override
  String toString() => message;
}
