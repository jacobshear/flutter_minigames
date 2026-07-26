import 'dart:math' as math;
import 'dart:ui' show Offset, Path, Size;

import 'vec3.dart';

/// A point projected into screen space, with the depth cues a painter needs.
class Projected {
  /// Position on the canvas, in pixels.
  final Offset screen;

  /// Distance in front of the camera (camera-space z). Larger = further away.
  /// Sort descending by this to paint back-to-front.
  final double depth;

  /// Pixels per world unit at this depth. Multiply a world radius by this to
  /// get its on-screen radius — this is what makes far things small.
  final double scale;

  /// False when the point is behind (or too near) the camera and must not be
  /// drawn; [screen] is meaningless in that case.
  final bool visible;

  const Projected({
    required this.screen,
    required this.depth,
    required this.scale,
    required this.visible,
  });
}

/// A pinhole camera looking down-range (+z) from [eye], pitched [pitch] radians
/// downward, with vertical field of view [fovY].
///
/// This is the whole "3-D engine": a projection. Games hold world-space state
/// (a ball at (x, y, z), cups on the floor plane) and ask the camera where each
/// point lands on the canvas and how big it should be. Depth ordering is the
/// painter's algorithm — sort by [Projected.depth] descending and draw.
class Camera3 {
  /// Camera position in world space.
  final Vec3 eye;

  /// Downward tilt in radians (0 = looking level along +z). A throw game wants
  /// a modest positive pitch so you see the floor receding.
  final double pitch;

  /// Vertical field of view, radians.
  final double fovY;

  /// Canvas size the projection maps into.
  final Size viewport;

  /// Points nearer than this are clipped.
  final double near;

  const Camera3({
    required this.eye,
    required this.viewport,
    this.pitch = 0.18,
    this.fovY = 0.95,
    this.near = 0.05,
  });

  Camera3 copyWith({Vec3? eye, double? pitch, double? fovY, Size? viewport}) =>
      Camera3(
        eye: eye ?? this.eye,
        pitch: pitch ?? this.pitch,
        fovY: fovY ?? this.fovY,
        viewport: viewport ?? this.viewport,
        near: near,
      );

  /// Focal length in pixels — how many pixels one world unit spans at unit
  /// depth. Derived from the vertical FOV and viewport height.
  double get focal => (viewport.height / 2) / math.tan(fovY / 2);

  /// Screen y of the horizon — where the ground plane converges. Ground lines
  /// drawn toward this point are the strongest depth cue available.
  double get horizonY => viewport.height / 2 - focal * math.tan(pitch);

  /// A horizontal circle (radius [radius] about [centre], lying in the plane
  /// `y == centre.y`) as a projected [Path].
  ///
  /// Built by projecting [segments] points around the real circle rather than
  /// drawing an ellipse with a guessed squash. That matters: a horizontal
  /// circle projects to a *conic* whose aspect changes with depth, and that
  /// variation is precisely the depth cue. Approximating the squash with a
  /// constant — or with `sin(elevation)` — is both visibly wrong and the reason
  /// a scene fails to read as 3-D.
  ///
  /// Returns null if any sampled point falls behind the near plane.
  Path? horizontalCirclePath(Vec3 centre, double radius, {int segments = 20}) {
    final path = Path();
    for (var i = 0; i < segments; i++) {
      final a = 2 * math.pi * i / segments;
      final p = project(Vec3(
        centre.x + math.cos(a) * radius,
        centre.y,
        centre.z + math.sin(a) * radius,
      ));
      if (!p.visible) return null;
      if (i == 0) {
        path.moveTo(p.screen.dx, p.screen.dy);
      } else {
        path.lineTo(p.screen.dx, p.screen.dy);
      }
    }
    return path..close();
  }

  /// Transform a world point into camera space (camera at origin looking +z).
  Vec3 toCameraSpace(Vec3 world) {
    final d = world - eye;
    // Rotate about x so a positive pitch tips the view DOWN — i.e. a distant
    // point at eye level rises toward the top of the frame, and the horizon
    // sits at `height/2 - focal·tan(pitch)`.
    final c = math.cos(pitch);
    final s = math.sin(pitch);
    return Vec3(
      d.x,
      d.y * c + d.z * s,
      -d.y * s + d.z * c,
    );
  }

  /// Project a world point onto the canvas.
  Projected project(Vec3 world) {
    final cam = toCameraSpace(world);
    if (cam.z <= near) {
      return const Projected(
          screen: Offset.zero, depth: 0, scale: 0, visible: false);
    }
    final f = focal;
    final scale = f / cam.z;
    return Projected(
      // Screen y grows downward, so world-up becomes negative screen offset.
      screen: Offset(
        viewport.width / 2 + cam.x * scale,
        viewport.height / 2 - cam.y * scale,
      ),
      depth: cam.z,
      scale: scale,
      visible: true,
    );
  }

  /// Where a world-space ray from the camera through a screen point meets the
  /// horizontal plane `y == planeY`. Returns null when the ray never does
  /// (looking at or above the horizon). Used to turn a tap/drag on the canvas
  /// into a spot on the floor.
  Vec3? screenToGround(Offset screen, {double planeY = 0}) {
    final f = focal;
    // Ray direction in camera space through the pixel.
    final cx = screen.dx - viewport.width / 2;
    final cy = viewport.height / 2 - screen.dy;
    final dirCam = Vec3(cx / f, cy / f, 1);
    // Rotate back into world space — the transpose of toCameraSpace's rotation.
    final c = math.cos(pitch);
    final s = math.sin(pitch);
    final dir = Vec3(
      dirCam.x,
      dirCam.y * c - dirCam.z * s,
      dirCam.y * s + dirCam.z * c,
    );
    if (dir.y.abs() < 1e-9) return null;
    final t = (planeY - eye.y) / dir.y;
    if (t <= 0) return null; // plane is behind the camera
    return eye + dir * t;
  }
}
