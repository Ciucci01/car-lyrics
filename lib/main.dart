import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:url_strategy/url_strategy.dart';

import 'providers/player_provider.dart';
import 'screens/config_error_screen.dart';
import 'screens/player_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? configError;
  try {
    await dotenv.load(fileName: '.env');
    configError = _describeMissingConfig();
  } catch (_) {
    configError =
        'No .env file found. Create one in the project root with '
        'SPOTIFY_CLIENT_ID and LYRICS_BASE_URL.';
  }

  setPathUrlStrategy();
  runApp(CarPlayApp(configError: configError));
}

String? _describeMissingConfig() {
  final missing = [
    'SPOTIFY_CLIENT_ID',
    'LYRICS_BASE_URL',
  ].where((key) => (dotenv.env[key] ?? '').isEmpty).toList();
  if (missing.isEmpty) return null;
  return 'Missing keys in .env: ${missing.join(', ')}.';
}

class CarPlayApp extends StatelessWidget {
  final String? configError;

  const CarPlayApp({super.key, this.configError});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1DB954),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        centerTitle: false,
        titleSpacing: 16,
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

    if (configError != null) {
      return MaterialApp(
        title: 'Spotify Lyrics',
        theme: theme,
        home: ConfigErrorScreen(message: configError!),
      );
    }

    return ChangeNotifierProvider(
      create: (_) => PlayerProvider(),
      child: MaterialApp(
        title: 'Spotify Lyrics',
        theme: theme,
        home: const PlayerScreen(),
      ),
    );
  }
}
