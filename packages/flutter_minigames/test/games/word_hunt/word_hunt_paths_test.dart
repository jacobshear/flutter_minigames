import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/word_hunt/word_hunt.dart';

void main() {
  // Hand-built 4×4 grid (row-major), same fixture as word_hunt_game_test.dart:
  //   c a t s
  //   o d e r
  //   g x x x
  //   x x x x
  const letters = [
    'c',
    'a',
    't',
    's',
    'o',
    'd',
    'e',
    'r',
    'g',
    'x',
    'x',
    'x',
    'x',
    'x',
    'x',
    'x',
  ];

  final dict = WordDictionary.fromWords([
    'cat',
    'cats',
    'cad',
    'cod',
    'dog',
    'ted',
    'oat',
    'rest',
  ]);

  WordHuntGame game() => WordHuntGame(dictionary: dict, minSolutions: 0);

  WordHuntState freshState() => WordHuntState(
        letters: letters,
        playerIds: const ['p1', 'p2'],
        found: const {},
        submitted: const [],
        paths: const {},
      );

  group('WordHuntState.paths', () {
    test('applyMove records paths parallel to found', () {
      final g = game();
      final s = g.applyMove(
        freshState(),
        const WordHuntMove([
          TracedWord('cat', [0, 1, 2]),
          TracedWord('rest', [7, 6, 3, 2]),
        ]),
      );
      expect(s.paths?['p1'], [
        [0, 1, 2],
        [7, 6, 3, 2],
      ]);
      expect(s.pathOf('p1', 'cat'), [0, 1, 2]);
      expect(s.pathOf('p1', 'rest'), [7, 6, 3, 2]);
      expect(s.pathOf('p1', 'nope'), isNull);
      expect(s.pathOf('p2', 'cat'), isNull);
    });

    test('round-trip through encode/decode preserves paths', () {
      final g = game();
      final s = g.applyMove(
        freshState(),
        const WordHuntMove([
          TracedWord('cat', [0, 1, 2]),
        ]),
      );
      final decoded = g.decodeState(g.encodeState(s), 1);
      expect(decoded.paths, s.paths);
      expect(decoded.pathOf('p1', 'cat'), [0, 1, 2]);
    });

    test('decoding a legacy JSON map without a paths key yields null', () {
      final g = game();
      final legacyJson = {
        'letters': letters,
        'playerIds': ['p1', 'p2'],
        'found': {
          'p1': ['cat'],
        },
        'submitted': ['p1'],
        // No 'paths' key at all — this is what a pre-schema-change state
        // looks like on disk.
      };
      final decoded = g.decodeState(legacyJson, 1);
      expect(decoded.paths, isNull);
      expect(decoded.pathOf('p1', 'cat'), isNull);
      expect(decoded.wordsOf('p1'), ['cat']);
    });

    test(
        'decoding a JSON map with an explicit null paths value also yields null',
        () {
      final g = game();
      final json = {
        'letters': letters,
        'playerIds': ['p1', 'p2'],
        'found': <String, dynamic>{},
        'submitted': <String>[],
        'paths': null,
      };
      final decoded = g.decodeState(json, 1);
      expect(decoded.paths, isNull);
    });

    test('findPathForWord reconstructs a valid path for every solver word', () {
      final g = game();
      final words = g.solveBoard(letters);
      expect(words, isNotEmpty);
      for (final word in words) {
        final path = g.findPathForWord(letters, word);
        expect(path, isNotNull, reason: '$word should be traceable');
        expect(
          g.isValidTrace(letters, word, path!),
          isTrue,
          reason: 'reconstructed path for $word must itself validate',
        );
      }
    });

    test('findPathForWord returns null for a word not on the board', () {
      final g = game();
      expect(g.findPathForWord(letters, 'zzzzz'), isNull);
    });

    test('findPathForWord handles the two-letter qu tile', () {
      const quLetters = [
        'qu',
        'i',
        't',
        'x',
        'x',
        'x',
        'x',
        'x',
        'x',
        'x',
        'x',
        'x',
        'x',
        'x',
        'x',
        'x',
      ];
      final quGame = WordHuntGame(
        dictionary: WordDictionary.fromWords(['quit']),
        minSolutions: 0,
      );
      final path = quGame.findPathForWord(quLetters, 'quit');
      expect(path, [0, 1, 2]);
      expect(quGame.isValidTrace(quLetters, 'quit', path!), isTrue);
    });
  });
}
