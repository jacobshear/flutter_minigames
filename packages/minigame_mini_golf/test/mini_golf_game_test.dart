
import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_mini_golf/minigame_mini_golf.dart';
import 'package:minigames_core/minigames_core.dart';

const p1 = 'p1';
const p2 = 'p2';
const players = [p1, p2];

MiniGolfState fresh({int seed = 0, int holes = 9}) =>
    MiniGolfGame(holeCount: holes).initialState(seed: seed, playerIds: players);

/// A putt that leaves the ball short of the cup (never sinks).
MiniGolfMove putt(String owner, {double nx = 0.5, double ny = 0.8}) =>
    MiniGolfMove(owner: owner, ballNx: nx, ballNy: ny);

MiniGolfMove sink(String owner) =>
    MiniGolfMove(owner: owner, ballNx: 0.5, ballNy: 0.2, sunk: true);

/// Plays [strokes] putts then holes out — [strokes] total strokes for the hole.
MiniGolfState holeOut(
  MiniGolfGame game,
  MiniGolfState s,
  String who, {
  required int strokes,
}) {
  var st = s;
  for (var i = 0; i < strokes - 1; i++) {
    st = game.applyMove(st, putt(who));
  }
  return game.applyMove(st, sink(who));
}

void main() {
  group('setup', () {
    test('opens on hole 1 with both balls on the tee', () {
      final s = fresh();
      expect(s.currentHole, 0);
      expect(s.holeCount, 9);
      expect(s.currentPlayerId, p1);
      expect(s.holeStrokesOf(p1), 0);
      expect(s.holeStrokesOf(p2), 0);
      expect(s.holedOutOf(p1), isFalse);
      expect(s.totalStrokes(p1), 0);
      final tee = s.currentCourse.normalizedTee;
      expect(s.ballNx[p1], tee.dx);
      expect(s.ballNy[p2], tee.dy);
    });

    test('supports 3, 6 and 9 hole matches', () {
      for (final n in [3, 6, 9]) {
        final s = fresh(holes: n);
        expect(s.holeCount, n);
        // Par is per hole now, so the total is the sum, not par × holes.
        var sum = 0;
        for (var h = 0; h < n; h++) {
          sum += s.parOf(h);
        }
        expect(s.totalPar, sum);
        expect(s.totalPar, greaterThanOrEqualTo(2 * n));
      }
    });

    test('par varies hole to hole', () {
      final s = fresh();
      final pars = {for (var h = 0; h < 9; h++) s.parOf(h)};
      expect(pars.length, greaterThan(1),
          reason: 'a course of one flat par is the old behaviour');
      for (final p in pars) {
        expect(p, inInclusiveRange(2, 5));
      }
    });
  });

  group('stroke counting', () {
    test('each putt costs a stroke and keeps the turn until holed out', () {
      const game = MiniGolfGame();
      var s = fresh();
      s = game.applyMove(s, putt(p1));
      expect(s.holeStrokesOf(p1), 1);
      expect(s.currentPlayerId, p1, reason: 'still putting');
      s = game.applyMove(s, putt(p1));
      expect(s.holeStrokesOf(p1), 2);
      expect(s.totalStrokes(p1), 2);
    });

    test('sinking hands off to the other player on the same hole', () {
      const game = MiniGolfGame();
      final s = holeOut(game, fresh(), p1, strokes: 3);
      expect(s.holedOutOf(p1), isTrue);
      expect(s.holeStrokesOf(p1), 3);
      expect(s.currentPlayerId, p2);
      expect(s.currentHole, 0, reason: 'p2 still has to play hole 1');
    });

    test('sinking parks the ball on the cup', () {
      const game = MiniGolfGame();
      final s0 = fresh();
      final cup = s0.currentCourse.normalizedCup;
      final s = game.applyMove(s0, sink(p1));
      expect(s.ballNx[p1], cup.dx);
      expect(s.ballNy[p1], cup.dy);
    });

    test('out of bounds costs the stroke and resets to the tee', () {
      const game = MiniGolfGame();
      final s0 = fresh();
      final tee = s0.currentCourse.normalizedTee;
      final s = game.applyMove(
        s0,
        const MiniGolfMove(
            owner: p1, ballNx: 0.9, ballNy: 0.9, outOfBounds: true),
      );
      expect(s.holeStrokesOf(p1), 1);
      expect(s.ballNx[p1], tee.dx);
      expect(s.ballNy[p1], tee.dy);
    });
  });

  group('hole advance', () {
    test('both holing out banks the scorecard and starts the next hole', () {
      const game = MiniGolfGame();
      var s = holeOut(game, fresh(), p1, strokes: 3);
      s = holeOut(game, s, p2, strokes: 5);

      expect(s.currentHole, 1, reason: 'advanced to hole 2');
      expect(s.scorecard[p1], [3]);
      expect(s.scorecard[p2], [5]);
      expect(s.totalStrokes(p1), 3);
      expect(s.totalStrokes(p2), 5);
      // Fresh hole: nobody holed out, strokes reset, p1 tees off.
      expect(s.currentPlayerId, p1);
      expect(s.holedOutOf(p1), isFalse);
      expect(s.holeStrokesOf(p1), 0);
      final tee = s.currentCourse.normalizedTee;
      expect(s.ballNx[p1], tee.dx);
    });

    test('a 3-hole match ends after three holes, fewest total wins', () {
      const game = MiniGolfGame(holeCount: 3);
      var s = fresh(holes: 3);
      // p1: 2+2+2 = 6, p2: 3+3+3 = 9
      for (var h = 0; h < 3; h++) {
        s = holeOut(game, s, p1, strokes: 2);
        s = holeOut(game, s, p2, strokes: 3);
      }
      expect(s.currentHole, 3);
      expect(s.totalStrokes(p1), 6);
      expect(s.totalStrokes(p2), 9);
      final out = game.outcome(s);
      expect(out, isNotNull);
      expect(out!.winnerId, p1);
    });

    test('equal totals draw', () {
      const game = MiniGolfGame(holeCount: 3);
      var s = fresh(holes: 3);
      for (var h = 0; h < 3; h++) {
        s = holeOut(game, s, p1, strokes: 4);
        s = holeOut(game, s, p2, strokes: 4);
      }
      expect(game.outcome(s)!.isDraw, isTrue);
    });

    test('no outcome while holes remain', () {
      const game = MiniGolfGame(holeCount: 3);
      var s = holeOut(game, fresh(holes: 3), p1, strokes: 2);
      s = holeOut(game, s, p2, strokes: 2);
      expect(s.currentHole, 1);
      expect(game.outcome(s), isNull);
    });
  });

  group('validation', () {
    test('rejects out-of-turn, wrong owner, and a holed-out player', () {
      const game = MiniGolfGame();
      final s = fresh();
      expect(game.validateMove(s, putt(p1), p1), isTrue);
      expect(game.validateMove(s, putt(p2), p2), isFalse, reason: 'p1 to play');
      expect(game.validateMove(s, putt(p2), p1), isFalse, reason: 'wrong owner');
    });

    test('rejects out-of-bounds settled coordinates', () {
      const game = MiniGolfGame();
      final s = fresh();
      expect(game.validateMove(s, putt(p1, nx: 1.4), p1), isFalse);
      expect(game.validateMove(s, putt(p1, ny: -0.2), p1), isFalse);
      // An explicit OOB putt carries no meaningful coords, so it's accepted.
      expect(
        game.validateMove(
          s,
          const MiniGolfMove(
              owner: p1, ballNx: 9, ballNy: 9, outOfBounds: true),
          p1,
        ),
        isTrue,
      );
    });

    test('rejects moves once the match is over', () {
      const game = MiniGolfGame(holeCount: 3);
      var s = fresh(holes: 3);
      for (var h = 0; h < 3; h++) {
        s = holeOut(game, s, p1, strokes: 2);
        s = holeOut(game, s, p2, strokes: 2);
      }
      expect(game.validateMove(s, putt(p1), p1), isFalse);
    });
  });

  group('serialization', () {
    test('state round-trips through JSON', () {
      const game = MiniGolfGame(holeCount: 6);
      var s = holeOut(game, fresh(holes: 6), p1, strokes: 3);
      s = holeOut(game, s, p2, strokes: 2);
      s = game.applyMove(s, putt(p1));

      final back =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(back.baseSeed, s.baseSeed);
      expect(back.holeCount, s.holeCount);
      expect(back.currentHole, s.currentHole);
      expect(back.currentPlayerId, s.currentPlayerId);
      expect(back.scorecard[p1], s.scorecard[p1]);
      expect(back.scorecard[p2], s.scorecard[p2]);
      expect(back.holeStrokes[p1], s.holeStrokes[p1]);
      expect(back.holedOut[p2], s.holedOut[p2]);
      expect(back.ballNx[p1], s.ballNx[p1]);
      expect(back.totalStrokes(p1), s.totalStrokes(p1));
      // Par is derived from the seed, so it survives the round trip for free.
      expect(back.totalPar, s.totalPar);
      expect(back.currentCourse.fingerprint, s.currentCourse.fingerprint);
    });

    test('move round-trips through JSON', () {
      const game = MiniGolfGame();
      for (final m in [
        putt(p1, nx: 0.31, ny: 0.62),
        sink(p2),
        const MiniGolfMove(
            owner: p1, ballNx: 0.1, ballNy: 0.1, outOfBounds: true),
      ]) {
        final back = game.decodeMove(game.encodeMove(m));
        expect(back.owner, m.owner);
        expect(back.ballNx, m.ballNx);
        expect(back.ballNy, m.ballNy);
        expect(back.sunk, m.sunk);
        expect(back.outOfBounds, m.outOfBounds);
      }
    });
  });

  group('coordinate bridge', () {
    test('normalized ball positions round-trip through world space', () {
      final s = fresh(seed: 12);
      final c = s.currentCourse;
      for (final n in [
        c.normalizedTee,
        c.normalizedCup,
        const Offset(0.25, 0.75),
      ]) {
        final world = c.denormalize(n.dx, n.dy);
        final back = c.normalize(world);
        expect(back.dx, closeTo(n.dx, 1e-9));
        expect(back.dy, closeTo(n.dy, 1e-9));
      }
    });

    test('ballWorld reports the tee at the start of a hole', () {
      final s = fresh(seed: 5);
      final w = s.ballWorld(p1);
      final tee = s.currentCourse.tee;
      expect(w.x, closeTo(tee.dx, 1e-6));
      expect(w.z, closeTo(tee.dy, 1e-6));
    });
  });

  test('a full 3-hole match runs through MatchController', () async {
    const game = MiniGolfGame(holeCount: 3);
    final transport = LocalTransport();
    final controller = await MatchController.create<MiniGolfState, MiniGolfMove>(
      game: game,
      transport: transport,
      matchId: 'mg-1',
      playerIds: players,
      localPlayerId: p1,
      hotSeat: true,
      seed: 3,
    );
    addTearDown(controller.dispose);

    for (var h = 0; h < 3; h++) {
      for (final who in players) {
        await controller.submitMove(putt(who));
        await controller.submitMove(sink(who));
      }
    }
    final s = controller.state!;
    expect(s.currentHole, 3);
    expect(s.scorecard[p1], [2, 2, 2]);
    expect(game.outcome(s)!.isDraw, isTrue);
  });
}
