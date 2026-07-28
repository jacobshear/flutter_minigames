import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/words/words.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled ENABLE list', () {
    late WordDictionary dict;

    setUpAll(() async {
      dict = await WordDictionary.load();
    });

    test('loads the full list', () {
      expect(dict.length, greaterThan(170000));
    });

    test('contains real words, rejects junk', () {
      expect(dict.contains('quixotic'), isTrue);
      expect(dict.contains('ZEBRA'), isTrue); // case-insensitive
      expect(dict.contains('qzqzqz'), isFalse);
      expect(dict.contains(''), isFalse);
    });

    test('hasPrefix prunes correctly', () {
      expect(dict.hasPrefix('quix'), isTrue);
      expect(dict.hasPrefix('zzz'), isFalse);
      expect(dict.hasPrefix('a'), isTrue);
    });

    test('pickWord is deterministic per seed and correct length', () {
      final a = dict.pickWord(length: 6, seed: 42);
      final b = dict.pickWord(length: 6, seed: 42);
      final c = dict.pickWord(length: 6, seed: 43);
      expect(a, b);
      expect(a.length, 6);
      expect(a == c, isFalse); // overwhelmingly likely distinct
    });
  });

  group('anagramsOf', () {
    final dict = WordDictionary.fromWords(
        ['ten', 'net', 'tent', 'tenet', 'nett', 'tee', 'no']);

    test('respects letter multiset and minLength', () {
      // letters: t,e,n,e,t → 'tenet' fits, 'nett' needs two t's (has), 'no' too short/absent n? n present but o absent
      final found = dict.anagramsOf('tenet');
      expect(
          found, containsAll(['ten', 'net', 'tent', 'tenet', 'tee', 'nett']));
      expect(found, isNot(contains('no')));
    });
  });
}
