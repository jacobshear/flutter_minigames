import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/word_bites/word_bites.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/words/words.dart';

void main() {
  final dict = WordDictionary.fromWords([
    'the', 'her', 'ten', 'net', 'rat', 'tar', 'art', 'toe', 'rate', 'tea',
    'stone', 'notes', 'onset', 'ratio', 'aal',
  ]);
  final game = WordBitesGame(dictionary: dict);

  /// A hand-built shared piece set for validation tests:
  ///   0 't' single, 1 'h' single, 2 'e' single,
  ///   3 'ra' horizontal domino, 4 'on' vertical domino, 5 'a' single.
  const pieces = [
    WordBitesPiece(id: 0, shape: WordBitesPieceShape.single, letters: 't'),
    WordBitesPiece(id: 1, shape: WordBitesPieceShape.single, letters: 'h'),
    WordBitesPiece(id: 2, shape: WordBitesPieceShape.single, letters: 'e'),
    WordBitesPiece(
        id: 3, shape: WordBitesPieceShape.horizontal, letters: 'ra'),
    WordBitesPiece(id: 4, shape: WordBitesPieceShape.vertical, letters: 'on'),
    WordBitesPiece(id: 5, shape: WordBitesPieceShape.single, letters: 'a'),
  ];

  WordBitesState fresh() => WordBitesState(
        playerIds: const ['p1', 'p2'],
        rows: 9,
        cols: 8,
        pieces: pieces,
        submissions: const [],
      );

  WordBitesPlacement at(int id, int row, int col) =>
      WordBitesPlacement(pieceId: id, row: row, col: col);

  group('piece generation', () {
    test('deterministic per seed', () {
      final a = WordBitesGame.generatePieces(42);
      final b = WordBitesGame.generatePieces(42);
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].id, b[i].id);
        expect(a[i].shape, b[i].shape);
        expect(a[i].letters, b[i].letters);
      }
    });

    test('different seeds give different sets', () {
      String sig(List<WordBitesPiece> ps) =>
          ps.map((p) => '${p.shape.name}:${p.letters}').join(',');
      // Across several seeds at least one differs from seed 0 (overwhelming).
      final base = sig(WordBitesGame.generatePieces(0));
      expect(
        List.generate(5, (i) => sig(WordBitesGame.generatePieces(i + 1)))
            .any((s) => s != base),
        isTrue,
      );
    });

    test('shape counts, lowercase letters, distinct digraphs', () {
      final ps = WordBitesGame.generatePieces(7);
      expect(ps.length, 9);
      expect(
        ps.where((p) => p.shape == WordBitesPieceShape.horizontal).length,
        WordBitesGame.horizontalDominoCount,
      );
      expect(
        ps.where((p) => p.shape == WordBitesPieceShape.vertical).length,
        WordBitesGame.verticalDominoCount,
      );
      expect(
        ps.where((p) => p.shape == WordBitesPieceShape.single).length,
        WordBitesGame.singleCount,
      );
      final digraphs = ps
          .where((p) => p.shape != WordBitesPieceShape.single)
          .map((p) => p.letters)
          .toList();
      expect(digraphs.toSet().length, digraphs.length, reason: 'no dupes');
      for (final d in digraphs) {
        expect(WordBitesGame.rankedDigraphs, contains(d));
      }
      for (final p in ps) {
        expect(p.letters, p.letters.toLowerCase());
      }
    });

    test('initialState uses the seeded pieces and starts with p1', () {
      final s = game.initialState(seed: 3, playerIds: const ['p1', 'p2']);
      expect(s.rows, 9);
      expect(s.cols, 8);
      expect(s.pieces.length, 9);
      expect(s.submissions, isEmpty);
      expect(game.currentPlayer(s), 'p1');
      expect(game.outcome(s), isNull);
    });
  });

  group('scoring table', () {
    test('length brackets', () {
      expect(WordBitesGame.scoreForLength(2), 0);
      expect(WordBitesGame.scoreForLength(3), 100);
      expect(WordBitesGame.scoreForLength(4), 400);
      expect(WordBitesGame.scoreForLength(5), 800);
      expect(WordBitesGame.scoreForLength(6), 1400);
      expect(WordBitesGame.scoreForLength(7), 1800);
      expect(WordBitesGame.scoreForLength(8), 2200);
      expect(WordBitesGame.scoreForLength(9), 2600);
      expect(WordBitesGame.scoreForLength(12), 2600);
    });
  });

  group('word validation (evidence geometry)', () {
    test('horizontal run of singles scores', () {
      final move = WordBitesMove(words: [
        WordBitesPlay(
          word: 'the',
          placements: [at(0, 2, 1), at(1, 2, 2), at(2, 2, 3)],
        ),
      ]);
      final plays = game.sanitizedPlays(fresh(), move);
      expect(plays.map((p) => p.word), ['the']);
    });

    test('vertical run of singles scores', () {
      final move = WordBitesMove(words: [
        WordBitesPlay(
          word: 'the',
          placements: [at(0, 1, 4), at(1, 2, 4), at(2, 3, 4)],
        ),
      ]);
      expect(game.sanitizedPlays(fresh(), move).length, 1);
    });

    test('horizontal domino contributes both letters', () {
      // 'ra' at (2,2)-(2,3) + 't' at (2,4) → "rat".
      final move = WordBitesMove(words: [
        WordBitesPlay(word: 'rat', placements: [at(3, 2, 2), at(0, 2, 4)]),
      ]);
      expect(game.sanitizedPlays(fresh(), move).length, 1);
    });

    test('vertical domino contributes one letter to a horizontal word', () {
      // 't'(1,2) + vertical 'on' anchored (1,3) so 'o' sits in row 1
      // ('n' hangs below at (2,3)) + 'e'(1,4) → row 1 spells "toe".
      final move = WordBitesMove(words: [
        WordBitesPlay(
          word: 'toe',
          placements: [at(0, 1, 2), at(4, 1, 3), at(2, 1, 4)],
        ),
      ]);
      expect(game.sanitizedPlays(fresh(), move).length, 1);
    });

    test('rejects non-dictionary and too-short words', () {
      final move = WordBitesMove(words: [
        // 'hte' is not a word.
        WordBitesPlay(
          word: 'hte',
          placements: [at(1, 0, 0), at(0, 0, 1), at(2, 0, 2)],
        ),
        // 'te' is too short even if it were a word.
        WordBitesPlay(word: 'te', placements: [at(0, 0, 4), at(2, 0, 5)]),
      ]);
      expect(game.sanitizedPlays(fresh(), move), isEmpty);
    });

    test('rejects word that does not match its evidence', () {
      // Evidence spells "the" but claims "her".
      final move = WordBitesMove(words: [
        WordBitesPlay(
          word: 'her',
          placements: [at(0, 2, 1), at(1, 2, 2), at(2, 2, 3)],
        ),
      ]);
      expect(game.sanitizedPlays(fresh(), move), isEmpty);
    });

    test('rejects non-maximal runs (GP rule)', () {
      // Arrangement spells "rate" in a row; claiming "rat" must fail.
      final placements = [at(3, 4, 1), at(0, 4, 3), at(2, 4, 4)];
      final rat = WordBitesMove(words: [
        WordBitesPlay(word: 'rat', placements: placements),
      ]);
      expect(game.sanitizedPlays(fresh(), rat), isEmpty);
      final rate = WordBitesMove(words: [
        WordBitesPlay(word: 'rate', placements: placements),
      ]);
      expect(game.sanitizedPlays(fresh(), rate).length, 1);
    });

    test('rejects overlapping or out-of-bounds placements', () {
      final overlap = WordBitesMove(words: [
        WordBitesPlay(
          word: 'the',
          placements: [at(0, 2, 1), at(1, 2, 1), at(2, 2, 3)],
        ),
      ]);
      expect(game.sanitizedPlays(fresh(), overlap), isEmpty);
      final oob = WordBitesMove(words: [
        // Horizontal domino anchored on the last column hangs off the board.
        WordBitesPlay(word: 'rat', placements: [at(3, 2, 7), at(0, 2, 9)]),
      ]);
      expect(game.sanitizedPlays(fresh(), oob), isEmpty);
    });

    test('rejects unknown piece ids and double-used pieces', () {
      final unknown = WordBitesMove(words: [
        WordBitesPlay(
          word: 'the',
          placements: [at(99, 2, 1), at(1, 2, 2), at(2, 2, 3)],
        ),
      ]);
      expect(game.sanitizedPlays(fresh(), unknown), isEmpty);
      final doubled = WordBitesMove(words: [
        // Uses the single 'a' twice — the set cannot form "aal".
        WordBitesPlay(
          word: 'aal',
          placements: [at(5, 2, 1), at(5, 2, 2), at(0, 2, 3)],
        ),
      ]);
      expect(game.sanitizedPlays(fresh(), doubled), isEmpty);
    });

    test('rejects evidence with junk pieces not touching the run', () {
      // "the" run plus an unrelated 'a' dropped elsewhere in the evidence.
      final move = WordBitesMove(words: [
        WordBitesPlay(
          word: 'the',
          placements: [at(0, 2, 1), at(1, 2, 2), at(2, 2, 3), at(5, 6, 6)],
        ),
      ]);
      expect(game.sanitizedPlays(fresh(), move), isEmpty);
    });

    test('dedupes repeated words within a submission', () {
      final play = WordBitesPlay(
        word: 'the',
        placements: [at(0, 2, 1), at(1, 2, 2), at(2, 2, 3)],
      );
      final move = WordBitesMove(words: [play, play]);
      expect(game.sanitizedPlays(fresh(), move).length, 1);
    });
  });

  group('round flow', () {
    final theePlay = WordBitesPlay(
      word: 'the',
      placements: [at(0, 2, 1), at(1, 2, 2), at(2, 2, 3)],
    );
    final ratPlay = WordBitesPlay(
      word: 'rat',
      placements: [at(3, 4, 2), at(0, 4, 4)],
    );

    test('p1 then p2 submit; higher validated score wins', () {
      var s = fresh();
      expect(game.validateMove(s, const WordBitesMove(words: []), 'p2'),
          isFalse, reason: 'out of turn');
      expect(game.validateMove(s, WordBitesMove(words: [theePlay]), 'p1'),
          isTrue);

      // p1 scores "the" + "rat" = 200; the bogus word is dropped silently.
      s = game.applyMove(
        s,
        WordBitesMove(words: [
          theePlay,
          ratPlay,
          WordBitesPlay(word: 'zzz', placements: [at(0, 0, 0)]),
        ]),
      );
      expect(s.submissions.length, 1);
      expect(s.scoreOf('p1'), 200);
      expect(game.currentPlayer(s), 'p2');
      expect(game.outcome(s), isNull);

      // p2 scores only "the" = 100.
      s = game.applyMove(s, WordBitesMove(words: [theePlay]));
      expect(s.isFinished, isTrue);
      expect(s.scoreOf('p2'), 100);
      expect(game.outcome(s), const GameOutcome.win('p1'));
      expect(game.validateMove(s, const WordBitesMove(words: []), 'p1'),
          isFalse, reason: 'finished');
    });

    test('equal scores draw', () {
      var s = fresh();
      s = game.applyMove(s, WordBitesMove(words: [theePlay]));
      s = game.applyMove(s, WordBitesMove(words: [ratPlay]));
      expect(game.outcome(s), const GameOutcome.draw());
    });

    test('client score is never trusted — recomputed from valid words', () {
      var s = fresh();
      // Submission full of junk scores zero regardless of what the client
      // thought it was worth (the move carries no score field at all).
      s = game.applyMove(
        s,
        WordBitesMove(words: [
          WordBitesPlay(word: 'qzx', placements: [at(0, 0, 0)]),
        ]),
      );
      expect(s.scoreOf('p1'), 0);
      expect(s.submissions.first.plays, isEmpty);
    });
  });

  group('serialization', () {
    test('state round-trip preserves pieces and submissions', () {
      var s = game.initialState(seed: 11, playerIds: const ['p1', 'p2']);
      final generated = s.pieces;
      // Fabricate a submission through applyMove on the hand-built set for
      // richer content.
      var s2 = fresh();
      s2 = game.applyMove(
        s2,
        WordBitesMove(words: [
          WordBitesPlay(
            word: 'the',
            placements: [at(0, 2, 1), at(1, 2, 2), at(2, 2, 3)],
          ),
        ]),
      );

      for (final state in [s, s2]) {
        final decoded =
            game.decodeState(game.encodeState(state), game.stateSchemaVersion);
        expect(decoded.playerIds, state.playerIds);
        expect(decoded.rows, state.rows);
        expect(decoded.cols, state.cols);
        expect(decoded.pieces.length, state.pieces.length);
        for (var i = 0; i < state.pieces.length; i++) {
          expect(decoded.pieces[i].id, state.pieces[i].id);
          expect(decoded.pieces[i].shape, state.pieces[i].shape);
          expect(decoded.pieces[i].letters, state.pieces[i].letters);
        }
        expect(decoded.submissions.length, state.submissions.length);
        for (var i = 0; i < state.submissions.length; i++) {
          final a = decoded.submissions[i];
          final b = state.submissions[i];
          expect(a.playerId, b.playerId);
          expect(a.score, b.score);
          expect(a.plays.length, b.plays.length);
          for (var j = 0; j < b.plays.length; j++) {
            expect(a.plays[j].word, b.plays[j].word);
            expect(
              a.plays[j].placements.map((p) => p.toJson()).toList(),
              b.plays[j].placements.map((p) => p.toJson()).toList(),
            );
          }
        }
      }
      expect(generated.length, 9);
    });

    test('move round-trip', () {
      final move = WordBitesMove(words: [
        WordBitesPlay(
          word: 'rat',
          placements: [at(3, 4, 2), at(0, 4, 4)],
        ),
      ]);
      final decoded = game.decodeMove(game.encodeMove(move));
      expect(decoded.words.length, 1);
      expect(decoded.words.first.word, 'rat');
      expect(
        decoded.words.first.placements.map((p) => p.toJson()).toList(),
        move.words.first.placements.map((p) => p.toJson()).toList(),
      );
    });
  });
}
