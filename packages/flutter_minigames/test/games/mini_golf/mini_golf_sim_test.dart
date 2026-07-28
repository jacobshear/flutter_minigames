import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/mini_golf/mini_golf.dart';

/// A plain walled corridor, so physics assertions aren't at the mercy of a
/// generated layout.
MiniGolfCourse straight({
  double length = 16,
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

void main() {
  group('rolling', () {
    test('a putt rolls, decelerates and settles', () {
      final c = straight();
      final r = MiniGolfPutt.simulate(
        course: c,
        from: c.tee,
        direction: _up,
        power: 0.55,
      );
      expect(r.path.length, greaterThan(20), reason: 'no roll recorded');
      expect(r.displacement, greaterThan(2.0));
      expect(r.sunk, isFalse);
      expect(r.outOfBounds, isFalse);
      expect(r.has(PuttEventKind.launch), isTrue);
      expect(r.has(PuttEventKind.rest), isTrue);
      // Monotonic slow-down: the second half of the roll covers less ground
      // than the first.
      final mid = r.path.length ~/ 2;
      final first = _span(r, 0, mid);
      final second = _span(r, mid, r.path.length - 1);
      expect(second, lessThan(first));
    });

    test('full power rolls about as far as the design constant says', () {
      final c = straight(length: 24);
      final r = MiniGolfPutt.simulate(
        course: c,
        from: const Offset(0, 1),
        direction: _up,
        power: 1.0,
      );
      expect(
        r.displacement,
        closeTo(MiniGolfCourse.maxPuttReach, MiniGolfCourse.maxPuttReach * 0.15),
        reason: 'reach ${r.displacement} vs ${MiniGolfCourse.maxPuttReach}',
      );
    });

    test('power maps monotonically to distance', () {
      final c = straight(length: 24);
      var last = 0.0;
      for (final p in [0.2, 0.4, 0.6, 0.8, 1.0]) {
        final r = MiniGolfPutt.simulate(
          course: c,
          from: const Offset(0, 1),
          direction: _up,
          power: p,
        );
        expect(r.displacement, greaterThan(last));
        last = r.displacement;
      }
    });

    test('identical inputs replay identically', () {
      final c = straight();
      final a = MiniGolfPutt.simulate(
        course: c,
        from: c.tee,
        direction: const Offset(0.3, 0.95),
        power: 0.7,
      );
      final b = MiniGolfPutt.simulate(
        course: c,
        from: c.tee,
        direction: const Offset(0.3, 0.95),
        power: 0.7,
      );
      expect(a.path.length, b.path.length);
      expect(a.settled, b.settled);
      expect(a.events.map((e) => e.toString()).join(),
          b.events.map((e) => e.toString()).join());
    });
  });

  group('rails', () {
    test('the ball banks off a side rail and comes back', () {
      final c = straight(length: 20, halfWidth: 1.5);
      final r = MiniGolfPutt.simulate(
        course: c,
        from: const Offset(0, 1),
        // Hard into the right-hand rail.
        direction: const Offset(0.85, 0.53),
        power: 0.95,
      );
      expect(r.has(PuttEventKind.rail), isTrue, reason: 'never touched a rail');
      expect(r.outOfBounds, isFalse, reason: 'the rail let it through');
      // Lateral velocity reversed: the ball reaches the rail, then heads back.
      final maxX = r.path.map((s) => s.position.x).reduce(math.max);
      expect(maxX, greaterThan(1.0), reason: 'never reached the rail');
      expect(r.settled.dx, lessThan(maxX - 0.2),
          reason: 'it stuck to the rail instead of bouncing');
    });

    test('a hard putt into the end rail never leaves the green', () {
      final c = straight(length: 9, halfWidth: 1.5, cup: const Offset(1.2, 7.6));
      for (final angle in [-0.6, -0.3, 0.0, 0.3, 0.6]) {
        final r = MiniGolfPutt.simulate(
          course: c,
          from: const Offset(0, 1),
          direction: Offset(math.sin(angle), math.cos(angle)),
          power: 1.0,
        );
        expect(r.outOfBounds, isFalse, reason: 'angle $angle escaped');
        expect(c.containsWorld(r.settled), isTrue);
      }
    });

    test('the ball bounces off a solid', () {
      final c = MiniGolfCourse(
        archetype: MiniGolfArchetype.islandGreen,
        seed: 0,
        outline: const [
          Offset(-2, 0),
          Offset(2, 0),
          Offset(2, 14),
          Offset(-2, 14),
        ],
        obstacles: const [
          MiniGolfObstacle(
            left: -0.9,
            right: 0.9,
            near: 4,
            far: 5.8,
            round: true,
            laneGap: 1.1,
          ),
        ],
        tee: const Offset(0, 1),
        cup: const Offset(0, 12.5),
        routeLength: 12,
        minFairwayWidth: 4,
        par: 3,
      );
      final r = MiniGolfPutt.simulate(
        course: c,
        from: const Offset(0, 1),
        direction: _up,
        power: 0.9,
      );
      expect(r.has(PuttEventKind.obstacle), isTrue);
      expect(r.settled.dy, lessThan(5.0),
          reason: 'it went straight through the post');
    });
  });

  group('the cup', () {
    test('a slow ball over the cup drops in', () {
      final c = straight(length: 12, cup: const Offset(0, 4));
      var sank = 0;
      for (var i = 0; i <= 95; i++) {
        final power = 0.05 + i * 0.01;
        final r = MiniGolfPutt.simulate(
          course: c,
          from: const Offset(0, 1),
          direction: _up,
          power: power,
        );
        if (r.sunk) {
          sank++;
          expect(r.has(PuttEventKind.drop), isTrue);
          expect(r.settled, c.cup);
        }
      }
      expect(sank, greaterThan(0), reason: 'no power ever holed a 3-unit putt');
    });

    test('a fast ball lips out and rolls on', () {
      final c = straight(length: 20, cup: const Offset(0, 4));
      final r = MiniGolfPutt.simulate(
        course: c,
        from: const Offset(0, 1),
        direction: _up,
        power: 1.0,
      );
      expect(r.sunk, isFalse, reason: 'a full-blooded putt should not drop');
      expect(r.has(PuttEventKind.lipOut), isTrue);
      expect(r.settled.dy, greaterThan(5.0), reason: 'it should carry past');
    });

    test('the drop is a descending pass through the cup mouth', () {
      final c = straight(length: 12, cup: const Offset(0, 2.2));
      final r = MiniGolfPutt.simulate(
        course: c,
        from: const Offset(0, 1),
        direction: _up,
        power: 0.16,
      );
      expect(r.sunk, isTrue);
      // The recorded path really falls: the last sample sits below the green.
      expect(r.path.last.position.y, lessThan(0));
      final drop = r.events.firstWhere((e) => e.kind == PuttEventKind.drop);
      final sink = r.events.firstWhere((e) => e.kind == PuttEventKind.sink);
      expect(drop.sample, lessThanOrEqualTo(sink.sample));
    });

    test('a putt that misses the cup keeps rolling', () {
      final c = straight(length: 14, cup: const Offset(1.1, 5));
      final r = MiniGolfPutt.simulate(
        course: c,
        from: const Offset(-1.0, 1),
        direction: _up,
        power: 0.5,
      );
      expect(r.sunk, isFalse);
      expect(r.settled.dy, greaterThan(3.0));
    });
  });

  group('generated holes', () {
    test('no ordinary putt on a generated hole ends out of bounds', () {
      for (var base = 0; base < 6; base++) {
        for (var h = 0; h < 9; h++) {
          final c = MiniGolfCourse.forHole(base, h);
          for (var a = 0; a < 8; a++) {
            final angle = -1.1 + a * 0.31;
            final r = MiniGolfPutt.simulate(
              course: c,
              from: c.tee,
              direction: Offset(math.sin(angle), math.cos(angle)),
              power: 0.55 + 0.05 * a,
            );
            expect(r.outOfBounds, isFalse,
                reason: '${c.archetype.name} base $base hole $h angle $a');
            expect(r.path.length, greaterThan(4));
          }
        }
      }
    });

    test('holes really do take more than one putt', () {
      // Fire the best putt available straight at the cup from the tee on every
      // hole of a course: none of them should hole out, because every hole is
      // longer than a putt's reach.
      for (var base = 0; base < 8; base++) {
        for (var h = 0; h < 9; h++) {
          final c = MiniGolfCourse.forHole(base, h);
          final to = c.cup - c.tee;
          final r = MiniGolfPutt.simulate(
            course: c,
            from: c.tee,
            direction: to / to.distance,
            power: 1.0,
          );
          expect(r.sunk, isFalse,
              reason: '${c.archetype.name} base $base hole $h is a one-putt');
        }
      }
    });

    test('the simulator agrees with the reach constant used to set par', () {
      final c = straight(length: 26);
      final r = MiniGolfPutt.simulate(
        course: c,
        from: const Offset(0, 1),
        direction: _up,
        power: 1.0,
      );
      expect(r.rollDistance,
          closeTo(MiniGolfCourse.maxPuttReach, MiniGolfCourse.maxPuttReach * 0.2));
    });
  });
}

double _span(PuttResult r, int from, int to) {
  var d = 0.0;
  for (var i = from + 1; i <= to; i++) {
    final a = r.path[i - 1].position;
    final b = r.path[i].position;
    d += math.sqrt((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z));
  }
  return d;
}
