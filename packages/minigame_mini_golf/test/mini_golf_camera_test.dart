import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_mini_golf/minigame_mini_golf.dart';
import 'package:minigames_3d/minigames_3d.dart';

/// A phone-shaped board.
const _size = Size(420, 560);

MiniGolfCamera _aimAt(MiniGolfCourse c, Offset ball) => MiniGolfCamera.targetFor(
      viewport: _size,
      course: c,
      ball: ball,
      phase: MiniGolfCameraPhase.aim,
    );

MiniGolfCamera _flightAt(MiniGolfCourse c, Offset ball, Offset velocity) =>
    MiniGolfCamera.targetFor(
      viewport: _size,
      course: c,
      ball: ball,
      phase: MiniGolfCameraPhase.flight,
      velocity: velocity,
    );

/// A plain walled corridor, so camera assertions aren't at the mercy of a
/// generated layout.
MiniGolfCourse _straight({double length = 16, double halfWidth = 1.6}) =>
    MiniGolfCourse(
      archetype: MiniGolfArchetype.straightNarrowing,
      seed: 0,
      outline: [
        Offset(-halfWidth, 0),
        Offset(halfWidth, 0),
        Offset(halfWidth, length),
        Offset(-halfWidth, length),
      ],
      obstacles: const [],
      tee: const Offset(0, 1),
      cup: Offset(0, length - 1.2),
      routeLength: length - 2.2,
      minFairwayWidth: halfWidth * 2,
      par: 3,
    );

