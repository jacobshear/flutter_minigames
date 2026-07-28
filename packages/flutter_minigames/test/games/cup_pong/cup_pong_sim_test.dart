import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/cup_pong/cup_pong.dart';
import 'package:flutter_minigames/src/engine3d/engine3d.dart';

/// A launch velocity from a speed, a fixed loft and a yaw — the same
/// decomposition [CupPongAim.solve] uses, without the swipe.
Vec3 launch(double speed, double loft, double yaw) => Vec3(
      speed * math.cos(loft) * math.sin(yaw),
      speed * math.sin(loft),
      speed * math.cos(loft) * math.cos(yaw),
    );

List<CupPongCup> fullRack() =>
    CupPongGame.rackFor([for (var i = 0; i < 10; i++) i]);

/// Fraction of evenly sampled flick powers that score, throwing straight at
/// [target] with the shipped tuning.
double makeRate(
  List<CupPongCup> rack,
  CupPongCup target, {
  CupPongTuning tuning = const CupPongTuning(),
  int samples = 121,
}) {
  final aim = CupPongAim(tuning: tuning);
  final yaw = CupPongAim.yawTo(CupPongWorld.mouthOf(target));
  final solved = aim.solvedSpeedFor(target);
  var made = 0;
  for (var i = 0; i < samples; i++) {
    final speed = LaunchSolver.speedFromPower(
      targetSpeed: solved,
      power: i / (samples - 1),
      band: tuning.speedBand,
    );
    final sim = CupPongThrowSim(
      cups: rack,
      velocity: launch(speed, tuning.loft, yaw),
      tuning: tuning,
    );
    if (sim.run() == CupPongEvent.made) made++;
  }
  return made / samples;
}

