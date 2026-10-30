import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'providers/player_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/player_screen.dart';
import 'screens/spotify_setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Le preferenze si leggono prima di disegnare: la prima schermata dipende
  // dal fatto che un client id ci sia, e deciderlo su un valore non ancora
  // caricato farebbe lampeggiare la configurazione a ogni avvio.
  final settings = SettingsProvider();
  await settings.ready;

  usePathUrlStrategy();
  runApp(CarLyricsApp(settings: settings));
}

class CarLyricsApp extends StatefulWidget {
  final SettingsProvider settings;

  const CarLyricsApp({super.key, required this.settings});

  @override
  State<CarLyricsApp> createState() => _CarLyricsAppState();
}

class _CarLyricsAppState extends State<CarLyricsApp> {
  @override
  void dispose() {
    widget.settings.dispose();
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

    // Separato da PlayerProvider di proposito: la' dentro tutto arriva da
    // Spotify, qui c'e' solo quello che l'utente ha scelto.
    return ChangeNotifierProvider.value(
      value: widget.settings,
      child: MaterialApp(
        title: 'Car Lyrics',
        theme: theme,
        home: const _Ingresso(),
      ),
    );
  }
}

/// Decide cosa aprire: senza client id non c'e' niente da mostrare, perche'
/// ogni chiamata a Spotify ne ha bisogno.
class _Ingresso extends StatelessWidget {
  const _Ingresso();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (settings.spotifyClientId.isEmpty) return const SpotifySetupScreen();

    // Le due closure leggono le impostazioni al momento della chiamata, non
    // ora: PlayerProvider non impara che SettingsProvider esiste, e un
    // cambio di indirizzo o di client id arriva senza ricostruire niente.
    return ChangeNotifierProvider(
      create: (_) => PlayerProvider(
        spotifyClientId: () => settings.spotifyClientId,
        lyricsProxyBaseUrl: () => settings.lyricsProxyUrl,
        lyricsProxyAuthorization: () => settings.lyricsProxyAuth.header,
      ),
      child: const PlayerScreen(),
    );
  }
}