void main() {
  group('damping', () {
    test('is frame-rate independent to floating-point precision', () {
      // The test that separates exponential damping from a raw lerp: a raw
      // `lerp(x, target, k)` converges N times further in N small steps, so it
      // behaves differently at 60 fps and at 240 fps.
      for (final lambda in [2.0, 5.0, 9.0]) {
        final oneStep = MiniGolfCamera.damp(0, 1, lambda, 1.0);
        for (final n in [30, 60, 120, 240, 1000]) {
          var x = 0.0;
          for (var i = 0; i < n; i++) {
            x = MiniGolfCamera.damp(x, 1, lambda, 1.0 / n);
          }
          expect(x, closeTo(oneStep, 1e-9),
              reason: 'lambda $lambda at $n steps');
        }
        // …and it really is the analytic solution.
        expect(oneStep, closeTo(1 - math.exp(-lambda), 1e-12));
      }
    });

    test('the whole rig composes the same way', () {
      final c = _straight();
      final target = _aimAt(c, const Offset(0, 1));
      final start = _flightAt(c, const Offset(0, 8), const Offset(0, 7));

      // Deliberately not the aim phase: aim has a dead zone, which is a
      // *desirable* discontinuity and would mask what this test is checking.
      const phase = MiniGolfCameraPhase.settle;
      final oneStep = start.step(target, phase, 1.0);
      for (final n in [60, 240]) {
        var rig = start;
        for (var i = 0; i < n; i++) {
          rig = rig.step(target, phase, 1.0 / n);
        }
        expect(rig.focusX, closeTo(oneStep.focusX, 1e-6), reason: '$n steps');
        expect(rig.focusZ, closeTo(oneStep.focusZ, 1e-6), reason: '$n steps');
        expect(rig.back, closeTo(oneStep.back, 1e-6), reason: '$n steps');
        expect(rig.height, closeTo(oneStep.height, 1e-6), reason: '$n steps');
        expect(rig.frame, closeTo(oneStep.frame, 1e-6), reason: '$n steps');
      }
    });

    test('a zero or negative step is a no-op', () {
      final c = _straight();
      final rig = _aimAt(c, const Offset(0, 1));
      final target = _aimAt(c, const Offset(0, 9));
      expect(rig.step(target, MiniGolfCameraPhase.flight, 0).focusZ, rig.focusZ);
      expect(
          rig.step(target, MiniGolfCameraPhase.flight, -1).focusZ, rig.focusZ);
    });

    test('every phase converges rather than overshooting', () {
      final c = _straight();
      final target = _aimAt(c, const Offset(0, 2));
      for (final phase in MiniGolfCameraPhase.values) {
        var rig = _flightAt(c, const Offset(0, 12), const Offset(0, 7.5));
        var lastGap = double.infinity;
        for (var i = 0; i < 240; i++) {
          rig = rig.step(target, phase, 1 / 60);
          final gap = (rig.focusZ - target.focusZ).abs();
          expect(gap, lessThanOrEqualTo(lastGap + 1e-9), reason: phase.name);
          lastGap = gap;
        }
        // The aim phase parks inside its dead zone, so the tolerance has to
        // be at least that wide.
        expect(rig.settledOn(target, epsilon: 0.25), isTrue,
            reason: '${phase.name} never arrived');
      }
    });
  });

  group('purity', () {
    test('the same inputs always produce the same rig', () {
      final c = MiniGolfCourse.forHole(4, 2);
      for (final phase in MiniGolfCameraPhase.values) {
        final a = MiniGolfCamera.targetFor(
          viewport: _size,
          course: c,
          ball: const Offset(0.3, 4),
          phase: phase,
          velocity: const Offset(1, 3),
        );
        final b = MiniGolfCamera.targetFor(
          viewport: _size,
          course: c,
          ball: const Offset(0.3, 4),
          phase: phase,
          velocity: const Offset(1, 3),
        );
        expect(a.toString(), b.toString(), reason: phase.name);
      }
    });

    test('aim framing ignores velocity — the camera never reads the drag', () {
      final c = _straight();
      final still = MiniGolfCamera.targetFor(
        viewport: _size,
        course: c,
        ball: const Offset(0, 3),
        phase: MiniGolfCameraPhase.aim,
      );
      final moving = MiniGolfCamera.targetFor(
        viewport: _size,
        course: c,
        ball: const Offset(0, 3),
        phase: MiniGolfCameraPhase.aim,
        velocity: const Offset(4, 6),
      );
      expect(moving.toString(), still.toString());
    });
  });

  group('zoom', () {
    test('set-back and height rise monotonically with ball speed', () {
      final c = _straight(length: 24);
      var lastBack = 0.0;
      var lastHeight = 0.0;
      for (var i = 0; i <= 8; i++) {
        final speed = i.toDouble();
        final rig = _flightAt(c, const Offset(0, 8), Offset(0, speed));
        expect(rig.back, greaterThanOrEqualTo(lastBack - 1e-9),
            reason: 'speed $speed pulled in');
        expect(rig.height, greaterThanOrEqualTo(lastHeight - 1e-9),
            reason: 'speed $speed dropped');
        lastBack = rig.back;
        lastHeight = rig.height;
      }
      // And the spread is meaningful, not a rounding artefact.
      final slow = _flightAt(c, const Offset(0, 8), const Offset(0, 0.5));
      final fast = _flightAt(c, const Offset(0, 8), const Offset(0, 7.9));
      expect(fast.back, greaterThan(slow.back * 1.5));
    });

    test('the field of view is never touched', () {
      final c = _straight();
      final slow = _flightAt(c, const Offset(0, 4), const Offset(0, 1));
      final fast = _flightAt(c, const Offset(0, 4), const Offset(0, 7.9));
      expect(slow.toCamera(_size).fovY, MiniGolfWorld.fovY);
      expect(fast.toCamera(_size).fovY, MiniGolfWorld.fovY);
    });

    test('look-ahead leads the ball along its velocity', () {
      final c = _straight(length: 24);
      final still = _flightAt(c, const Offset(0, 6), const Offset(0, 0.2));
      final quick = _flightAt(c, const Offset(0, 6), const Offset(0, 7.0));
      expect(quick.focusZ - 6, greaterThan(still.focusZ - 6),
          reason: 'a fast ball should be looked ahead of, not at');
      // Lateral velocity steers the look-at sideways.
      final sideways = _flightAt(c, const Offset(0, 6), const Offset(5, 2));
      expect(sideways.focusX, greaterThan(0.4));
    });
  });

  group('limits', () {
    test('the minimum set-back holds with the ball hard against a rail', () {
      const halfWidth = 1.6;
      final c = _straight(halfWidth: halfWidth);
      const wall = halfWidth - MiniGolfCourse.ballRadius;
      for (final ball in [
        const Offset(wall, 2),
        const Offset(wall, 8),
        const Offset(-wall, 12),
      ]) {
        for (final phase in [
          MiniGolfCameraPhase.aim,
          MiniGolfCameraPhase.flight,
        ]) {
          final rig = MiniGolfCamera.targetFor(
            viewport: _size,
            course: c,
            ball: ball,
            phase: phase,
            velocity: const Offset(0, 0.4),
          );
          expect(rig.back, greaterThanOrEqualTo(MiniGolfCamera.minBack - 1e-9),
              reason: 'near-first-person degeneration at $ball / ${phase.name}');
        }
      }
    });

    test('the eye slides toward the open side of a rail-pinned ball', () {
      const halfWidth = 1.6;
      final c = _straight(halfWidth: halfWidth);
      const wall = halfWidth - MiniGolfCourse.ballRadius;
      // Ball on the right rail: the camera should step left, into the fairway.
      final right = _aimAt(c, const Offset(wall, 6));
      expect(right.focusX, lessThan(wall - 0.3));
      // …and mirrored on the left.
      final left = _aimAt(c, const Offset(-wall, 6));
      expect(left.focusX, greaterThan(-wall + 0.3));
      // A centred ball gets no bias at all.
      final middle = _aimAt(c, const Offset(0, 6));
      expect(middle.focusX.abs(), lessThan(0.05));
    });

    test('the camera never drops to the green or inverts', () {
      for (var base = 0; base < 4; base++) {
        for (var h = 0; h < 9; h++) {
          final c = MiniGolfCourse.forHole(base, h);
          for (final phase in MiniGolfCameraPhase.values) {
            for (final speed in [0.0, 3.0, 7.9]) {
              final rig = MiniGolfCamera.targetFor(
                viewport: _size,
                course: c,
                ball: c.tee,
                phase: phase,
                velocity: Offset(0, speed),
              );
              final cam = rig.toCamera(_size);
              expect(cam.eye.y, greaterThan(1.0),
                  reason: '${c.archetype.name} ${phase.name}');
              expect(cam.pitch, greaterThan(0.05));
              expect(cam.pitch, lessThan(math.pi / 2 - 0.05));
              expect(cam.eye.z, lessThan(c.tee.dy),
                  reason: 'camera got in front of the ball');
            }
          }
        }
      }
    });

    test('the dead zone ignores a trickling ball', () {
      final c = _straight();
      const ball = Offset(0, 6);
      final rig = _aimAt(c, ball);
      // A nudge smaller than the dead zone must not move the camera at all.
      final nudged = _aimAt(c, ball + const Offset(0.03, 0.05));
      final stepped = rig.step(nudged, MiniGolfCameraPhase.aim, 1 / 60);
      expect(identical(stepped, rig), isTrue);
      // A real move does.
      final moved = _aimAt(c, ball + const Offset(0, 1.5));
      final stepped2 = rig.step(moved, MiniGolfCameraPhase.aim, 1 / 60);
      expect(stepped2.focusZ, greaterThan(rig.focusZ));
      // The dead zone is aim-only: flight tracks every millimetre.
      final tracked = rig.step(nudged, MiniGolfCameraPhase.flight, 1 / 60);
      expect(identical(tracked, rig), isFalse);
    });
  });

  group('framing across a putt', () {
    /// Replays the board's camera machine over a recorded putt and reports the
    /// extreme screen positions the ball reached.
    ({double minX, double maxX, double minY, double maxY, double minBack})
        _replay(MiniGolfCourse course, PuttResult putt) {
      var rig = _aimAt(course, course.tee);
      var minX = double.infinity, maxX = -double.infinity;
      var minY = double.infinity, maxY = -double.infinity;
      var minBack = double.infinity;

      void observe(MiniGolfCamera r, Vec3 ball) {
        final cam = r.toCamera(_size);
        final p = cam.project(ball);
        expect(p.visible, isTrue, reason: 'ball fell behind the camera');
        minX = math.min(minX, p.screen.dx);
        maxX = math.max(maxX, p.screen.dx);
        minY = math.min(minY, p.screen.dy);
        maxY = math.max(maxY, p.screen.dy);
        minBack = math.min(minBack, r.back);
      }

      // Flight.
      for (var i = 0; i < putt.path.length; i++) {
        final s = putt.path[i];
        final j = math.min(i + 1, putt.path.length - 1);
        final n = putt.path[j].position;
        final velocity = Offset(
          (n.x - s.position.x) * PuttResult.sampleHz,
          (n.z - s.position.z) * PuttResult.sampleHz,
        );
        final ball = Offset(s.position.x, s.position.z);
        final target = MiniGolfCamera.targetFor(
          viewport: _size,
          course: course,
          ball: ball,
          phase: MiniGolfCameraPhase.flight,
          velocity: velocity,
        );
        rig = rig.step(target, MiniGolfCameraPhase.flight, 1 / 60);
        // A sunk ball drops below the green; frame its last rolling position.
        observe(rig, Vec3(s.position.x, math.max(0.0, s.position.y), s.position.z));
      }

      // Settle: half a second easing back to aim framing.
      final rest = putt.settled;
      final aim = _aimAt(course, rest);
      for (var i = 0; i < 36; i++) {
        rig = rig.step(aim, MiniGolfCameraPhase.settle, 1 / 60);
        observe(rig, Vec3(rest.dx, MiniGolfWorld.ballY, rest.dy));
      }
      return (
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        minBack: minBack
      );
    }

    test('the ball never leaves a safe screen box, on every archetype', () {
      for (final a in MiniGolfArchetype.values) {
        // Find a seed for this archetype and fire a hard putt down the hole.
        MiniGolfCourse? course;
        for (var s = 0; s < 400 && course == null; s++) {
          final c = MiniGolfCourse.forSeed(s);
          if (c.archetype == a) course = c;
        }
        expect(course, isNotNull, reason: a.name);
        final c = course!;

        for (final power in [0.45, 0.75, 1.0]) {
          final putt = MiniGolfPutt.simulate(
            course: c,
            from: c.tee,
            direction: const Offset(0.14, 0.99),
            power: power,
          );
          final r = _replay(c, putt);
          expect(r.minX, greaterThan(_size.width * 0.05),
              reason: '${a.name} @$power drifted off the left');
          expect(r.maxX, lessThan(_size.width * 0.95),
              reason: '${a.name} @$power drifted off the right');
          expect(r.minY, greaterThan(_size.height * 0.06),
              reason: '${a.name} @$power rode up into the sky');
          expect(r.maxY, lessThan(_size.height * 0.97),
              reason: '${a.name} @$power fell off the bottom');
          expect(r.minBack,
              greaterThanOrEqualTo(MiniGolfCamera.minBack - 1e-9),
              reason: '${a.name} @$power closed in too far');
        }
      }
    });

    test('settle returns to aim framing in about half a second', () {
      final c = _straight(length: 20);
      const rest = Offset(0.4, 9);
      final aim = _aimAt(c, rest);
      final start = _flightAt(c, rest, const Offset(0, 7.5));
      final gap0 = (start.back - aim.back).abs();
      expect(gap0, greaterThan(3), reason: 'need a real gap to close');

      double gapAfter(int frames) {
        var rig = start;
        for (var i = 0; i < frames; i++) {
          rig = rig.step(aim, MiniGolfCameraPhase.settle, 1 / 60);
        }
        return (rig.back - aim.back).abs() / gap0;
      }

      // Not a cut: an eighth of a second in it is still visibly on its way.
      expect(gapAfter(8), greaterThan(0.25),
          reason: 'the settle snapped instead of easing');
      // Most of the way by 0.4 s, effectively there by 0.6 s.
      expect(gapAfter(24), lessThan(0.10));
      expect(gapAfter(36), lessThan(0.03));
    });

    test('the preview sweep starts at the cup and ends at the tee', () {
      final c = MiniGolfCourse.forHole(2, 3);
      var rig = MiniGolfCamera.previewStart(viewport: _size, course: c);
      final aim = _aimAt(c, c.tee);
      expect(rig.focusZ, greaterThan(c.cup.dy - 3),
          reason: 'the reveal should open on the cup');

      var frames = 0;
      while (!rig.settledOn(aim, epsilon: 0.05) && frames < 600) {
        rig = rig.step(aim, MiniGolfCameraPhase.preview, 1 / 60);
        frames++;
      }
      expect(frames, lessThan(240), reason: 'the reveal outstays its welcome');
      expect(frames, greaterThan(30), reason: 'that was a cut, not a sweep');
      expect(rig.focusZ, closeTo(aim.focusZ, 0.1));
    });
  });

  group('aim interest', () {
    test('a clear line frames the cup itself when it is reachable', () {
      final c = _straight(length: 14);
      expect(MiniGolfCamera.aimInterest(c, const Offset(0, 7)), c.cup);
    });

    test('an unreachable cup is never framed — a putt cannot get there', () {
      // Framing a cup three putts away is what pulls the camera back until the
      // ball is a speck.
      final c = _straight(length: 26);
      for (final ball in [
        const Offset(0, 1),
        const Offset(0.6, 5),
        const Offset(-0.4, 9),
      ]) {
        final interest = MiniGolfCamera.aimInterest(c, ball);
        expect((interest - ball).distance,
            lessThanOrEqualTo(MiniGolfCourse.maxPuttReach + 0.5),
            reason: 'framed $interest from $ball');
      }
    });

    test('interest never runs beyond a putt on any generated hole', () {
      for (var base = 0; base < 4; base++) {
        for (var h = 0; h < 9; h++) {
          final c = MiniGolfCourse.forHole(base, h);
          final interest = MiniGolfCamera.aimInterest(c, c.tee);
          expect((interest - c.tee).distance,
              lessThanOrEqualTo(MiniGolfCourse.maxPuttReach + 0.5),
              reason: '${c.archetype.name} base $base hole $h');
        }
      }
    });

    test('a blocked line frames the bend instead of the cup', () {
      // A dogleg from the tee: the cup is around the corner, so the camera must
      // frame something reachable rather than a point through a wall.
      MiniGolfCourse? dogleg;
      for (var s = 0; s < 400 && dogleg == null; s++) {
        final c = MiniGolfCourse.forSeed(s);
        if (c.archetype == MiniGolfArchetype.doglegLeft) dogleg = c;
      }
      final c = dogleg!;
      final interest = MiniGolfCamera.aimInterest(c, c.tee);
      expect(interest, isNot(c.cup));
      // Whatever it picked has to be somewhere the ball could actually go.
      expect(c.containsWorld(interest), isTrue);
      expect((interest - c.tee).distance,
          lessThanOrEqualTo(MiniGolfCourse.maxPuttReach + 0.5));
    });
  });
}
