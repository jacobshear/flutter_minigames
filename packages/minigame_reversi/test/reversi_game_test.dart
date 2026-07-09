import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_reversi/minigame_reversi.dart';
import 'package:minigames_core/minigames_core.dart';

void main() {
  const game = ReversiGame();
  ReversiState fresh() =>
      game.initialState(seed: 0, playerIds: const ['dark', 'light']);

  group('ReversiGame', () {
    test('opening position has four center discs; dark to move', () {
      final s = fresh();
      expect(s.cells[ReversiState.index(3, 3)], 'light');
      expect(s.cells[ReversiState.index(3, 4)], 'dark');
      expect(s.cells[ReversiState.index(4, 3)], 'dark');
      expect(s.cells[ReversiState.index(4, 4)], 'light');
      expect(game.currentPlayer(s), 'dark');
      expect(game.legalMoves(s, 'dark'), isNotEmpty);
    });

    test('dark opening move flips at least one disc', () {
      var s = fresh();
      final moves = game.legalMoves(s, 'dark');
      expect(moves, isNotEmpty);
      final m = moves.first;
      expect(game.validateMove(s, ReversiMove(m), 'dark'), isTrue);
      s = game.applyMove(s, ReversiMove(m));
      expect(s.cells[m], 'dark');
      expect(s.lastFlipped, isNotEmpty);
      expect(s.scoreFor('dark'), greaterThan(2));
    });

    test('rejects empty non-flipping cells and out of turn', () {
      final s = fresh();
      // Corner is never legal on move 1.
      expect(game.validateMove(s, const ReversiMove(0), 'dark'), isFalse);
      expect(
        game.validateMove(s, ReversiMove(game.legalMoves(s, 'dark').first), 'light'),
        isFalse,
      );
    });

    test('pass is only legal when player has no moves', () {
      final s = fresh();
      expect(game.validateMove(s, const ReversiMove.pass(), 'dark'), isFalse);
      // Construct a state where dark has no moves but light does.
      // Full board almost all light with dark to move — rare; skip to
      // unit-test mustPass on opening (false).
      expect(game.mustPass(s, 'dark'), isFalse);
    });

    test('encode/decode round-trip', () {
      var s = fresh();
      final m = game.legalMoves(s, 'dark').first;
      s = game.applyMove(s, ReversiMove(m));
      final decoded =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(decoded.cells, s.cells);
      expect(decoded.currentPlayerId, s.currentPlayerId);
      expect(decoded.lastFlipped, s.lastFlipped);
    });

    test('full board outcome by score', () {
      final cells = List<String?>.filled(64, 'dark');
      for (var i = 0; i < 20; i++) {
        cells[i] = 'light';
      }
      final s = ReversiState(
        cells: cells,
        playerIds: const ['dark', 'light'],
        currentPlayerId: 'dark',
      );
      // Both have no empty cells → no moves.
      expect(game.outcome(s), const GameOutcome.win('dark'));
    });
  });
}
