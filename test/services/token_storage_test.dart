import 'dart:convert';

import 'package:car_lyrics/models/spotify_tokens.dart';
import 'package:car_lyrics/services/storage_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un Keystore che si rompe solo dove gli si dice. Legge e scrive davvero
/// negli altri casi, cosi' i test possono distinguere "non scrive" da "non
/// legge": sono guasti con conseguenze opposte.
class _FlakySecureStorage extends FlutterSecureStoragePlatform {
  _FlakySecureStorage({
    this.failRead = false,
    this.failWrite = false,
    this.failDelete = false,
  });

  final bool failRead;
  final bool failWrite;
  final bool failDelete;
  final Map<String, String> values = {};

  Never _boom() => throw PlatformException(code: 'Exception encountered');

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => failRead ? _boom() : values[key];

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (failWrite) _boom();
    values[key] = value;
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    if (failDelete) _boom();
    values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => failRead ? _boom() : values;

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    if (failDelete) _boom();
    values.clear();
  }
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

  Future<void> seedVecchioArchivio() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', 'vecchio accesso');
    await prefs.setString('refresh_token', 'vecchio rinnovo');
    await prefs.setInt('expiry_date', 1700000000000);
  }

  test('rilegge quello che ha salvato', () async {
    final storage = TokenStorage();
    expect(await storage.save(tokens), isTrue);

    final loaded = await storage.load();

    expect(loaded?.accessToken, 'accesso');
    expect(loaded?.refreshToken, 'rinnovo');
    expect(loaded?.expiresAt, tokens.expiresAt);
  });

  test('scrive i tre valori in una chiave sola', () async {
    await TokenStorage().save(tokens);

    // Tre scritture separate possono riuscirne due e lasciare una terna
    // mista che in lettura sembra buona.
    final raw = await const FlutterSecureStorage().read(key: 'spotify_tokens');
    expect(jsonDecode(raw!), {
      'access': 'accesso',
      'refresh': 'rinnovo',
      'expiry': 1700000000000,
    });

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('refresh_token'), isNull);
  });

  test('senza niente da nessuna parte restituisce null', () async {
    expect(await TokenStorage().load(), isNull);
  });

  test('una chiave illeggibile non viene scambiata per una sessione', () async {
    FlutterSecureStorage.setMockInitialValues({'spotify_tokens': 'non json'});

    expect(await TokenStorage().load(), isNull);
  });

  test('sposta i token rimasti in SharedPreferences', () async {
    await seedVecchioArchivio();

    final loaded = await TokenStorage().load();

    expect(loaded?.accessToken, 'vecchio accesso');
    expect(loaded?.refreshToken, 'vecchio rinnovo');

    // Il vecchio archivio in chiaro non deve restare indietro.
    final prefs = await SharedPreferences.getInstance();
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
    // Inutilizzabile, ma non va lasciato in chiaro per sempre.
    expect(prefs.getString('refresh_token'), isNull);
  });

  test('se la migrazione non riesce a scrivere non butta il chiaro', () async {
    await seedVecchioArchivio();
    FlutterSecureStoragePlatform.instance = _FlakySecureStorage(
      failWrite: true,
    );

    // La sessione funziona per questo avvio...
    expect((await TokenStorage().load())?.refreshToken, 'vecchio rinnovo');

    // ...e il vecchio archivio resta dov'e', cosi' al prossimo avvio si
    // ritenta. Buttarlo qui significherebbe un login ad ogni avvio, per
    // sempre e senza un errore visibile.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('refresh_token'), 'vecchio rinnovo');
  });

  test('un Keystore illeggibile non blocca l avvio', () async {
    FlutterSecureStoragePlatform.instance = _FlakySecureStorage(failRead: true);

    expect(await TokenStorage().load(), isNull);
  });

  test('un archivio che non scrive non fa cadere la sessione', () async {
    FlutterSecureStoragePlatform.instance = _FlakySecureStorage(
      failWrite: true,
    );

    // I token restano validi in memoria: il login appena fatto non deve
    // fallire solo perche' non si e' riusciti a persisterlo.
    expect(await TokenStorage().save(tokens), isFalse);
  });

  test('clear() ammette di non aver cancellato', () async {
    FlutterSecureStoragePlatform.instance = _FlakySecureStorage(
      failDelete: true,
    );

    // Chi chiama non deve annunciare un logout che non e' avvenuto: al
    // riavvio la sessione ripartirebbe da sola.
    expect(await TokenStorage().clear(), isFalse);
  });

  test('clear() riuscito svuota entrambi gli archivi', () async {
    await seedVecchioArchivio();
    final storage = TokenStorage();
    await storage.save(tokens);

    expect(await storage.clear(), isTrue);

    expect(await storage.load(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('refresh_token'), isNull);
  });
}
