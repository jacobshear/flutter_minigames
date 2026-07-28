import 'dart:math' as math;

import 'vec3.dart';

/// Analytic collision helpers for throw games.
///
/// All tests are **swept** — they take the segment a ball travelled during one
/// step (`from` → `to`) rather than just its end point, so a fast ball can't
/// tunnel through a cup mouth or a hoop between frames. That tunnelling is the
/// classic failure of naive point-in-volume checks at throw speeds.
class Surfaces {
  const Surfaces._();

  /// Where the segment crosses the horizontal plane `y == planeY` moving
  /// **downward**, as a 0..1 fraction along the segment, or null if it doesn't.
  static double? descendingPlaneCrossing(
    Vec3 from,
    Vec3 to,
    double planeY,
  ) {
    final dy = to.y - from.y;
    if (dy >= 0) return null; // not descending
    if (from.y < planeY || to.y > planeY) return null; // doesn't straddle
    final t = (planeY - from.y) / dy;
    if (t < 0 || t > 1) return null;
    return t;
  }

  /// Point at fraction [t] along the segment.
  static Vec3 lerp(Vec3 from, Vec3 to, double t) => from + (to - from) * t;

  /// Does the segment pass **downward** through the horizontal disc of radius
  /// [radius] centred at [centre]? This is the "went in" test — a basketball
  /// falling through the hoop, or a ball dropping into a cup mouth.
  ///
  /// Descending-only is deliberate: a ball rising through the hoop from below
  /// is not a basket.
  static bool passesDownThroughDisc(
    Vec3 from,
    Vec3 to,
    Vec3 centre,
    double radius,
  ) {
    final t = descendingPlaneCrossing(from, to, centre.y);
    if (t == null) return false;
    final at = lerp(from, to, t);
    final dx = at.x - centre.x;
    final dz = at.z - centre.z;
    return dx * dx + dz * dz <= radius * radius;
  }

  /// Where the segment crosses the vertical plane at depth [z] while travelling
  /// away from the viewer, or null if it doesn't.
  ///
  /// The primitive for face-on targets — a dartboard or an archery butt. The
  /// caller turns the returned point into a score by measuring its offset from
  /// the target centre (radius for rings, angle for dartboard sectors).
  static Vec3? verticalPlaneHit(Vec3 from, Vec3 to, double z) {
    final dz = to.z - from.z;
    if (dz <= 0) return null; // only when heading down-range
    if (from.z > z || to.z < z) return null;
    final t = (z - from.z) / dz;
    if (t < 0 || t > 1) return null;
    return lerp(from, to, t);
  }

  /// Horizontal distance from a point to a vertical axis at ([cx], [cz]).
  static double horizontalDistance(Vec3 p, double cx, double cz) {
    final dx = p.x - cx;
    final dz = p.z - cz;
    return math.sqrt(dx * dx + dz * dz);
  }

  /// Contact with a hoop/cup **rim**: the ring of radius [radius] at [centre].
  /// Returns the outward surface normal to bounce off, or null for no contact.
  ///
  /// The rim is treated as a torus of thickness [thickness]; the normal points
  /// from the nearest point on the ring toward the ball, which gives the
  /// characteristic rattle when a shot catches the iron.
  static Vec3? rimContact(
    Vec3 ball,
    double ballRadius,
    Vec3 centre,
    double radius,
    double thickness,
  ) {
    final dx = ball.x - centre.x;
    final dz = ball.z - centre.z;
    final horiz = math.sqrt(dx * dx + dz * dz);
    if (horiz < 1e-9) return null; // dead centre: no rim contact
    // Nearest point on the ring to the ball.
    final nearest = Vec3(
      centre.x + dx / horiz * radius,
      centre.y,
      centre.z + dz / horiz * radius,
    );
    final away = ball - nearest;
    final d = away.length;
    if (d > ballRadius + thickness) return null;
    if (d < 1e-9) {
      // Degenerate: the ball's centre is exactly on the rim wire, so "away from
      // the wire" is undefined. Push it radially outward — any unit normal is
      // valid here, and an outward one keeps the rattle behaving sanely instead
      // of returning a zero vector that would make the bounce a silent no-op.
      return Vec3(dx / horiz, 0, dz / horiz);
    }
    return away.normalized;
  }

  /// Contact with an axis-aligned vertical plane facing the viewer (a
  /// backboard) spanning [xMin]..[xMax] and [yMin]..[yMax] at depth [z].
  /// Returns the fraction along the segment at which it is struck, or null.
  static double? backboardCrossing(
    Vec3 from,
    Vec3 to,
    double z,
    double xMin,
    double xMax,
    double yMin,
    double yMax,
  ) {
    final dz = to.z - from.z;
    if (dz <= 0) return null; // only when travelling away from the viewer
    if (from.z > z || to.z < z) return null;
    final t = (z - from.z) / dz;
    if (t < 0 || t > 1) return null;
    final at = lerp(from, to, t);
    if (at.x < xMin || at.x > xMax) return null;
    if (at.y < yMin || at.y > yMax) return null;
    return t;
  }

  /// Contact with the outside wall of a vertical cylinder (a cup) whose axis is
  /// at ([cx], [cz]) with the given [radius], between [yBottom] and [yTop].
  /// Returns the outward normal, or null.
  static Vec3? cylinderWallContact(
    Vec3 ball,
    double ballRadius,
    double cx,
    double cz,
    double radius,
    double yBottom,
    double yTop,
  ) {
    if (ball.y < yBottom || ball.y > yTop) return null;
    final dx = ball.x - cx;
    final dz = ball.z - cz;
    final horiz = math.sqrt(dx * dx + dz * dz);
    if (horiz > radius + ballRadius || horiz < 1e-9) return null;
    return Vec3(dx / horiz, 0, dz / horiz);
  }
}
