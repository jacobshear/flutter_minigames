import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/mini_golf/mini_golf.dart';

/// The half of mini golf that used to be judged by eye: the ball dropping into
/// the cup, horseshoeing out of it, banking off a rail, rolling rather than
/// sliding, and dying into rest.
///
/// Every one of these is presentation over an outcome the reducer already owns,
/// so the tests check both halves: that the *motion* is there, and that adding
/// it left `sunk` / `settled` — the only things [MiniGolfGame] reads — alone.
MiniGolfCourse straight({
  double length = 14,
  double halfWidth = 1.5,
  Offset? cup,
}) =>
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
      cup: cup ?? Offset(0, length - 1.2),
      routeLength: length - 2.2,
      minFairwayWidth: halfWidth * 2,
      par: 3,
    );

const _up = Offset(0, 1);

/// The slowest putt from the tee that actually drops, on a course whose cup is
/// close enough to reach at low power.
PuttResult sinker(MiniGolfCourse c) {
  for (var i = 4; i < 120; i++) {
    final r = MiniGolfPutt.simulate(
      course: c,
      from: c.tee,
      direction: _up,
      power: i * 0.01,
    );
    if (r.sunk) return r;
  }
  fail('no power holed the putt');
}

void main() {
  group('the drop', () {
    test('the ball falls into the cup and lands on the bottom', () {
      final c = straight(length: 12, cup: const Offset(0, 4));
      final r = sinker(c);
      final drop = r.events.firstWhere((e) => e.kind == PuttEventKind.drop);
      final sink = r.events.firstWhere((e) => e.kind == PuttEventKind.sink);
      expect(drop.sample, lessThanOrEqualTo(sink.sample));

      // Long enough to watch: the old drop parked the ball at the bottom the
      // instant it crossed the mouth, which was over in a couple of frames.
      final after = r.path.length - 1 - drop.sample;
      expect(after, greaterThan(12),
          reason: 'the drop lasted $after frames — too quick to see');

      // It really descends, monotonically at first, and finishes at the bottom
      // of the cup rather than hovering at the lip.
      final depths = [
        for (var i = drop.sample; i < r.path.length; i++) r.path[i].position.y,
      ];
      expect(depths.first, greaterThan(depths.last));
      expect(r.path.last.position.y,
          closeTo(MiniGolfWorld.cupRestY, MiniGolfCourse.ballRadius));
      // …and it stays inside the cup while it does it.
      for (var i = drop.sample; i < r.path.length; i++) {
        final p = r.path[i].position;
        final off = Offset(p.x - c.cup.dx, p.z - c.cup.dy);
        expect(off.distance, lessThanOrEqualTo(MiniGolfCourse.cupRadius + 1e-6),
            reason: 'the ball left the cup at frame $i');
      }
    });

    test('a ball that catches the lip off-centre rattles', () {
      // Struck at the cup from an angle, so it drops in off-centre and has to
      // find the bottom via the wall.
      final c = straight(length: 12, cup: const Offset(0.6, 4));
      var rattled = false;
      for (var i = 10; i < 90 && !rattled; i++) {
        final to = c.cup - c.tee;
        final r = MiniGolfPutt.simulate(
          course: c,
          from: c.tee,
          direction: to / to.distance,
          power: i * 0.01,
        );
        if (r.sunk && r.has(PuttEventKind.rattle)) rattled = true;
      }
      expect(rattled, isTrue,
          reason: 'no holed putt ever touched the cup wall');
    });

    test('the drop never changes what the reducer is told', () {
      // The frames after the ball crosses the mouth are pure presentation, so
      // the two things the move carries must be settled before they happen.
      final c = straight(length: 12, cup: const Offset(0, 4));
      final r = sinker(c);
      expect(r.sunk, isTrue);
      expect(r.settled, c.cup);
      expect(r.outOfBounds, isFalse);

      // Truncating the whole animated tail leaves the same reported outcome —
      // which is what "the drop is downstream of the decision" means.
      final sink = r.events.firstWhere((e) => e.kind == PuttEventKind.sink);
      expect(sink.sample, lessThan(r.path.length - 1),
          reason: 'the outcome was only reached on the very last frame');
    });

    test('a rendered drop is drawn inside the cup, not on top of it', () {
      final c = straight(length: 12, cup: const Offset(0, 4));
      final r = sinker(c);
      const size = Size(320, 520);
      var below = 0;
      for (final s in r.path) {
        final view = MiniGolfView(
          course: c,
          ball: MiniGolfBallView(
            position: s.position,
            spin: s.spin,
            roll: s.roll,
          ),
        );
        if (view.ball.inCup) below++;
        final rec = ui.PictureRecorder();
        paintMiniGolfScene(
          Canvas(rec, Offset.zero & size),
          size,
          view,
          const MiniGolfStyle(),
          ColorScheme.fromSeed(seedColor: const Color(0xFF3FA45A)),
        );
        expect(rec.endRecording(), isNotNull);
      }
      // A good stretch of the recording has the ball below the lip, which is
      // the window in which the painter clips it to the mouth.
      expect(below, greaterThan(8));
    });
  });

  group('the lip-out', () {
    test('a fast ball rides the rim and is thrown off line', () {
      final c = straight(length: 20, cup: const Offset(0, 4));
      final r = MiniGolfPutt.simulate(
        course: c,
        from: const Offset(0, 1),
        direction: _up,
        power: 1.0,
      );
      expect(r.sunk, isFalse, reason: 'a full-blooded putt should not drop');
      expect(r.has(PuttEventKind.lipOut), isTrue);
      final lip = r.events.firstWhere((e) => e.kind == PuttEventKind.lipOut);

      // It dips into the mouth on the way past — but never far enough to count
      // as being in the cup, or it would be clipped away mid-horseshoe.
      final window = r.path.sublist(
        lip.sample,
        math.min(lip.sample + 30, r.path.length),
      );
      final lowest = window.map((s) => s.position.y).reduce(math.min);
      expect(lowest, lessThan(MiniGolfWorld.ballY - 0.02),
          reason: 'it sailed over the hole without dipping into it');
      expect(lowest, greaterThan(MiniGolfCourse.ballRadius * 0.35),
          reason: 'the horseshoe dipped deep enough to be drawn as holed');

      // And it is thrown sideways. A dead-straight lip-out — the old behaviour,
      // which only scaled the speed — reads as the ball ignoring the hole.
      final sideways = window.last.position.x.abs();
      expect(sideways, greaterThan(MiniGolfCourse.cupRadius * 0.5),
          reason: 'deflected only $sideways across');
      expect(r.settled.dy, greaterThan(5.0), reason: 'it should carry past');
    });

    test('a slow ball over the same cup still drops', () {
      // The lip-out must be a *speed* rule, not a geometry one.
      final c = straight(length: 20, cup: const Offset(0, 4));
      final r = sinker(c);
      expect(r.sunk, isTrue);
      expect(r.has(PuttEventKind.lipOut), isFalse);
    });
  });

  group('rolling', () {
    test('the ball turns further the further it rolls', () {
      final c = straight(length: 24);
      final r = MiniGolfPutt.simulate(
        course: c,
        from: const Offset(0, 1),
        direction: _up,
        power: 1.0,
      );
      // Total turn is distance / radius, so a long putt turns the ball many
      // times over; a ball that only translated would report zero.
      expect(r.path.last.spin,
          closeTo(r.rollDistance / MiniGolfCourse.ballRadius, 0.5));
      expect(r.path.last.spin, greaterThan(2 * math.pi * 5));

      // Monotone: every sample has turned at least as far as the one before.
      for (var i = 1; i < r.path.length; i++) {
        expect(r.path[i].spin, greaterThanOrEqualTo(r.path[i - 1].spin));
      }
    });

    test('the ball rolls about the axis across its travel, not the view axis',
        () {
      final c = straight(length: 24);
      final r = MiniGolfPutt.simulate(
        course: c,
        from: const Offset(0, 1),
        direction: _up,
        power: 0.6,
      );
      // Travelling along +z, the turn is about ±x. So the local axis that
      // started pointing along x must still point along x, while the ones that
      // started up and down-range must have swapped places at some point.
      final end = r.path.last.roll;
      expect(end.ax.x.abs(), closeTo(1.0, 1e-6),
          reason: 'the ball rolled about the wrong axis');
      final tipped = r.path.any((s) => s.roll.ay.z.abs() > 0.9);
      expect(tipped, isTrue, reason: 'the ball never turned over');
    });

    test('a ball that goes nowhere does not spin', () {
      const roll = BallRoll.identity;
      final same = roll.rolled(0, 0, MiniGolfCourse.ballRadius);
      expect(same.ax.x, 1);
      expect(same.ay.y, 1);
      expect(same.az.z, 1);
    });
  });

  group('bounces', () {
    test('a harder bank is reported as a harder bank', () {
      final c = straight(length: 20, halfWidth: 1.5);
      double strengthAt(double power) {
        final r = MiniGolfPutt.simulate(
          course: c,
          from: const Offset(0, 1),
          direction: const Offset(0.85, 0.53),
          power: power,
        );
        final rails = r.events.where((e) => e.kind == PuttEventKind.rail);
        expect(rails, isNotEmpty, reason: 'no rail hit at power $power');
        return rails.first.strength;
      }

      final soft = strengthAt(0.45);
      final hard = strengthAt(1.0);
      expect(hard, greaterThan(soft));
      expect(hard, lessThanOrEqualTo(1.0));
      expect(soft, greaterThanOrEqualTo(0.0));
    });

    test('a bank records where it happened, on the rail', () {
      final c = straight(length: 20, halfWidth: 1.5);
      final r = MiniGolfPutt.simulate(
        course: c,
        from: const Offset(0, 1),
        direction: const Offset(0.85, 0.53),
        power: 0.95,
      );
      final rail = r.events.firstWhere((e) => e.kind == PuttEventKind.rail);
      // The contact point sits on the boundary, not at the ball's centre.
      expect(rail.at.dx, closeTo(1.5, 0.05));
    });
  });

  group('settling', () {
    test('the ball dies into rest instead of being switched off', () {
      final c = straight(length: 24);
      final r = MiniGolfPutt.simulate(
        course: c,
        from: const Offset(0, 1),
        direction: _up,
        power: 0.8,
      );
      double step(int i) {
        final a = r.path[i - 1].position;
        final b = r.path[i].position;
        return math.sqrt((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z));
      }

      final last = r.path.length - 1;
      // The final frame it moves must be a crawl — a putt that stops dead has a
      // big last step. One ball radius per frame would be a visible jolt.
      expect(step(last), lessThan(MiniGolfCourse.ballRadius * 0.25),
          reason: 'stopped dead with a step of ${step(last)}');
      // And it has been slowing for a while, not braking on the last frame.
      expect(step(last), lessThan(step(last - 8)));
      expect(step(last - 8), lessThan(step(last - 24)));
    });
  });
}
