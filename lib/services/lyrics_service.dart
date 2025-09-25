import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/lyrics.dart';

class LyricsService {
  static const String baseUrl = 'http://100.117.190.80:5554';

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
