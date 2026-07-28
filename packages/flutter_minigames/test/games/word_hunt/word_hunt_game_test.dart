import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/word_hunt/word_hunt.dart';
import 'package:flutter_minigames/src/core/core.dart';

void main() {
  // Hand-built 4×4 grid (row-major):
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
    'cat', 'cats', 'cad', 'cod', 'dog', 'ted', 'oat', 'rest',
    // In the dictionary but NOT traceable on the grid above (o and t don't
    // touch via d-o-t order… d(5)-o(4) ok, o(4)-t(2) not adjacent).
    'dot',
    'zebra',
    'at', // too short to ever score
  ]);

  WordHuntGame game() => WordHuntGame(dictionary: dict, minSolutions: 0);

  WordHuntState freshState() => WordHuntState(
        letters: letters,
        playerIds: const ['p1', 'p2'],
        found: const {},
        submitted: const [],
      );

  group('adjacency and path validation', () {
    test('8-directional adjacency includes diagonals', () {
      // Cell 5 (row 1, col 1) touches all 8 surrounding cells.
      expect(
        WordHuntGame.neighborsOf(5, 4).toSet(),
        {0, 1, 2, 4, 6, 8, 9, 10},
      );
      expect(WordHuntGame.areAdjacent(0, 5, 4), isTrue); // diagonal
      expect(WordHuntGame.areAdjacent(0, 1, 4), isTrue); // orthogonal
      expect(WordHuntGame.areAdjacent(0, 2, 4), isFalse); // two apart
      expect(WordHuntGame.areAdjacent(3, 4, 4), isFalse); // row wrap
      expect(WordHuntGame.areAdjacent(7, 7, 4), isFalse); // same cell
    });

    test('accepts a legal trace', () {
      expect(game().isValidTrace(letters, 'cat', [0, 1, 2]), isTrue);
      expect(game().isValidTrace(letters, 'rest', [7, 6, 3, 2]), isTrue);
    });

    test('rejects non-adjacent steps', () {
      // c(0) → t(2) skips a column.
      expect(game().isValidTrace(letters, 'cat', [0, 2, 1]), isFalse);
    });

    test('rejects tile reuse', () {
      // t-e-t reusing cell 2.
      expect(game().isValidTrace(letters, 'tet', [2, 6, 2]), isFalse);
    });

    test('rejects paths that do not spell the word', () {
      expect(game().isValidTrace(letters, 'cat', [0, 1, 3]), isFalse);
    });

    test('rejects words not in the dictionary', () {
      // 'cats' backwards is a fine path but not a word.
      expect(game().isValidTrace(letters, 'stac', [3, 2, 1, 0]), isFalse);
    });

    test('rejects words under three letters and bad cells', () {
      expect(game().isValidTrace(letters, 'at', [1, 2]), isFalse);
      expect(game().isValidTrace(letters, 'cat', [0, 1, 16]), isFalse);
      expect(game().isValidTrace(letters, 'cat', [-1, 1, 2]), isFalse);
      expect(game().isValidTrace(letters, 'cat', []), isFalse);
    });

    test('handles the two-letter qu tile', () {
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
      expect(quGame.isValidTrace(quLetters, 'quit', [0, 1, 2]), isTrue);
      expect(quGame.solveBoard(quLetters), ['quit']);
    });
  });

  group('scoring', () {
    test('GP-style length table', () {
      expect(WordHuntGame.scoreForLength(2), 0);
      expect(WordHuntGame.scoreForLength(3), 100);
      expect(WordHuntGame.scoreForLength(4), 400);
      expect(WordHuntGame.scoreForLength(5), 800);
      expect(WordHuntGame.scoreForLength(6), 1400);
      expect(WordHuntGame.scoreForLength(7), 1800);
      expect(WordHuntGame.scoreForLength(8), 2200);
      expect(WordHuntGame.scoreForLength(12), 2200);
    });
  });

  group('board solver', () {
    test('finds exactly the traceable dictionary words', () {
      expect(
        game().solveBoard(letters),
        ['cad', 'cat', 'cats', 'cod', 'dog', 'oat', 'rest', 'ted'],
      );
    });
  });

  group('board generation', () {
    test('rollBoard is deterministic per seed', () {
      expect(WordHuntGame.rollBoard(7), WordHuntGame.rollBoard(7));
      expect(
        WordHuntGame.rollBoard(7),
        isNot(equals(WordHuntGame.rollBoard(8))),
      );
      expect(WordHuntGame.rollBoard(7).length, 16);
    });

    test('generateBoard is deterministic and meets the threshold', () {
      // Build a dictionary from a word that is guaranteed findable on the
      // seed+1 candidate, so generation may have to skip seed 0's board.
      final b1 = WordHuntGame.rollBoard(1);
      final word = b1[0] + b1[1] + b1[5]; // 0-1 and 1-5 are adjacent
      final g = WordHuntGame(
        dictionary: WordDictionary.fromWords([word]),
        minSolutions: 1,
      );
      final board = g.generateBoard(0);
      expect(board, g.generateBoard(0));
      expect(g.solveBoard(board), isNotEmpty);
      // If the seed-0 candidate lacked the word, the loop must have re-rolled.
      final b0 = WordHuntGame.rollBoard(0);
      if (g.solveBoard(b0).isEmpty) {
        expect(board, isNot(equals(b0)));
      }
    });

    test('unreachable threshold falls back to the best candidate', () {
      final g = WordHuntGame(
        dictionary: WordDictionary.fromWords(['zzzzz']),
        minSolutions: 1000,
        maxGenerationAttempts: 4,
      );
      final board = g.generateBoard(3);
      expect(board.length, 16);
      expect(board, g.generateBoard(3)); // still deterministic
    });

    test('initialState boards are seed-deterministic', () {
      final g = game();
      final a = g.initialState(seed: 42, playerIds: const ['p1', 'p2']);
      final b = g.initialState(seed: 42, playerIds: const ['p1', 'p2']);
      expect(a.letters, b.letters);
      expect(a.letters.length, 16);
      expect(g.currentPlayer(a), 'p1');
      expect(g.outcome(a), isNull);
    });
  });

  group('round flow', () {
    test('p1 round, p2 round, outcome by score', () {
      final g = game();
      var s = freshState();

      // Not p2's turn yet.
      expect(g.validateMove(s, const WordHuntMove([]), 'p2'), isFalse);
      expect(g.validateMove(s, const WordHuntMove([]), 'p1'), isTrue);

      // p1: cat (100) + dog (100) = 200.
      s = g.applyMove(
        s,
        const WordHuntMove([
          TracedWord('cat', [0, 1, 2]),
          TracedWord('dog', [5, 4, 8]),
        ]),
      );
      expect(s.wordsOf('p1'), ['cat', 'dog']);
      expect(s.scoreOf('p1'), 200);
      expect(g.currentPlayer(s), 'p2');
      expect(g.outcome(s), isNull);

      // p1 can't go again.
      expect(g.validateMove(s, const WordHuntMove([]), 'p1'), isFalse);
      expect(g.validateMove(s, const WordHuntMove([]), 'p2'), isTrue);

      // p2: cats (400) — wins.
      s = g.applyMove(
        s,
        const WordHuntMove([
          TracedWord('cats', [0, 1, 2, 3]),
        ]),
      );
      expect(s.scoreOf('p2'), 400);
      expect(g.outcome(s), const GameOutcome.win('p2'));
      expect(g.validateMove(s, const WordHuntMove([]), 'p2'), isFalse);
    });

    test('equal scores draw (including two empty rounds)', () {
      final g = game();
      var s = freshState();
      s = g.applyMove(
        s,
        const WordHuntMove([
          TracedWord('cat', [0, 1, 2])
        ]),
      );
      s = g.applyMove(
        s,
        const WordHuntMove([
          TracedWord('ted', [2, 6, 5])
        ]),
      );
      expect(s.scoreOf('p1'), s.scoreOf('p2'));
      expect(g.outcome(s), const GameOutcome.draw());

      var empty = freshState();
      empty = g.applyMove(empty, const WordHuntMove([]));
      empty = g.applyMove(empty, const WordHuntMove([]));
      expect(g.outcome(empty), const GameOutcome.draw());
    });

    test('applyMove drops invalid, duplicate, and fabricated entries', () {
      final g = game();
      final s = g.applyMove(
        freshState(),
        const WordHuntMove([
          TracedWord('cat', [0, 1, 2]),
          TracedWord('cat', [0, 1, 2]), // duplicate → dropped
          TracedWord('dot', [5, 4, 2]), // o(4)-t(2) not adjacent → dropped
          TracedWord('zebra', [0, 1, 2, 3, 4]), // letters mismatch → dropped
          TracedWord('stac', [3, 2, 1, 0]), // not a word → dropped
          TracedWord('rest', [7, 6, 3, 2]), // valid
        ]),
      );
      expect(s.wordsOf('p1'), ['cat', 'rest']);
      expect(s.scoreOf('p1'), 100 + 400);
    });
  });

  group('serialization', () {
    test('state round-trips mid-game and at the end', () {
      final g = game();
      var s = freshState();
      s = g.applyMove(
        s,
        const WordHuntMove([
          TracedWord('cats', [0, 1, 2, 3])
        ]),
      );

      final decodedMid = g.decodeState(g.encodeState(s), 1);
      expect(decodedMid.letters, s.letters);
      expect(decodedMid.playerIds, s.playerIds);
      expect(decodedMid.found, s.found);
      expect(decodedMid.submitted, s.submitted);
      expect(g.currentPlayer(decodedMid), 'p2');
      expect(g.outcome(decodedMid), isNull);

      s = g.applyMove(s, const WordHuntMove([]));
      final decodedEnd = g.decodeState(g.encodeState(s), 1);
      expect(g.outcome(decodedEnd), const GameOutcome.win('p1'));
      expect(decodedEnd.scoreOf('p1'), 400);
    });

    test('move round-trips with paths intact', () {
      final g = game();
      const move = WordHuntMove([
        TracedWord('cat', [0, 1, 2]),
        TracedWord('rest', [7, 6, 3, 2]),
      ]);
      final decoded = g.decodeMove(g.encodeMove(move));
      expect(decoded.words.length, 2);
      expect(decoded.words[0].word, 'cat');
      expect(decoded.words[0].path, [0, 1, 2]);
      expect(decoded.words[1].word, 'rest');
      expect(decoded.words[1].path, [7, 6, 3, 2]);
    });
  });
}
