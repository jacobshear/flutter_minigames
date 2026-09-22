import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show Vector2;
import 'package:flutter_minigames/src/games/eight_ball/eight_ball.dart';
import 'package:flutter_minigames/src/core/core.dart';

// NOTE: mirrors test/games/shuffleboard/shuffleboard_replay_test.dart's
// convention (itself mirroring cup_pong_board_test.dart) — these widget
// tests deliberately never `await controller.dispose()`, since
// MatchController.dispose() awaits a StreamController.close() that does not
// complete inside testWidgets' fake-async zone. Unmounting the widget is
// what actually needs covering.

Widget _host(MatchController<EightBallState, EightBallMove> c) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            height: 620,
            child: EightBallBoard(controller: c),
          ),
        ),
      ),
    );

/// Advances the fake clock in small increments so both `MatchController`'s
/// real `Timer`-based replay pacing AND the board's Flame ticker (which caps
/// physics steps per `update()` call — see EightBallScene.update) make
/// forward progress. Sized generously: EightBallScene.simConfig's low
/// damping/high restitution (real billiard rolls) settle slower than most
/// sibling physics games — see the rationale on EightBallGame.replayStepDelay.
Future<void> _settle(WidgetTester tester, {int iterations = 500}) async {
  for (var i = 0; i < iterations; i++) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

/// Runs the SAME physics harness the board's scene uses (`EightBallScene.
/// createSim` is public exactly so a test can — see its doc comment) to
/// produce a realistic, physically-settled shot from [preShot], mirroring
/// `EightBallScene._handleSettled`'s own outcome-packaging exactly: every
/// ball still simulated gets its settled spot, and any ball [preShot] already
/// had pocketed is carried forward untouched (it was never added to the sim
/// — see `createSim`'s `if (b.pocketed) continue;`). Returns the settled
/// [BallPosition]s, the first ball the cue struck, and the impulse that
/// produced them, so a test can submit a move a real board would have and
/// expect a replay driven by the same impulse to land on the same outcome.
({List<BallPosition> positions, int? firstHit, double ix, double iy})
    _realSettledShot(EightBallState preShot, double ix, double iy) {
  final built = EightBallScene.createSim(preShot);
  final sim = built.sim;
  int? firstHit;
  sim.onDiscCollision = (a, b) {
    if (firstHit != null) return;
    final an = int.parse(a.id), bn = int.parse(b.id);
    if (an == EightBallGame.cueNumber) {
      firstHit = bn;
    } else if (bn == EightBallGame.cueNumber) {
      firstHit = an;
    }
  };
  sim.launch(built.cue!, Vector2(ix, iy));
  final outcome = sim.runUntilSettled();
  final settledByNumber = {for (final b in outcome.bodies) int.parse(b.id): b};
  final positions = [
    for (final b in preShot.balls)
      if (settledByNumber[b.number] != null)
        BallPosition(
          number: b.number,
          nx: (settledByNumber[b.number]!.x / EightBallGame.tableW + 0.5)
              .clamp(0.0, 1.0),
          ny: (settledByNumber[b.number]!.y / EightBallGame.tableL)
              .clamp(0.0, 1.0),
          pocketed: settledByNumber[b.number]!.removed,
        )
      else
        // Already pocketed before this shot — never simulated, carry it
        // forward as-is.
        BallPosition(number: b.number, nx: b.nx, ny: b.ny, pocketed: true),
  ];
  return (positions: positions, firstHit: firstHit, ix: ix, iy: iy);
}

/// Builds and submits a shot move for [owner] from [preShot] using the real
/// physics harness, and returns the resulting authoritative state (decoded
/// straight from the transport, matching what a receiving board must
/// eventually converge on).
Future<EightBallState> _submitRealShot(
  MatchController<EightBallState, EightBallMove> controller,
  GameTransport transport,
  String matchId,
  EightBallState preShot,
  String owner,
  double ix,
  double iy,
) async {
  final real = _realSettledShot(preShot, ix, iy);
  final move = EightBallMove.shot(
    owner: owner,
    positions: real.positions,
    firstHitNumber: real.firstHit,
    shotImpulseX: ix,
    shotImpulseY: iy,
  );
  expect(await controller.submitMove(move), isTrue);
  final match = await transport.loadMatch(matchId);
  return controller.game.decodeState(match!.state, match.schemaVersion);
}

void main() {
  group('opponent shot replay', () {
    testWidgets(
        'a remote shot with a recorded impulse replays via physics and '
        'reconciles to the authoritative outcome', (tester) async {
      final transport = LocalTransport();
      const game = EightBallGame();

      final host = await MatchController.create<EightBallState, EightBallMove>(
        game: game,
        transport: transport,
        matchId: 'rep1',
        playerIds: const ['p1', 'p2'],
        localPlayerId: 'p1',
        seed: 0,
      );

      // p1 breaks with a soft, straight tap — real physics, run through the
      // same harness the board's scene uses, so the outcome is exactly what
      // a real shot with this impulse produces.
      final preShot = game.initialState(seed: 0, playerIds: const ['p1', 'p2']);
      final expectedState =
          await _submitRealShot(host, transport, 'rep1', preShot, 'p1', 0, -5);
      expect(expectedState.lastShot, isNotNull);

      // p2 opens the match cold, after p1 already moved — MatchController
      // exposes the pre-shot snapshot first, then replays the real turn.
      final guest = MatchController<EightBallState, EightBallMove>(
        game: game,
        transport: transport,
        matchId: 'rep1',
        localPlayerId: 'p2',
      );
      await guest.connect(replayLastTurn: true);
      expect(guest.isReplayingLastTurn, isTrue);

      await tester.pumpWidget(_host(guest));
      await tester.pump();

      // Cold mount: the board must show the pre-shot rack, not have started
      // any physics replay yet.
      final boardState = tester.state(find.byType(EightBallBoard)) as dynamic;
      final coldShown = boardState.debugState as EightBallState;
      expect(coldShown.shotsTaken, 0);
      expect(boardState.debugIsReplaying as bool, isFalse);

      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(guest.isReplayingLastTurn, isFalse,
          reason: 'the controller-level replay should have landed by now');
      expect(boardState.debugIsReplaying as bool, isFalse,
          reason: 'the board physics replay should have settled by now');

      final shown = boardState.debugState as EightBallState;
      expect(shown.balls.length, expectedState.balls.length);
      for (final expectedBall in expectedState.balls) {
        final shownBall =
            shown.balls.firstWhere((b) => b.number == expectedBall.number);
        expect(shownBall.pocketed, expectedBall.pocketed,
            reason: 'ball ${expectedBall.number}');
        if (!expectedBall.pocketed) {
          expect(shownBall.nx, closeTo(expectedBall.nx, 1e-6),
              reason: 'ball ${expectedBall.number} nx');
          expect(shownBall.ny, closeTo(expectedBall.ny, 1e-6),
              reason: 'ball ${expectedBall.number} ny');
        }
      }
      expect(shown.currentPlayerId, expectedState.currentPlayerId);
      expect(shown.shotsTaken, expectedState.shotsTaken);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a remote shot with NO recorded impulse (legacy move) never replays '
        '— the board just snaps to the authoritative state', (tester) async {
      final transport = LocalTransport();
      const game = EightBallGame();

      final host = await MatchController.create<EightBallState, EightBallMove>(
        game: game,
        transport: transport,
        matchId: 'rep2',
        playerIds: const ['p1', 'p2'],
        localPlayerId: 'p1',
        seed: 0,
      );

      final preShot = game.initialState(seed: 0, playerIds: const ['p1', 'p2']);
      final real = _realSettledShot(preShot, 0, -5);
      // A legacy-shaped move: settled positions, but no impulse recorded.
      final legacyMove = EightBallMove.shot(
        owner: 'p1',
        positions: real.positions,
        firstHitNumber: real.firstHit,
      );
      expect(await host.submitMove(legacyMove), isTrue);

      final guest = MatchController<EightBallState, EightBallMove>(
        game: game,
        transport: transport,
        matchId: 'rep2',
        localPlayerId: 'p2',
      );
      await guest.connect(replayLastTurn: true);

      await tester.pumpWidget(_host(guest));
      await tester.pump();
      // Past replayDelay (700ms) + this transition's replayStepDelay (900ms
      // — `to.lastShot` is null, the fast non-physics path), with margin for
      // the controller's own tail timer so none is left pending at test end.
      await _settle(tester, iterations: 80);

      expect(tester.takeException(), isNull);
      final boardState = tester.state(find.byType(EightBallBoard)) as dynamic;
      expect(boardState.debugIsReplaying as bool, isFalse,
          reason: 'no impulse input was recorded, so there is nothing to '
              'physics-replay');

      final expectedMatch = await transport.loadMatch('rep2');
      final expectedState =
          game.decodeState(expectedMatch!.state, expectedMatch.schemaVersion);
      final shown = boardState.debugState as EightBallState;
      for (final expectedBall in expectedState.balls) {
        final shownBall =
            shown.balls.firstWhere((b) => b.number == expectedBall.number);
        expect(shownBall.pocketed, expectedBall.pocketed);
        if (!expectedBall.pocketed) {
          expect(shownBall.nx, closeTo(expectedBall.nx, 1e-9));
          expect(shownBall.ny, closeTo(expectedBall.ny, 1e-9));
        }
      }
    });

    testWidgets(
        'a second sub-move landing mid-replay abandons the in-flight sim '
        'and jumps straight to the newest snapshot', (tester) async {
      final transport = LocalTransport();
      const game = EightBallGame();

      final host = await MatchController.create<EightBallState, EightBallMove>(
        game: game,
        transport: transport,
        matchId: 'rep3',
        playerIds: const ['p1', 'p2'],
        localPlayerId: 'p1',
        seed: 0,
      );

      // A full-power break: measured (see eight_ball_physics_test.dart's
      // sibling checks) to reliably pot at least one ball, which — on the
      // still-open table — keeps p1's turn (EightBallGame._applyShot's
      // `madeOwn` is true for any pot while the table is open). That makes
      // shot 2 a genuine continuation of the SAME turn (recorded via
      // Match.turnSteps), so the guest's replay queue holds two frames.
      final preShot = game.initialState(seed: 0, playerIds: const ['p1', 'p2']);
      final afterBreak =
          await _submitRealShot(host, transport, 'rep3', preShot, 'p1', 0, -20);
      expect(afterBreak.currentPlayerId, 'p1',
          reason: 'sanity: the break potted something and kept the turn');

      final afterSecond = await _submitRealShot(
          host, transport, 'rep3', afterBreak, 'p1', 0, -6);

      final guest = MatchController<EightBallState, EightBallMove>(
        game: game,
        transport: transport,
        matchId: 'rep3',
        localPlayerId: 'p2',
      );
      await guest.connect(replayLastTurn: true);
      await tester.pumpWidget(_host(guest));
      await tester.pump();

      // Past MatchController.replayDelay: the guest's board starts replaying
      // the break (shot 1) via real physics — which, per
      // EightBallGame.replayStepDelay's own measurements, takes several
      // seconds to settle.
      await tester.pump(const Duration(milliseconds: 750));
      final boardState = tester.state(find.byType(EightBallBoard)) as dynamic;
      expect(boardState.debugIsReplaying as bool, isTrue,
          reason: 'the break is still mid-flight this soon after it started');

      // EightBallGame.replayStepDelay scales with the recorded impulse (a
      // full-power break holds ~10.5s), so the break plays out before the
      // controller lands shot 2's frame, then shot 2 replays and the board
      // reconciles. The budget covers replayDelay + the break's step delay +
      // the last frame's tail, so no controller timer is left pending.
      await _settle(tester, iterations: 850);
      expect(tester.takeException(), isNull);
      expect(boardState.debugIsReplaying as bool, isFalse);

      final shown = boardState.debugState as EightBallState;
      expect(shown.shotsTaken, afterSecond.shotsTaken);
      for (final expectedBall in afterSecond.balls) {
        final shownBall =
            shown.balls.firstWhere((b) => b.number == expectedBall.number);
        expect(shownBall.pocketed, expectedBall.pocketed,
            reason: 'ball ${expectedBall.number}');
      }
    });
  });
}
