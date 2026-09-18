import 'package:car_play/models/lyrics_text_size.dart';
import 'package:car_play/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Il ripristino parte non atteso dal costruttore, come in PlayerProvider:
  /// il provider deve restare sincrono per ChangeNotifierProvider.
  Future<SettingsProvider> ripristinato() async {
    final settings = SettingsProvider();
    await pumpEventQueue();
    return settings;
  }

  group('la scala parte dai valori storici', () {
    test('medio lascia le righe come sono sempre state', () {
      expect(LyricsTextSize.medium.currentLineSize, 20);
      expect(LyricsTextSize.medium.otherLineSize, 16);
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
}
