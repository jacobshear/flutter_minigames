import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/engine3d/engine3d.dart';

/// Simulate a throw and report whether it dropped into the target disc.
bool lands({
  required Vec3 from,
  required Vec3 target,
  required double loft,
  required double speed,
  required double acceptRadius,
  double yaw = 0,
  ThrowConfig config = const ThrowConfig(),
}) {
  final horizontal = speed * math.cos(loft);
  final p = Projectile(
    position: from,
    velocity: Vec3(
      horizontal * math.sin(yaw),
      speed * math.sin(loft),
      horizontal * math.cos(yaw),
    ),
    config: config,
  );
  for (var i = 0; i < config.maxSteps; i++) {
    final before = p.step();
    if (Surfaces.passesDownThroughDisc(
        before, p.position, target, acceptRadius)) {
      return true;
    }
    if (p.position.y < target.y - 6) return false;
  }
  return false;
}

void main() {
  group('speedToHit', () {
    test('matches the closed-form ballistic identity', () {
      const z = 6.0, dy = 0.0, loft = 0.7, g = 22.0;
      final v = LaunchSolver.speedToHit(
        horizontalDistance: z,
        heightDelta: dy,
        loft: loft,
        gravity: g,
      );
      expect(v, isNotNull);
      // Substitute back: Δy should come out as given.
      final t = z / (v! * math.cos(loft));
      final y = v * math.sin(loft) * t - 0.5 * g * t * t;
      expect(y, closeTo(dy, 1e-9));
    });

    test('a higher target needs more speed', () {
      double solve(double dy) => LaunchSolver.speedToHit(
            horizontalDistance: 6,
            heightDelta: dy,
            loft: 0.8,
            gravity: 22,
          )!;
      expect(solve(1.5), greaterThan(solve(0.0)));
    });

    test('returns null when the target is above the straight-line reach', () {
      // At a shallow loft a high, near target simply cannot be reached.
      expect(
        LaunchSolver.speedToHit(
          horizontalDistance: 2,
          heightDelta: 5,
          loft: 0.2,
          gravity: 22,
        ),
        isNull,
      );
    });

    test('velocityToHit aims at the target as well as powering the throw', () {
      const from = Vec3(0, 1.2, 0);
      const target = Vec3(2, 1.2, 6);
      final v =
          LaunchSolver.velocityToHit(from: from, target: target, loft: 0.7)!;
      expect(v.x, greaterThan(0), reason: 'target is to the right');
      expect(v.z, greaterThan(0));
      // Lateral/depth split should match the direction to the target.
      expect(v.x / v.z, closeTo(2 / 6, 1e-9));
    });
  });

  group('drag refinement', () {
    test('the drag-free solve undershoots, and refining fixes it', () {
      const from = Vec3(0, 1.2, 0);
      const target = Vec3(0, 0.85, 5.0);
      const loft = 0.72;
      const accept = 0.09;

      final analytic = LaunchSolver.speedToHit(
        horizontalDistance: 5.0,
        heightDelta: target.y - from.y,
        loft: loft,
      )!;
      final refined = LaunchSolver.refineForDrag(
        from: from,
        target: target,
        loft: loft,
        analyticSpeed: analytic,
      );
      // Drag costs range, so the honest speed is a little higher.
      expect(refined, greaterThan(analytic));
      expect(refined / analytic, lessThan(1.3), reason: 'only a nudge');
      // And the refined speed actually lands it.
      expect(
        lands(
            from: from,
            target: target,
            loft: loft,
            speed: refined,
            acceptRadius: accept),
        isTrue,
      );
    });
  });

  group('playability', () {
    // The finding this guards: at true scale the make window is ~1% of the
    // input space, so a linear speed range can miss on every attempt. Banding
    // around the solved speed is what makes the game playable at all.
    //
    // Numbers below are measured, not guessed — this configuration (a front-row
    // cup at 2.4 m with a fattened acceptance radius) yields ~32% of flicks
    // scoring, which is a game of skill rather than luck.
    const from = Vec3(0, 1.2, 0);
    const target = Vec3(0, 0.85, 2.4);
    const loft = 0.72;
    // Acceptance radius is deliberately larger than the cup we *draw*: widening
    // it in physics only is the strongest playability lever there is.
    const accept = 0.12;

    double solvedSpeed() {
      final analytic = LaunchSolver.speedToHit(
        horizontalDistance: target.z - from.z,
        heightDelta: target.y - from.y,
        loft: loft,
      )!;
      return LaunchSolver.refineForDrag(
          from: from, target: target, loft: loft, analyticSpeed: analytic);
    }

    /// Fraction of evenly spaced flick powers that score.
    double makeRateBanded(double band) {
      final target0 = solvedSpeed();
      var made = 0;
      const n = 100;
      for (var i = 0; i < n; i++) {
        final speed = LaunchSolver.speedFromPower(
          targetSpeed: target0,
          power: i / (n - 1),
          band: band,
        );
        if (lands(
            from: from,
            target: target,
            loft: loft,
            speed: speed,
            acceptRadius: accept)) {
          made++;
        }
      }
      return made / n;
    }

    test('banding around the solved speed gives a wide, usable window', () {
      final rate = makeRateBanded(0.09);
      // A meaningful slice of the flick range should score — a medium flick is
      // roughly right and skill is fine modulation — but not so much that
      // every throw goes in.
      expect(rate, greaterThan(0.25),
          reason: 'banded window too tight to be fun: $rate');
      expect(rate, lessThan(0.90), reason: 'no skill left in it: $rate');
    });

    test('a naive wide absolute speed range is far worse', () {
      // Sweep an absolute range the way a naive implementation would.
      var made = 0;
      const n = 100;
      for (var i = 0; i < n; i++) {
        final speed = 4.5 + (14.0 - 4.5) * i / (n - 1);
        if (lands(
            from: from,
            target: target,
            loft: loft,
            speed: speed,
            acceptRadius: accept)) {
          made++;
        }
      }
      final naive = made / n;
      expect(naive, lessThan(makeRateBanded(0.09)),
          reason: 'banding must beat a naive absolute range (naive=$naive)');
    });

    test('a tighter band is harder than a looser one', () {
      expect(makeRateBanded(0.05), greaterThanOrEqualTo(makeRateBanded(0.20)));
    });

    test('further targets are naturally harder at the same band', () {
      double rateAt(double z) {
        final tgt = Vec3(0, 0.85, z);
        final analytic = LaunchSolver.speedToHit(
          horizontalDistance: z,
          heightDelta: tgt.y - from.y,
          loft: loft,
        )!;
        final t = LaunchSolver.refineForDrag(
            from: from, target: tgt, loft: loft, analyticSpeed: analytic);
        var made = 0;
        const n = 60;
        for (var i = 0; i < n; i++) {
          final speed = LaunchSolver.speedFromPower(
              targetSpeed: t, power: i / (n - 1), band: 0.09);
          if (lands(
              from: from,
              target: tgt,
              loft: loft,
              speed: speed,
              acceptRadius: accept)) {
            made++;
          }
        }
        return made / n;
      }

      // Back-row cups should be harder than front-row ones, for free — the
      // difficulty gradient falls out of the geometry with no special-casing.
      expect(rateAt(5.0), lessThan(rateAt(2.4)));
    });

    test('a fattened acceptance radius widens the window', () {
      double rateAt(double accept) {
        final t = solvedSpeed();
        var made = 0;
        const n = 60;
        for (var i = 0; i < n; i++) {
          final speed = LaunchSolver.speedFromPower(
              targetSpeed: t, power: i / (n - 1), band: 0.12);
          if (lands(
              from: from,
              target: target,
              loft: loft,
              speed: speed,
              acceptRadius: accept)) {
            made++;
          }
        }
        return made / n;
      }

      expect(rateAt(0.12), greaterThanOrEqualTo(rateAt(0.05)));
    });
  });

  group('Camera3 depth rendering', () {
    const viewport = Size(400, 700);
    final cam = Camera3(
      eye: const Vec3(0, 1.4, 0),
      viewport: viewport,
      pitch: 0.22,
    );

    test('the horizon sits above centre when pitched down', () {
      expect(cam.horizonY, lessThan(viewport.height / 2));
      // And a very distant floor point converges toward it.
      final far = cam.project(const Vec3(0, 0, 4000));
      expect(far.screen.dy, closeTo(cam.horizonY, 1.0));
    });

    test('a projected circle squashes more the further away it is', () {
      double aspect(double z) {
        final path = cam.horizontalCirclePath(Vec3(0, 0, z), 0.35)!;
        final b = path.getBounds();
        return b.height / b.width;
      }

      // The aspect must *change* with depth — a constant squash is exactly
      // what stops a scene reading as 3-D.
      final near = aspect(2.5);
      final far = aspect(7.0);
      expect(far, lessThan(near));
      expect(near, greaterThan(0));
    });

    test('a circle behind the camera yields no path', () {
      expect(cam.horizontalCirclePath(const Vec3(0, 0, -5), 0.3), isNull);
    });
  });

  group('Scene3 depth ordering', () {
    test('paints furthest first', () {
      final cam = Camera3(
        eye: const Vec3(0, 1.4, 0),
        viewport: const Size(400, 700),
        pitch: 0.2,
      );
      final scene = Scene3(cam)
        ..add(const Vec3(0, 0, 3), (_, __) {})
        ..add(const Vec3(0, 0, 9), (_, __) {})
        ..add(const Vec3(0, 0, 6), (_, __) {});
      final order = scene.sorted.map((e) => e.anchor.z).toList();
      expect(order, [9.0, 6.0, 3.0]);
    });

    test('drops items behind the camera', () {
      final cam = Camera3(
        eye: const Vec3(0, 1.4, 0),
        viewport: const Size(400, 700),
      );
      final scene = Scene3(cam)
        ..add(const Vec3(0, 0, 5), (_, __) {})
        ..add(const Vec3(0, 0, -5), (_, __) {});
      expect(scene.length, 2);
      expect(scene.sorted.length, 1);
    });
  });
}
