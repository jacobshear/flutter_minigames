import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:minigames_3d/minigames_3d.dart';

import 'mini_golf_course.dart';

/// World layout constants for the 3-D mini-golf scene.
///
/// The green lies on the ground plane `y == 0`; the ball rolls with its centre
/// one radius above it. Course geometry is `(x, z)` — see [MiniGolfCourse] —
/// and this class is the only place those pairs become [Vec3]s.
///
/// The camera lives in `mini_golf_camera.dart`; this file deliberately knows
/// nothing about it, so the rig can depend on the world and not the other way
/// round.
class MiniGolfWorld {
  const MiniGolfWorld._();

  /// The putting surface.
  static const double groundY = 0;

  /// Height of the ball's centre while it rolls.
  static const double ballY = MiniGolfCourse.ballRadius;

  /// How far the flagstick stands above the green.
  static const double flagHeight = 1.35;

  /// Vertical field of view.
  ///
  /// **Fixed, always.** Zoom is done by dollying the eye (see
  /// [MiniGolfCamera]); animating the field of view warps the perspective and
  /// is the classic way to make a follow camera nauseating.
  static const double fovY = 0.95;

  /// A world point from a course `(x, z)` pair at height [y].
  static Vec3 at(Offset xz, [double y = groundY]) => Vec3(xz.dx, y, xz.dy);

  /// How deep the cup is below the green.
  ///
  /// Shallower than a real one on purpose. The camera looks down the hole at a
  /// fairly flat angle, and anything more than about two ball widths deep is
  /// hidden behind the near lip entirely — the ball would drop out of sight and
  /// the moment would be over before you saw it land. At this depth the ball
  /// falls a clear two-and-a-half times its own height and still comes to rest
  /// where you can see it nestled in the bottom.
  static const double cupDepth = 0.30;

  /// Where a holed ball comes to rest: sitting on the bottom of the cup.
  static const double cupRestY = -(cupDepth - MiniGolfCourse.ballRadius);

  /// The rolling ball's centre for a course `(x, z)` pair.
  static Vec3 ballAt(Offset xz) => Vec3(xz.dx, ballY, xz.dy);
}

/// A ball's 3-D orientation: the images of its local axes after rolling.
///
/// A ball that only translates reads as *sliding*. A real one turns about the
/// axis perpendicular to its travel by `distance / radius`, so its markings
/// sweep across the visible face and round off the rim — which is the whole
/// difference between a putt and a puck. The simulator integrates this from the
/// recorded motion and the painter draws the markings through it.
class BallRoll {
  /// Images of the ball's local X / Y / Z axes, in world space.
  final Vec3 ax;
  final Vec3 ay;
  final Vec3 az;

  const BallRoll({required this.ax, required this.ay, required this.az});

  /// Unrolled: local axes still aligned with the world.
  static const identity = BallRoll(
    ax: Vec3(1, 0, 0),
    ay: Vec3(0, 1, 0),
    az: Vec3(0, 0, 1),
  );

  /// The orientation after rolling ([dx], [dz]) along the ground with the given
  /// [radius] (same units).
  ///
  /// Rolling along d̂ turns the ball about `up × d̂`, which for a ground-plane
  /// travel of `(dx, 0, dz)` is `(dz, 0, -dx)`, by `distance / radius` — so the
  /// face pointing at the viewer travels forward over the top.
  BallRoll rolled(double dx, double dz, double radius) {
    final dist = math.sqrt(dx * dx + dz * dz);
    if (dist < 1e-9 || radius <= 0) return this;
    final kx = dz / dist;
    final kz = -dx / dist;
    final angle = dist / radius;
    return BallRoll(
      ax: _rodrigues(ax, kx, kz, angle),
      ay: _rodrigues(ay, kx, kz, angle),
      az: _rodrigues(az, kx, kz, angle),
    );
  }

  /// Rotate [v] about the horizontal unit axis ([kx], 0, [kz]) by [angle].
  static Vec3 _rodrigues(Vec3 v, double kx, double kz, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    // k × v, with k.y == 0.
    final cx = -kz * v.y;
    final cy = kz * v.x - kx * v.z;
    final cz = kx * v.y;
    final dot = kx * v.x + kz * v.z; // k · v
    return Vec3(
      v.x * c + cx * s + kx * dot * (1 - c),
      v.y * c + cy * s,
      v.z * c + cz * s + kz * dot * (1 - c),
    );
  }
}
