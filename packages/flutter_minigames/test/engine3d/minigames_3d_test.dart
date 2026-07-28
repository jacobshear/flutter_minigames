import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/engine3d/engine3d.dart';

const viewport = Size(400, 700);

Camera3 cam({double pitch = 0.18}) => Camera3(
      eye: const Vec3(0, 1.5, -2),
      viewport: viewport,
      pitch: pitch,
    );

void main() {
  group('Camera3 projection', () {
    test('a point straight ahead lands on the centre line', () {
      final c = Camera3(eye: const Vec3(0, 1, 0), viewport: viewport, pitch: 0);
      final p = c.project(const Vec3(0, 1, 10));
      expect(p.visible, isTrue);
      expect(p.screen.dx, closeTo(viewport.width / 2, 0.001));
      expect(p.screen.dy, closeTo(viewport.height / 2, 0.001));
    });

    test('further things are smaller and deeper', () {
      final c = cam();
      final near = c.project(const Vec3(0, 1, 4));
      final far = c.project(const Vec3(0, 1, 12));
      expect(far.depth, greaterThan(near.depth));
      expect(far.scale, lessThan(near.scale));
      // A ball of fixed world size shrinks with distance — the core depth cue.
      expect(far.scale / near.scale, lessThan(0.5));
    });

    test('points behind the camera are not visible', () {
      expect(cam().project(const Vec3(0, 1.5, -10)).visible, isFalse);
    });

    test('world +x projects to the right, world +y projects upward', () {
      final c = Camera3(eye: const Vec3(0, 1, 0), viewport: viewport, pitch: 0);
      final right = c.project(const Vec3(2, 1, 10));
      final up = c.project(const Vec3(0, 3, 10));
      expect(right.screen.dx, greaterThan(viewport.width / 2));
      expect(up.screen.dy, lessThan(viewport.height / 2)); // screen y is down
    });

    test('pitching down brings distant ground up toward the centre', () {
      final level =
          Camera3(eye: const Vec3(0, 1.5, 0), viewport: viewport, pitch: 0);
      final tilted =
          Camera3(eye: const Vec3(0, 1.5, 0), viewport: viewport, pitch: 0.35);
      const far = Vec3(0, 0, 40); // a distant point on the floor
      expect(tilted.project(far).screen.dy,
          lessThan(level.project(far).screen.dy));
    });

    test('screenToGround inverts a floor point back to itself', () {
      final c = cam();
      const ground = Vec3(1.2, 0, 9);
      final p = c.project(ground);
      final back = c.screenToGround(p.screen, planeY: 0);
      expect(back, isNotNull);
      expect(back!.x, closeTo(ground.x, 0.001));
      expect(back.z, closeTo(ground.z, 0.001));
    });

    test('screenToGround returns null above the horizon', () {
      final c = cam(pitch: 0.18);
      // Well above the horizon line: the ray never meets the floor.
      expect(c.screenToGround(Offset(200, c.horizonY - 40)), isNull);
    });
  });

  group('Projectile', () {
    test('a lobbed ball rises, peaks, then falls', () {
      final p = Projectile(
        position: const Vec3(0, 1, 0),
        velocity: const Vec3(0, 8, 9),
      );
      var peak = p.position.y;
      var rising = true;
      var everFell = false;
      for (var i = 0; i < 400; i++) {
        final prevY = p.position.y;
        p.step();
        if (p.position.y > peak) peak = p.position.y;
        if (rising && p.position.y < prevY) rising = false;
        if (!rising && p.position.y < prevY) everFell = true;
      }
      expect(peak, greaterThan(1.5), reason: 'should have risen');
      expect(everFell, isTrue, reason: 'gravity should bring it down');
      expect(p.position.z, greaterThan(0), reason: 'travels down-range');
    });

    test('is deterministic for the same launch', () {
      List<double> run() {
        final p = Projectile(
          position: const Vec3(0, 1, 0),
          velocity: const Vec3(0.4, 7, 10),
        );
        return [
          for (var i = 0; i < 120; i++) ...[
            (p..step()).position.y,
          ],
        ];
      }

      expect(run(), run());
    });

    test('bounce reflects the normal component and keeps it moving', () {
      final p = Projectile(
        position: const Vec3(0, 0.2, 5),
        velocity: const Vec3(1, -6, 2),
      );
      p.bounce(const Vec3(0, 1, 0), restitution: 0.5);
      expect(p.velocity.y, greaterThan(0), reason: 'now moving up');
      expect(p.velocity.y, lessThan(6 * 0.5 + 0.001));
      expect(p.velocity.z, greaterThan(0), reason: 'keeps travelling forward');
    });

    test('bounce ignores a surface it is already leaving', () {
      final p = Projectile(
        position: const Vec3(0, 1, 5),
        velocity: const Vec3(0, 3, 2),
      );
      p.bounce(const Vec3(0, 1, 0));
      expect(p.velocity.y, 3);
    });
  });

  group('ThrowAim', () {
    const aim = ThrowAim();

    test('a flick up-screen throws down-range and upward', () {
      final v = aim.launch(0, -200);
      expect(v, isNotNull);
      expect(v!.z, greaterThan(0), reason: 'into the screen');
      expect(v.y, greaterThan(0), reason: 'lofted');
      expect(v.x, closeTo(0, 1e-9), reason: 'straight flick, no steer');
    });

    test('a diagonal flick steers laterally', () {
      final right = aim.launch(120, -200)!;
      final left = aim.launch(-120, -200)!;
      expect(right.x, greaterThan(0));
      expect(left.x, lessThan(0));
      expect(right.z, greaterThan(0));
    });

    test('a longer flick throws harder and flatter', () {
      final soft = aim.launch(0, -80)!;
      final hard = aim.launch(0, -260)!;
      expect(hard.length, greaterThan(soft.length));
      // Flatter = a smaller share of the speed goes upward.
      expect(hard.y / hard.length, lessThan(soft.y / soft.length));
    });

    test('tiny flicks and backwards swipes do not throw', () {
      expect(aim.launch(2, -3), isNull);
      expect(aim.launch(0, 200), isNull, reason: 'down-screen is not a throw');
    });

    test('power saturates at 1', () {
      expect(aim.power(0, -1000), 1.0);
      expect(aim.power(0, -260), closeTo(1.0, 1e-9));
    });
  });

  group('Surfaces', () {
    test('a descending ball through a disc counts, a rising one does not', () {
      const centre = Vec3(0, 3, 10);
      expect(
        Surfaces.passesDownThroughDisc(
            const Vec3(0, 3.4, 10), const Vec3(0, 2.6, 10), centre, 0.35),
        isTrue,
      );
      expect(
        Surfaces.passesDownThroughDisc(
            const Vec3(0, 2.6, 10), const Vec3(0, 3.4, 10), centre, 0.35),
        isFalse,
        reason: 'up through the hoop is not a basket',
      );
    });

    test('a descending ball outside the disc misses', () {
      const centre = Vec3(0, 3, 10);
      expect(
        Surfaces.passesDownThroughDisc(
            const Vec3(1.2, 3.4, 10), const Vec3(1.2, 2.6, 10), centre, 0.35),
        isFalse,
      );
    });

    test('a fast ball cannot tunnel through the disc in one step', () {
      const centre = Vec3(0, 3, 10);
      expect(
        Surfaces.passesDownThroughDisc(
            const Vec3(0, 8, 10), const Vec3(0, -2, 10), centre, 0.35),
        isTrue,
      );
    });

    test('rim contact returns a unit outward normal', () {
      const centre = Vec3(0, 3, 10);
      final n = Surfaces.rimContact(
          const Vec3(0.45, 3, 10), 0.12, centre, 0.45, 0.03);
      expect(n, isNotNull);
      expect(n!.length, closeTo(1, 1e-9));
      // Dead centre and well clear of the ring: no contact.
      expect(
        Surfaces.rimContact(const Vec3(0, 3, 10), 0.12, centre, 0.45, 0.03),
        isNull,
      );
    });

    test('backboard is struck only when travelling away from the viewer', () {
      expect(
        Surfaces.backboardCrossing(
            const Vec3(0, 3, 9.5), const Vec3(0, 3, 10.5), 10, -1, 1, 2, 4),
        isNotNull,
      );
      expect(
        Surfaces.backboardCrossing(
            const Vec3(0, 3, 10.5), const Vec3(0, 3, 9.5), 10, -1, 1, 2, 4),
        isNull,
      );
      expect(
        Surfaces.backboardCrossing(
            const Vec3(5, 3, 9.5), const Vec3(5, 3, 10.5), 10, -1, 1, 2, 4),
        isNull,
        reason: 'off the edge of the board',
      );
    });

    test('cylinder wall contact points away from the axis', () {
      final n = Surfaces.cylinderWallContact(
          const Vec3(0.3, 0.1, 10), 0.05, 0, 10, 0.28, 0, 0.3);
      expect(n, isNotNull);
      expect(n!.x, greaterThan(0));
      expect(n.y, 0, reason: 'wall normals are horizontal');
      expect(
        Surfaces.cylinderWallContact(
            const Vec3(2, 0.1, 10), 0.05, 0, 10, 0.28, 0, 0.3),
        isNull,
      );
    });
  });

  test('end to end: a tuned lob drops through a hoop', () {
    const hoop = Vec3(0, 3.05, 9);
    const radius = 0.45;
    var made = false;
    for (var speed = 9.0; speed <= 16.0 && !made; speed += 0.1) {
      const loft = 0.85;
      final p = Projectile(
        position: const Vec3(0, 1.6, 0),
        velocity: Vec3(0, speed * math.sin(loft), speed * math.cos(loft)),
      );
      for (var i = 0; i < 900; i++) {
        final from = p.step();
        if (Surfaces.passesDownThroughDisc(from, p.position, hoop, radius)) {
          made = true;
          break;
        }
        if (p.position.y < -1) break;
      }
    }
    expect(made, isTrue, reason: 'some sane launch must be able to score');
  });
}
