import 'package:car_lyrics/providers/player_provider.dart';
import 'package:car_lyrics/providers/settings_provider.dart';
import 'package:car_lyrics/screens/spotify_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

/// Monta la sola schermata: all'avvio non c'e' nessun PlayerProvider, ed e'
/// il caso che conta di piu' perche' e' quello che vede chi installa l'app.
Future<SettingsProvider> _montaDaSola(WidgetTester tester) async {
  final settings = SettingsProvider();
  await settings.ready;

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: settings,
      child: const MaterialApp(home: SpotifySetupScreen()),
    ),
  );
  return settings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('mostra il redirect URI da registrare, per intero', (
    tester,
  ) async {
    await _montaDaSola(tester);

    // Se qui comparisse un indirizzo diverso da quello che l'app usa davvero,
    // il login fallirebbe dopo che l'utente ha gia' fatto tutto il giro.
    expect(find.text(PlayerProvider.redirectUri), findsOneWidget);
    expect(PlayerProvider.redirectUri, 'car-lyrics://callback');
  });

  testWidgets('l id inserito arriva alle impostazioni', (tester) async {
    final settings = await _montaDaSola(tester);

    await tester.enterText(find.byType(TextField), '  abc123  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(settings.spotifyClientId, 'abc123');
  });

  testWidgets('un campo vuoto non salva niente', (tester) async {
    final settings = await _montaDaSola(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(settings.spotifyClientId, '');
  });

  testWidgets('riparte dall id gia impostato', (tester) async {
    SharedPreferences.setMockInitialValues({'spotify_client_id': 'gia-messo'});

    await _montaDaSola(tester);

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'gia-messo',
    );
  });

  testWidgets('cambiare l id dal menu chiude la sessione in corso', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'spotify_client_id': 'vecchio'});
    final settings = SettingsProvider();
    await settings.ready;
    seedTokens();

    final api = FakeSpotifyApi();
    final player = buildPlayerProvider(api);
    try {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: player),
          ],
          child: const MaterialApp(home: SpotifySetupScreen(canGoBack: true)),
        ),
      );

      await tester.enterText(find.byType(TextField), 'nuovo');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // I token erano stati emessi per l'altra registrazione: tenerli porta
      // a un 401 che si ripara da solo solo dopo un giro a vuoto.
      expect(settings.spotifyClientId, 'nuovo');
      expect(player.status, ConnectionStatus.disconnected);
    } finally {
      player.dispose();
    }
  });
}
