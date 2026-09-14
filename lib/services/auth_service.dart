import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/spotify_tokens.dart';
import '../utils/app_log.dart';

class SpotifyAuth {
  static const _requestTimeout = Duration(seconds: 10);
  static const _tokenEndpoint = 'https://accounts.spotify.com/api/token';
  static const _authorizeEndpoint = 'https://accounts.spotify.com/authorize';
  static const _verifierAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  final String clientId;
  final http.Client _client;

  SpotifyAuth({String? clientId, http.Client? client})
    : clientId = clientId ?? dotenv.env['SPOTIFY_CLIENT_ID'] ?? '',
      _client = client ?? http.Client();

  bool get isConfigured => clientId.isNotEmpty;

  static String createCodeVerifier() {
    final random = Random.secure();
    return List.generate(
      96,
      (_) => _verifierAlphabet[random.nextInt(_verifierAlphabet.length)],
    ).join();
  }

  static String codeChallengeFor(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  static String createState() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => _verifierAlphabet[random.nextInt(_verifierAlphabet.length)],
    ).join();
  }

  Uri authorizeUrl({
    required String redirectUri,
    required List<String> scopes,
    required String codeChallenge,
    required String state,
  }) {
    return Uri.parse(_authorizeEndpoint).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'scope': scopes.join(' '),
        'state': state,
        'code_challenge_method': 'S256',
        'code_challenge': codeChallenge,
      },
    );
  }

  Future<SpotifyTokens?> exchangeCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    return _postToken({
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': clientId,
      'code_verifier': codeVerifier,
    });
  }

  Future<SpotifyTokens?> refresh(String refreshToken) async {
    return _postToken({
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': clientId,
    }, previousRefreshToken: refreshToken);
  }

  Future<SpotifyTokens?> _postToken(
    Map<String, String> body, {
    String? previousRefreshToken,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_tokenEndpoint),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: body,
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        logError(
          'Richiesta token fallita: ${response.statusCode} ${response.body}',
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tokens = SpotifyTokens.fromTokenResponse(
        json,
        previousRefreshToken: previousRefreshToken,
      );
      if (tokens == null) {
        logError('Risposta token priva di access_token o refresh_token');
      }
      return tokens;
    } catch (error, stackTrace) {
      logError('Errore di rete sulla richiesta token', error, stackTrace);
      return null;
    }
  }
}
