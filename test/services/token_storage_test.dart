import 'package:car_play/models/spotify_tokens.dart';
import 'package:car_play/services/storage_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simula un Keystore illeggibile: succede dopo un ripristino da backup o un
/// wipe delle credenziali del dispositivo.
class _BrokenSecureStorage extends FlutterSecureStoragePlatform {
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => throw PlatformException(code: 'Exception encountered');

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async => throw PlatformException(code: 'Exception encountered');

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => false;

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => throw PlatformException(code: 'Exception encountered');

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => {};

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tokens = SpotifyTokens(
    accessToken: 'accesso',
    refreshToken: 'rinnovo',
    expiresAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('rilegge quello che ha salvato', () async {
    final storage = TokenStorage();
    await storage.save(tokens);

    final loaded = await storage.load();

    expect(loaded?.accessToken, 'accesso');
    expect(loaded?.refreshToken, 'rinnovo');
    expect(loaded?.expiresAt, tokens.expiresAt);

    // Il punto di tutto: niente finisce in chiaro.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('refresh_token'), isNull);
    expect(prefs.getString('access_token'), isNull);
    expect(
      await const FlutterSecureStorage().read(key: 'refresh_token'),
      'rinnovo',
    );
  });

  test('senza niente da nessuna parte restituisce null', () async {
    expect(await TokenStorage().load(), isNull);
  });

  test('sposta i token rimasti in SharedPreferences', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', 'vecchio accesso');
    await prefs.setString('refresh_token', 'vecchio rinnovo');
    await prefs.setInt('expiry_date', 1700000000000);

    final loaded = await TokenStorage().load();

    expect(loaded?.accessToken, 'vecchio accesso');
    expect(loaded?.refreshToken, 'vecchio rinnovo');

    // Il vecchio archivio in chiaro non deve restare indietro.
    expect(prefs.getString('refresh_token'), isNull);
    expect(prefs.getString('access_token'), isNull);
    expect(prefs.getInt('expiry_date'), isNull);

    // E la volta dopo i token arrivano dall'archivio sicuro.
    expect((await TokenStorage().load())?.refreshToken, 'vecchio rinnovo');
  });

  test('una migrazione parziale non viene raccolta', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('refresh_token', 'vecchio rinnovo');

    expect(await TokenStorage().load(), isNull);
  });

  test('un Keystore illeggibile non blocca l avvio', () async {
    FlutterSecureStoragePlatform.instance = _BrokenSecureStorage();

    expect(await TokenStorage().load(), isNull);
  });

  test('un archivio che non scrive non fa cadere la sessione', () async {
    FlutterSecureStoragePlatform.instance = _BrokenSecureStorage();
    final storage = TokenStorage();

    // I token restano validi in memoria: il login appena fatto non deve
    // fallire solo perche' non si e' riusciti a persisterlo.
    await expectLater(storage.save(tokens), completes);
    await expectLater(storage.clear(), completes);
  });
}
