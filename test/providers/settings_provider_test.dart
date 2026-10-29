import 'package:car_lyrics/models/lyrics_text_size.dart';
import 'package:car_lyrics/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Il costruttore resta sincrono per ChangeNotifierProvider, quindi il
  /// ripristino si attende a parte: e' la stessa cosa che fa `main`.
  Future<SettingsProvider> ripristinato() async {
    final settings = SettingsProvider();
    await settings.ready;
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

  group('il client id di Spotify', () {
    test('parte vuoto: non viene da nessun file incluso nella build', () async {
      expect((await ripristinato()).spotifyClientId, '');
    });

    test('si rilegge all avvio successivo, senza spazi intorno', () async {
      await (await ripristinato()).setSpotifyClientId('  abc123  ');

      expect((await ripristinato()).spotifyClientId, 'abc123');
    });

    test('avvisa chi ascolta solo quando cambia davvero', () async {
      final settings = await ripristinato();
      var avvisi = 0;
      settings.addListener(() => avvisi++);

      await settings.setSpotifyClientId('abc123');
      expect(avvisi, 1);

      await settings.setSpotifyClientId(' abc123 ');
      expect(avvisi, 1);
    });

    test('convive con le altre due preferenze', () async {
      final settings = await ripristinato();
      await settings.setSpotifyClientId('abc123');
      await settings.setLyricsProxyUrl('https://lyrics.example.com');
      await settings.setLyricsTextSize(LyricsTextSize.huge);

      final riletto = await ripristinato();
      expect(riletto.spotifyClientId, 'abc123');
      expect(riletto.lyricsProxyUrl, 'https://lyrics.example.com');
      expect(riletto.lyricsTextSize, LyricsTextSize.huge);
    });

    test(
      'ready si completa prima che il valore salvato sia leggibile',
      () async {
        SharedPreferences.setMockInitialValues({'spotify_client_id': 'abc123'});

        // Senza attendere `ready` si leggerebbe ancora il vuoto iniziale, ed e'
        // il motivo per cui main lo attende: deciderlo prima farebbe comparire
        // la schermata di configurazione a chi un client id ce l'ha gia'.
        final settings = SettingsProvider();
        expect(settings.spotifyClientId, '');

        await settings.ready;
        expect(settings.spotifyClientId, 'abc123');
      },
    );
  });
}
