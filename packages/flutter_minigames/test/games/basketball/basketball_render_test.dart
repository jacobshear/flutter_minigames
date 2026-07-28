import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/basketball/basketball.dart';

/// The scene is a pure function of a [BasketballView], so it can be exercised
/// straight onto a canvas with no widget tree at all. These tests do not assert
/// on pixels — they assert the painter is total: it must not throw, and it must
/// place the pieces the depth cues depend on.
void main() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF007AFF));
  const style = BasketballStyle();

  void paint(BasketballView view, Size size) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    paintBasketballCourt(canvas, size, view, style, scheme);
    recorder.endRecording().dispose();
  }

  group('the painter is total', () {
    test('paints a ready court at any sane size', () {
      for (final size in const [
        Size(320, 480),
        Size(390, 620),
        Size(834, 500),
        Size(120, 120),
      ]) {
        paint(BasketballView.ready(), size);
      }
    });

    test('a degenerate size is a no-op, not a crash', () {
      paint(BasketballView.ready(), Size.zero);
      paint(BasketballView.ready(), const Size(0, 400));
    });

    test('paints a whole shot, frame by frame, without throwing', () {
      final sim = BasketballRoundSim(
        mode: BasketballHoopMode.normal,
        rng: math.Random(1),
      );
      sim.shoot(0);
      final step = BasketballCourt.throwConfig.fixedDt;
      for (var i = 0; i < 260; i++) {
        sim.advance(step);
        paint(
          BasketballView(
            hoopCentre: sim.hoopCentre,
            netWobble: sim.balls.fold(0.0, (a, b) => math.max(a, b.netWobble)),
            balls: [
              for (final b in sim.balls)
                BasketballBallView(
                  position: b.position,
                  spin: b.spin,
                  opacity: b.opacity,
                  ready: identical(b, sim.ready),
                ),
            ],
          ),
          const Size(390, 620),
        );
      }
    });

    test('paints a crowded court and a swung rig', () {
      final sim = BasketballRoundSim(
        mode: BasketballHoopMode.moving,
        rng: math.Random(2),
      );
      final step = BasketballCourt.throwConfig.fixedDt;
      for (var i = 0; i < 8; i++) {
        if (sim.ready != null) sim.shoot(i.isEven ? 0.3 : -0.6);
        for (var t = 0.0; t < 0.3; t += step) {
          sim.advance(step);
        }
      }
      expect(sim.balls.length, greaterThan(3));
      paint(
        BasketballView(
          hoopCentre: sim.hoopCentre,
          balls: [
            for (final b in sim.balls)
              BasketballBallView(position: b.position, spin: b.spin, opacity: b.opacity),
          ],
          trail: [for (final b in sim.live) b.position],
        ),
        const Size(390, 620),
      );
    });
  });

  group('the camera places the scene where the depth cues need it', () {
    const size = Size(390, 620);
    final camera = BasketballView.ready().cameraFor(size);

    test('the floor converges on a horizon inside the frame', () {
      expect(camera.horizonY, greaterThan(0));
      expect(camera.horizonY, lessThan(size.height));
    });

    test('the hoop sits in the upper part of the frame, backboard included', () {
      final rim = camera.project(
        BasketballCourt.hoopCentreAt(BasketballHoopMode.normal, 0),
      );
      expect(rim.visible, isTrue);
      expect(rim.screen.dy, inInclusiveRange(0, size.height * 0.45));

      final boardTop = camera.project(Vec3(
        0,
        BasketballCourt.backboardBottom + BasketballCourt.backboardHeight,
        BasketballCourt.backboardZ,
      ));
      expect(boardTop.visible, isTrue);
      expect(boardTop.screen.dy, greaterThan(0),
          reason: 'the backboard must not be cut off at the top');
    });

    test('the ball and its floor shadow are both in frame at rest', () {
      final ball = camera.project(BasketballCourt.spawnPoint);
      final shadow = camera.project(
        Vec3(0, 0, BasketballCourt.spawnPoint.z),
      );
      expect(ball.visible, isTrue);
      expect(shadow.visible, isTrue);
      expect(ball.screen.dy, lessThan(size.height));
      expect(shadow.screen.dy, lessThan(size.height),
          reason: 'a resting ball whose shadow is off-frame looks like it '
              'floats — the shadow is the height cue');
      expect(shadow.screen.dy, greaterThan(ball.screen.dy));
    });

    test('the whole arc stays in frame — you never lose the ball', () {
      final sim = BasketballRoundSim(
        mode: BasketballHoopMode.normal,
        rng: math.Random(3),
      );
      final ball = sim.shoot(0)!;
      final step = BasketballCourt.throwConfig.fixedDt;
      var highest = double.infinity;
      for (var i = 0; i < 150 && !ball.made; i++) {
        sim.advance(step);
        final p = camera.project(ball.position);
        if (p.visible && p.screen.dy < highest) highest = p.screen.dy;
      }
      expect(highest, greaterThan(0),
          reason: 'the apex clipped off the top of the frame');
    });

    test('a ball shrinks as it flies away — the primary depth cue', () {
      final near = camera.project(BasketballCourt.spawnPoint);
      final far = camera.project(
        Vec3(0, BasketballCourt.rimHeight, BasketballCourt.hoopZ),
      );
      final nearPx = BasketballCourt.ballRadius * near.scale * 2;
      final farPx = BasketballCourt.ballRadius * far.scale * 2;
      // Roughly halves between the spawn line and the rim — big enough at the
      // near end to read its lateral offset, small enough at the far end that
      // the recession is unmistakable.
      expect(nearPx, greaterThan(28), reason: 'near diameter ${nearPx}px');
      expect(farPx, lessThan(nearPx * 0.6), reason: 'far diameter ${farPx}px');
    });

    test('the rim projects to a depth-varying conic, never a fixed ellipse', () {
      Rect boundsAt(double z) {
        final path = camera.horizontalCirclePath(
          Vec3(0, BasketballCourt.rimHeight, z),
          BasketballCourt.rimRadius,
          segments: 40,
        );
        return path!.getBounds();
      }

      final near = boundsAt(BasketballCourt.hoopZ - 1.5);
      final far = boundsAt(BasketballCourt.hoopZ + 1.5);
      double aspect(Rect r) => r.height / r.width;
      // Same physical circle, different apparent squash: that variation IS the
      // depth cue, and it is exactly what a constant-aspect ellipse throws away.
      expect(aspect(near), isNot(closeTo(aspect(far), 0.02)),
          reason: 'near ${aspect(near)}, far ${aspect(far)}');
      expect(near.width, greaterThan(far.width));
    });
  });

  group('the board runs a live round', () {
    testWidgets('mounts, ticks, takes a flick and tears down cleanly', (
      tester,
    ) async {
      final submitted = <List<int>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: SizedBox(
              height: 700,
              child: BasketballRoundBoard(
                game: const BasketballGame(),
                playerLabel: 'P1',
                opponentLabel: 'P2',
                seed: 5,
                onComplete: submitted.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.textContaining('Round 1/2'), findsOneWidget);

      // A horizontal flick launches a ball; the sim then runs on the ticker.
      await tester.drag(
        find.byType(CustomPaint).first,
        const Offset(60, 0),
        warnIfMissed: false,
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.takeException(), isNull);
    });

    testWidgets('reports one score per round, exactly once', (tester) async {
      final submitted = <List<int>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: SizedBox(
              height: 700,
              child: BasketballRoundBoard(
                game: const BasketballGame(),
                playerLabel: 'P1',
                opponentLabel: 'P2',
                onComplete: submitted.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      for (var round = 0; round < BasketballGame.roundCount; round++) {
        await tester.tap(find.text('End round'));
        // Ticks are clamped to 0.1 s, so time is fed in slices.
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      expect(submitted.length, 1);
      expect(submitted.single.length, BasketballGame.roundCount);
      expect(submitted.single.every((s) => s >= 0), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.takeException(), isNull);
    });
  });

  group('chrome', () {
    testWidgets('the seven-segment scoreboard renders', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Material(
            child: Center(
              child: BasketballScoreboard(
                leftLabel: 'You',
                rightLabel: 'Them',
                leftScore: 7,
                rightScore: 12,
                secondsLeft: 45,
                leftAccent: Color(0xFFE8802B),
                rightAccent: Color(0xFF2E6FB0),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('YOU'), findsOneWidget);
      expect(find.text('THEM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the launcher tile animates and disposes cleanly', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 160,
              height: 160,
              child: BasketballTileArt(phase: 0.35),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  });
}
