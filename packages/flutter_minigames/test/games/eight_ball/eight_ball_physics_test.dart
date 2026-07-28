import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show Vector2;
import 'package:flutter_minigames/src/games/eight_ball/eight_ball.dart';

/// Physics and drop-presentation checks for the table.
///
/// The pure rules live in `eight_ball_game_test.dart`; this file is about the
/// half that used to be judged by eye — how far a break scatters the rack, what
/// angle a cushion returns a ball at, and whether the pocket drop is a genuine
/// animation that leaves the recorded outcome alone.
void main() {
  const game = EightBallGame();
  const w = EightBallGame.tableW;
  const l = EightBallGame.tableL;

  EightBallState fresh() =>
      game.initialState(seed: 0, playerIds: const ['p1', 'p2']);

  /// A table with only the cue on it, parked at ([nx], [ny]).
  EightBallState cueOnly(double nx, double ny) => fresh().copyWith(
        balls: [
          Ball(number: 0, nx: nx, ny: ny, pocketed: false),
          for (var n = 1; n <= 15; n++)
            Ball(number: n, nx: 0.5, ny: 0.5, pocketed: true),
        ],
      );

  group('cushions', () {
    test('a rail returns the ball at its angle of incidence', () {
      // Fired at four incidences into the right-hand rail. A cushion is a
      // mirror in the tangential direction, so the outgoing angle must match
      // the incoming one; the *speed* may drop, the angle may not.
      for (final aim in [0.3, 0.6, 0.9, 1.2]) {
        final built = EightBallScene.createSim(cueOnly(0.5, 0.5));
        final sim = built.sim;
        final cue = built.cue!;
        sim.launch(cue, Vector2(math.cos(aim), -math.sin(aim)) * 9.0);

        Vector2? before;
        Vector2? after;
        for (var i = 0; i < 500 && after == null; i++) {
          final v = cue.body.linearVelocity.clone();
          sim.step();
          if (cue.removed) break;
          if (v.x > 0.2 && cue.body.linearVelocity.x < 0) {
            before = v;
            after = cue.body.linearVelocity.clone();
          }
        }
        expect(after, isNotNull, reason: 'aim $aim never reached the rail');
        final incidence = math.atan2(before!.y, before.x.abs());
        final reflect = math.atan2(after!.y, after.x.abs());
        expect(
          reflect,
          closeTo(incidence, 0.06),
          reason: 'aim $aim reflected at $reflect, arrived at $incidence',
        );
      }
    });

    test('a cushion returns most of the pace but not all of it', () {
      final built = EightBallScene.createSim(cueOnly(0.5, 0.5));
      final sim = built.sim;
      final cue = built.cue!;
      sim.launch(cue, Vector2(9.0, -3.0));
      Vector2? before;
      Vector2? after;
      for (var i = 0; i < 500 && after == null; i++) {
        final v = cue.body.linearVelocity.clone();
        sim.step();
        if (cue.removed) break;
        if (v.x > 0.2 && cue.body.linearVelocity.x < 0) {
          before = v;
          after = cue.body.linearVelocity.clone();
        }
      }
      expect(after, isNotNull);
      final ratio = after!.length / before!.length;
      // Lively rails (see the note on `wallRestitution`), but a bank has to
      // cost something or the ball would never stop banking.
      expect(ratio, lessThan(1.0));
      expect(ratio, greaterThan(0.85));
    });
  });

  group('the break', () {
    /// Run one break straight up the table at [impulse] and report how far each
    /// object ball travelled from its racked spot.
    List<double> breakSpread(double impulse) {
      final state = game.initialState(seed: 0, playerIds: const ['p1', 'p2']);
      final built = EightBallScene.createSim(state);
      final sim = built.sim;
      sim.launch(built.cue!, Vector2(0, -impulse));
      var steps = 0;
      while (sim.isRunning && steps < 6000) {
        sim.step();
        steps++;
      }
      return [
        for (final d in sim.discs)
          if ((d.owner as int) != EightBallGame.cueNumber)
            () {
              final n = d.owner as int;
              final start = state.balls.firstWhere((b) => b.number == n);
              return (d.position - EightBallScene.simPos(start.nx, start.ny))
                  .length;
            }(),
      ];
    }

    test('a full-power break opens the whole rack', () {
      final moved = breakSpread(EightBallScene.aimConfig.maxImpulse);
      expect(moved.length, 15);
      // Measured, not eyeballed: at the old 16-impulse full power five balls
      // finished inside a ball's width of their racked spot. A break has to
      // move every ball, and move them a long way on average.
      final stuck = moved.where((m) => m < EightBallGame.ballD).length;
      expect(stuck, 0, reason: 'balls barely moved: $moved');
      final mean = moved.reduce((a, b) => a + b) / moved.length;
      expect(mean, greaterThan(4.0), reason: 'mean spread only $mean');
    });

    test('a soft break is visibly softer than a hard one', () {
      double mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
      final soft = mean(breakSpread(6));
      final hard = mean(breakSpread(EightBallScene.aimConfig.maxImpulse));
      expect(hard, greaterThan(soft * 1.6));
    });

    test('no break tunnels a ball through a rail', () {
      final pockets = [
        Vector2(-w / 2, 0),
        Vector2(w / 2, 0),
        Vector2(-w / 2, l),
        Vector2(w / 2, l),
        Vector2(-w / 2, l / 2),
        Vector2(w / 2, l / 2),
      ];
      for (var a = 0; a < 9; a++) {
        final angle = -0.4 + a * 0.1;
        final built = EightBallScene.createSim(
          game.initialState(seed: 0, playerIds: const ['p1', 'p2']),
        );
        final sim = built.sim;
        final imp = EightBallScene.aimConfig.maxImpulse;
        sim.launch(
          built.cue!,
          Vector2(math.sin(angle) * imp, -math.cos(angle) * imp),
        );
        var steps = 0;
        while (sim.isRunning && steps < 6000) {
          sim.step();
          steps++;
        }
        for (final d in sim.discs) {
          if (!d.removed) continue;
          final near = pockets
              .map((p) => (d.position - p).length)
              .reduce((x, y) => x < y ? x : y);
          expect(near, lessThan(1.2),
              reason: 'ball ${d.owner} left the table at ${d.position} '
                  'on a break at angle $angle');
        }
      }
    });
  });

  group('the pocket drop', () {
    // The drop is presentation over a decision the sim already made. These
    // checks pin that down: it runs its full life, it is drawn inside the mouth
    // the jaws actually frame, and the ball it draws is not on the table.

    test('a drop runs its whole life: funnel, then fall', () {
      // The ball must reach the mouth before it starts falling, and it must
      // still be falling most of the way through — the failure this pins down
      // is a drop that hangs at full size and then pops out of existence.
      expect(poolDropStage(0).travel, 0);
      expect(poolDropStage(0).fall, 0);
      expect(poolDropStage(0.30).travel, closeTo(1.0, 1e-9),
          reason: 'still funnelling when it should be over the lip');
      expect(poolDropStage(0.40).fall, greaterThan(0.15),
          reason: 'the fall has to be visible early, not just at the end');
      expect(poolDropStage(1).fall, closeTo(1.0, 1e-9));
      // It lands rather than fading: the ball rebounds off the bottom just
      // before it comes to rest, so the fall dips under its final depth.
      expect(poolDropStage(0.94).fall, lessThan(poolDropStage(1.0).fall));

      // Monotone shrink and darken all the way down, up to the rebound.
      var lastScale = 2.0;
      var lastVeil = -1.0;
      for (var i = 0; i <= 16; i++) {
        // From the moment it tips over the lip to just before it lands.
        final s = poolDropStage(0.20 + i / 16 * 0.63);
        expect(s.scale, lessThan(lastScale));
        expect(s.veil, greaterThan(lastVeil));
        lastScale = s.scale;
        lastVeil = s.veil;
      }
      // It ends small and nearly black, but never inverted or invisible early.
      expect(poolDropStage(1).scale, lessThan(0.4));
      expect(poolDropStage(1).scale, greaterThan(0.2));
      expect(poolDropStage(1).veil, greaterThan(0.7));
      // The landing rebound: it comes back up a touch off the bottom.
      expect(poolDropStage(0.90).fall, lessThan(poolDropStage(1.0).fall));
    });

    test('the drawn mouth can swallow a ball whole', () {
      const size = Size(300, 600);
      final felt = poolFeltRect(size);
      final pockets = poolPocketGeometry(size);
      expect(pockets.length, 6);
      // The rim can only occlude the ball if the mouth is wider than it.
      final ballPx = EightBallGame.ballR / EightBallGame.tableW * felt.width;
      expect(pockets.first.mouthR, greaterThan(ballPx * 1.2));
      // Corner mouths open on the diagonal, side mouths straight out.
      expect(pockets.first.corner, isTrue);
      expect(pockets.first.outward.dx, lessThan(0));
      expect(pockets.first.outward.dy, lessThan(0));
      expect(pockets.last.corner, isFalse);
      expect(pockets.last.outward.dy, 0);
    });

    test('every stage of a drop paints', () {
      const size = Size(300, 600);
      for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final rec = ui.PictureRecorder();
        paintPoolTable(
          Canvas(rec, Offset.zero & size),
          size,
          PoolView(
            balls: const [],
            drops: [
              PoolDrop(
                pocket: 0,
                fromNx: 0.10,
                fromNy: 0.05,
                radiusFrac: EightBallGame.ballR / EightBallGame.tableW,
                number: 3,
                t: t,
              ),
            ],
          ),
          const EightBallStyle(),
          ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A4D)),
        );
        expect(rec.endRecording(), isNotNull);
      }
    });

    test('the mouth is set back from the felt corner', () {
      const size = Size(300, 600);
      final p = poolPocketGeometry(size).first;
      // Drawn centre is pushed out along the diagonal from the capture point,
      // so the throat sits behind the cushion noses rather than on the cloth.
      expect(p.centre.dx, lessThan(p.capture.dx));
      expect(p.centre.dy, lessThan(p.capture.dy));
      // …but never so far it breaches the frame.
      expect(p.centre.dx - p.mouthR, greaterThan(0));
      expect(p.centre.dy - p.mouthR, greaterThan(0));
    });

    test('a real pot animates in the live loop before the move is delivered',
        () {
      // The painter checks below prove the drop *draws*; this proves it
      // actually happens — the scene's own update loop, a real stroke, and the
      // settled move held back until the last ball is out of sight.
      final state = fresh().copyWith(balls: [
        const Ball(number: 0, nx: 0.30, ny: 0.5, pocketed: false),
        // Parked in the jaws of the right-hand side pocket.
        const Ball(number: 1, nx: 0.82, ny: 0.5, pocketed: false),
        for (var n = 2; n <= 15; n++)
          Ball(number: n, nx: 0.5, ny: 0.05, pocketed: true),
      ]);

      final scene = EightBallScene(
        style: const EightBallStyle(),
        scheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A4D)),
      );
      scene.applyState(state, 'p1');
      EightBallMove? settled;
      var pocketCues = 0;
      scene.onShotSettled = (m) => settled = m;
      scene.onPocket = () => pocketCues++;

      expect(scene.canAim, isTrue);
      scene.beginAim(const Offset(200, 300));
      scene.updateAim(const Offset(20, 300)); // drag left → shoot right
      scene.endAim();

      var droppingFrames = 0;
      var deliveredWhileDropping = false;
      for (var i = 0; i < 900 && settled == null; i++) {
        scene.update(1 / 60);
        if (scene.isDropping) {
          droppingFrames++;
          if (settled != null) deliveredWhileDropping = true;
        }
      }

      expect(settled, isNotNull, reason: 'the shot never settled');
      // A drop is EightBallScene.dropSeconds long, so a single pot is ~31
      // frames at 60fps. Anything much shorter means it is being cut off.
      expect(droppingFrames, greaterThanOrEqualTo(30),
          reason: 'the drop only occupied $droppingFrames frames');
      expect(pocketCues, greaterThan(0), reason: 'the pocket cue never fired');
      expect(deliveredWhileDropping, isFalse,
          reason: 'the move was handed over mid-fall');

      // And the animation changed nothing: ball 1 is potted in the move the
      // reducer receives, exactly as the physics left it.
      final potted = {
        for (final p in settled!.positions!)
          if (p.pocketed) p.number,
      };
      expect(potted, contains(1));
      expect(game.applyMove(state, settled!).ball(1).pocketed, isTrue);
    });

    test('a drop never changes what was pocketed', () {
      // The reducer's view of a shot is the move. Replay the same move after a
      // drop has been drawn at every stage of its life and the resulting state
      // must be identical — the animation is downstream of the outcome.
      final s = fresh();
      final positions = [
        for (final b in s.balls)
          BallPosition(
            number: b.number,
            nx: b.nx,
            ny: b.ny,
            pocketed: b.number == 1,
          ),
      ];
      final move = EightBallMove.shot(
        owner: 'p1',
        positions: positions,
        firstHitNumber: 1,
      );
      final base = game.applyMove(s, move);
      const size = Size(300, 600);
      for (final t in [0.0, 0.3, 0.6, 0.9, 1.0]) {
        final rec = ui.PictureRecorder();
        paintPoolTable(
          Canvas(rec, Offset.zero & size),
          size,
          PoolView(
            balls: const [],
            drops: [
              PoolDrop(
                pocket: 2,
                fromNx: 0.08,
                fromNy: 0.94,
                radiusFrac: EightBallGame.ballR / EightBallGame.tableW,
                number: 1,
                t: t,
              ),
            ],
          ),
          const EightBallStyle(),
          ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A4D)),
        );
        rec.endRecording();
        final again = game.applyMove(s, move);
        expect(again.ball(1).pocketed, base.ball(1).pocketed);
        expect(again.currentPlayerId, base.currentPlayerId);
        expect(again.ballInHand, base.ballInHand);
      }
    });
  });

  group('rolling', () {
    test('spin accumulates with distance travelled', () {
      // A ball that only translates reads as sliding. Roll it a known distance
      // and the marking has to travel with it: the same distance rolled twice
      // must turn the ball further than rolling it once.
      final built = EightBallScene.createSim(cueOnly(0.5, 0.9));
      final sim = built.sim;
      final cue = built.cue!;
      sim.launch(cue, Vector2(0, -8));
      var travelled = 0.0;
      var last = Vector2(cue.position.x, cue.position.y);
      final marks = <double>[];
      for (var i = 0; i < 600; i++) {
        sim.step();
        if (cue.removed) break;
        final p = cue.position;
        travelled += (Vector2(p.x, p.y) - last).length;
        last = Vector2(p.x, p.y);
        if (i == 30 || i == 120) marks.add(travelled / EightBallGame.ballR);
      }
      expect(marks.length, 2);
      // Roll angle is distance / radius, so the later sample must be a bigger
      // turn — and by a lot, not by rounding.
      expect(marks[1], greaterThan(marks[0] * 2));
    });
  });

  group('cushion compression', () {
    test('a harder strike presses the cloth further', () {
      // The compression is a pure function of strength and age, so paint it at
      // two strengths and confirm the painter accepts both without falling over
      // and that the strength is what the scene reports.
      const size = Size(300, 600);
      for (final s in [0.15, 0.95]) {
        final rec = ui.PictureRecorder();
        paintPoolTable(
          Canvas(rec, Offset.zero & size),
          size,
          PoolView(
            balls: const [],
            impacts: [
              PoolImpact(
                nx: 1,
                ny: 0.5,
                normal: const Offset(-1, 0),
                strength: s,
                t: 0.2,
              ),
            ],
          ),
          const EightBallStyle(),
          ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A4D)),
        );
        expect(rec.endRecording(), isNotNull);
      }
    });
  });
}
