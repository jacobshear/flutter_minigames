import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show Vector2;
import 'package:flutter_minigames/src/flame/flame.dart';

void main() {
  group('TableSimulation (headless)', () {
    test('a launched disc moves then settles within the budget', () {
      final sim = TableSimulation(
        config: const TableSimConfig(maxSteps: 1400),
      );
      // Long narrow table, y-down, far end (top) left open.
      final bounds = const Rect.fromLTRB(-3, 0, 3, 13);
      sim.addBounds(bounds, top: false);

      final disc = sim.addDisc(
        id: 'p1-0',
        position: Vector2(0, 11),
        radius: 0.42,
      );
      final start = disc.position.clone();

      var fired = false;
      SimOutcome? viaCallback;
      sim.onSettled = (o) {
        fired = true;
        viaCallback = o;
      };

      // Push it up-table (toward the far/open end).
      sim.launch(disc, Vector2(0, -14));
      expect(sim.isRunning, isTrue);

      final outcome = sim.runUntilSettled();

      expect(sim.isRunning, isFalse, reason: 'run should end');
      expect(fired, isTrue, reason: 'onSettled callback fires exactly once');
      expect(outcome.timedOut, isFalse, reason: 'should rest, not time out');
      expect(outcome.steps, greaterThan(0));
      expect(outcome.steps, lessThan(1400));

      final settled = outcome['p1-0']!;
      final travelled = (Vector2(settled.x, settled.y) - start).length;
      expect(travelled, greaterThan(1.0), reason: 'disc must have moved');

      // Callback outcome matches the returned one.
      expect(viaCallback!['p1-0']!.y, closeTo(settled.y, 1e-9));
    });

    test('a disc that slides off the open end is removed', () {
      final sim = TableSimulation(
        // Off the far (top) edge => removed.
        shouldRemove: (d) => d.position.y < 0,
      );
      sim.addBounds(const Rect.fromLTRB(-3, 0, 3, 13), top: false);
      final disc = sim.addDisc(
        id: 'runaway',
        position: Vector2(0, 4),
        radius: 0.42,
      );
      // Hard shove straight off the open end.
      sim.launch(disc, Vector2(0, -60));
      final outcome = sim.runUntilSettled();

      expect(disc.removed, isTrue);
      expect(outcome['runaway']!.removed, isTrue);
    });

    test('a moving disc knocks a resting disc (collision fires)', () {
      final sim = TableSimulation();
      sim.addBounds(const Rect.fromLTRB(-3, 0, 3, 13));

      final shooter = sim.addDisc(
        id: 'a',
        position: Vector2(0, 10),
        radius: 0.42,
      );
      final target = sim.addDisc(
        id: 'b',
        position: Vector2(0, 6),
        radius: 0.42,
      );
      final targetStart = target.position.clone();

      var collisions = 0;
      sim.onDiscCollision = (_, __) => collisions++;

      sim.launch(shooter, Vector2(0, -16));
      final outcome = sim.runUntilSettled();

      expect(collisions, greaterThan(0), reason: 'discs should touch');
      final targetEnd = outcome['b']!;
      final moved = (Vector2(targetEnd.x, targetEnd.y) - targetStart).length;
      expect(moved, greaterThan(0.3), reason: 'target should be knocked along');
    });

    test('outcome round-trips through JSON', () {
      final sim = TableSimulation();
      sim.addBounds(const Rect.fromLTRB(-3, 0, 3, 13));
      final disc = sim.addDisc(id: 'x', position: Vector2(1, 8), radius: 0.4);
      sim.launch(disc, Vector2(-3, -5));
      final outcome = sim.runUntilSettled();

      final restored = SimOutcome.fromJson(
        Map<String, dynamic>.from(outcome.toJson()),
      );
      expect(restored.bodies.length, outcome.bodies.length);
      expect(restored['x']!.x, closeTo(outcome['x']!.x, 1e-9));
      expect(restored['x']!.y, closeTo(outcome['x']!.y, 1e-9));
      expect(restored.timedOut, outcome.timedOut);
    });
  });

  group('AimToImpulse', () {
    test('slingshot: impulse points opposite the drag, capped', () {
      const aim = AimToImpulse(maxDrag: 200, maxImpulse: 20, minImpulse: 4);
      // Drag down-right => launch up-left.
      final imp = aim.impulse(Vector2(100, 100));
      expect(imp.x, lessThan(0));
      expect(imp.y, lessThan(0));
      // Huge drag saturates at the cap.
      final capped = aim.impulse(Vector2(0, 5000));
      expect(capped.length, closeTo(20, 1e-6));
    });

    test('dead zone swallows tiny drags', () {
      const aim = AimToImpulse(deadZone: 10);
      expect(aim.impulse(Vector2(3, 3)).length, 0);
      expect(aim.power01(Vector2(3, 3)), 0);
    });

    test('power01 climbs from 0 to 1 across the drag range', () {
      const aim = AimToImpulse(maxDrag: 100, deadZone: 0);
      expect(aim.power01(Vector2(0, 0)), 0);
      expect(aim.power01(Vector2(50, 0)), closeTo(0.5, 1e-9));
      expect(aim.power01(Vector2(999, 0)), 1);
    });
  });

  group('SettleDetector', () {
    test('needs consecutive calm frames, fires once', () {
      final d = SettleDetector(framesRequired: 3, maxSteps: 100);
      expect(d.step(calm: true), isFalse);
      expect(d.step(calm: false), isFalse); // resets the streak
      expect(d.step(calm: true), isFalse);
      expect(d.step(calm: true), isFalse);
      expect(d.step(calm: true), isTrue); // 3 in a row
      expect(d.step(calm: true), isFalse); // already done
      expect(d.isSettled, isTrue);
      expect(d.timedOut, isFalse);
    });

    test('times out under a never-calm sim', () {
      final d = SettleDetector(framesRequired: 5, maxSteps: 10);
      for (var i = 0; i < 9; i++) {
        expect(d.step(calm: false), isFalse);
      }
      expect(d.step(calm: false), isTrue);
      expect(d.timedOut, isTrue);
    });
  });
}
