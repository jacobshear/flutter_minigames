import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_shuffleboard/minigame_shuffleboard.dart';

/// Presentation-layer behaviour: the parts of "feel" that are assertable
/// without a running Flame loop — how a sliding puck accumulates spin, and how
/// a puck tips over a lip and falls off the table.
void main() {
  group('SlideSpin', () {
    test('accumulates with distance travelled, not with number of steps', () {
      final a = SlideSpin('p1-0');
      // One 2-unit hop.
      a.advance(2, 0, 0.5);
      final oneHop = a.angle.abs();

      final b = SlideSpin('p1-0');
      // Same 2 units, taken in twenty small steps.
      for (var i = 0; i < 20; i++) {
        b.advance(0.1, 0, 0.5);
      }
      expect(b.angle.abs(), closeTo(oneHop, 1e-9));
      expect(oneHop, closeTo(2 / 0.5 * SlideSpin.turnsPerRadius, 1e-9));
    });

    test('grows monotonically with further travel', () {
      final s = SlideSpin('p1-0');
      var last = 0.0;
      for (var i = 0; i < 8; i++) {
        s.advance(0.4, 0.3, 0.44); // 0.5 units per step
        expect(s.angle.abs(), greaterThan(last));
        last = s.angle.abs();
      }
      // 8 steps x 0.5 units on a 0.44 radius.
      expect(last, closeTo(4 / 0.44 * SlideSpin.turnsPerRadius, 1e-9));
    });

    test('a puck that has not moved does not turn', () {
      final s = SlideSpin('p1-0');
      s.advance(0, 0, 0.44);
      expect(s.angle, 0);
    });

    test('direction is stable per puck, and pucks differ', () {
      final a = SlideSpin('p1-0')..advance(1, 0, 0.5);
      final b = SlideSpin('p1-0')..advance(1, 0, 0.5);
      expect(a.angle, b.angle, reason: 'same id must turn the same way');
      final ids = ['p1-0', 'p1-1', 'p1-2', 'p2-0', 'p2-1', 'p2-2'];
      final signs = {
        for (final id in ids) (SlideSpin(id)..advance(1, 0, 0.5)).angle.sign,
      };
      expect(signs.length, 2, reason: 'not every puck turns the same way');
    });
  });

  group('fall off a lip', () {
    FallingPuck at(double p, {double carry = 0, FallEdge edge = FallEdge.top}) =>
        shuffleboardFallFrame(
          edge: edge,
          along: 0.5,
          carry: carry,
          exit: 0.6,
          spinDir: 1,
          spin0: 0,
          color: const Color(0xFFD8443C),
          radiusFrac: 0.44 / 6,
          progress: p,
          aspect: 6 / 13,
        );

    test('starts on the lip, round and fully opaque', () {
      final f = at(0);
      expect(f.ny.abs(), lessThan(0.01), reason: 'centre sits on the lip');
      expect(f.squashY, closeTo(1, 0.02), reason: 'not yet tipped');
      expect(f.scale, closeTo(1, 0.001));
      expect(f.alpha, 1);
      expect(f.rim, lessThan(0.05));
    });

    test('runs for its whole duration — still drawn at the last frame', () {
      // Anything that vanishes early reads as a pop, not a fall.
      for (final p in [0.2, 0.4, 0.6, 0.8, 0.95, 0.99]) {
        expect(at(p).alpha, greaterThan(0.0),
            reason: 'puck must still be visible at progress $p');
      }
      expect(at(1).alpha, closeTo(0, 1e-9));
      expect(kShuffleboardFallDuration, greaterThan(0.5));
    });

    test('travels off the edge and never comes back', () {
      var prev = double.negativeInfinity;
      for (var i = 0; i <= 20; i++) {
        final f = at(i / 20);
        final out = -f.ny; // distance past the far lip
        expect(out, greaterThanOrEqualTo(prev - 1e-12),
            reason: 'the fall must not retreat toward the lane');
        prev = out;
      }
      expect(prev, greaterThan(0.05), reason: 'it has to actually clear');
    });

    test('shrinks and darkens as it falls away', () {
      expect(at(1).scale, lessThan(at(0.4).scale));
      expect(at(0.4).scale, lessThanOrEqualTo(at(0).scale));
      final start = at(0).color.computeLuminance();
      final end = at(1).color.computeLuminance();
      expect(end, lessThan(start));
    });

    test('tips: the side wall comes into view, then the face reopens', () {
      final mid = at(0.32); // end of the tip phase
      expect(mid.squashY, lessThan(0.45), reason: 'foreshortened over the lip');
      expect(mid.rim, greaterThan(0.5), reason: 'edge turned toward us');
      expect(mid.rimDy, -1, reason: 'side wall on the far side of the lip');
      // Having tumbled past edge-on, the other face opens back up.
      expect(at(0.9).squashY, greaterThan(mid.squashY));
    });

    test('carries the lateral momentum it left with', () {
      // Same shot, one with sideways speed along the lip and one without.
      var prev = 0.5;
      for (var i = 1; i <= 10; i++) {
        final f = at(i / 10, carry: 0.8);
        expect(f.nx, greaterThan(prev), reason: 'keeps sliding along the lip');
        prev = f.nx;
      }
      expect(prev, greaterThan(0.5));
      for (var i = 0; i <= 10; i++) {
        expect(at(i / 10).nx, closeTo(0.5, 1e-9),
            reason: 'no sideways speed => straight off the lip');
      }
      // Momentum has a direction: the opposite sign goes the other way.
      expect(at(1, carry: -0.8).nx, lessThan(0.5));
    });

    test('keeps turning all the way down', () {
      var prev = double.negativeInfinity;
      for (var i = 0; i <= 10; i++) {
        final spin = at(i / 10).spin;
        expect(spin, greaterThanOrEqualTo(prev));
        prev = spin;
      }
      expect(prev, greaterThan(1.5), reason: 'a visible tumble, not a nudge');
    });

    test('each lip sends the puck out its own side', () {
      expect(at(1, edge: FallEdge.top).ny, lessThan(0));
      expect(at(1, edge: FallEdge.left).nx, lessThan(0));
      expect(at(1, edge: FallEdge.right).nx, greaterThan(1));
      // A side fall foreshortens across, not down-lane.
      expect(at(0.32, edge: FallEdge.left).squashX, lessThan(0.45));
      expect(at(0.32, edge: FallEdge.left).squashY, 1);
    });
  });
}
