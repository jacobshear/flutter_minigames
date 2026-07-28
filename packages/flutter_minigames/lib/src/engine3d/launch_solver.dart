import 'dart:math' as math;

import 'projectile.dart';
import 'vec3.dart';

/// Solves "how hard do I have to throw to land *there*".
///
/// ## Why a solver instead of a speed range
///
/// This is the single most important piece of tuning in a 3-D throw game. At
/// true physical scale the target is brutally small: a regulation beer-pong cup
/// at 2.4 m gives roughly a **1% make window** over the plausible input space,
/// and mapping a swipe linearly onto an absolute speed range (say 4.5–14 m/s)
/// can miss *every single time* — the sliver of speeds that score is narrower
/// than one pixel of swipe.
///
/// So instead of mapping the flick to an absolute speed, we:
/// 1. solve the exact speed `v*` that lands in the target, then
/// 2. map the flick to a narrow band around it (`v* ± ~9%`).
///
/// A medium flick is then roughly right and skill becomes fine modulation —
/// which is exactly how the games we're matching feel. Difficulty still scales
/// naturally with distance, because a fixed ± band is a tighter *absolute*
/// window the further away the target is.
class LaunchSolver {
  const LaunchSolver._();

  /// Speed needed to travel [horizontalDistance] and arrive [heightDelta]
  /// above the launch point, thrown at [loft] radians, ignoring drag.
  ///
  /// From the standard ballistic identity
  /// `Δy = z·tanθ − g·z² / (2·v²·cos²θ)`, rearranged for v:
  ///
  ///     v* = (z / cosθ) · sqrt( g / (2·(z·tanθ − Δy)) )
  ///
  /// Returns null when the shot is impossible at that loft — i.e. the target
  /// sits at or above the straight-line reach (`z·tanθ ≤ Δy`), where no finite
  /// speed works and you must throw higher.
  static double? speedToHit({
    required double horizontalDistance,
    required double heightDelta,
    required double loft,
    double gravity = 22,
  }) {
    final z = horizontalDistance;
    if (z <= 0 || gravity <= 0) return null;
    final cos = math.cos(loft);
    if (cos.abs() < 1e-6) return null;
    final denom = z * math.tan(loft) - heightDelta;
    if (denom <= 1e-9) return null; // unreachable at this elevation
    final v = (z / cos) * math.sqrt(gravity / (2 * denom));
    return v.isFinite && v > 0 ? v : null;
  }

  /// The launch velocity that lands a throw from [from] onto [target] at the
  /// given [loft], or null if unreachable. Direction is taken from the
  /// horizontal offset between the two points, so this aims and powers at once.
  static Vec3? velocityToHit({
    required Vec3 from,
    required Vec3 target,
    required double loft,
    double gravity = 22,
  }) {
    final dx = target.x - from.x;
    final dz = target.z - from.z;
    final horizontal = math.sqrt(dx * dx + dz * dz);
    final speed = speedToHit(
      horizontalDistance: horizontal,
      heightDelta: target.y - from.y,
      loft: loft,
      gravity: gravity,
    );
    if (speed == null || horizontal < 1e-9) return null;
    final up = speed * math.sin(loft);
    final along = speed * math.cos(loft);
    return Vec3(along * dx / horizontal, up, along * dz / horizontal);
  }

  /// Refines [analyticSpeed] against the real integrator, which includes drag
  /// (the closed form does not, so it always throws a little short).
  ///
  /// Binary-searches the speed whose flight passes closest to [target]'s height
  /// at [target]'s range. Deterministic, and cheap enough to run per shot.
  static double refineForDrag({
    required Vec3 from,
    required Vec3 target,
    required double loft,
    required double analyticSpeed,
    ThrowConfig config = const ThrowConfig(),
    int iterations = 24,
  }) {
    final dx = target.x - from.x;
    final dz = target.z - from.z;
    final horizontal = math.sqrt(dx * dx + dz * dz);
    if (horizontal < 1e-9) return analyticSpeed;

    // Height error at the target's range for a given launch speed: positive
    // means the ball is still above the target when it gets there.
    double errorFor(double speed) {
      final p = Projectile(
        position: from,
        velocity: Vec3(
          math.cos(loft) * speed * dx / horizontal,
          math.sin(loft) * speed,
          math.cos(loft) * speed * dz / horizontal,
        ),
        config: config,
      );
      for (var i = 0; i < config.maxSteps; i++) {
        final before = p.position;
        p.step();
        final travelled = math.sqrt(
          math.pow(p.position.x - from.x, 2) +
              math.pow(p.position.z - from.z, 2),
        );
        if (travelled >= horizontal) {
          // Interpolate the height at exactly the target range.
          final prev = math.sqrt(
            math.pow(before.x - from.x, 2) + math.pow(before.z - from.z, 2),
          );
          final span = travelled - prev;
          final t = span < 1e-12 ? 0.0 : (horizontal - prev) / span;
          final y = before.y + (p.position.y - before.y) * t;
          return y - target.y;
        }
        if (p.position.y < target.y - 8) break; // fell well short
      }
      return -double.maxFinite; // never got there: way too slow
    }

    var lo = analyticSpeed * 0.6;
    var hi = analyticSpeed * 2.0;
    for (var i = 0; i < iterations; i++) {
      final mid = (lo + hi) / 2;
      if (errorFor(mid) < 0) {
        lo = mid; // undershooting, throw harder
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  /// Maps a 0..1 flick [power] onto a speed band around the solved [target]
  /// speed: `target · (1 ∓ band)`. A dead-centre flick is perfect; the edges of
  /// the range are the near-misses.
  static double speedFromPower({
    required double targetSpeed,
    required double power,
    double band = 0.09,
  }) =>
      targetSpeed * (1 - band + 2 * band * power.clamp(0.0, 1.0));
}
