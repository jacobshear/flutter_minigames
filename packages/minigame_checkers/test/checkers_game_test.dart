import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_checkers/minigame_checkers.dart';
import 'package:minigames_core/minigames_core.dart';

void main() {
  const game = CheckersGame();
  CheckersState fresh() =>
      game.initialState(seed: 0, playerIds: const ['a', 'b']);

  group('CheckersGame', () {
    test('opening: dark to move, 12 pieces each on dark squares', () {
      final s = fresh();
      expect(game.currentPlayer(s), 'a');
      expect(s.pieceCount('a'), 12);
      expect(s.pieceCount('b'), 12);
      for (var i = 0; i < 64; i++) {
        if (s.cells[i] != null) {
          final (r, c) = CheckersState.rc(i);
          expect(CheckersState.isDarkSquare(r, c), isTrue);
        }
      }
    });

    test('quiet forward diagonal is legal; backward is not for men', () {
      final s = fresh();
      // Dark men on row 5 sit on even cols: (5,0) → (4,1).
      final darkFrom = CheckersState.index(5, 0);
      expect(s.cells[darkFrom], 'a');
      final to = CheckersState.index(4, 1);
      expect(
        game.validateMove(s, CheckersMove(from: darkFrom, to: to), 'a'),
        isTrue,
      );
      final back = CheckersState.index(6, 1);
      expect(
        game.validateMove(s, CheckersMove(from: darkFrom, to: back), 'a'),
        isFalse,
      );
    });

    test('turn passes after quiet move', () {
      var s = fresh();
      final from = CheckersState.index(5, 0);
      final to = CheckersState.index(4, 1);
      s = game.applyMove(s, CheckersMove(from: from, to: to));
      expect(s.cells[to], 'a');
      expect(s.cells[from], isNull);
      expect(game.currentPlayer(s), 'b');
    });

    test('capture removes opponent; quiet moves stay legal when capture exists',
        () {
      // a at (4,1), b at (3,2), land (2,3) empty; also quiet (5,0) free.
      final cells = List<String?>.filled(64, null);
      final kings = List<bool>.filled(64, false);
      cells[CheckersState.index(4, 1)] = 'a';
      cells[CheckersState.index(3, 2)] = 'b';
      var s = CheckersState(
        cells: cells,
        isKing: kings,
        playerIds: const ['a', 'b'],
        currentPlayerId: 'a',
      );
      final legal = game.legalMoves(s, 'a');
      expect(legal, isNotEmpty);
      final hasCapture = legal.any((m) {
        final (fr, _) = CheckersState.rc(m.from);
        final (tr, _) = CheckersState.rc(m.to);
        return (tr - fr).abs() == 2;
      });
      final hasQuiet = legal.any((m) {
        final (fr, _) = CheckersState.rc(m.from);
        final (tr, _) = CheckersState.rc(m.to);
        return (tr - fr).abs() == 1;
      });
      expect(hasCapture, isTrue);
      expect(hasQuiet, isTrue);

      final move = CheckersMove(
        from: CheckersState.index(4, 1),
        to: CheckersState.index(2, 3),
      );
      expect(game.validateMove(s, move, 'a'), isTrue);
      s = game.applyMove(s, move);
      expect(s.cells[CheckersState.index(3, 2)], isNull);
      expect(s.cells[CheckersState.index(2, 3)], 'a');
      expect(s.lastCaptured, CheckersState.index(3, 2));
    });

    test('multi-jump keeps turn and locks the piece', () {
      final cells = List<String?>.filled(64, null);
      final kings = List<bool>.filled(64, false);
      // a (5,0) → jump b (4,1) to (3,2) → jump b (2,3) to (1,4).
      cells[CheckersState.index(5, 0)] = 'a';
      cells[CheckersState.index(4, 1)] = 'b';
      cells[CheckersState.index(2, 3)] = 'b';
      cells[CheckersState.index(0, 1)] = 'b'; // spare
      var s = CheckersState(
        cells: cells,
        isKing: kings,
        playerIds: const ['a', 'b'],
        currentPlayerId: 'a',
      );
      s = game.applyMove(
        s,
        CheckersMove(
          from: CheckersState.index(5, 0),
          to: CheckersState.index(3, 2),
        ),
      );
      expect(s.mustContinueFrom, CheckersState.index(3, 2));
      expect(game.currentPlayer(s), 'a');
      expect(
        game
            .legalMoves(s, 'a')
            .every((m) => m.from == CheckersState.index(3, 2)),
        isTrue,
      );
      s = game.applyMove(
        s,
        CheckersMove(
          from: CheckersState.index(3, 2),
          to: CheckersState.index(1, 4),
        ),
      );
      expect(s.mustContinueFrom, isNull);
      expect(game.currentPlayer(s), 'b');
      expect(s.pieceCount('b'), 1);
    });

    test('crowning on last rank', () {
      final cells = List<String?>.filled(64, null);
      final kings = List<bool>.filled(64, false);
      cells[CheckersState.index(1, 0)] = 'a'; // wait (1,0) light square
      cells[CheckersState.index(1, 2)] = 'a'; // (1,2) odd = dark
      cells[CheckersState.index(7, 0)] = 'b'; // keep b alive on dark? (7,0) odd
      var s = CheckersState(
        cells: cells,
        isKing: kings,
        playerIds: const ['a', 'b'],
        currentPlayerId: 'a',
      );
      s = game.applyMove(
        s,
        CheckersMove(
          from: CheckersState.index(1, 2),
          to: CheckersState.index(0, 1),
        ),
      );
      expect(s.isKing[CheckersState.index(0, 1)], isTrue);
      expect(s.lastBecameKing, isTrue);
      expect(game.currentPlayer(s), 'b');
    });

    test('no pieces loses', () {
      final s = CheckersState(
        cells: List<String?>.filled(64, null)
          ..[CheckersState.index(5, 0)] = 'a',
        isKing: List<bool>.filled(64, false),
        playerIds: const ['a', 'b'],
        currentPlayerId: 'a',
      );
      expect(game.outcome(s), const GameOutcome.win('a'));
    });

    test('state survives encode/decode', () {
      final s = fresh();
      final next = game.applyMove(
        s,
        CheckersMove(
          from: CheckersState.index(5, 0),
          to: CheckersState.index(4, 1),
        ),
      );
      final json = game.encodeState(next);
      final back = game.decodeState(json, 1);
      expect(back.cells, next.cells);
      expect(back.isKing, next.isKing);
      expect(back.currentPlayerId, next.currentPlayerId);
      expect(back.lastFrom, next.lastFrom);
      expect(back.lastTo, next.lastTo);
    });
  });
}
