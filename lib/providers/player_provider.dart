import 'dart:async';
import 'dart:convert';

import 'package:car_play/services/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../models/lyrics.dart';
import '../services/lyrics_service.dart';
import '../services/spotify_service.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PlayerProvider with ChangeNotifier {
  Lyrics? _lyrics;
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _isConnected = false;
  String? _currentTrackId;
  int _currentLineIndex = 0;

  Lyrics? get lyrics => _lyrics;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  int get currentLineIndex => _currentLineIndex;

  String? _accessToken;
  static const String clientId = 'SPOTIFY_CLIENT_ID_RIMOSSO';
  static const String clientSecret = '0fc0f0bac5244630b92c60f7651d5aad';

  PlayerProvider() {
    TokenStorage.loadTokens()
        .then((value) {
          _isLoading = false;

          if (value == null) return;
          setAccessToken(value['access_token'], value['refresh_token']);
        })
        .whenComplete(() {
          _isLoading = false;
        });
  }

  Future<void> connectSpotify(BuildContext context) async {
    _isLoading = true;
    notifyListeners();

    try {
      const redirectUrl = 'car-play://callback';
      const scopes = [
        'user-read-playback-state',
        'user-modify-playback-state',
        'user-read-currently-playing',
      ];

      final authUrl = Uri.https('accounts.spotify.com', '/authorize', {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUrl,
        'scope': scopes.join(' '),
        'state': 'spotify_auth_${DateTime.now().millisecondsSinceEpoch}',
      });

      // Usa WebView invece del browser esterno
      final authCode = await _showSpotifyAuthWebView(
        context,
        authUrl.toString(),
      );

      if (authCode != null) {
        final success = await _exchangeCodeForToken(authCode);
        if (success) {
          _isConnected = true;
          await loadCurrentTrack();
          _startPlaybackPolling();
        }
      }
    } catch (e) {
      print('Error connecting to Spotify: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> _showSpotifyAuthWebView(
    BuildContext context,
    String authUrl,
  ) async {
    final completer = Completer<String?>();

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(authUrl))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (navigation) {
            // Controlla se è l'URL di callback
            if (navigation.url.startsWith('car-play://callback')) {
              final uri = Uri.parse(navigation.url);
              final code = uri.queryParameters['code'];

              completer.complete(code);
              Navigator.of(context).pop();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text('Login with Spotify'),
            leading: IconButton(
              icon: Icon(Icons.close),
              onPressed: () {
                completer.complete(null);
                Navigator.of(context).pop();
              },
            ),
          ),
          body: WebViewWidget(controller: controller),
        ),
      ),
    );

    return completer.future;
  }

  Future<bool> _exchangeCodeForToken(String code) async {
    try {
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}',
        },
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': 'car-play://callback',
        },
      );

      if (response.statusCode == 200) {
        final tokenData = json.decode(response.body);
        final accessToken = tokenData['access_token'];
        final refreshToken = tokenData['refresh_token'];

        setAccessToken(accessToken, refreshToken);
        return true;
      }
      return false;
    } catch (e) {
      print('Token exchange error: $e');
      return false;
    }
  }

  void setAccessToken(String token, String refreshToken) async {
    _accessToken = token;
    SpotifyService.initialize(token, refreshToken);
    TokenStorage.saveTokens(token, refreshToken, 3600);
    _isConnected = true;

    await loadCurrentTrack();
    _startPlaybackPolling();
    notifyListeners();
  }

  Future<void> processAuthCode(String code) async {
    _isLoading = true;
    print('setto true processAuthCode');
    notifyListeners();

    try {
      // Implementa lo scambio code/token qui
      _isConnected = true;
      await loadCurrentTrack();
      _startPlaybackPolling();
    } catch (e) {
      print('Auth processing error: $e');
      _isConnected = false;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadCurrentTrack() async {
    final trackId = await SpotifyService.getCurrentTrackId();
    if (trackId != null && trackId != _currentTrackId) {
      _currentTrackId = trackId;
      await loadLyrics(trackId);

      // Aggiorna stato riproduzione
      _isPlaying = await SpotifyService.getIsPlaying();
      notifyListeners();
    }
  }

  Future<void> loadLyrics(String trackId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _lyrics = await LyricsService.getLyrics(trackId);
      _currentLineIndex = 0;
    } catch (e) {
      print('Error loading lyrics: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await SpotifyService.pause();
    } else {
      await SpotifyService.resume();
    }
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  Future<void> skipToNext() async {
    await SpotifyService.next();
    await loadCurrentTrack();
  }

  Future<void> skipToPrevious() async {
    await SpotifyService.previous();
    await loadCurrentTrack();
  }

  void updateCurrentLine(int positionMs) {
    if (_lyrics == null) return;

    for (int i = 0; i < _lyrics!.lines.length; i++) {
      final line = _lyrics!.lines[i];
      final lineStart = line.startTime;

      if (positionMs >= lineStart) {
        if (i == _lyrics!.lines.length - 1 ||
            positionMs < _lyrics!.lines[i + 1].startTime) {
          if (_currentLineIndex != i) {
            _currentLineIndex = i;
            notifyListeners();
          }
          break;
        }
      }
    }
  }

  void _startPlaybackPolling() {
    // Polling ogni 2 secondi per aggiornamenti
    Timer.periodic(Duration(seconds: 2), (timer) async {
      if (!_isConnected) {
        timer.cancel();
        return;
      }

      try {
        final playback = await SpotifyService.getCurrentPlayback();
        if (playback != null) {
          // Aggiorna track corrente
          if (playback['id'] != null && playback['id'] != _currentTrackId) {
            _currentTrackId = playback['id'];
            await loadLyrics(playback['id']!);
          }

          // Aggiorna stato riproduzione
          _isPlaying = playback['is_playing'] ?? false;

          // Aggiorna lyrics in tempo reale
          if (playback['progress_ms'] != null) {
            updateCurrentLine(playback['progress_ms'] as int);
          }

          notifyListeners();
        }
      } catch (e) {
        print('Polling error: $e');
      }
    });
  }
}
