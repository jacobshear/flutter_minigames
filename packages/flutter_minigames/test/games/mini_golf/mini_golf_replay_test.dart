import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/mini_golf/mini_golf.dart';
import 'package:flutter_minigames/src/core/core.dart';

const p1 = 'p1';
const p2 = 'p2';
const players = [p1, p2];

MiniGolfState fresh({int seed = 0, int holes = 9}) =>
    MiniGolfGame(holeCount: holes).initialState(seed: seed, playerIds: players);

/// A putt with recorded input — the shape a board actually submits.
MiniGolfMove aimedPutt(
  String owner, {
  required double nx,
  required double ny,
  double dirX = 0,
  double dirY = 1,
  double power = 0.5,
  bool sunk = false,
  bool outOfBounds = false,
  int? holeIndex,
}) =>
    MiniGolfMove(
      owner: owner,
      ballNx: nx,
      ballNy: ny,
      sunk: sunk,
      outOfBounds: outOfBounds,
      dirX: dirX,
      dirY: dirY,
      power: power,
      holeIndex: holeIndex,
    );

void main() {
  group('MiniGolfStroke recording', () {
    test('a move with input fields records lastStroke and bumps strokeSeq', () {
      const game = MiniGolfGame();
      final s0 = fresh();
      final tee = s0.currentCourse.normalizedTee;

      final s1 = game.applyMove(
        s0,
        aimedPutt(p1, nx: 0.5, ny: 0.6, dirX: 0.1, dirY: 0.9, power: 0.42),
      );

      expect(s1.strokeSeq, 1);
      final stroke = s1.lastStroke;
      expect(stroke, isNotNull);
      expect(stroke!.owner, p1);
      expect(stroke.fromNx, closeTo(tee.dx, 1e-9));
      expect(stroke.fromNy, closeTo(tee.dy, 1e-9));
      expect(stroke.dirX, 0.1);
      expect(stroke.dirY, 0.9);
      expect(stroke.power, 0.42);
      expect(stroke.holeIndex, 0);
      expect(stroke.strokeId, 1);
    });

    test('strokeId keeps increasing across strokes and holes', () {
      const game = MiniGolfGame();
      var s = fresh();
      s = game.applyMove(s, aimedPutt(p1, nx: 0.5, ny: 0.6));
      expect(s.lastStroke!.strokeId, 1);
      s = game.applyMove(
        s,
        aimedPutt(p1, nx: 0.5, ny: 0.2, sunk: true),
      );
      expect(s.lastStroke!.strokeId, 2);
      expect(s.lastStroke!.holeIndex, 0);
      expect(s.strokeSeq, 2);
    });

    test(
        'a hole-ending stroke records the hole it was actually played on, '
        'even though currentHole has already advanced', () {
      const game = MiniGolfGame(holeCount: 3);
      var s = fresh(holes: 3);
      // p1 holes hole 0 in one, then p2 holes it too — advancing to hole 1.
      s = game.applyMove(s, aimedPutt(p1, nx: 0.5, ny: 0.2, sunk: true));
      s = game.applyMove(s, aimedPutt(p2, nx: 0.5, ny: 0.2, sunk: true));

      expect(s.currentHole, 1, reason: 'the reducer already advanced');
      expect(s.lastStroke!.owner, p2);
      expect(s.lastStroke!.holeIndex, 0,
          reason: 'the stroke that holed out was played on hole 0');
    });

    test('a move without input fields leaves lastStroke stale, not null', () {
      const game = MiniGolfGame();
      var s = fresh();
      s = game.applyMove(
        s,
        aimedPutt(p1, nx: 0.5, ny: 0.6, dirX: 0, dirY: 1, power: 0.3),
      );
      final recorded = s.lastStroke;
      expect(recorded, isNotNull);

      // A legacy move (no dirX/dirY/power) still advances strokeSeq, but
      // does not overwrite lastStroke — so a board tracking the highest
      // strokeId it has shown never sees a replay-worthy stroke for it.
      s = game.applyMove(
        s,
        const MiniGolfMove(owner: p2, ballNx: 0.5, ballNy: 0.7),
      );
      expect(s.strokeSeq, 2);
      expect(s.lastStroke, same(recorded));
    });

    test('initial state has no lastStroke', () {
      expect(fresh().lastStroke, isNull);
      expect(fresh().strokeSeq, 0);
    });
  });

  group('serialization', () {
    test('state round-trips lastStroke and strokeSeq through JSON', () {
      const game = MiniGolfGame();
      var s = fresh();
      s = game.applyMove(
        s,
        aimedPutt(p1, nx: 0.55, ny: 0.61, dirX: 0.2, dirY: 0.8, power: 0.77),
      );

      final back =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(back.strokeSeq, s.strokeSeq);
      final stroke = back.lastStroke;
      final original = s.lastStroke!;
      expect(stroke, isNotNull);
      expect(stroke!.owner, original.owner);
      expect(stroke.fromNx, original.fromNx);
      expect(stroke.fromNy, original.fromNy);
      expect(stroke.dirX, original.dirX);
      expect(stroke.dirY, original.dirY);
      expect(stroke.power, original.power);
      expect(stroke.holeIndex, original.holeIndex);
      expect(stroke.strokeId, original.strokeId);
    });

    test('a LEGACY state json (no strokeSeq/lastStroke keys) decodes clean',
        () {
      const game = MiniGolfGame();
      final s = fresh();
      final json = game.encodeState(s);
      json.remove('strokeSeq');
      json.remove('lastStroke');

      final back = game.decodeState(json, 3);
      expect(back.strokeSeq, 0);
      expect(back.lastStroke, isNull);
      // Everything else still decodes normally.
      expect(back.currentHole, s.currentHole);
      expect(back.currentPlayerId, s.currentPlayerId);
    });

    test('move round-trips the recorded-input fields through JSON', () {
      const game = MiniGolfGame();
      final move =
          aimedPutt(p1, nx: 0.3, ny: 0.4, dirX: -0.5, dirY: 0.86, power: 0.9);
      final back = game.decodeMove(game.encodeMove(move));
      expect(back.dirX, move.dirX);
      expect(back.dirY, move.dirY);
      expect(back.power, move.power);
      expect(back.holeIndex, move.holeIndex);
    });

    test('a legacy-shaped move json (no input keys) decodes to null input', () {
      const game = MiniGolfGame();
      final json = game.encodeMove(const MiniGolfMove(
        owner: p1,
        ballNx: 0.5,
        ballNy: 0.5,
      ));
      json.remove('dirX');
      json.remove('dirY');
      json.remove('power');
      json.remove('holeIndex');
      final back = game.decodeMove(json);
      expect(back.dirX, isNull);
      expect(back.dirY, isNull);
      expect(back.power, isNull);
      expect(back.holeIndex, isNull);
    });
  });

  group('replayStepDelay', () {
    test('is at least a readable hold when there is no recorded stroke', () {
      const game = MiniGolfGame();
      final s = fresh();
      final delay = game.replayStepDelay(s, s);
      expect(delay.inMilliseconds, greaterThanOrEqualTo(400));
    });

    test('covers the actual simulated roll of a recorded stroke', () {
      const game = MiniGolfGame();
      var s = fresh();
      final before = s;
      s = game.applyMove(
        s,
        aimedPutt(p1, nx: 0.5, ny: 0.5, dirX: 0, dirY: 1, power: 0.8),
      );
      final delay = game.replayStepDelay(before, s);
      final course = s.holeCourse(s.lastStroke!.holeIndex);
      final result = MiniGolfPutt.simulate(
        course: course,
        from: course.denormalize(s.lastStroke!.fromNx, s.lastStroke!.fromNy),
        direction: Offset(s.lastStroke!.dirX, s.lastStroke!.dirY),
        power: s.lastStroke!.power,
      );
      expect(
        delay.inMilliseconds,
        greaterThanOrEqualTo((result.duration * 1000).round()),
        reason: 'the delay must not cut the replayed roll short',
      );
      expect(
        delay.inMilliseconds,
        lessThanOrEqualTo((result.duration * 1000).round() + 300),
        reason: 'no ceiling: the hold is exactly the roll plus a beat',
      );
    });
  });

  group('board replay (widget)', () {
    Widget host(MatchController<MiniGolfState, MiniGolfMove> c) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 620,
                child: MiniGolfBoard(controller: c),
              ),
            ),
          ),
        );

    Future<void> pumpOut(WidgetTester tester, {int frames = 260}) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
    }

    testWidgets(
        'replays a remote stroke and converges on the authoritative ball '
        'position with no exceptions', (tester) async {
      const game = MiniGolfGame(holeCount: 3);
      final transport = LocalTransport();
      final controller =
          await MatchController.create<MiniGolfState, MiniGolfMove>(
        game: game,
        transport: transport,
        matchId: 'replay-remote',
        playerIds: players,
        localPlayerId: p1,
        hotSeat: false,
        seed: 11,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(controller));
      await tester.pump();

      // Simulate the putt headlessly to get a physically real settled spot —
      // exactly what a board would submit — rather than an arbitrary point.
      final course = controller.state!.currentCourse;
      final tee = course.normalizedTee;
      const direction = Offset(0.05, 1);
      const power = 0.55;
      final result = MiniGolfPutt.simulate(
        course: course,
        from: course.denormalize(tee.dx, tee.dy),
        direction: direction,
        power: power,
      );
      final settledN = course.normalize(result.settled);

      // Submitted directly through the controller (never through the
      // board's own drag gesture), so the board treats it exactly like a
      // stroke that arrived from a remote opponent.
      await controller.submitMove(MiniGolfMove(
        owner: p1,
        ballNx: settledN.dx,
        ballNy: settledN.dy,
        sunk: result.sunk,
        outOfBounds: result.outOfBounds,
        dirX: direction.dx,
        dirY: direction.dy,
        power: power,
        holeIndex: 0,
      ));
      await tester.pump();

      final boardState = tester.state(find.byType(MiniGolfBoard)) as dynamic;
      expect(boardState.debugIsReplaying as bool, isTrue,
          reason: 'a stroke that did not originate from this board replays');

      await pumpOut(tester);

      expect(boardState.debugIsReplaying as bool, isFalse);
      final finalState = controller.state!;
      expect(finalState.ballNx[p1], closeTo(settledN.dx, 1e-9));
      expect(finalState.ballNy[p1], closeTo(settledN.dy, 1e-9));
      final shown = boardState.debugState as MiniGolfState;
      expect(shown.ballNx[p1], closeTo(settledN.dx, 1e-6));
      expect(shown.ballNy[p1], closeTo(settledN.dy, 1e-6));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cold mount with an existing lastStroke does not replay',
        (tester) async {
      const game = MiniGolfGame();
      final transport = LocalTransport();
      final controller =
          await MatchController.create<MiniGolfState, MiniGolfMove>(
        game: game,
        transport: transport,
        matchId: 'replay-cold',
        playerIds: players,
        localPlayerId: p1,
        hotSeat: true,
        seed: 4,
      );
      addTearDown(controller.dispose);

      // Play a stroke before the board ever mounts.
      final course = controller.state!.currentCourse;
      final tee = course.normalizedTee;
      final result = MiniGolfPutt.simulate(
        course: course,
        from: course.denormalize(tee.dx, tee.dy),
        direction: const Offset(0, 1),
        power: 0.4,
      );
      final settledN = course.normalize(result.settled);
      await controller.submitMove(MiniGolfMove(
        owner: p1,
        ballNx: settledN.dx,
        ballNy: settledN.dy,
        sunk: result.sunk,
        outOfBounds: result.outOfBounds,
        dirX: 0,
        dirY: 1,
        power: 0.4,
        holeIndex: 0,
      ));

      await tester.pumpWidget(host(controller));
      await tester.pump();

      final boardState = tester.state(find.byType(MiniGolfBoard)) as dynamic;
      expect(boardState.debugIsReplaying as bool, isFalse,
          reason: 'contract point 3: cold-mount never replays');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposing the board mid-replay does not throw',
        (tester) async {
      const game = MiniGolfGame(holeCount: 3);
      final transport = LocalTransport();
      final controller =
          await MatchController.create<MiniGolfState, MiniGolfMove>(
        game: game,
        transport: transport,
        matchId: 'replay-dispose',
        playerIds: players,
        localPlayerId: p1,
        hotSeat: false,
        seed: 9,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(controller));
      await tester.pump();

      final course = controller.state!.currentCourse;
      final tee = course.normalizedTee;
      const direction = Offset(0, 1);
      const power = 0.6;
      final result = MiniGolfPutt.simulate(
        course: course,
        from: course.denormalize(tee.dx, tee.dy),
        direction: direction,
        power: power,
      );
      final settledN = course.normalize(result.settled);
      await controller.submitMove(MiniGolfMove(
        owner: p1,
        ballNx: settledN.dx,
        ballNy: settledN.dy,
        sunk: result.sunk,
        outOfBounds: result.outOfBounds,
        dirX: direction.dx,
        dirY: direction.dy,
        power: power,
        holeIndex: 0,
      ));
      // A few frames into the replay, but not out.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 64));

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 64));
      expect(tester.takeException(), isNull);
    });
  });
}
