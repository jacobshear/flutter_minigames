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

  /// The rolling ball's centre for a course `(x, z)` pair.
  static Vec3 ballAt(Offset xz) => Vec3(xz.dx, ballY, xz.dy);
}
