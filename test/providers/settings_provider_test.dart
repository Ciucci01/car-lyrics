import 'package:car_lyrics/models/lyrics_text_size.dart';
import 'package:car_lyrics/models/proxy_auth.dart';
import 'package:car_lyrics/providers/settings_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  /// Il ripristino parte non atteso dal costruttore, come in PlayerProvider:
  /// il provider deve restare sincrono per ChangeNotifierProvider.
  Future<SettingsProvider> ripristinato() async {
    final settings = SettingsProvider();
    await pumpEventQueue();
    return settings;
  }

  group('la scala parte dai valori storici', () {
    test('la taglia piu piccola e l app com era prima', () {
      // La scala parte da qui e sale: in auto nessuno vuole il testo piu'
      // piccolo di com'era, mentre in cima lo spazio mancava.
      expect(LyricsTextSize.small.currentLineSize, 20);
      expect(LyricsTextSize.small.otherLineSize, 16);
      expect(LyricsTextSize.values.first, LyricsTextSize.small);
    });

    test('gli altri livelli mantengono la proporzione fra le due righe', () {
      for (final size in LyricsTextSize.values) {
        expect(
          size.currentLineSize / size.otherLineSize,
          closeTo(20 / 16, 0.001),
        );
      }
    });

    test('ogni livello e piu grande del precedente', () {
      final taglie = LyricsTextSize.values
          .map((size) => size.currentLineSize)
          .toList();
      expect(taglie, orderedEquals(taglie.toList()..sort()));
      expect(taglie.toSet().length, taglie.length);
    });
  });

  group('la preferenza', () {
    test('parte da medio quando non e mai stata scelta', () async {
      expect((await ripristinato()).lyricsTextSize, LyricsTextSize.medium);
    });

    test('si rilegge all avvio successivo', () async {
      await (await ripristinato()).setLyricsTextSize(LyricsTextSize.large);

      expect((await ripristinato()).lyricsTextSize, LyricsTextSize.large);
    });

    test('avvisa chi ascolta quando cambia', () async {
      final settings = await ripristinato();
      var avvisi = 0;
      settings.addListener(() => avvisi++);

      await settings.setLyricsTextSize(LyricsTextSize.huge);
      expect(avvisi, 1);

      // Riscegliere la stessa taglia non e' un cambiamento visibile.
      await settings.setLyricsTextSize(LyricsTextSize.huge);
      expect(avvisi, 1);
    });

    test('un valore salvato che non riconosce non blocca l avvio', () async {
      SharedPreferences.setMockInitialValues({
        'lyrics_text_size': 'gigantesco',
      });

      expect((await ripristinato()).lyricsTextSize, LyricsTextSize.medium);
    });
  });

  group('la fonte dei testi', () {
    test('parte vuota, cioe senza proxy', () async {
      expect((await ripristinato()).lyricsProxyUrl, '');
    });

    test('si rilegge all avvio successivo, senza spazi intorno', () async {
      await (await ripristinato()).setLyricsProxyUrl(
        '  https://lyrics.example.com  ',
      );

      expect(
        (await ripristinato()).lyricsProxyUrl,
        'https://lyrics.example.com',
      );
    });

    test('svuotarla torna alla sola LRCLIB', () async {
      final settings = await ripristinato();
      await settings.setLyricsProxyUrl('https://lyrics.example.com');

      await settings.setLyricsProxyUrl('');

      expect(settings.lyricsProxyUrl, '');
      expect((await ripristinato()).lyricsProxyUrl, '');
    });

    test('avvisa chi ascolta solo quando cambia davvero', () async {
      final settings = await ripristinato();
      var avvisi = 0;
      settings.addListener(() => avvisi++);

      await settings.setLyricsProxyUrl('https://lyrics.example.com');
      expect(avvisi, 1);

      // Lo stesso indirizzo con spazi intorno e' lo stesso indirizzo.
      await settings.setLyricsProxyUrl(' https://lyrics.example.com ');
      expect(avvisi, 1);
    });

    test('le due preferenze non si cancellano a vicenda', () async {
      final settings = await ripristinato();
      await settings.setLyricsProxyUrl('https://lyrics.example.com');
      await settings.setLyricsTextSize(LyricsTextSize.huge);

      final riletto = await ripristinato();
      expect(riletto.lyricsProxyUrl, 'https://lyrics.example.com');
      expect(riletto.lyricsTextSize, LyricsTextSize.huge);
    });
  });

  group('le credenziali del proxy', () {
    test('partono assenti', () async {
      expect((await ripristinato()).lyricsProxyAuth.header, isNull);
    });

    test('stanno nel Keystore e non nelle preferenze in chiaro', () async {
      await (await ripristinato()).setLyricsProxyAuth(
        const ProxyAuth.basic('io', 'segreta'),
      );

      final riletto = (await ripristinato()).lyricsProxyAuth;
      expect(riletto.type, ProxyAuthType.basic);
      expect(riletto.username, 'io');
      expect(riletto.password, 'segreta');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().any((k) => k.contains('auth')), isFalse);
    });

    test('toglierle le cancella dal Keystore', () async {
      final settings = await ripristinato();
      await settings.setLyricsProxyAuth(const ProxyAuth.bearer('abc'));

      await settings.setLyricsProxyAuth(const ProxyAuth.none());

      expect(
        await const FlutterSecureStorage().read(key: 'lyrics_proxy_auth'),
        isNull,
      );
    });

    test('generano gli header come li vuole nginx', () {
      expect(const ProxyAuth.bearer('abc').header, 'Bearer abc');
      // "Aladdin:open sesame", l'esempio della RFC 7617.
      expect(
        const ProxyAuth.basic('Aladdin', 'open sesame').header,
        'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
      );
    });
  });
}
