import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_connect_four/minigame_connect_four.dart';
import 'package:minigames_core/minigames_core.dart';

void main() {
  const game = ConnectFourGame();
  ConnectFourState fresh() =>
      game.initialState(seed: 0, playerIds: const ['p0', 'p1']);

  group('ConnectFourGame', () {
    test('player 0 moves first, then alternates', () {
      var s = fresh();
      expect(game.currentPlayer(s), 'p0');
      s = game.applyMove(s, const ConnectFourMove(0));
      expect(game.currentPlayer(s), 'p1');
      s = game.applyMove(s, const ConnectFourMove(1));
      expect(game.currentPlayer(s), 'p0');
    });

    test('gravity stacks discs from the bottom', () {
      var s = fresh();
      s = game.applyMove(s, const ConnectFourMove(3)); // p0 bottom
      s = game.applyMove(s, const ConnectFourMove(3)); // p1 above
      expect(s.cellAt(0, 3), 'p0');
      expect(s.cellAt(1, 3), 'p1');
      expect(s.cellAt(2, 3), isNull);
      expect(s.lastCol, 3);
      expect(s.lastRow, 1);
    });

    test('rejects full columns, out-of-range, and out-of-turn', () {
      var s = fresh();
      // Fill column 0 completely (6 drops).
      for (var i = 0; i < 6; i++) {
        s = game.applyMove(s, const ConnectFourMove(0));
        // After each p0/p1 alternate; when full next must use other col to
        // keep turn order for remaining tests — fill with alternating.
        // Actually each move is on col 0 and alternates players automatically.
      }
      expect(s.dropRow(0), isNull);
      expect(game.validateMove(s, const ConnectFourMove(0), 'p0'), isFalse);
      expect(game.validateMove(s, const ConnectFourMove(7), 'p0'), isFalse);
      expect(game.validateMove(s, const ConnectFourMove(1), 'p1'), isFalse);
      expect(game.validateMove(s, const ConnectFourMove(1), 'p0'), isTrue);
    });

    test('detects a horizontal win', () {
      var s = fresh();
      // p0: cols 0,1,2,3 on bottom row; p1 plays col 6 between.
      for (final col in [0, 6, 1, 6, 2, 6, 3]) {
        s = game.applyMove(s, ConnectFourMove(col));
      }
      expect(game.outcome(s), const GameOutcome.win('p0'));
      expect(game.winningLine(s), isNotNull);
      expect(game.winningLine(s)!.length, 4);
    });

    test('detects a vertical win', () {
      var s = fresh();
      // p0 stacks 4 in col 2; p1 plays col 5.
      for (final col in [2, 5, 2, 5, 2, 5, 2]) {
        s = game.applyMove(s, ConnectFourMove(col));
      }
      expect(game.outcome(s), const GameOutcome.win('p0'));
    });

    test('detects a diagonal win', () {
      var s = fresh();
      // Build diagonal p0: (0,0) (1,1) (2,2) (3,3) with supports.
      // Sequence carefully:
      // col0: p0
      // col1: p1, p0
      // col2: p1, p1, p0  — need two p1 first
      // col3: p1, p1, p1, p0
      //
      // Moves:
      // p0→0, p1→1, p0→1, p1→2, p0→6, p1→2, p0→2, p1→3, p0→6, p1→3, p0→6, p1→3, p0→3
      final moves = [0, 1, 1, 2, 6, 2, 2, 3, 6, 3, 6, 3, 3];
      for (final col in moves) {
        s = game.applyMove(s, ConnectFourMove(col));
      }
      expect(s.cellAt(0, 0), 'p0');
      expect(s.cellAt(1, 1), 'p0');
      expect(s.cellAt(2, 2), 'p0');
      expect(s.cellAt(3, 3), 'p0');
      expect(game.outcome(s), const GameOutcome.win('p0'));
    });

    test('state survives encode/decode round-trip', () {
      var s = fresh();
      s = game.applyMove(s, const ConnectFourMove(2));
      s = game.applyMove(s, const ConnectFourMove(4));
      final decoded =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(decoded.cells, s.cells);
      expect(decoded.playerIds, s.playerIds);
      expect(decoded.lastCol, s.lastCol);
      expect(decoded.lastRow, s.lastRow);
      expect(game.currentPlayer(decoded), game.currentPlayer(s));
    });
  });
}