void main() {
  const tuning = CupPongTuning();

  group('ballistics', () {
    test('the ball arcs: it rises, falls, and travels down-range', () {
      final aim = CupPongAim(tuning: tuning);
      final apex = fullRack().first;
      final v = launch(
        aim.solvedSpeedFor(apex),
        tuning.loft,
        CupPongAim.yawTo(CupPongWorld.mouthOf(apex)),
      );
      final sim = CupPongThrowSim(cups: const [], velocity: v, tuning: tuning);

      var peak = CupPongWorld.launchPoint.y;
      var peakAtStep = 0;
      final zs = <double>[];
      var step = 0;
      while (!sim.finished && step < 400) {
        sim.step();
        step++;
        zs.add(sim.position.z);
        if (sim.position.y > peak) {
          peak = sim.position.y;
          peakAtStep = step;
        }
      }

      // Rose meaningfully above the hand, then came back down.
      expect(peak, greaterThan(CupPongWorld.launchPoint.y + 0.05));
      expect(peakAtStep, greaterThan(0));
      expect(peakAtStep, lessThan(step));
      // Monotonically down-range: a first-person throw never comes back at you.
      for (var i = 1; i < zs.length; i++) {
        expect(zs[i], greaterThanOrEqualTo(zs[i - 1] - 1e-9));
      }
      expect(zs.last, greaterThan(CupPongWorld.rackApexZ * 0.5));
    });

    test('the solved speed drops the ball into the cup it solved for', () {
      final rack = fullRack();
      final aim = CupPongAim(tuning: tuning);
      for (final cup in rack) {
        final mouth = CupPongWorld.mouthOf(cup);
        final sim = CupPongThrowSim(
          // Only this cup exists, so a make can only be this cup.
          cups: [cup],
          velocity: launch(
            aim.solvedSpeedFor(cup),
            tuning.loft,
            CupPongAim.yawTo(mouth),
          ),
          tuning: tuning,
        );
        expect(sim.run(), CupPongEvent.made, reason: 'cup ${cup.id}');
        expect(sim.hitCupId, cup.id);
      }
    });

    test('the simulation is deterministic', () {
      final rack = fullRack();
      final v = launch(2.4, tuning.loft, 0.01);
      List<double> trace() {
        final sim = CupPongThrowSim(
          cups: rack,
          velocity: v,
          tuning: tuning,
        );
        final out = <double>[];
        while (!sim.finished) {
          sim.step();
          out.add(sim.position.z);
        }
        return out;
      }

      expect(trace(), trace());
    });

    test('a badly under-powered throw lands short and misses', () {
      final rack = fullRack();
      final aim = CupPongAim(tuning: tuning);
      final sim = CupPongThrowSim(
        cups: rack,
        velocity: launch(aim.solvedSpeedFor(rack.first) * 0.55, tuning.loft, 0),
        tuning: tuning,
      );
      expect(sim.run(), CupPongEvent.missed);
      expect(sim.position.z, lessThan(CupPongWorld.rackApexZ));
    });

    test('the scoring radius is fatter than the drawn mouth', () {
      // Rule 2 of the tuning: draw true, score generous. A ball whose descent
      // crosses the mouth plane outside the painted rim still drops.
      expect(
        tuning.acceptanceRadius,
        greaterThan(CupPongWorld.cupMouthRadius * 1.2),
      );
      expect(
        tuning.acceptanceRadius,
        lessThan(CupPongWorld.cupMouthRadius * 2.1),
      );

      final cup = fullRack().first;
      final mouth = CupPongWorld.mouthOf(cup);
      final offset =
          (CupPongWorld.cupMouthRadius + tuning.acceptanceRadius) / 2;
      final sim = CupPongThrowSim(
        cups: [cup],
        velocity: Vec3.zero,
        tuning: tuning,
      )
        // Park the ball just above the mouth plane, outside the painted rim but
        // inside the acceptance radius, and let it fall.
        ..ball.position = Vec3(mouth.x + offset, mouth.y + 0.03, mouth.z)
        ..ball.velocity = const Vec3(0, -0.5, 0);
      expect(sim.run(), CupPongEvent.made);
    });
  });

  group('aim solver', () {
    test('a straight-up flick targets the apex; steering picks another cup',
        () {
      final rack = fullRack();
      final aim = CupPongAim(tuning: tuning);
      final straight = aim.solve(cups: rack, dx: 0, dy: -120);
      expect(straight, isNotNull);
      expect(straight!.target.id, 0, reason: 'apex is on the centre line');

      final right = aim.solve(cups: rack, dx: 90, dy: -120);
      expect(right, isNotNull);
      expect(right!.target.x, greaterThan(0));
      final left = aim.solve(cups: rack, dx: -90, dy: -120);
      expect(left!.target.x, lessThan(0));
    });

    test('sweeping the swipe angle walks the target across the rack', () {
      // Direction is the whole aiming axis now that there is no cursor to
      // place, so it has to be monotone: leaning further right may only ever
      // select a cup at or right of the last one, never jump back.
      final rack = fullRack();
      final aim = CupPongAim(tuning: tuning);
      var previous = double.negativeInfinity;
      final seen = <double>{};
      for (var dx = -400.0; dx <= 400.0; dx += 10) {
        final s = aim.solve(cups: rack, dx: dx, dy: -140)!;
        expect(s.target.x, greaterThanOrEqualTo(previous),
            reason: 'dx = $dx went backwards');
        previous = s.target.x;
        seen.add(s.target.x);
      }
      expect(seen.length, greaterThanOrEqualTo(3),
          reason: 'a sweep has to reach more than one column');
    });

    test('a downward or tiny swipe does not throw', () {
      final rack = fullRack();
      final aim = CupPongAim(tuning: tuning);
      expect(aim.solve(cups: rack, dx: 0, dy: 120), isNull);
      expect(aim.solve(cups: rack, dx: 2, dy: -3), isNull);
      expect(aim.solve(cups: const [], dx: 0, dy: -120), isNull);
    });

    test('power bands the speed around the solved value, never replaces it',
        () {
      final rack = fullRack();
      final aim = CupPongAim(tuning: tuning);
      final soft = aim.solve(cups: rack, dx: 0, dy: -40)!;
      final hard = aim.solve(cups: rack, dx: 0, dy: -400)!;
      expect(hard.power, greaterThan(soft.power));
      expect(hard.velocity.length, greaterThan(soft.velocity.length));
      for (final s in [soft, hard]) {
        expect(
          s.velocity.length,
          closeTo(s.solvedSpeed, s.solvedSpeed * tuning.speedBand + 1e-6),
        );
      }
    });

    test('lateral deviation from the targeted cup stays inside the cap', () {
      final rack = fullRack();
      final aim = CupPongAim(tuning: tuning);
      for (final dx in [-260.0, -60.0, 0.0, 60.0, 260.0]) {
        final s = aim.solve(cups: rack, dx: dx, dy: -140)!;
        final launchYaw = math.atan2(s.velocity.x, s.velocity.z);
        final toTarget = CupPongAim.yawTo(s.targetMouth);
        expect(
          (launchYaw - toTarget).abs(),
          lessThanOrEqualTo(tuning.residualYaw + 1e-9),
        );
      }
    });

    test('the aim ray can reach the outermost back-row cup', () {
      final rack = fullRack();
      final aim = CupPongAim(tuning: tuning);
      final widest = rack.reduce((a, b) => a.x.abs() > b.x.abs() ? a : b);
      final reached = aim.solve(cups: rack, dx: 400, dy: -140)!;
      expect(reached.target.x.abs(), closeTo(widest.x.abs(), 1e-9));
    });
  });

  group('a miss behaves like a ping-pong ball', () {
    /// A deliberately soft throw: it lands on the felt well short of the rack,
    /// which is the case the player sees most often.
    CupPongThrowSim shortThrow() {
      final aim = CupPongAim(tuning: tuning);
      final apex = fullRack().first;
      return CupPongThrowSim(
        cups: fullRack(),
        velocity: launch(
          aim.solvedSpeedFor(apex) * 0.72,
          tuning.loft,
          CupPongAim.yawTo(CupPongWorld.mouthOf(apex)),
        ),
        tuning: tuning,
      );
    }

    test('it bounces, rolls on after landing, and comes to rest', () {
      final sim = shortThrow();
      double? touchdownZ;
      var bounces = 0;
      var steps = 0;
      while (!sim.finished && steps++ < 20000) {
        final e = sim.step();
        if (e == CupPongEvent.tableBounce) {
          bounces++;
          touchdownZ ??= sim.position.z;
        }
      }
      expect(sim.finished, isTrue);
      expect(bounces, greaterThan(0), reason: 'it has to arrive with weight');
      expect(touchdownZ, isNotNull);
      // The regression this guards: the old table branch bounced every grounded
      // step and scrubbed friction on each one, so the ball stopped within a
      // few frames of landing. It must now carry.
      expect(sim.position.z - touchdownZ!, greaterThan(0.05),
          reason: 'a ball that stops dead where it lands is the bug');
    });

    test('a ball that settles on the felt reports itself at rest', () {
      final sim = shortThrow();
      expect(sim.run(), CupPongEvent.missed);
      expect(sim.atRest, isTrue,
          reason: 'it stopped on the table, so the board may leave it lying');
      expect(sim.position.y, closeTo(CupPongWorld.ballRadius, 1e-6));
      expect(
          sim.position.z,
          inInclusiveRange(
            CupPongWorld.nearZ,
            CupPongWorld.farZ,
          ));
    });

    test('a ball that leaves the table is NOT reported at rest', () {
      // Thrown far too hard: it clears the rack and goes over the far edge.
      final aim = CupPongAim(tuning: tuning);
      final apex = fullRack().first;
      final sim = CupPongThrowSim(
        cups: const [],
        velocity: launch(
          aim.solvedSpeedFor(apex) * 2.2,
          tuning.loft,
          CupPongAim.yawTo(CupPongWorld.mouthOf(apex)),
        ),
        tuning: tuning,
      );
      expect(sim.run(), CupPongEvent.missed);
      expect(sim.atRest, isFalse,
          reason: 'nothing should be left lying out past the rail');
    });

    test('spin accumulates with travel, in flight and on the roll', () {
      final sim = shortThrow();
      final samples = <double>[];
      var lastZ = sim.position.z;
      var rolledSpin = 0.0;
      var rolledDistance = 0.0;
      while (!sim.finished) {
        final beforeSpin = sim.spin;
        final rolling = sim.rolling;
        sim.step();
        if (samples.length < 40 && sim.position.z > lastZ + 0.02) {
          samples.add(sim.spin);
          lastZ = sim.position.z;
        }
        if (rolling) {
          rolledSpin += (sim.spin - beforeSpin).abs();
          rolledDistance += (sim.position.z - lastZ).abs();
        }
      }
      expect(samples.length, greaterThan(3));
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i], greaterThan(samples[i - 1]),
            reason: 'the ball must keep turning as it travels');
      }
      expect(rolledSpin, greaterThan(0),
          reason: 'a rolling ball turns at v/r, it does not slide');
      expect(rolledDistance, greaterThanOrEqualTo(0));
    });
  });

  group('make rate (regression guard for the tuning)', () {
    // These numbers are the whole reason CupPongAim exists. A naive absolute
    // speed range scores essentially never; the solved-speed band plus the
    // fattened acceptance radius put a near cup in the "skill, not luck" zone.
    // If a tuning change moves these outside the asserted band, that is a
    // playability regression, not a flaky test.
    test('a near cup is makeable but not automatic', () {
      final rack = fullRack();
      final rate = makeRate(rack, rack.first);
      expect(rate, greaterThan(0.20), reason: 'measured ~0.62');
      expect(rate, lessThan(0.90), reason: 'measured ~0.62');
    });

    test('the deepest, widest cup is markedly harder than the apex', () {
      final rack = fullRack();
      final near = makeRate(rack, rack.first);
      // Back row, outermost column: nothing in front of it to catch a short
      // throw, and the fixed ± speed band is a tighter absolute window further
      // out. Both effects push the same way.
      final far = makeRate(rack, rack.last);
      expect(far, lessThan(near));
      expect(far, lessThan(near - 0.15), reason: 'measured ~0.32 vs ~0.62');
      expect(far, greaterThan(0.05), reason: 'still winnable');
    });

    test('widening the band makes the game harder, monotonically', () {
      final rack = fullRack();
      final tight = makeRate(
        rack,
        rack.first,
        tuning: tuning.copyWith(speedBand: 0.12),
        samples: 61,
      );
      final wide = makeRate(
        rack,
        rack.first,
        tuning: tuning.copyWith(speedBand: 0.40),
        samples: 61,
      );
      expect(wide, lessThan(tight));
    });

    test('shrinking the acceptance radius makes the game harder', () {
      final rack = fullRack();
      final fat = makeRate(rack, rack.last, samples: 61);
      final thin = makeRate(
        rack,
        rack.last,
        tuning: tuning.copyWith(acceptanceScale: 1.0),
        samples: 61,
      );
      expect(thin, lessThan(fat));
    });
  });
}
