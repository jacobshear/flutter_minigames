import 'dart:math' as math;

import 'vec3.dart';

/// Tuning for a thrown ball.
class ThrowConfig {
  /// Downward acceleration, world units/s². Negative-y is down.
  final double gravity;

  /// Fraction of velocity bled per second to air drag (0 = vacuum).
  final double drag;

  /// Speed below which a grounded ball is considered at rest.
  final double restSpeed;

  /// Fixed integration step. Physics always advances at this rate so a throw
  /// replays identically regardless of frame rate.
  final double fixedDt;

  /// Hard cap on steps for one throw, so a pathological shot still terminates.
  final int maxSteps;

  /// Steady acceleration from wind, world units/s². Crosswind (x) is the
  /// interesting one: it pushes a shot sideways in proportion to how long the
  /// projectile is in the air, so distant targets drift far more than near
  /// ones — which is exactly what makes wind a skill mechanic rather than
  /// noise. Leave at zero for indoor games.
  final Vec3 wind;

  const ThrowConfig({
    this.gravity = 22,
    this.drag = 0.06,
    this.restSpeed = 0.35,
    this.fixedDt = 1 / 120,
    this.maxSteps = 2400,
    this.wind = Vec3.zero,
  });

  ThrowConfig copyWith({Vec3? wind, double? gravity, double? drag}) =>
      ThrowConfig(
        gravity: gravity ?? this.gravity,
        drag: drag ?? this.drag,
        restSpeed: restSpeed,
        fixedDt: fixedDt,
        maxSteps: maxSteps,
        wind: wind ?? this.wind,
      );
}

/// A ball in flight: position, velocity and spin under gravity and drag.
///
/// Deliberately a plain integrator rather than a physics engine — a throw game
/// needs one moving body against a handful of analytic surfaces, and keeping it
/// pure means a whole shot can be simulated headlessly in a test.
class Projectile {
  final ThrowConfig config;

  Vec3 position;
  Vec3 velocity;

  /// Accumulated roll/spin angle, for rendering a spinning ball.
  double spin;

  /// Spin rate (radians/second) — set at launch, decays with drag.
  double spinRate;

  Projectile({
    required this.position,
    required this.velocity,
    this.config = const ThrowConfig(),
    this.spin = 0,
    this.spinRate = 0,
  });

  /// Advance one fixed step. Returns the position before the step, so callers
  /// can do swept collision tests against the segment travelled.
  Vec3 step() {
    final from = position;
    final dt = config.fixedDt;
    // Gravity, wind and a simple linear drag term.
    final decay = 1 - config.drag * dt;
    final w = config.wind;
    velocity = Vec3(
      (velocity.x + w.x * dt) * decay,
      (velocity.y - config.gravity * dt + w.y * dt) * decay,
      (velocity.z + w.z * dt) * decay,
    );
    position = position + velocity * dt;
    spin += spinRate * dt;
    spinRate *= decay;
    return from;
  }

  /// Reflect off a surface with unit normal [n], keeping [restitution] of the
  /// normal component and [friction] scrubbing the tangential part.
  void bounce(Vec3 n, {double restitution = 0.45, double friction = 0.12}) {
    final vn = velocity.dot(n);
    if (vn >= 0) return; // already separating
    final normalPart = n * vn;
    final tangent = velocity - normalPart;
    velocity = tangent * (1 - friction) - normalPart * restitution;
    spinRate *= 0.7;
  }

  /// True once the ball is resting on the floor plane at [floorY].
  bool restingOn(double floorY, {double radius = 0}) =>
      position.y - radius <= floorY + 1e-3 &&
      velocity.length < config.restSpeed;
}

/// Maps a swipe on the canvas to a launch velocity.
///
/// The mapping every 3-D throw game needs: a flick up-screen throws the ball
/// **down-range** (+z) and **up** (+y), while the swipe's horizontal component
/// steers laterally (±x). Longer, faster flicks throw harder and flatter.
class ThrowAim {
  /// Swipe length (pixels) that corresponds to full power.
  final double fullPowerDrag;

  /// Speed at full power, world units/s.
  final double maxSpeed;

  /// Speed at the minimum registering flick.
  final double minSpeed;

  /// Swipe shorter than this does not throw.
  final double deadZone;

  /// Launch elevation in radians at low power (loftier) and full power
  /// (flatter) — power flattens the arc, as a harder real throw does.
  final double loftAtMinPower;
  final double loftAtMaxPower;

  /// Yaw applied by a fully sideways swipe, in radians.
  final double maxYaw;

  const ThrowAim({
    this.fullPowerDrag = 260,
    this.maxSpeed = 15.5,
    this.minSpeed = 6.5,
    this.deadZone = 14,
    this.loftAtMinPower = 0.72,
    this.loftAtMaxPower = 0.34,
    this.maxYaw = 0.42,
  });

  /// 0..1 power for a swipe of ([dx], [dy]) pixels (screen space, y down).
  /// Only an up-screen swipe throws; a sideways-only swipe steers but does not.
  double power(double dx, double dy) {
    if (-dy <= 0) return 0; // must be a forward (up-screen) flick
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < deadZone) return 0;
    return (len / fullPowerDrag).clamp(0.0, 1.0);
  }

  /// The launch velocity for a swipe of ([dx], [dy]) pixels, or null if the
  /// swipe was too short or not a forward throw.
  Vec3? launch(double dx, double dy) {
    final p = power(dx, dy);
    if (p <= 0) return null;
    final speed = minSpeed + (maxSpeed - minSpeed) * p;
    final loft = loftAtMinPower + (loftAtMaxPower - loftAtMinPower) * p;
    final len = math.sqrt(dx * dx + dy * dy);
    final yaw = maxYaw * (dx / (len == 0 ? 1 : len));
    // Elevation splits speed between up and down-range; yaw then splits the
    // horizontal part between depth and lateral.
    final up = speed * math.sin(loft);
    final horizontal = speed * math.cos(loft);
    return Vec3(
      horizontal * math.sin(yaw),
      up,
      horizontal * math.cos(yaw),
    );
  }
}
