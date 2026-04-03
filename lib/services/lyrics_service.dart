import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/lyrics.dart';

class LyricsService {
  static String get baseUrl => dotenv.env['LYRICS_BASE_URL'] ?? '';

  static Future<Lyrics> getLyrics(String trackId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/?trackid=$trackId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return Lyrics.fromJson(jsonData);
      } else {
        throw Exception('Failed to load lyrics: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching lyrics: $e');
    }
  }
}
