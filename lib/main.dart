import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'providers/player_provider.dart';
import 'providers/settings_provider.dart';
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
        'SPOTIFY_CLIENT_ID.';
  }

  usePathUrlStrategy();
  runApp(CarPlayApp(configError: configError));
}

String? _describeMissingConfig() {
  // L'unica chiave che serve: la fonte dei testi si imposta dentro l'app.
  final missing = [
    'SPOTIFY_CLIENT_ID',
  ].where((key) => (dotenv.env[key] ?? '').isEmpty).toList();
  if (missing.isEmpty) return null;
  return 'Missing keys in .env: ${missing.join(', ')}.';
}

class CarPlayApp extends StatefulWidget {
  final String? configError;

  const CarPlayApp({super.key, this.configError});

  @override
  State<CarPlayApp> createState() => _CarPlayAppState();
}

class _CarPlayAppState extends State<CarPlayApp> {
  /// Tenuto qui, e non creato dentro `build`, perche' `PlayerProvider` lo
  /// interroga ad ogni richiesta di testo per sapere dove sta il proxy: deve
  /// essere lo stesso oggetto per tutta la vita dell'app.
  final SettingsProvider _settings = SettingsProvider();

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

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

    final configError = widget.configError;
    if (configError != null) {
      return MaterialApp(
        title: 'Spotify Lyrics',
        theme: theme,
        home: ConfigErrorScreen(message: configError),
      );
    }

    return MultiProvider(
      providers: [
        // Separato da PlayerProvider di proposito: la' dentro tutto arriva da
        // Spotify, qui c'e' solo come l'utente vuole vedere la schermata.
        ChangeNotifierProvider.value(value: _settings),
        ChangeNotifierProvider(
          create: (_) => PlayerProvider(
            lyricsProxyBaseUrl: () => _settings.lyricsProxyUrl,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Spotify Lyrics',
        theme: theme,
        home: const PlayerScreen(),
      ),
    );
  }
}
