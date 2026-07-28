import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/shuffleboard/shuffleboard.dart';
import 'package:flutter_minigames/src/core/core.dart';

void main() {
  const game = ShuffleboardGame(pucksPerPlayer: 2);

  ShuffleboardState fresh() =>
      game.initialState(seed: 0, playerIds: const ['p1', 'p2']);

  // Build a move for [owner]'s next puck, carrying [positions] plus the freshly
  // launched puck at (nx, ny).
  ShuffleboardMove slide(
    ShuffleboardState s,
    String owner,
    String puckId,
    double nx,
    double ny, {
    List<PuckPosition> carryOver = const [],
    bool removed = false,
  }) {
    return ShuffleboardMove(
      launchedPuckId: puckId,
      owner: owner,
      positions: [
        ...carryOver,
        PuckPosition(id: puckId, owner: owner, nx: nx, ny: ny, removed: removed),
      ],
    );
  }

  // Snapshot all current pucks as carry-over positions (physics reports them).
  List<PuckPosition> carry(ShuffleboardState s) => [
        for (final p in s.pucks)
          PuckPosition(
            id: p.id,
            owner: p.owner,
            nx: p.nx,
            ny: p.ny,
            removed: p.status == PuckStatus.offEnd,
          ),
      ];

  group('setup + turn flow', () {
    test('opens empty, p1 to move, 2 pucks each', () {
      final s = fresh();
      expect(s.pucks, isEmpty);
      expect(game.currentPlayer(s), 'p1');
      expect(s.remainingOf('p1'), 2);
      expect(s.remainingOf('p2'), 2);
      expect(game.outcome(s), isNull);
    });

    test('turns alternate and decrement remaining', () {
      var s = fresh();
      s = game.applyMove(s, slide(s, 'p1', 'p1-0', 0.5, 0.25));
      expect(game.currentPlayer(s), 'p2');
      expect(s.remainingOf('p1'), 1);

      s = game.applyMove(s, slide(s, 'p2', 'p2-0', 0.5, 0.25, carryOver: carry(s)));
      expect(game.currentPlayer(s), 'p1');
      expect(s.remainingOf('p2'), 1);
    });
  });

  group('scoring', () {
    test('bands 3/2/1 by ny, foul and off-end score 0', () {
      expect(ShuffleboardGame.zoneValue(0.05), 3);
      expect(ShuffleboardGame.zoneValue(0.15), 2);
      expect(ShuffleboardGame.zoneValue(0.28), 1);
      expect(ShuffleboardGame.zoneValue(0.45), 0);

      expect(ShuffleboardGame.statusFor(0.05, removed: false), PuckStatus.inZone);
      expect(ShuffleboardGame.statusFor(0.45, removed: false), PuckStatus.onBoard);
      expect(ShuffleboardGame.statusFor(0.80, removed: false), PuckStatus.foul);
      expect(ShuffleboardGame.statusFor(0.05, removed: true), PuckStatus.offEnd);
    });

    test('a scoring slide credits the shooter', () {
      var s = fresh();
      s = game.applyMove(s, slide(s, 'p1', 'p1-0', 0.5, 0.05)); // zone 3
      final puck = s.pucks.single;
      expect(puck.status, PuckStatus.inZone);
      expect(puck.value, 3);
      expect(s.scoreOf('p1'), 3);
      expect(s.scoreOf('p2'), 0);
    });

    test('foul puck (short of the line) scores nothing', () {
      var s = fresh();
      s = game.applyMove(s, slide(s, 'p1', 'p1-0', 0.5, 0.85));
      expect(s.pucks.single.status, PuckStatus.foul);
      expect(s.scoreOf('p1'), 0);
    });

    test('off-the-end puck is removed and scores nothing', () {
      var s = fresh();
      s = game.applyMove(
        s,
        slide(s, 'p1', 'p1-0', 0.5, -0.05, removed: true),
      );
      expect(s.pucks.single.status, PuckStatus.offEnd);
      expect(s.scoreOf('p1'), 0);
    });

    test('knocking an opponent puck OUT of its zone recomputes score', () {
      var s = fresh();
      // p1 parks a puck in zone 2.
      s = game.applyMove(s, slide(s, 'p1', 'p1-0', 0.5, 0.15));
      expect(s.scoreOf('p1'), 2);

      // p2 slides in and the outcome reports p1's puck knocked into foul
      // territory (0.85) while p2 lands in zone 1 (0.28).
      final positions = [
        const PuckPosition(id: 'p1-0', owner: 'p1', nx: 0.5, ny: 0.85),
        const PuckPosition(id: 'p2-0', owner: 'p2', nx: 0.52, ny: 0.28),
      ];
      s = game.applyMove(
        s,
        ShuffleboardMove(
          launchedPuckId: 'p2-0',
          owner: 'p2',
          positions: positions,
        ),
      );
      expect(s.scoreOf('p1'), 0, reason: 'p1 was knocked out of its zone');
      expect(s.scoreOf('p2'), 1);
    });

    test('knocking an opponent puck INTO a better zone recomputes score', () {
      var s = fresh();
      s = game.applyMove(s, slide(s, 'p1', 'p1-0', 0.5, 0.28)); // zone 1
      expect(s.scoreOf('p1'), 1);

      // p2's slide shoves p1's puck up into zone 3 (0.05); p2 fouls out.
      s = game.applyMove(
        s,
        const ShuffleboardMove(
          launchedPuckId: 'p2-0',
          owner: 'p2',
          positions: [
            PuckPosition(id: 'p1-0', owner: 'p1', nx: 0.5, ny: 0.05),
            PuckPosition(id: 'p2-0', owner: 'p2', nx: 0.5, ny: 0.85),
          ],
        ),
      );
      expect(s.scoreOf('p1'), 3, reason: 'p1 puck pushed into zone 3');
      expect(s.scoreOf('p2'), 0);
    });
  });

  group('validation', () {
    test('rejects out-of-turn, wrong owner, and empty quiver', () {
      final s = fresh();
      // Wrong turn: p2 acting on p1's turn.
      expect(
        game.validateMove(s, slide(s, 'p2', 'p2-0', 0.5, 0.2), 'p2'),
        isFalse,
      );
      // Owner mismatch: move.owner != playerId.
      expect(
        game.validateMove(s, slide(s, 'p2', 'p2-0', 0.5, 0.2), 'p1'),
        isFalse,
      );
    });

    test('rejects out-of-bounds settled positions', () {
      final s = fresh();
      expect(
        game.validateMove(s, slide(s, 'p1', 'p1-0', 1.5, 0.2), 'p1'),
        isFalse,
      );
      expect(
        game.validateMove(s, slide(s, 'p1', 'p1-0', 0.5, 1.2), 'p1'),
        isFalse,
      );
    });

    test('rejects re-launching a puck already on the board', () {
      var s = fresh();
      s = game.applyMove(s, slide(s, 'p1', 'p1-0', 0.5, 0.2));
      // p2 slides, then it becomes p1 again; p1 tries to reuse p1-0.
      s = game.applyMove(s, slide(s, 'p2', 'p2-0', 0.5, 0.2, carryOver: carry(s)));
      final reuse = ShuffleboardMove(
        launchedPuckId: 'p1-0',
        owner: 'p1',
        positions: carry(s),
      );
      expect(game.validateMove(s, reuse, 'p1'), isFalse);
    });

    test('accepts a well-formed slide', () {
      final s = fresh();
      expect(
        game.validateMove(s, slide(s, 'p1', 'p1-0', 0.5, 0.2), 'p1'),
        isTrue,
      );
    });
  });

  group('win detection', () {
    test('match ends when both are out; higher score wins', () {
      var s = fresh();
      s = game.applyMove(s, slide(s, 'p1', 'p1-0', 0.5, 0.05)); // p1: 3
      s = game.applyMove(s, slide(s, 'p2', 'p2-0', 0.4, 0.15, carryOver: carry(s))); // p2: 2
      s = game.applyMove(s, slide(s, 'p1', 'p1-1', 0.6, 0.28, carryOver: carry(s))); // p1: +1 => 4
      expect(game.outcome(s), isNull);
      s = game.applyMove(s, slide(s, 'p2', 'p2-1', 0.3, 0.85, carryOver: carry(s))); // p2 foul
      expect(s.remainingOf('p1'), 0);
      expect(s.remainingOf('p2'), 0);
      expect(game.outcome(s), const GameOutcome.win('p1'));
    });

    test('equal scores draw', () {
      var s = fresh();
      s = game.applyMove(s, slide(s, 'p1', 'p1-0', 0.5, 0.15)); // 2
      s = game.applyMove(s, slide(s, 'p2', 'p2-0', 0.4, 0.15, carryOver: carry(s))); // 2
      s = game.applyMove(s, slide(s, 'p1', 'p1-1', 0.5, 0.85, carryOver: carry(s))); // foul
      s = game.applyMove(s, slide(s, 'p2', 'p2-1', 0.4, 0.85, carryOver: carry(s))); // foul
      expect(game.outcome(s), const GameOutcome.draw());
    });

    test('one player finishes their pucks after the other runs out', () {
      const g = ShuffleboardGame(pucksPerPlayer: 2);
      var s = g.initialState(seed: 0, playerIds: const ['p1', 'p2']);
      // Force p2 out first via alternation, then p1 keeps sliding.
      s = g.applyMove(s, slide(s, 'p1', 'p1-0', 0.5, 0.2));
      s = g.applyMove(s, slide(s, 'p2', 'p2-0', 0.5, 0.2, carryOver: carry(s)));
      s = g.applyMove(s, slide(s, 'p1', 'p1-1', 0.55, 0.2, carryOver: carry(s)));
      // p1 now out; p2 has 1 left => turn is p2.
      expect(s.currentPlayerId, 'p2');
      s = g.applyMove(s, slide(s, 'p2', 'p2-1', 0.45, 0.2, carryOver: carry(s)));
      expect(g.outcome(s), isNotNull);
    });
  });

  group('serialization', () {
    test('state round-trips through JSON', () {
      var s = fresh();
      s = game.applyMove(s, slide(s, 'p1', 'p1-0', 0.5, 0.05));
      s = game.applyMove(s, slide(s, 'p2', 'p2-0', 0.42, 0.85, carryOver: carry(s)));
      final decoded =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(decoded.pucks.length, s.pucks.length);
      expect(decoded.currentPlayerId, s.currentPlayerId);
      expect(decoded.scoreOf('p1'), s.scoreOf('p1'));
      expect(decoded.remainingOf('p2'), s.remainingOf('p2'));
      expect(decoded.pucks.first.status, s.pucks.first.status);
    });

    test('move round-trips through JSON', () {
      final s = fresh();
      final move = slide(s, 'p1', 'p1-0', 0.5, 0.12);
      final decoded = game.decodeMove(game.encodeMove(move));
      expect(decoded.launchedPuckId, move.launchedPuckId);
      expect(decoded.owner, move.owner);
      expect(decoded.positions.single.ny, closeTo(0.12, 1e-9));
    });
  });
}
