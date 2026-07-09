import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_tictactoe/minigame_tictactoe.dart';
import 'package:minigames_core/minigames_core.dart';

void main() {
  const game = TicTacToeGame();
  TicTacToeState fresh() =>
      game.initialState(seed: 0, playerIds: const ['x', 'o']);

  group('TicTacToeGame', () {
    test('X moves first, then O alternates', () {
      var s = fresh();
      expect(game.currentPlayer(s), 'x');
      s = game.applyMove(s, const TicTacToeMove(0));
      expect(game.currentPlayer(s), 'o');
      s = game.applyMove(s, const TicTacToeMove(1));
      expect(game.currentPlayer(s), 'x');
    });

    test('rejects taken cells, out-of-range cells, and out-of-turn moves', () {
      var s = fresh();
      s = game.applyMove(s, const TicTacToeMove(4)); // x takes center
      expect(game.validateMove(s, const TicTacToeMove(4), 'o'), isFalse); // taken
      expect(game.validateMove(s, const TicTacToeMove(9), 'o'), isFalse); // range
      expect(game.validateMove(s, const TicTacToeMove(0), 'x'), isFalse); // not x's turn
      expect(game.validateMove(s, const TicTacToeMove(0), 'o'), isTrue);
    });

    test('detects a row win', () {
      var s = fresh();
      // x:0 o:3 x:1 o:4 x:2 -> x wins top row
      for (final cell in const [0, 3, 1, 4, 2]) {
        s = game.applyMove(s, TicTacToeMove(cell));
      }
      expect(game.outcome(s), const GameOutcome.win('x'));
    });

    test('detects a diagonal win', () {
      var s = fresh();
      for (final cell in const [0, 1, 4, 2, 8]) {
        s = game.applyMove(s, TicTacToeMove(cell));
      }
      expect(game.outcome(s), const GameOutcome.win('x'));
    });

    test('detects a draw on a full board', () {
      var s = fresh();
      // x o x / x o o / o x x  -> no line, board full
      for (final cell in const [0, 1, 2, 4, 3, 5, 7, 6, 8]) {
        s = game.applyMove(s, TicTacToeMove(cell));
      }
      expect(game.outcome(s), const GameOutcome.draw());
    });

    test('state survives an encode/decode round-trip', () {
      var s = fresh();
      s = game.applyMove(s, const TicTacToeMove(0));
      s = game.applyMove(s, const TicTacToeMove(4));
      final decoded =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(decoded.cells, s.cells);
      expect(decoded.playerIds, s.playerIds);
      expect(game.currentPlayer(decoded), game.currentPlayer(s));
    });
  });
}
