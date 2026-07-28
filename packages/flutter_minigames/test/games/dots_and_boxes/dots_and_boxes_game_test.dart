import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/dots_and_boxes/dots_and_boxes.dart';
import 'package:flutter_minigames/src/core/core.dart';

void main() {
  // 2×2 boxes keeps tests short.
  const game = DotsAndBoxesGame(gridSize: 2);
  DotsAndBoxesState fresh() =>
      game.initialState(seed: 0, playerIds: const ['a', 'b']);

  group('DotsAndBoxesGame', () {
    test('player a starts; turn passes when no box completed', () {
      var s = fresh();
      expect(game.currentPlayer(s), 'a');
      s = game.applyMove(s, const DotsAndBoxesMove.h(0));
      expect(game.currentPlayer(s), 'b');
      expect(s.lastKeptTurn, isFalse);
    });

    test('rejects taken edges and out-of-turn moves', () {
      var s = fresh();
      s = game.applyMove(s, const DotsAndBoxesMove.h(0));
      expect(game.validateMove(s, const DotsAndBoxesMove.h(0), 'b'), isFalse);
      expect(game.validateMove(s, const DotsAndBoxesMove.h(1), 'a'), isFalse);
      expect(game.validateMove(s, const DotsAndBoxesMove.h(1), 'b'), isTrue);
    });

    test('completing a box awards it and keeps the turn', () {
      var s = fresh();
      // Complete box (0,0): top h0, left v0, right v1, bottom h2
      // n=2: h index row*2+col, v index row*3+col
      s = game.applyMove(s, const DotsAndBoxesMove.h(0)); // a top
      s = game.applyMove(s, const DotsAndBoxesMove.v(0)); // b left
      s = game.applyMove(s, const DotsAndBoxesMove.v(1)); // a right
      // b claims bottom → completes box for b, keeps turn
      s = game.applyMove(s, const DotsAndBoxesMove.h(2));
      expect(s.boxes[0], 'b');
      expect(s.lastCompletedBoxes, [0]);
      expect(s.lastKeptTurn, isTrue);
      expect(game.currentPlayer(s), 'b');
    });

    test('can complete two boxes with one edge', () {
      var s = fresh();
      // Set up two side-by-side boxes that share the middle vertical.
      // Box (0,0): needs top0, left v0, bottom h2, right v1
      // Box (0,1): needs top1, right v2, bottom h3, left v1
      // Claim all but the shared v1, then claim v1 to complete both.

      // tops
      s = game.applyMove(s, const DotsAndBoxesMove.h(0)); // a
      s = game.applyMove(s, const DotsAndBoxesMove.h(1)); // b
      // bottoms
      s = game.applyMove(s, const DotsAndBoxesMove.h(2)); // a
      s = game.applyMove(s, const DotsAndBoxesMove.h(3)); // b
      // outer verticals
      s = game.applyMove(s, const DotsAndBoxesMove.v(0)); // a left of box0
      s = game.applyMove(s, const DotsAndBoxesMove.v(2)); // b right of box1
      // shared middle completes both for a
      s = game.applyMove(s, const DotsAndBoxesMove.v(1)); // a
      expect(s.boxes[0], 'a');
      expect(s.boxes[1], 'a');
      expect(s.lastCompletedBoxes.toSet(), {0, 1});
      expect(s.lastKeptTurn, isTrue);
      expect(game.currentPlayer(s), 'a');
    });

    test('outcome is win by higher box count', () {
      // Manually fill a finished state: a has 3 boxes, b has 1
      final s = DotsAndBoxesState(
        n: 2,
        hEdges: List<String?>.filled(6, 'a'),
        vEdges: List<String?>.filled(6, 'a'),
        boxes: ['a', 'a', 'a', 'b'],
        playerIds: const ['a', 'b'],
        currentPlayerId: 'a',
      );
      expect(game.outcome(s), const GameOutcome.win('a'));
    });

    test('outcome is draw when scores tie', () {
      final s = DotsAndBoxesState(
        n: 2,
        hEdges: List<String?>.filled(6, 'a'),
        vEdges: List<String?>.filled(6, 'a'),
        boxes: ['a', 'a', 'b', 'b'],
        playerIds: const ['a', 'b'],
        currentPlayerId: 'a',
      );
      expect(game.outcome(s), const GameOutcome.draw());
    });

    test('state survives encode/decode', () {
      var s = fresh();
      s = game.applyMove(s, const DotsAndBoxesMove.h(0));
      s = game.applyMove(s, const DotsAndBoxesMove.v(0));
      final decoded =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(decoded.hEdges, s.hEdges);
      expect(decoded.vEdges, s.vEdges);
      expect(decoded.boxes, s.boxes);
      expect(decoded.currentPlayerId, s.currentPlayerId);
      expect(decoded.n, s.n);
    });
  });
}
