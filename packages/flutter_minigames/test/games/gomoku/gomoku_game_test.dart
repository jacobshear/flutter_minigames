import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/gomoku/gomoku.dart';
import 'package:flutter_minigames/src/core/core.dart';

void main() {
  const game = GomokuGame();
  GomokuState fresh() =>
      game.initialState(seed: 0, playerIds: const ['black', 'white']);

  GomokuState play(GomokuState s, List<(int, int)> moves) {
    for (final (r, c) in moves) {
      final m = GomokuMove(s.index(r, c));
      expect(game.validateMove(s, m, s.currentPlayerId), isTrue,
          reason: 'move ($r,$c) should be legal');
      s = game.applyMove(s, m);
    }
    return s;
  }

  group('GomokuGame', () {
    test('opens empty, black to move, 15×15', () {
      final s = fresh();
      expect(s.size, 15);
      expect(s.cells.length, 225);
      expect(s.cells.every((c) => c == null), isTrue);
      expect(game.currentPlayer(s), 'black');
      expect(game.outcome(s), isNull);
    });

    test('turns alternate by stone parity', () {
      var s = fresh();
      s = play(s, [(7, 7)]);
      expect(game.currentPlayer(s), 'white');
      s = play(s, [(7, 8)]);
      expect(game.currentPlayer(s), 'black');
    });

    test('rejects occupied cells, out of turn, and out of range', () {
      var s = fresh();
      s = play(s, [(7, 7)]);
      expect(game.validateMove(s, GomokuMove(s.index(7, 7)), 'white'), isFalse);
      expect(game.validateMove(s, GomokuMove(s.index(0, 0)), 'black'), isFalse);
      expect(game.validateMove(s, const GomokuMove(-1), 'white'), isFalse);
      expect(game.validateMove(s, const GomokuMove(225), 'white'), isFalse);
    });

    test('horizontal five wins', () {
      final s = play(fresh(), [
        (7, 3), (0, 0), (7, 4), (0, 1), (7, 5), (0, 2), (7, 6), (0, 3), (7, 7),
      ]);
      expect(game.outcome(s), const GameOutcome.win('black'));
      expect(game.winningLine(s).length, 5);
    });

    test('vertical five wins for white', () {
      final s = play(fresh(), [
        (0, 0), (3, 7), (0, 1), (4, 7), (0, 2), (5, 7), (0, 3), (6, 7),
        (14, 14), (7, 7),
      ]);
      expect(game.outcome(s), const GameOutcome.win('white'));
    });

    test('diagonal and anti-diagonal fives win', () {
      final diag = play(fresh(), [
        (3, 3), (0, 1), (4, 4), (0, 2), (5, 5), (0, 3), (6, 6), (0, 4), (7, 7),
      ]);
      expect(diag.cells[diag.index(7, 7)], 'black');
      expect(game.outcome(diag), const GameOutcome.win('black'));

      final anti = play(fresh(), [
        (3, 11), (0, 1), (4, 10), (0, 2), (5, 9), (0, 3), (6, 8), (0, 4),
        (7, 7),
      ]);
      expect(game.outcome(anti), const GameOutcome.win('black'));
    });

    test('overlines (six or more) win in freestyle rules', () {
      // Black builds _ X X X X _ then fills the gap for six in a row.
      final s = play(fresh(), [
        (7, 4), (0, 0), (7, 5), (0, 2), (7, 6), (0, 4), (7, 8), (0, 6),
        (7, 9), (0, 8), (7, 7),
      ]);
      expect(game.outcome(s), const GameOutcome.win('black'));
      expect(game.winningLine(s).length, 6);
    });

    test('four in a row is not a win; no moves after game over', () {
      final four = play(fresh(), [
        (7, 3), (0, 0), (7, 4), (0, 1), (7, 5), (0, 2), (7, 6),
      ]);
      expect(game.outcome(four), isNull);

      final won = play(four, [(0, 3), (7, 7)]);
      expect(game.outcome(won), isNotNull);
      expect(
        game.validateMove(won, GomokuMove(won.index(10, 10)),
            won.currentPlayerId),
        isFalse,
      );
    });

    test('full board with no five is a draw', () {
      const g = GomokuGame(boardSize: 5);
      // Alternating rows with one flipped stripe — no color lines up five in
      // any row, column, or full-length diagonal.
      const rows = ['bwbwb', 'bwbwb', 'wbwbw', 'bwbwb', 'bwbwb'];
      final cells = <String?>[
        for (final row in rows)
          for (final ch in row.split('')) ch == 'b' ? 'black' : 'white',
      ];
      final s = GomokuState(
        cells: cells,
        playerIds: const ['black', 'white'],
        size: 5,
      );
      expect(game.winningLine(s), isEmpty);
      expect(g.outcome(s), const GameOutcome.draw());
    });

    test('encode/decode round-trip', () {
      var s = fresh();
      s = play(s, [(7, 7), (7, 8), (8, 8)]);
      final decoded =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(decoded.cells, s.cells);
      expect(decoded.size, s.size);
      expect(decoded.lastCell, s.lastCell);
      expect(decoded.currentPlayerId, s.currentPlayerId);

      final m = game.decodeMove(game.encodeMove(GomokuMove(s.index(3, 4))));
      expect(m.cell, s.index(3, 4));
    });

    test('custom board size flows through initial state', () {
      const g = GomokuGame(boardSize: 9);
      final s = g.initialState(seed: 1, playerIds: const ['a', 'b']);
      expect(s.size, 9);
      expect(s.cells.length, 81);
    });
  });
}
