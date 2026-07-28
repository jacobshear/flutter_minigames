import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/basketball/basketball.dart';
import 'package:flutter_minigames/src/engine3d/engine3d.dart';

/// Headless physics + tuning. Every test here runs the same [BasketballRoundSim]
/// the widget runs, with no Flutter binding — which is the point: the make-rate
/// tests below are the regression guard against tuning drift. If someone nudges
/// `makeRadius`, the aim cone, gravity or the loft, these move and say so.
void main() {
  group('flight', () {
    test('a shot arcs — it rises, peaks, then falls through the rim plane', () {
      final sim = BasketballRoundSim(mode: BasketballHoopMode.normal, rng: math.Random(1));
      sim.ready = _ballAt(0);
      final ball = sim.shoot(0)!;

      var peak = ball.position.y;
      var peakStep = 0;
      var step = 0;
      var rising = true;
      var everFell = false;
      while (step++ < 400) {
        final before = ball.position.y;
        sim.advance(BasketballCourt.throwConfig.fixedDt);
        final after = ball.position.y;
        if (after > peak) {
          peak = after;
          peakStep = step;
        }
        if (rising && after < before) rising = false;
        if (!rising && after < before) everFell = true;
        if (ball.atRest) break;
      }

      expect(peak, greaterThan(BasketballCourt.rimHeight),
          reason: 'the ball must clear the rim on the way up');
      expect(peakStep, greaterThan(10), reason: 'it should not peak instantly');
      expect(everFell, isTrue, reason: 'and it must come back down');
      expect(ball.made, isTrue, reason: 'a dead-centre shot is a basket');
    });

    test('a ball rising through the rim is NOT a basket', () {
      final sim = BasketballRoundSim(mode: BasketballHoopMode.normal, rng: math.Random(2));
      // Drop a ball into the sim directly beneath the hoop, travelling upward
      // through the exact centre of the ring.
      final rising = LiveBall(
        id: 99,
        spawnX: 0,
        body: Projectile(
          position: Vec3(0, BasketballCourt.rimHeight - 0.6, BasketballCourt.hoopZ),
          velocity: const Vec3(0, 9, 0),
          config: BasketballCourt.throwConfig,
        ),
      )..launched = true;
      sim.live.add(rising);

      for (var i = 0; i < 40; i++) {
        sim.advance(BasketballCourt.throwConfig.fixedDt);
      }
      expect(rising.position.y, greaterThan(BasketballCourt.rimHeight),
          reason: 'it really did pass up through the ring');
      expect(rising.made, isFalse);
      expect(sim.makes, 0);
    });

    test('a fast shot cannot tunnel through the hoop between frames', () {
      final sim = BasketballRoundSim(mode: BasketballHoopMode.normal, rng: math.Random(3));
      // 40 m/s straight down covers 0.33 m per fixed step — nearly three ball
      // diameters, so a naive point-in-disc test would step clean past the ring
      // and score nothing.
      final bullet = LiveBall(
        id: 98,
        spawnX: 0,
        body: Projectile(
          position: Vec3(0, BasketballCourt.rimHeight + 0.30, BasketballCourt.hoopZ),
          velocity: const Vec3(0, -40, 0),
          config: BasketballCourt.throwConfig,
        ),
      )..launched = true;
      sim.live.add(bullet);

      final step = BasketballCourt.throwConfig.fixedDt;
      final travelPerStep = 40 * step;
      expect(travelPerStep, greaterThan(BasketballCourt.ballRadius * 2),
          reason: 'the step really is bigger than the ball');

      sim.advance(step);
      sim.advance(step);
      expect(bullet.made, isTrue);
      expect(sim.makes, 1);
    });

    test('a make is scored once, not once per frame inside the ring', () {
      final sim = BasketballRoundSim(mode: BasketballHoopMode.normal, rng: math.Random(4));
      sim.ready = _ballAt(0);
      final ball = sim.shoot(0)!;
      for (var i = 0; i < 400 && !ball.atRest; i++) {
        sim.advance(BasketballCourt.throwConfig.fixedDt);
      }
      expect(ball.made, isTrue);
      expect(sim.makes, 1);
    });
  });

  group('aiming', () {
    test('the launch solve is a single constant — power is not an input', () {
      final a = BasketballAim.solveSpeed(BasketballHoopMode.normal);
      final b = BasketballAim.solveSpeed(BasketballHoopMode.normal);
      expect(a, b);
      // Solved for very close to the true range; the small excess centres the
      // radial error across the spread of spawn offsets.
      expect(BasketballAim.solveRange(BasketballHoopMode.normal),
          closeTo(BasketballCourt.hoopDistance, 0.05));
      expect(BasketballAim.solveRange(BasketballHoopMode.moving),
          greaterThan(BasketballAim.solveRange(BasketballHoopMode.normal)));
    });

    test('a correctly-aimed shot scores from every spawn offset', () {
      for (final spawnX in const [-0.33, -0.2, -0.1, 0.0, 0.1, 0.2, 0.33]) {
        final aim = BasketballAim.leadAim(BasketballHoopMode.normal, spawnX, 0);
        final ball = simulateShot(
          mode: BasketballHoopMode.normal,
          aim: aim,
          spawnX: spawnX,
        );
        expect(ball.made, isTrue, reason: 'perfect line from spawnX=$spawnX');
      }
    });

    test('lateral aim error beyond the window misses', () {
      const spawnX = 0.0;
      final ideal = BasketballAim.leadAim(BasketballHoopMode.normal, spawnX, 0);
      for (final err in const [0.25, 0.4, 0.8, -0.25, -0.4, -0.8]) {
        final ball = simulateShot(
          mode: BasketballHoopMode.normal,
          aim: ideal + err,
          spawnX: spawnX,
        );
        expect(ball.made, isFalse, reason: 'aim error $err should miss');
      }
      // ...but a small error still drops (shooter's roll off the iron).
      for (final err in const [0.05, -0.05]) {
        final ball = simulateShot(
          mode: BasketballHoopMode.normal,
          aim: ideal + err,
          spawnX: spawnX,
        );
        expect(ball.made, isTrue, reason: 'aim error $err should still drop');
      }
    });

    test('the randomised spawn offset is what forces a re-aim each ball', () {
      // The line that scores from the left edge of the spawn spread must NOT
      // score from the right edge. Without that, a player could memorise one
      // drag and spam it — the whole skill of the game.
      final leftAim =
          BasketballAim.leadAim(BasketballHoopMode.normal, -0.33, 0);
      final rightAim =
          BasketballAim.leadAim(BasketballHoopMode.normal, 0.33, 0);
      expect((leftAim - rightAim).abs(), greaterThan(0.3),
          reason: 'the two ideal lines are far apart in drag units');

      expect(
        simulateShot(
          mode: BasketballHoopMode.normal,
          aim: leftAim,
          spawnX: -0.33,
        ).made,
        isTrue,
      );
      expect(
        simulateShot(
          mode: BasketballHoopMode.normal,
          aim: leftAim,
          spawnX: 0.33,
        ).made,
        isFalse,
        reason: 'the left ball line must not also score from the right ball',
      );
      expect(
        simulateShot(
          mode: BasketballHoopMode.normal,
          aim: rightAim,
          spawnX: -0.33,
        ).made,
        isFalse,
      );
    });

    test('the aim cone is the same in both modes (fixed drag mapping)', () {
      expect(
        BasketballAim.maxYaw(BasketballHoopMode.normal),
        BasketballAim.maxYaw(BasketballHoopMode.moving),
      );
      // Wide enough to reach the rig at full swing from the opposite spawn edge.
      final reach = math.atan(
        (BasketballHoopMode.moving.swing + BasketballCourt.spawnSpread) /
            BasketballCourt.hoopDistance,
      );
      expect(
        BasketballAim.maxYaw(BasketballHoopMode.moving),
        greaterThan(reach),
      );
    });

    test('drag maps horizontally only, with a dead zone', () {
      expect(BasketballAim.aimFromDrag(0, -180), isNotNull);
      expect(BasketballAim.aimFromDrag(0, -180), closeTo(0, 1e-9),
          reason: 'a purely vertical flick adds no steer');
      expect(BasketballAim.aimFromDrag(10, 8), isNull, reason: 'dead zone');
      expect(BasketballAim.aimFromDrag(200, 0), closeTo(1.0, 1e-9));
      expect(BasketballAim.aimFromDrag(-200, 0), closeTo(-1.0, 1e-9));
      expect(BasketballAim.aimFromDrag(-900, 0), closeTo(-1.0, 1e-9),
          reason: 'clamped');
      expect(BasketballAim.aimFromDrag(100, 0), closeTo(0.5, 1e-9));
    });
  });

  group('moving hoop', () {
    test('is a linear triangle wave, ±1 unit, 8 s, starting right', () {
      const mode = BasketballHoopMode.moving;
      expect(mode.period, 8.0);
      expect(mode.swing, 1.0);
      expect(mode.offsetAt(0), closeTo(0, 1e-9));
      expect(mode.offsetAt(2), closeTo(1.0, 1e-9));
      expect(mode.offsetAt(4), closeTo(0, 1e-9));
      expect(mode.offsetAt(6), closeTo(-1.0, 1e-9));
      expect(mode.offsetAt(8), closeTo(0, 1e-9));
      // Constant speed, no easing: equal time slices move equal distances.
      for (var i = 0; i < 7; i++) {
        final a = mode.offsetAt(i * 0.25);
        final b = mode.offsetAt((i + 1) * 0.25);
        expect((b - a).abs(), closeTo(0.125, 1e-9));
      }
      expect(BasketballHoopMode.normal.offsetAt(3.7), 0);
    });

    test('the rig slides laterally only — never nearer or further', () {
      for (final t in const [0.0, 1.3, 3.9, 7.7]) {
        final c = BasketballCourt.hoopCentreAt(BasketballHoopMode.moving, t);
        expect(c.z, BasketballCourt.hoopZ);
        expect(c.y, BasketballCourt.rimHeight);
      }
    });

    test('a shot must be led — the un-led line misses', () {
      // At t = 0 the rig is dead centre and moving; aiming straight at where it
      // is now puts the ball where it was.
      expect(
        simulateShot(mode: BasketballHoopMode.moving, aim: 0, spawnX: 0).made,
        isFalse,
      );
      expect(
        simulateShot(
          mode: BasketballHoopMode.moving,
          aim: BasketballAim.leadAim(BasketballHoopMode.moving, 0, 0),
          spawnX: 0,
        ).made,
        isTrue,
      );
    });
  });

  group('a made shot knows how it went in', () {
    test('a dead-centre shot is a swish and touches nothing', () {
      final ball = simulateShot(mode: BasketballHoopMode.normal, aim: 0);
      expect(ball.made, isTrue);
      expect(ball.touchedIron, isFalse);
      expect(ball.swish, isTrue);
    });

    test('a shot at the edge of the window rattles in', () {
      // Inside the make window but far enough off-line to catch iron first.
      // This is the shot the presentation has to tell apart from a swish.
      final ball = simulateShot(mode: BasketballHoopMode.normal, aim: -0.085);
      expect(ball.made, isTrue, reason: 'still a basket');
      expect(ball.touchedIron, isTrue, reason: 'but it went in off the ring');
      expect(ball.swish, isFalse);
    });

    test('a rattle-in whips the net less than a swish does', () {
      final swish = simulateShot(mode: BasketballHoopMode.normal, aim: 0);
      final rattle = simulateShot(mode: BasketballHoopMode.normal, aim: -0.085);
      expect(swish.made && rattle.made, isTrue);
      // Both are captured at rest, so compare what the sim set at the moment of
      // the make rather than the decayed value: re-run to the make itself.
      // Built exactly as simulateShot does — the ready ball's lateral offset is
      // randomised, and a rattle aim only rattles from the offset it was
      // measured at.
      double wobbleAtMake(double aim) {
        final sim = BasketballRoundSim(
          mode: BasketballHoopMode.normal,
          rng: math.Random(1),
        );
        sim.ready = LiveBall(
          id: -1,
          spawnX: 0,
          body: Projectile(
            position: BasketballCourt.spawnPoint,
            velocity: Vec3.zero,
            config: BasketballCourt.throwConfig,
          ),
        );
        final b = sim.shoot(aim)!;
        for (var i = 0; i < 600; i++) {
          sim.advance(BasketballCourt.throwConfig.fixedDt);
          if (b.made) return b.netWobble;
        }
        return 0;
      }

      expect(wobbleAtMake(0), greaterThan(wobbleAtMake(-0.085)),
          reason: 'a clean drop hits the cords at full pace');
    });

    test('the net settles again — the wobble is a ring, not a latch', () {
      final sim = BasketballRoundSim(
        mode: BasketballHoopMode.normal,
        rng: math.Random(1),
      );
      sim.ready = LiveBall(
        id: -1,
        spawnX: 0,
        body: Projectile(
          position: BasketballCourt.spawnPoint,
          velocity: Vec3.zero,
          config: BasketballCourt.throwConfig,
        ),
      );
      final ball = sim.shoot(0)!;
      var peak = 0.0;
      for (var i = 0; i < 600; i++) {
        sim.advance(BasketballCourt.throwConfig.fixedDt);
        if (ball.netWobble > peak) peak = ball.netWobble;
        if (ball.made && ball.netWobble == 0) break;
      }
      expect(peak, greaterThan(0.9));
      expect(ball.netWobble, 0, reason: 'it has to relax back');
    });

    test('spin accumulates with distance travelled', () {
      final sim = BasketballRoundSim(
        mode: BasketballHoopMode.normal,
        rng: math.Random(1),
      );
      final ball = sim.shoot(0)!;
      // A ball waiting on the line is given a random idle spin, so absolute
      // spin is not monotonic — what has to grow is how far it has turned
      // *since launch*.
      final launchSpin = ball.spin;
      final samples = <double>[];
      var lastZ = ball.position.z;
      for (var i = 0; i < 200 && !ball.made; i++) {
        sim.advance(BasketballCourt.throwConfig.fixedDt);
        if (ball.position.z > lastZ + 0.25) {
          samples.add((ball.spin - launchSpin).abs());
          lastZ = ball.position.z;
        }
      }
      expect(samples.length, greaterThan(4),
          reason: 'the ball has to cover ground');
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i], greaterThan(samples[i - 1]),
            reason: 'a ball in flight keeps turning');
      }
    });
  });

  group('cadence', () {
    test('balls respawn on a 250 ms cooldown and several fly at once', () {
      final sim = BasketballRoundSim(
        mode: BasketballHoopMode.normal,
        rng: math.Random(11),
      );
      expect(sim.ready, isNotNull, reason: 'a ball is waiting immediately');
      sim.shoot(0);
      expect(sim.ready, isNull, reason: 'and is gone once thrown');

      sim.advance(0.20);
      expect(sim.ready, isNull, reason: 'still cooling down at 200 ms');
      sim.advance(0.08);
      expect(sim.ready, isNotNull, reason: 'back by 280 ms');

      // Four in a second, all still airborne together.
      var fired = 1;
      for (var i = 0; i < 3; i++) {
        sim.shoot(0.4);
        fired++;
        sim.advance(0.26);
      }
      expect(fired, 4);
      expect(sim.live.where((b) => !b.atRest).length, greaterThanOrEqualTo(3));
    });

    test('missed balls persist, bounce and roll rather than vanishing', () {
      final sim = BasketballRoundSim(
        mode: BasketballHoopMode.normal,
        rng: math.Random(12),
      );
      sim.ready = _ballAt(0);
      final ball = sim.shoot(-1)!; // hard miss, wide left
      // Land it, then keep watching: it must still be there, bouncing.
      _run(sim, 1.7);
      expect(ball.made, isFalse);
      expect(ball.position.y, lessThan(BasketballCourt.rimHeight),
          reason: 'it has come down');
      expect(sim.live, contains(ball), reason: 'and is still on the court');
      expect(ball.opacity, 1.0, reason: 'fully visible, not fading yet');
      expect(ball.atRest, isFalse, reason: 'still bouncing/rolling');

      // It rolls to a stop and only then fades out.
      for (var i = 0; i < 1200 && !ball.atRest; i++) {
        sim.advance(BasketballCourt.throwConfig.fixedDt);
      }
      expect(ball.atRest, isTrue);
      _run(sim, LiveBall.lingerSeconds + LiveBall.fadeSeconds + 0.2);
      expect(sim.live, isNot(contains(ball)));
    });

    test('the clock stops shots and the round is not open forever', () {
      final sim = BasketballRoundSim(
        mode: BasketballHoopMode.normal,
        rng: math.Random(13),
        duration: 1.0,
      );
      expect(sim.expired, isFalse);
      _run(sim, 1.2);
      expect(sim.expired, isTrue);
      expect(sim.remaining, 0);
      expect(sim.shoot(0), isNull, reason: 'no shooting after the buzzer');
    });

    test('physics is fixed-step: one big advance equals many small ones', () {
      LiveBall run(double chunk, int chunks) {
        final sim = BasketballRoundSim(
          mode: BasketballHoopMode.normal,
          rng: math.Random(14),
        );
        sim.ready = _ballAt(0.1);
        final b = sim.shoot(0.2)!;
        for (var i = 0; i < chunks; i++) {
          sim.advance(chunk);
        }
        return b;
      }

      final a = run(BasketballCourt.throwConfig.fixedDt, 60);
      final b = run(BasketballCourt.throwConfig.fixedDt * 6, 10);
      expect(a.position.x, closeTo(b.position.x, 1e-9));
      expect(a.position.y, closeTo(b.position.y, 1e-9));
      expect(a.position.z, closeTo(b.position.z, 1e-9));
    });
  });

  group('make rate (tuning regression guard)', () {
    // A "competent player" aims the ideal line and misses it by a bit. This is
    // the number that actually says whether the game is playable; the uniform
    // sweep below says whether the geometry has drifted.
    double competentRate(BasketballHoopMode mode, double sigma, int trials) {
      final rng = math.Random(2024);
      var made = 0;
      for (var i = 0; i < trials; i++) {
        final time = rng.nextDouble() * mode.period;
        final spawnX =
            (rng.nextDouble() * 2 - 1) * BasketballCourt.spawnSpread;
        final ideal = BasketballAim.leadAim(mode, spawnX, time);
        final noise = _gaussian(rng) * sigma;
        final ball = simulateShot(
          mode: mode,
          aim: (ideal + noise).clamp(-1.0, 1.0),
          spawnX: spawnX,
          atTime: time,
        );
        if (ball.made) made++;
      }
      return made / trials;
    }

    double uniformRate(BasketballHoopMode mode, int trials) {
      final rng = math.Random(99);
      var made = 0;
      for (var i = 0; i < trials; i++) {
        final ball = simulateShot(
          mode: mode,
          aim: rng.nextDouble() * 2 - 1,
          spawnX: (rng.nextDouble() * 2 - 1) * BasketballCourt.spawnSpread,
          atTime: rng.nextDouble() * mode.period,
        );
        if (ball.made) made++;
      }
      return made / trials;
    }

    test('a careful player makes most shots in a normal match', () {
      final rate = competentRate(BasketballHoopMode.normal, 0.06, 300);
      expect(rate, greaterThan(0.80), reason: 'measured $rate');
      expect(rate, lessThanOrEqualTo(1.0));
    });

    test('a hurried player still scores, but pays for the rush', () {
      final rate = competentRate(BasketballHoopMode.normal, 0.16, 300);
      expect(rate, inInclusiveRange(0.40, 0.85), reason: 'measured $rate');
    });

    test('a moving rig is harder than a static one at the same aim precision',
        () {
      const sigma = 0.16;
      final normal = competentRate(BasketballHoopMode.normal, sigma, 300);
      final moving = competentRate(BasketballHoopMode.moving, sigma, 300);
      expect(moving, lessThan(normal),
          reason: 'normal $normal vs moving $moving');
      expect(moving, inInclusiveRange(0.25, 0.75), reason: 'measured $moving');
    });

    test('random drags do not score — the window is a sliver of the input', () {
      final normal = uniformRate(BasketballHoopMode.normal, 400);
      final moving = uniformRate(BasketballHoopMode.moving, 400);
      // ~13% of the drag range scores. Much higher and the game plays itself;
      // much lower and it is unlearnable.
      expect(normal, inInclusiveRange(0.08, 0.20), reason: 'measured $normal');
      expect(moving, inInclusiveRange(0.06, 0.18), reason: 'measured $moving');
    });
  });
}

/// Advance a sim by [seconds] of round time. `advance` deliberately clamps a
/// single call (frame-spike protection), so bulk time has to be fed in slices.
void _run(BasketballRoundSim sim, double seconds) {
  final step = BasketballCourt.throwConfig.fixedDt;
  for (var t = 0.0; t < seconds; t += step) {
    sim.advance(step);
  }
}

LiveBall _ballAt(double spawnX) => LiveBall(
      id: 0,
      spawnX: spawnX,
      body: Projectile(
        position: Vec3(
          spawnX,
          BasketballCourt.spawnPoint.y,
          BasketballCourt.spawnZ,
        ),
        velocity: Vec3.zero,
        config: BasketballCourt.throwConfig,
      ),
    );

/// Box-Muller, so "competent" means normally distributed aim error rather than
/// a uniform smear.
double _gaussian(math.Random rng) {
  final u = 1 - rng.nextDouble();
  final v = rng.nextDouble();
  return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
}
