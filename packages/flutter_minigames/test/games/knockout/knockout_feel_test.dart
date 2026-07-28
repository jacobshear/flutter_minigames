import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/knockout/knockout.dart';

/// Presentation-layer behaviour: the parts of "feel" that are assertable
/// without a running Flame loop — how a sliding puck accumulates spin, and how
/// a puck tips over a lip and falls into the void. Knocking pucks off is the
/// whole game, so the fall gets the most coverage here.
void main() {
  group('KnockoutSlideSpin', () {
    test('accumulates with distance travelled, not with number of steps', () {
      final a = KnockoutSlideSpin('p1-0')..advance(2, 0, 0.5);
      final b = KnockoutSlideSpin('p1-0');
      for (var i = 0; i < 20; i++) {
        b.advance(0.1, 0, 0.5);
      }
      expect(b.angle.abs(), closeTo(a.angle.abs(), 1e-9));
      expect(a.angle.abs(),
          closeTo(2 / 0.5 * KnockoutSlideSpin.turnsPerRadius, 1e-9));
    });

    test('grows monotonically with further travel', () {
      final s = KnockoutSlideSpin('p1-0');
      var last = 0.0;
      for (var i = 0; i < 8; i++) {
        s.advance(0.4, 0.3, 0.5); // 0.5 units per step
        expect(s.angle.abs(), greaterThan(last));
        last = s.angle.abs();
      }
      expect(last, closeTo(4 / 0.5 * KnockoutSlideSpin.turnsPerRadius, 1e-9));
    });

    test('a puck that has not moved does not turn', () {
      final s = KnockoutSlideSpin('p1-0')..advance(0, 0, 0.5);
      expect(s.angle, 0);
    });

    test('direction is stable per puck, and pucks differ', () {
      final ids = ['p1-0', 'p1-1', 'p1-2', 'p2-0', 'p2-1', 'p2-2'];
      final signs = {
        for (final id in ids)
          (KnockoutSlideSpin(id)..advance(1, 0, 0.5)).angle.sign,
      };
      expect(signs.length, 2, reason: 'not every puck turns the same way');
    });
  });

  group('fall off a lip', () {
    KnockoutFallingPuck at(double p,
            {double carry = 0, KnockoutFallEdge edge = KnockoutFallEdge.top}) =>
        knockoutFallFrame(
          edge: edge,
          along: 0.5,
          carry: carry,
          exit: 0.6,
          spinDir: 1,
          spin0: 0,
          color: const Color(0xFF3E7BFA),
          radiusFrac: 0.5 / 10,
          progress: p,
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
      for (final p in [0.2, 0.4, 0.6, 0.8, 0.95, 0.99]) {
        expect(at(p).alpha, greaterThan(0.0),
            reason: 'puck must still be visible at progress $p');
      }
      expect(at(1).alpha, closeTo(0, 1e-9));
      expect(kKnockoutFallDuration, greaterThan(0.5));
    });

    test('travels off the edge and never comes back', () {
      var prev = double.negativeInfinity;
      for (var i = 0; i <= 20; i++) {
        final out = -at(i / 20).ny;
        expect(out, greaterThanOrEqualTo(prev - 1e-12),
            reason: 'the fall must not retreat toward the slab');
        prev = out;
      }
      expect(prev, greaterThan(0.05), reason: 'it has to actually clear');
    });

    test('shrinks and darkens as it drops into the void', () {
      expect(at(1).scale, lessThan(at(0.4).scale));
      expect(at(0.4).scale, lessThanOrEqualTo(at(0).scale));
      expect(at(1).color.computeLuminance(),
          lessThan(at(0).color.computeLuminance()));
    });

    test('tips: the side wall comes into view, then the face reopens', () {
      final mid = at(0.30); // end of the tip phase
      expect(mid.squashY, lessThan(0.45), reason: 'foreshortened over the lip');
      expect(mid.rim, greaterThan(0.5), reason: 'edge turned toward us');
      expect(mid.rimDy, -1, reason: 'side wall on the far side of the lip');
      expect(at(0.9).squashY, greaterThan(mid.squashY));
    });

    test('carries the lateral momentum it left with', () {
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
      expect(at(1, carry: -0.8).nx, lessThan(0.5));
    });

    test('a harder knock-off carries further out', () {
      double out(double exit) => -knockoutFallFrame(
            edge: KnockoutFallEdge.top,
            along: 0.5,
            carry: 0,
            exit: exit,
            spinDir: 1,
            spin0: 0,
            color: const Color(0xFF3E7BFA),
            radiusFrac: 0.5 / 10,
            progress: 1,
          ).ny;
      expect(out(1.2), greaterThan(out(0.2)));
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
      expect(at(1, edge: KnockoutFallEdge.top).ny, lessThan(0));
      expect(at(1, edge: KnockoutFallEdge.bottom).ny, greaterThan(1));
      expect(at(1, edge: KnockoutFallEdge.left).nx, lessThan(0));
      expect(at(1, edge: KnockoutFallEdge.right).nx, greaterThan(1));
      expect(at(0.30, edge: KnockoutFallEdge.left).squashX, lessThan(0.45));
      expect(at(0.30, edge: KnockoutFallEdge.left).squashY, 1);
    });
  });

  group('a puck knocked off is eliminated exactly once', () {
    const game = KnockoutGame(pucksPerPlayer: 3);
    KnockoutState fresh() =>
        game.initialState(seed: 0, playerIds: const ['p1', 'p2']);

    test('one fallen opponent puck: one elimination, counted once', () {
      final before = fresh();
      final move = KnockoutMove(
        flickedPuckId: 'p1-0',
        owner: 'p1',
        positions: [
          for (final p in before.pucks)
            KnockoutPosition(
              id: p.id,
              owner: p.owner,
              nx: p.nx,
              ny: p.ny,
              fell: p.id == 'p2-1',
            ),
        ],
      );
      expect(game.validateMove(before, move, 'p1'), isTrue);
      final result = game.classifyShot(before, move);
      expect(result.oppKnocked, 1);
      expect(result.ownLost, 0);

      final after = game.applyMove(before, move);
      expect(after.liveCountOf('p2'), before.liveCountOf('p2') - 1);
      expect(after.liveCountOf('p1'), before.liveCountOf('p1'));
      expect(after.pucks.where((p) => p.id == 'p2-1'), isEmpty);
      // And it cannot be knocked off a second time: it is no longer reportable.
      final replay = KnockoutMove(
        flickedPuckId: 'p2-0',
        owner: 'p2',
        positions: [
          ...[
            for (final p in after.pucks)
              KnockoutPosition(
                  id: p.id, owner: p.owner, nx: p.nx, ny: p.ny, fell: false),
          ],
          const KnockoutPosition(
              id: 'p2-1', owner: 'p2', nx: 0.5, ny: 0.5, fell: true),
        ],
      );
      expect(game.validateMove(after, replay, 'p2'), isFalse,
          reason: 'a dead puck cannot be reported as falling again');
    });

    test('a flick that takes one of each counts each side once', () {
      final before = fresh();
      final move = KnockoutMove(
        flickedPuckId: 'p1-0',
        owner: 'p1',
        positions: [
          for (final p in before.pucks)
            KnockoutPosition(
              id: p.id,
              owner: p.owner,
              nx: p.nx,
              ny: p.ny,
              fell: p.id == 'p2-0' || p.id == 'p1-2',
            ),
        ],
      );
      final result = game.classifyShot(before, move);
      expect(result.oppKnocked, 1);
      expect(result.ownLost, 1);
      final after = game.applyMove(before, move);
      expect(after.liveCountOf('p1'), 2);
      expect(after.liveCountOf('p2'), 2);
    });
  });
}
