import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/darts/darts.dart';
import 'package:flutter_minigames/src/engine3d/engine3d.dart';

/// Where a flick lands, as a board-face offset. Headless: the whole throw runs
/// on the fixed-step integrator, so these numbers are the ones the game gets.
DartsImpact fire({
  double aimX = 0,
  double aimY = 0,
  double power = 0.5,
  double swipeDx = 0,
}) {
  final impact = DartsFlight.simulateFlick(
    aimX: aimX,
    aimY: aimY,
    power: power,
    swipeDx: swipeDx,
  );
  expect(impact, isNotNull, reason: 'aim ($aimX, $aimY) should be reachable');
  return impact!;
}

/// A swipe of [length] pixels, [degrees] off straight-up (positive = right).
(double, double) swipe({required double length, double degrees = 0}) {
  final a = degrees * math.pi / 180;
  return (math.sin(a) * length, -math.cos(a) * length);
}

/// Fly a swipe. Fails the test if the swipe was not a throw at all.
DartsImpact fling({required double length, double degrees = 0}) {
  final s = swipe(length: length, degrees: degrees);
  final impact = DartsFlight.simulateSwipe(s.$1, s.$2);
  expect(impact, isNotNull, reason: '$length px at $degrees° should throw');
  return impact!;
}

void main() {
  group('the swipe', () {
    test('a swipe throws; a tap does not', () {
      expect(DartsSwing.read(0, 0), isNull, reason: 'a tap is not a throw');
      expect(DartsFlight.simulateSwipe(0, 0), isNull);
      final thrown = fling(length: 180);
      expect(thrown.onFloor, isFalse);
      expect(thrown.onBoard, isTrue);
    });

    test('the dead zone still rejects a twitch', () {
      final tiny = swipe(length: DartsWorld.flick.deadZone - 1);
      expect(DartsSwing.read(tiny.$1, tiny.$2), isNull);
      final just = swipe(length: DartsWorld.flick.deadZone + 1);
      expect(DartsSwing.read(just.$1, just.$2), isNotNull);
    });

    test('a swipe down the screen is not a throw', () {
      expect(DartsSwing.read(0, 200), isNull);
      expect(DartsSwing.read(60, 200), isNull);
      // Nor is a purely sideways one.
      expect(DartsSwing.read(200, 0), isNull);
    });

    test('length walks the dart up the board, monotonically', () {
      var previous = -double.infinity;
      for (final length in const [18.0, 60.0, 120.0, 200.0, 280.0, 340.0]) {
        final y = fling(length: length).boardY;
        expect(y, greaterThan(previous), reason: 'length $length');
        previous = y;
      }
    });

    test('direction walks the dart across the board, monotonically', () {
      var previous = -double.infinity;
      for (final degrees in const [
        -45.0,
        -25.0,
        -10.0,
        0.0,
        10.0,
        25.0,
        45.0
      ]) {
        final x = fling(length: 200, degrees: degrees).boardX;
        expect(x, greaterThan(previous), reason: '$degrees°');
        previous = x;
      }
    });

    test('the swipe alone reaches every ring on the board', () {
      // Sweep the whole gesture space and collect what it can score. With no
      // reticle this is the only aiming there is, so anything unreachable here
      // is unreachable in the game.
      final hits = <String>{};
      var lowest = 0.0, highest = 0.0, widest = 0.0, worstRadius = 0.0;
      for (var length = 18.0; length <= 380; length += 4) {
        for (var degrees = -50.0; degrees <= 50; degrees += 2) {
          final impact = fling(length: length, degrees: degrees);
          hits.add(impact.hit.label);
          lowest = math.min(lowest, impact.boardY);
          highest = math.max(highest, impact.boardY);
          widest = math.max(widest, impact.boardX.abs());
          worstRadius = math.max(worstRadius, impact.radius);
        }
      }
      const r = DartsWorld.boardRadius;
      expect(lowest, lessThan(-0.9 * r), reason: 'the bottom of the board');
      expect(highest, greaterThan(0.9 * r), reason: 'the top of the board');
      expect(widest, greaterThan(0.9 * r), reason: 'the sides of the board');
      expect(hits, contains('BULL'));
      expect(hits, contains('T20'), reason: 'the treble 20 is still the prize');
      expect(hits.where((h) => h.startsWith('D')).length, greaterThan(6),
          reason: 'doubles all round the rim, or there is no checkout');
      // And nothing in that whole space sails off the face.
      expect(worstRadius, lessThan(r));
      expect(hits, isNot(contains('MISS')));
    });

    test('the same swipe always lands in the same place', () {
      final a = fling(length: 213, degrees: 17);
      final b = fling(length: 213, degrees: 17);
      expect(a.boardX, b.boardX);
      expect(a.boardY, b.boardY);
      expect(a.hit, b.hit);
    });

    test('the dart lands where the swipe pointed, within a bed', () {
      // [DartsSwing.bandDrop] is a fit to the integrator, so the landing is
      // near the intended point rather than on it. The slack is the touch in
      // the throw — but it has to stay small enough that the swipe is honest.
      for (var length = 18.0; length <= 380; length += 7) {
        for (final degrees in const [-40.0, 0.0, 40.0]) {
          final s = swipe(length: length, degrees: degrees);
          final swing = DartsSwing.read(s.$1, s.$2)!;
          final impact = DartsFlight.simulate(swing.velocity!);
          expect((impact.boardY - swing.landY).abs(), lessThan(0.025),
              reason: 'height for $length px at $degrees°');
          expect((impact.boardX - swing.landX).abs(), lessThan(0.005),
              reason: 'lateral for $length px at $degrees°');
        }
      }
    });
  });

  group('the solver', () {
    test('a centred flick lands on the aim point, within a millimetre', () {
      for (final aim in const [
        (0.0, 0.0),
        (0.0, 0.23),
        (0.0, -0.23),
        (0.2, 0.1),
        (-0.2, -0.1),
      ]) {
        final impact = fire(aimX: aim.$1, aimY: aim.$2);
        expect((impact.boardX - aim.$1).abs(), lessThan(0.001),
            reason: 'x for $aim');
        expect((impact.boardY - aim.$2).abs(), lessThan(0.001),
            reason: 'y for $aim');
      }
    });

    test('every point on the board is reachable at the fixed loft', () {
      for (var i = 0; i < 24; i++) {
        final a = 2 * math.pi * i / 24;
        const r = DartsWorld.boardRadius * 0.97;
        final impact = fire(aimX: math.sin(a) * r, aimY: math.cos(a) * r);
        expect(impact.onFloor, isFalse);
        expect(impact.hit.isMiss, isFalse,
            reason: 'the very edge of the board still scores (a double)');
      }
    });

    test('the solved speed is a real speed, not a fallback', () {
      final v = DartsAim.solveSpeed(DartsWorld.boardPoint(0, 0));
      expect(v, isNotNull);
      expect(v!, greaterThan(4));
      expect(v, lessThan(9));
    });

    test('drag refinement matters — the closed form alone throws short', () {
      final target = DartsWorld.boardPoint(0, 0);
      final analytic = LaunchSolver.speedToHit(
        horizontalDistance: target.z - DartsWorld.release.z,
        heightDelta: target.y - DartsWorld.release.y,
        loft: DartsWorld.loft,
        gravity: DartsWorld.config.gravity,
      )!;
      final refined = DartsAim.solveSpeed(target)!;
      expect(refined, greaterThan(analytic));
      // Firing the un-refined speed undershoots the bull.
      final short = DartsFlight.simulate(
        Vec3(0, math.sin(DartsWorld.loft) * analytic,
            math.cos(DartsWorld.loft) * analytic),
      );
      expect(short.boardY, lessThan(-0.002));
    });
  });

  group('the flick', () {
    test('power walks the dart up the board, monotonically', () {
      var previous = -double.infinity;
      for (final p in const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]) {
        final y = fire(power: p).boardY;
        expect(y, greaterThan(previous), reason: 'power $p');
        previous = y;
      }
    });

    test('a sideways swipe walks it across, monotonically', () {
      var previous = -double.infinity;
      for (final dx in const [-200.0, -80.0, 0.0, 80.0, 200.0]) {
        final x = fire(swipeDx: dx).boardX;
        expect(x, greaterThan(previous), reason: 'dx $dx');
        previous = x;
      }
    });

    test('even the worst flick still finds the board', () {
      // The band is what makes the game playable: a flick at either extreme of
      // the power range, thrown fully sideways, is a bad dart — but it is a
      // dart *in the board*, not one on the floor.
      for (final p in const [0.0, 1.0]) {
        for (final dx in const [-260.0, 260.0]) {
          final impact = fire(power: p, swipeDx: dx);
          expect(impact.onFloor, isFalse, reason: 'power $p dx $dx');
          expect(impact.radius, lessThan(DartsWorld.boardRadius),
              reason: 'power $p dx $dx should stay inside the double ring');
        }
      }
    });
  });

  group('grouping', () {
    test('a deliberate flick groups tightly but not on a pinhead', () {
      // Sample the flicks a player who means it produces: near-centred power,
      // near-straight swipe.
      final xs = <double>[];
      final ys = <double>[];
      for (var i = 0; i <= 6; i++) {
        for (var j = 0; j <= 4; j++) {
          final power = 0.38 + i * (0.24 / 6);
          final dx = -28.0 + j * 14.0;
          final impact = fire(power: power, swipeDx: dx);
          xs.add(impact.boardX);
          ys.add(impact.boardY);
        }
      }
      final spreadX = xs.reduce(math.max) - xs.reduce(math.min);
      final spreadY = ys.reduce(math.max) - ys.reduce(math.min);
      final worst = [
        for (var i = 0; i < xs.length; i++)
          math.sqrt(xs[i] * xs[i] + ys[i] * ys[i]),
      ].reduce(math.max);

      // Not pinpoint: there is real skill in the flick.
      expect(spreadY, greaterThan(0.01), reason: 'vertical spread $spreadY');
      expect(spreadX, greaterThan(0.01), reason: 'lateral spread $spreadX');
      // Not scattered: the whole group is inside the treble ring's radius, so
      // aiming at a bed means landing in or beside it.
      expect(worst, lessThan(DartsWorld.boardRadius * 0.5),
          reason: 'worst dart landed $worst from the bull');
    });

    test('the treble is a real target, and a real miss', () {
      // Aim mid-treble-20 and vary the flick: a clean one trebles, a sloppy
      // one drops into the single bed above or below.
      const t20 = DartsWorld.boardRadius *
          (DartsBoardGeometry.innerTrebleRatio +
              DartsBoardGeometry.outerTrebleRatio) /
          2;
      expect(fire(aimY: t20).hit, const DartHit(20, 3));
      expect(fire(aimY: t20, power: 0.30).hit, const DartHit(20, 1));
      expect(fire(aimY: t20, power: 0.70).hit, const DartHit(20, 1));
      // A wide swipe walks off into the neighbouring sector entirely.
      expect(fire(aimY: t20, swipeDx: 200).hit.sector, isNot(20));
    });

    test('the same flick always lands in the same place', () {
      final a = fire(aimX: 0.1, aimY: 0.12, power: 0.61, swipeDx: 17);
      final b = fire(aimX: 0.1, aimY: 0.12, power: 0.61, swipeDx: 17);
      expect(a.boardX, b.boardX);
      expect(a.boardY, b.boardY);
      expect(a.hit, b.hit);
    });
  });

  group('the flight', () {
    test('a dart takes a believable fraction of a second to arrive', () {
      final flight = DartsFlight(
        velocity: DartsAim.launch(aimX: 0, aimY: 0, power: 0.5, swipeDx: 0)!,
      );
      var guard = 0;
      while (!flight.done && guard++ < 5000) {
        flight.advance(1 / 60);
      }
      expect(flight.done, isTrue);
      expect(flight.elapsed, greaterThan(0.25));
      expect(flight.elapsed, lessThan(0.8));
    });

    test('the dart rises then falls — it is a throw, not a laser', () {
      final flight = DartsFlight(
        velocity: DartsAim.launch(aimX: 0, aimY: 0, power: 0.5, swipeDx: 0)!,
      );
      var apex = flight.position.y;
      while (!flight.done) {
        flight.advance(1 / 240);
        apex = math.max(apex, flight.position.y);
      }
      expect(apex, greaterThan(DartsWorld.release.y + 0.15));
      expect(apex, greaterThan(flight.impact!.point.y));
    });

    test('a flat rocket cannot tunnel through the board', () {
      // Swept collision is the point: one 1/120 s step at 60 m/s covers half a
      // metre, so an end-point test would put this dart behind the wall.
      final impact = DartsFlight.simulate(const Vec3(0, 0.9, 60));
      expect(impact.onFloor, isFalse);
      expect(impact.point.z, closeTo(DartsWorld.boardZ, 1e-6));
    });

    test('a dart thrown at the floor is a miss, not a score', () {
      final impact = DartsFlight.simulate(const Vec3(0, -2, 1.5));
      expect(impact.onFloor, isTrue);
      expect(impact.hit, DartHit.miss);
      expect(impact.onBoard, isFalse);
    });

    test('a dart past the surround is a miss but still sticks in the wall', () {
      final impact =
          fire(aimX: 0, aimY: DartsWorld.boardRadius * 0.97, power: 1.0);
      expect(impact.onFloor, isFalse);
      if (impact.radius > DartsWorld.boardRadius) {
        expect(impact.hit, DartHit.miss);
        expect(impact.onBoard, isFalse);
      }
    });

    test('a swing flies the same whether it is ticked or run headlessly', () {
      // The widget releases the swing into a ticked flight; the tests fly it
      // headlessly. Both must be the same dart.
      final swing = DartsSwing.read(40, -220)!;
      final predicted = DartsFlight.simulate(swing.velocity!);
      final flown = DartsFlight(velocity: swing.velocity!);
      while (!flown.done) {
        flown.advance(1 / 60);
      }
      expect(flown.impact!.point.x, closeTo(predicted.point.x, 1e-9));
      expect(flown.impact!.point.y, closeTo(predicted.point.y, 1e-9));
      expect(flown.impact!.hit, predicted.hit);
    });

    test('advance() and the headless loop agree', () {
      final velocity =
          DartsAim.launch(aimX: 0.05, aimY: 0.1, power: 0.55, swipeDx: -12)!;
      final headless = DartsFlight.simulate(velocity);
      final ticked = DartsFlight(velocity: velocity);
      while (!ticked.done) {
        ticked.advance(1 / 60);
      }
      expect(ticked.impact!.boardX, closeTo(headless.boardX, 1e-9));
      expect(ticked.impact!.boardY, closeTo(headless.boardY, 1e-9));
    });
  });
}
