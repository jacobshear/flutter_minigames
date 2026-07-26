import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_archery/minigame_archery.dart';
import 'package:minigames_3d/minigames_3d.dart';

/// A hand-built target so the wind under test is explicit rather than seeded.
TargetConditions at(double distance, {double wind = 0, double angle = 0}) =>
    TargetConditions(
      index: 0,
      distance: distance,
      windSpeed: wind,
      windAngle: angle,
    );

void main() {
  group('the solved launch', () {
    test('a perfect release in still air is dead centre at every target', () {
      for (var seed = 0; seed < 25; seed++) {
        for (final c in ArcheryGame.conditionsForSeed(seed)) {
          final shot =
              ArcheryBallistics.fire(conditions: c, power: 0.5, windScale: 0);
          expect(shot.onFace, isTrue);
          expect(
            shot.ring,
            10,
            reason: 'seed $seed at ${c.distance} m missed the gold '
                '(${shot.offsetX.toStringAsFixed(3)}, '
                '${shot.offsetY.toStringAsFixed(3)})',
          );
          expect(shot.radius, lessThan(0.02));
        }
      }
    });

    test('the band is a real trade: under-drawn low, over-drawn high', () {
      final c = at(30);
      final low = ArcheryBallistics.fire(conditions: c, power: 0, windScale: 0);
      final high = ArcheryBallistics.fire(conditions: c, power: 1, windScale: 0);
      expect(low.offsetY, lessThan(-0.2));
      expect(high.offsetY, greaterThan(0.2));
      // Still on the face at both extremes — a mistimed shot scores badly, it
      // does not vanish into the grass.
      expect(low.onFace, isTrue);
      expect(high.onFace, isTrue);
      expect(low.ring, lessThan(10));
      expect(high.ring, lessThan(10));
    });

    test('the whole draw band stays within a couple of rings', () {
      // The playability claim, stated as a test: anywhere in the band scores.
      for (final d in [14.0, 22.0, 30.0, 38.0]) {
        for (var p = 0.0; p <= 1.0; p += 0.05) {
          final shot =
              ArcheryBallistics.fire(conditions: at(d), power: p, windScale: 0);
          expect(shot.onFace, isTrue, reason: 'power $p at $d m fell off');
          expect(shot.ring, greaterThanOrEqualTo(4));
        }
      }
    });

    test('flight time grows with range — which is what makes wind bite', () {
      final near =
          ArcheryBallistics.fire(conditions: at(15), power: 0.5, windScale: 0);
      final far =
          ArcheryBallistics.fire(conditions: at(38), power: 0.5, windScale: 0);
      expect(far.timeToImpactSeconds,
          greaterThan(near.timeToImpactSeconds * 1.4));
    });
  });

  group('the reticle is the aim point', () {
    /// Where the sight is sitting, in metres from the face centre, for a hold
    /// of [held] on arrow [seed] with the finger dragged to ([aimYaw],
    /// [aimPitch]). Built through [ArcheryView] on purpose: this is the exact
    /// expression the painter projects, so the test pins the thing the player
    /// actually looks at rather than a re-derivation of it.
    (double, double) reticleFor(
      double d,
      double held,
      int seed, {
      double aimYaw = 0,
      double aimPitch = 0,
    }) {
      final (sy, sp) =
          ArcheryDraw.swayOffset(heldSeconds: held, shotSeed: seed);
      final p = ArcheryView(
        conditions: at(d),
        aimYaw: aimYaw + sy,
        aimPitch: aimPitch + sp,
        drawBias: ArcheryBallistics.drawBias(d, ArcheryDraw.power(held)),
      ).aimPoint;
      return (p.x, p.y - ArcheryBallistics.targetCentreHeight);
    }

    ArcheryShotResult shotFor(
      double d,
      double held,
      int seed, {
      double aimYaw = 0,
      double aimPitch = 0,
      double windScale = 0,
      double wind = 0,
    }) {
      final (sy, sp) =
          ArcheryDraw.swayOffset(heldSeconds: held, shotSeed: seed);
      return ArcheryBallistics.fire(
        conditions: at(d, wind: wind),
        power: ArcheryDraw.power(held),
        aimYaw: aimYaw + sy,
        aimPitch: aimPitch + sp,
        windScale: windScale,
      );
    }

    test('in still air the arrow lands where the sight was pointing', () {
      // The contract, stated as a number. A spread of aim points right across
      // the face, at four ranges, at four points in the draw: the impact must
      // be on the reticle, not merely near it.
      //
      // This is the regression for the reported bug. It used to fail by up to
      // 44 cm — three and a half rings — because the draw moved the arrow
      // vertically with nothing on screen to show for it.
      var worst = 0.0;
      for (final d in [15.0, 22.0, 30.0, 38.0]) {
        for (final held in [
          0.5,
          ArcheryDraw.fullDrawSeconds,
          ArcheryDraw.sweetHoldSeconds,
          ArcheryDraw.fullDrawSeconds + ArcheryDraw.focusGraceSeconds,
        ]) {
          for (final ax in [-0.45, -0.2, 0.0, 0.2, 0.45]) {
            for (final ay in [-0.3, 0.0, 0.3]) {
              final yaw = math.atan(ax / d);
              final pitch = math.atan(ay / d);
              final (rx, ry) =
                  reticleFor(d, held, 7, aimYaw: yaw, aimPitch: pitch);
              final shot =
                  shotFor(d, held, 7, aimYaw: yaw, aimPitch: pitch);
              final miss = math.sqrt((shot.offsetX - rx) * (shot.offsetX - rx) +
                  (shot.offsetY - ry) * (shot.offsetY - ry));
              if (miss > worst) worst = miss;
            }
          }
        }
      }
      // 5 mm — a twenty-fourth of a ring. Everything above that is wind.
      expect(worst, lessThan(0.005), reason: 'reticle lied by ${worst}m');
    });

    test('aiming at the 6-ring scores 6, not a gold', () {
      // Aim is not decoration: point it at a ring and that is the ring you get.
      for (final d in [15.0, 22.0, 30.0, 38.0]) {
        for (final entry in const [
          (0.0, 10),
          (1.5, 8),
          (2.5, 6),
          (3.5, 4),
          (4.5, 2),
        ]) {
          final (bands, expected) = entry;
          final offset = ArcheryGame.ringWidth * bands;
          final shot = ArcheryBallistics.fire(
            conditions: at(d),
            power: 0.5,
            aimYaw: math.atan(offset / d),
            windScale: 0,
          );
          expect(shot.offsetX, closeTo(offset, 0.005));
          expect(shot.ring, expected,
              reason: 'aimed $bands rings out at $d m and scored ${shot.ring}');
        }
      }
    });

    test('the sight tells the truth about the draw, not just the aim', () {
      // Same aim, three points in the draw: the reticle moves with the shot.
      const d = 38.0;
      final snatched = reticleFor(d, ArcheryDraw.fullDrawSeconds, 11).$2;
      final ripe = reticleFor(d, ArcheryDraw.sweetHoldSeconds, 11).$2;
      final satOn = reticleFor(
        d,
        ArcheryDraw.fullDrawSeconds + ArcheryDraw.focusGraceSeconds,
        11,
      ).$2;
      expect(snatched, lessThan(-0.1)); // under-drawn: sight sits low
      expect(satOn, greaterThan(0.1)); // over-held: sight sits high
      // The ripe hold sits between them — the sway is all that is left of it.
      expect(ripe, greaterThan(snatched));
      expect(ripe, lessThan(satOn));
      expect(
        ArcheryBallistics.drawBias(
            d, ArcheryDraw.power(ArcheryDraw.sweetHoldSeconds)),
        closeTo(0, 0.005),
      );
      // And a hold that shows a low sight really does shoot low.
      expect(shotFor(d, ArcheryDraw.fullDrawSeconds, 11).offsetY,
          closeTo(snatched, 0.005));
    });

    test('wind is the only thing the sight cannot see', () {
      // The mechanic, pinned: everything the reticle omits is wind drift and
      // nothing else, so aiming off into it is a complete answer.
      const d = 30.0;
      const held = ArcheryDraw.sweetHoldSeconds;
      final (rx, ry) = reticleFor(d, held, 3);
      final still = shotFor(d, held, 3);
      final windy = shotFor(d, held, 3, wind: 6, windScale: 1);
      expect(still.offsetX, closeTo(rx, 0.005));
      expect(still.offsetY, closeTo(ry, 0.005));
      // The windy arrow misses the reticle, and by the pure drift.
      final drift = windy.offsetX - rx;
      expect(drift.abs(), greaterThan(ArcheryGame.ringWidth));
      // Hold off by exactly that and the sight is honest again.
      final held2 = shotFor(d, held, 3,
          aimYaw: -math.atan(drift / d), wind: 6, windScale: 1);
      expect(held2.ring, 10);
    });
  });

  group('difficulty', () {
    /// Gold and face rates for a shooter who holds the sight on the middle and
    /// looses somewhere in the steady window without correcting anything —
    /// the floor, not the ceiling. A skilled shooter reads the sight and does
    /// better; this is what the game gives away for free.
    (double, double) rates(double d) {
      var gold = 0;
      var face = 0;
      var n = 0;
      for (var seed = 0; seed < 120; seed++) {
        for (var t = ArcheryDraw.fullDrawSeconds;
            t <= ArcheryDraw.fullDrawSeconds + ArcheryDraw.focusGraceSeconds;
            t += 0.02) {
          final (y, p) = ArcheryDraw.swayOffset(heldSeconds: t, shotSeed: seed);
          final shot = ArcheryBallistics.fire(
            conditions: at(d),
            power: ArcheryDraw.power(t),
            aimYaw: y,
            aimPitch: p,
            windScale: 0,
          );
          n++;
          if (shot.ring == 10) gold++;
          if (shot.onFace) face++;
        }
      }
      return (100 * gold / n, 100 * face / n);
    }

    test('the gold is earned, and it gets dearer with range', () {
      // Measured bands, generous enough not to be brittle and tight enough to
      // catch the failure mode that prompted this: before the retune the same
      // sweep could not score below an 8 at 15 m and golded 40% of the time
      // with the sight parked in the middle.
      const bands = [
        (15.0, 70.0, 95.0),
        (22.0, 38.0, 66.0),
        (30.0, 22.0, 46.0),
        (38.0, 12.0, 34.0),
      ];
      var previous = 100.0;
      for (final (distance, floor, ceiling) in bands) {
        final (gold, face) = rates(distance);
        expect(gold, greaterThan(floor),
            reason: '$distance m golds only ${gold.toStringAsFixed(1)}%');
        expect(gold, lessThan(ceiling),
            reason: '$distance m golds ${gold.toStringAsFixed(1)}% — free');
        // Monotone: every target is harder than the one before it.
        expect(gold, lessThan(previous));
        previous = gold;
        // Satisfying, not punishing: the face is never in doubt in still air.
        expect(face, 100);
      }
    });

    test('a parked sight no longer guarantees a decent ring', () {
      // The old shape of the bug: at 15 m *every* release in the window scored
      // 8 or better whatever the player did. Ring 6 and worse must be reachable
      // by doing nothing, or aim has nothing to buy.
      final seen = <int>{};
      for (var seed = 0; seed < 60; seed++) {
        for (var t = ArcheryDraw.fullDrawSeconds;
            t <= ArcheryDraw.fullDrawSeconds + ArcheryDraw.focusGraceSeconds;
            t += 0.02) {
          final (y, p) = ArcheryDraw.swayOffset(heldSeconds: t, shotSeed: seed);
          seen.add(ArcheryBallistics.fire(
            conditions: at(22),
            power: ArcheryDraw.power(t),
            aimYaw: y,
            aimPitch: p,
            windScale: 0,
          ).ring);
        }
      }
      expect(seen, containsAll(<int>[10, 8, 6]));
    });
  });

  group('wind', () {
    test('the same shot drifts to the downwind side', () {
      final c = at(30, wind: 6);
      final still =
          ArcheryBallistics.fire(conditions: c, power: 0.5, windScale: 0);
      final windy =
          ArcheryBallistics.fire(conditions: c, power: 0.5, windScale: 1);
      expect(still.ring, 10);
      // Wind blows toward +x, so the arrow lands right of centre.
      expect(c.crossComponent, greaterThan(0));
      expect(windy.offsetX, greaterThan(0.15));
      expect(windy.ring, lessThan(10));

      // Mirror it: the identical wind from the other side lands left, by the
      // same amount.
      final mirrored = ArcheryBallistics.fire(
        conditions: at(30, wind: 6, angle: math.pi),
        power: 0.5,
      );
      expect(mirrored.offsetX, closeTo(-windy.offsetX, 1e-9));
    });

    test('drift grows with distance for the same wind', () {
      double driftAt(double d) => ArcheryBallistics.fire(
            conditions: at(d, wind: 6),
            power: 0.5,
          ).offsetX;

      final near = driftAt(15);
      final mid = driftAt(26);
      final far = driftAt(38);

      expect(near, greaterThan(0));
      expect(mid, greaterThan(near));
      expect(far, greaterThan(mid));
      // Quantitative: the far target drifts more than twice as far as the near
      // one under identical wind. (Time of flight roughly 1.55x, and drift goes
      // as t².)
      expect(far, greaterThan(near * 2.2));
      // And the near target still scores through it while the far one does not.
      expect(near, lessThan(ArcheryGame.ringWidth * 2));
      expect(far, greaterThan(ArcheryGame.ringWidth * 3));
    });

    test('a light wind is almost free, a gale is decisive', () {
      final light = ArcheryBallistics.fire(
        conditions: at(15, wind: 1),
        power: 0.5,
      );
      final gale = ArcheryBallistics.fire(
        conditions: at(38, wind: 8.5),
        power: 0.5,
      );
      expect(light.ring, 10);
      expect(gale.ring, lessThanOrEqualTo(2));
    });

    test('aiming off into the wind puts it back in the gold', () {
      // The skill loop, end to end: the reticle lies, the archer corrects.
      final c = at(30, wind: 6);
      final uncorrected =
          ArcheryBallistics.fire(conditions: c, power: 0.5);
      expect(uncorrected.ring, lessThan(10));
      // Aim off by the angle the drift subtends, upwind.
      final correction = -math.atan(uncorrected.offsetX / c.distance);
      final corrected =
          ArcheryBallistics.fire(conditions: c, power: 0.5, aimYaw: correction);
      expect(corrected.ring, 10);
    });

    test('a tailwind lands long and high, a headwind short and low', () {
      final tail = ArcheryBallistics.fire(
        conditions: at(30, wind: 8, angle: math.pi / 2),
        power: 0.5,
      );
      final head = ArcheryBallistics.fire(
        conditions: at(30, wind: 8, angle: -math.pi / 2),
        power: 0.5,
      );
      expect(tail.offsetY, greaterThan(head.offsetY));
    });
  });

  group('collision', () {
    test('a fast arrow cannot tunnel through the target', () {
      const distance = 15.0;
      // Four times the solved speed, integrated at a deliberately coarse 60 Hz:
      // the arrow covers well over a whole face width per step, so any
      // point-inside-the-face test would sail straight through it.
      final speed = ArcheryBallistics.solveSpeed(distance) * 4;
      const dt = 1 / 60;
      final stepLength = speed * dt;
      expect(stepLength, greaterThan(ArcheryGame.faceRadius * 2));

      // Aim it flat enough that, at this speed, it is heading for the middle
      // of the face — the point of the test is the crossing, not the score.
      final drop =
          ArcheryBallistics.gravity * distance * distance / (2 * speed * speed);
      final loft = math.atan(
        (drop +
                ArcheryBallistics.targetCentreHeight -
                ArcheryBallistics.bowHeight) /
            distance,
      );
      final projectile = Projectile(
        position: ArcheryBallistics.bowOrigin,
        velocity: Vec3(0, math.sin(loft) * speed, math.cos(loft) * speed),
        config: const ThrowConfig(gravity: 9.81, drag: 0, fixedDt: dt),
      );

      Vec3? hit;
      var samplesInsideTheFace = 0;
      for (var i = 0; i < 600; i++) {
        final from = projectile.step();
        hit = Surfaces.verticalPlaneHit(from, projectile.position, distance);
        if ((projectile.position.z - distance).abs() <
            ArcheryGame.faceRadius) {
          samplesInsideTheFace++;
        }
        if (hit != null) break;
      }

      // The swept test caught it...
      expect(hit, isNotNull);
      expect(hit!.z, closeTo(distance, 1e-9));
      expect(
        ArcheryGame.onFace(
          hit.x,
          hit.y - ArcheryBallistics.targetCentreHeight,
        ),
        isTrue,
      );
      // ...and no integration step ever landed near the plane, which is exactly
      // how a naive check would have missed the target entirely.
      expect(samplesInsideTheFace, 0);
    });

    test('every shot in the band records an impact on the plane', () {
      for (var p = 0.0; p <= 1.0; p += 0.1) {
        final shot =
            ArcheryBallistics.fire(conditions: at(15), power: p, windScale: 0);
        expect(shot.impact, isNotNull, reason: 'power $p never crossed');
      }
    });

    test('a shot aimed well wide passes the plane and lands in the grass', () {
      final shot = ArcheryBallistics.fire(
        conditions: at(20),
        power: 0.5,
        aimYaw: 0.35,
        windScale: 0,
      );
      expect(shot.impact, isNotNull);
      expect(shot.onFace, isFalse);
      expect(shot.ring, 0);
      expect(shot.path.last.y, lessThanOrEqualTo(0.01));
      expect(shot.flightSeconds, greaterThan(shot.timeToImpactSeconds));
    });
  });

  group('determinism', () {
    test('the same inputs always produce the same shot', () {
      final c = ArcheryGame.conditionsAt(4, 2);
      final a = ArcheryBallistics.fire(
          conditions: c, power: 0.61, aimYaw: 0.004, aimPitch: -0.002);
      final b = ArcheryBallistics.fire(
          conditions: c, power: 0.61, aimYaw: 0.004, aimPitch: -0.002);
      expect(a.offsetX, b.offsetX);
      expect(a.offsetY, b.offsetY);
      expect(a.ring, b.ring);
      expect(a.path.length, b.path.length);
    });

    test('the flight can be sampled at any point in time', () {
      final shot = ArcheryBallistics.fire(conditions: at(25), power: 0.5);
      expect(shot.positionAt(0).z, closeTo(0, 1e-9));
      expect(shot.positionAt(shot.flightSeconds).z, closeTo(25, 0.2));
      final mid = shot.positionAt(shot.flightSeconds / 2);
      expect(mid.z, greaterThan(5));
      expect(mid.z, lessThan(25));
      // The nose pitches down as it drops.
      expect(shot.directionAt(0).y,
          greaterThan(shot.directionAt(shot.flightSeconds).y));
    });
  });

  group('the draw', () {
    test('the sweet spot lands inside the steady hold, not before it', () {
      // The bug this pins: the perfect release used to sit at 0.84 s, *before*
      // full draw, while every cue on screen said "now" from 1.05 s onward.
      const sweet = ArcheryDraw.sweetHoldSeconds;
      expect(sweet, greaterThan(ArcheryDraw.fullDrawSeconds));
      expect(
        sweet,
        lessThan(ArcheryDraw.fullDrawSeconds + ArcheryDraw.focusGraceSeconds),
      );
      expect(ArcheryDraw.power(sweet), closeTo(0.5, 1e-9));
      final shot = ArcheryBallistics.fire(
        conditions: at(25),
        power: ArcheryDraw.power(sweet),
        windScale: 0,
      );
      expect(shot.ring, 10);
      // And the meter marks it, rather than marking a fraction of a bar that
      // has already pinned full.
      expect(ArcheryDraw.sweetMeterFraction, greaterThan(0.6));
      expect(ArcheryDraw.sweetMeterFraction, lessThan(0.85));
      expect(ArcheryDraw.holdProgress(ArcheryDraw.fullDrawSeconds),
          lessThan(ArcheryDraw.sweetMeterFraction));
    });

    test('the shot ripens through the hold: snatched weak, sat-on strong', () {
      expect(ArcheryDraw.power(0), 0);
      // Coming to full stretch is not yet the shot.
      expect(ArcheryDraw.power(0.2), lessThan(ArcheryDraw.drawnPower));
      expect(
        ArcheryDraw.power(ArcheryDraw.fullDrawSeconds),
        closeTo(ArcheryDraw.drawnPower, 1e-9),
      );
      expect(ArcheryDraw.drawnPower, lessThan(0.5));
      // Then it climbs monotonically across the grace, through 0.5, to ripe.
      var last = -1.0;
      for (var t = ArcheryDraw.fullDrawSeconds;
          t <= ArcheryDraw.fullDrawSeconds + ArcheryDraw.focusGraceSeconds;
          t += 0.05) {
        final p = ArcheryDraw.power(t);
        expect(p, greaterThan(last));
        last = p;
      }
      expect(
        ArcheryDraw.power(
            ArcheryDraw.fullDrawSeconds + ArcheryDraw.focusGraceSeconds),
        closeTo(ArcheryDraw.ripePower, 1e-9),
      );
      expect(ArcheryDraw.ripePower, greaterThan(0.5));
    });

    test('the reticle contracts as the bow comes to full draw', () {
      final loose = ArcheryDraw.swayAmplitude(0);
      final half = ArcheryDraw.swayAmplitude(ArcheryDraw.fullDrawSeconds / 2);
      final full = ArcheryDraw.swayAmplitude(ArcheryDraw.fullDrawSeconds);
      expect(half, lessThan(loose));
      expect(full, lessThan(half));
      expect(full, closeTo(ArcheryDraw.minSway, 1e-9));
    });

    test('focus breaks after the grace, and the shot goes with it', () {
      const full = ArcheryDraw.fullDrawSeconds;
      const grace = ArcheryDraw.focusGraceSeconds;
      expect(ArcheryDraw.focusBreak(full), 0);
      expect(ArcheryDraw.focusBreak(full + grace), 0);
      expect(ArcheryDraw.focusBreak(full + grace + 0.4), greaterThan(0));
      expect(
        ArcheryDraw.focusBreak(full + grace + ArcheryDraw.focusFadeSeconds),
        closeTo(1, 1e-9),
      );
      // A broken hold both wanders more and creeps forward (weaker).
      expect(
        ArcheryDraw.swayAmplitude(full + grace + 1.2),
        greaterThan(ArcheryDraw.swayAmplitude(full) * 6),
      );
      expect(ArcheryDraw.power(full + grace + 1.2), lessThan(0.5));
      expect(ArcheryDraw.isWarning(full + grace - 0.2), isTrue);
      expect(ArcheryDraw.isWarning(full + 0.1), isFalse);
    });

    test('sway is deterministic per arrow but differs between arrows', () {
      final a = ArcheryDraw.swayOffset(heldSeconds: 0.7, shotSeed: 5);
      final b = ArcheryDraw.swayOffset(heldSeconds: 0.7, shotSeed: 5);
      final c = ArcheryDraw.swayOffset(heldSeconds: 0.7, shotSeed: 6);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('a ripe hold beats a snatched one, and both stay on the face', () {
      int ringFor(double held, int seed) {
        final (y, p) = ArcheryDraw.swayOffset(heldSeconds: held, shotSeed: seed);
        return ArcheryBallistics.fire(
          conditions: at(30),
          power: ArcheryDraw.power(held),
          aimYaw: y,
          aimPitch: p,
          windScale: 0,
        ).ring;
      }

      var ripe = 0;
      var snatched = 0;
      for (var seed = 0; seed < 40; seed++) {
        ripe += ringFor(ArcheryDraw.sweetHoldSeconds, seed);
        snatched += ringFor(ArcheryDraw.fullDrawSeconds * 0.5, seed);
      }
      expect(ripe, greaterThan(snatched * 1.4));

      // The bow is measurably calmer once it is at full stretch.
      final (sy, sp) = ArcheryDraw.swayOffset(
          heldSeconds: ArcheryDraw.fullDrawSeconds, shotSeed: 3);
      final (ey, ep) = ArcheryDraw.swayOffset(
          heldSeconds: ArcheryDraw.fullDrawSeconds * 0.33, shotSeed: 3);
      expect(ey.abs() + ep.abs(), greaterThan(sy.abs() + sp.abs()));
    });
  });
}
