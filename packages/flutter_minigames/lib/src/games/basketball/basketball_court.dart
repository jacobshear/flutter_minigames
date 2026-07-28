import 'dart:math' as math;

import 'package:flutter_minigames/src/engine3d/engine3d.dart';

/// Whether the rig stands still or slides side to side.
///
/// This is a **match option chosen at creation**, not a per-round escalation:
/// GamePigeon offers Basketball in a normal and a moving-hoop flavour and the
/// choice applies to the whole match, both players, both rounds.
enum BasketballHoopMode {
  /// Static rig.
  normal,

  /// The whole rig (backboard, rim, net, pole) slides laterally.
  moving;

  /// Lateral half-amplitude of the slide, metres. 0 for [normal].
  double get swing => this == BasketballHoopMode.moving ? 1.0 : 0.0;

  /// Seconds for one full left-right-left cycle.
  double get period => 8.0;

  String get label => this == BasketballHoopMode.moving ? 'Moving' : 'Normal';

  /// Lateral offset of the rig at round time [t].
  ///
  /// A **linear triangle wave**, not a sine: constant speed, no easing,
  /// starting dead centre and moving right. Easing it would be smoother and
  /// wrong — the constant speed is what makes the lead readable.
  double offsetAt(double t) {
    if (swing == 0) return 0;
    final p = (t % period) / period;
    final tri = p < 0.25
        ? p * 4
        : p < 0.75
            ? 2 - p * 4
            : p * 4 - 4;
    return tri * swing;
  }
}

/// World geometry for the first-person court, in metres.
///
/// The shooter stands at the origin looking down-range (+z); the hoop is a
/// horizontal circle at [rimHeight] a **fixed** distance away. The distance
/// never changes — not between rounds, not between players. Everything the sim
/// and the painter need agrees on these numbers, so a shot that reads as a
/// swish on screen is the same shot the swept disc test scored.
///
/// Dimensions are near-regulation (3.05 m rim, 18-inch hoop, 6-inch ball) —
/// true scale is what makes the perspective read correctly. Gravity is *not*
/// true scale: 14 m/s² instead of 9.81 gives a ~1 s flight, which is the
/// GamePigeon cadence. Real gravity made every shot a moon lob.
class BasketballCourt {
  const BasketballCourt._();

  /// Rim plane height.
  static const double rimHeight = 3.05;

  /// True rim radius (18-inch hoop).
  static const double rimRadius = 0.2286;

  /// Iron thickness used for rattle contacts.
  static const double rimThickness = 0.022;

  /// Ball radius (a size-7 ball is ~0.121 m).
  static const double ballRadius = 0.12;

  /// Effective radius of the swept "went in" disc.
  ///
  /// Detection is **purely geometric** — it never asks whether the ball touched
  /// iron first, which matches the shipped game. A perfectly clean pass needs
  /// the centre inside `rimRadius - ballRadius` = 0.109 m; we allow 0.130 m, so
  /// a ball that clips the iron on the way down can still drop (shooter's
  /// roll). Tuned against the make-rate tests — moving it moves those numbers,
  /// which is exactly the regression guard we want.
  static const double makeRadius = 0.130;

  /// Backboard face dimensions and placement.
  static const double backboardWidth = 1.83;
  static const double backboardHeight = 1.07;
  static const double backboardBottom = 2.90;

  /// Gap between the back of the rim circle and the backboard face.
  static const double rimStandoff = 0.15;

  /// Fixed range from the spawn line to the hoop centre.
  static const double hoopDistance = 3.6;

  /// Depth of the spawn line. Broken out as its own constant so [hoopZ] stays
  /// const-evaluable (a const expression can't read a field off a const Vec3).
  static const double spawnZ = 2.90;

  /// Where balls spawn (x is randomised per ball, see [spawnSpread]).
  static const Vec3 spawnPoint = Vec3(0, 0.62, spawnZ);

  /// Half-width of the randomised lateral spawn offset.
  ///
  /// This is where the skill lives. Power and arc are fixed, so the *only*
  /// thing a shot needs is the right bearing — and because every ball appears
  /// at a different lateral offset, that bearing changes every time. You have
  /// to re-read the ball and re-aim, at four balls a second.
  static const double spawnSpread = 0.33;

  /// Depth of the hoop centre.
  static const double hoopZ = spawnZ + hoopDistance;

  /// Camera sits behind and slightly above the spawn line — the shooter's
  /// eyeline. Pitched a hair downward so the floor converges into frame (the
  /// strongest depth cue) while the backboard still clears the top edge.
  static const Vec3 cameraEye = Vec3(0, 1.55, -0.55);
  static const double cameraPitch = 0.06;
  static const double cameraFov = 1.12;

  /// Release angle. 1.12 rad (64°) is loftier than a real jump shot but gives
  /// a ~52° entry angle at this range, which both looks like basketball and
  /// widens the effective opening for a descending ball.
  static const double loft = 1.20;

  /// Total drag pixels that map to a full-lateral aim (matches the shipped
  /// `inverse_lerp(-200, 200, delta.x)`).
  static const double fullDragPixels = 200;

  /// Drags shorter than this do not throw.
  static const double dragDeadZone = 30;

  /// Minimum seconds between a shot and the next ball appearing (~4 balls/s).
  static const double respawnCooldown = 0.25;

  /// Fixed-step ballistics shared by the live board and the headless tests.
  static const ThrowConfig throwConfig = ThrowConfig(
    gravity: 14,
    drag: 0.05,
    fixedDt: 1 / 120,
    maxSteps: 1200,
    restSpeed: 0.3,
  );

  /// Depth of the backboard face.
  static double get backboardZ => hoopZ + rimRadius + rimStandoff;

  /// Far wall of the gym, purely scenery.
  static double get backWallZ => hoopZ + 8.2;

  /// Hoop centre at round time [t] for [mode].
  static Vec3 hoopCentreAt(BasketballHoopMode mode, double t) =>
      Vec3(mode.offsetAt(t), rimHeight, hoopZ);
}

/// Turns a horizontal drag into a launch velocity.
///
/// ## Fixed arc, directional aim
///
/// The shipped game transmits **one directional float per shot**: power and arc
/// are constants, and the drag only steers. So the solver runs **once per
/// match**, not once per shot — [LaunchSolver] finds the speed that drops a
/// ball through the hoop at the fixed range, and every ball is thrown at
/// exactly that speed and [BasketballCourt.loft]. The drag picks a bearing.
///
/// That inverts where the difficulty sits, and for the better: instead of
/// modulating an invisible power band, you are reading a ball that appeared at
/// a random lateral offset and picking the line that gets it home, four times a
/// second.
class BasketballAim {
  const BasketballAim._();

  /// Range the fixed launch is solved for, given [mode].
  ///
  /// Not simply [BasketballCourt.hoopDistance]: because the launch speed is a
  /// constant, the ball always descends to rim height after the same horizontal
  /// travel, while the actual spawn-to-hoop distance varies with the spawn
  /// offset and (in moving mode) the rig's position. Solving for the mean of
  /// that spread — `d ≈ D + E[lateral²]/2D` — centres the radial error in the
  /// make disc instead of biasing every shot short.
  static double solveRange(BasketballHoopMode mode) {
    const d = BasketballCourt.hoopDistance;
    // Variance of a uniform ±a offset is a²/3; hoop and spawn are independent.
    final meanSquare = mode.swing * mode.swing / 3 +
        BasketballCourt.spawnSpread * BasketballCourt.spawnSpread / 3;
    return d + meanSquare / (2 * d);
  }

  /// The one launch speed used for every shot in a [mode] match.
  static double solveSpeed(BasketballHoopMode mode) {
    final range = solveRange(mode);
    final from = BasketballCourt.spawnPoint;
    final target = Vec3(0, BasketballCourt.rimHeight, from.z + range);
    final analytic = LaunchSolver.speedToHit(
      horizontalDistance: range,
      heightDelta: target.y - from.y,
      loft: BasketballCourt.loft,
      gravity: BasketballCourt.throwConfig.gravity,
    );
    if (analytic == null) return range * 2.4;
    return LaunchSolver.refineForDrag(
      from: from,
      target: target,
      loft: BasketballCourt.loft,
      analyticSpeed: analytic,
      config: BasketballCourt.throwConfig,
    );
  }

  /// Half-angle of the aim cone: a full-left drag throws at `-maxYaw`, a
  /// full-right drag at `+maxYaw`.
  ///
  /// **Mode-independent on purpose.** The drag mapping is a fixed
  /// `inverse_lerp(-200, 200, dx)` in the shipped game, so the cone behind it
  /// must be fixed too — and it has to be wide enough to reach the rig at the
  /// far end of its travel, or a moving-hoop match would have unreachable
  /// shots. Sizing it for the widest case (the rig at full swing, the ball
  /// spawned at the opposite edge) and then *keeping* that width in normal
  /// matches is what makes the control feel identical in both modes and keeps
  /// the make window an honest sliver of the drag: about ±28 px of a ±200 px
  /// throw.
  ///
  /// Derived rather than picked, so it tracks any change to the geometry.
  static double maxYaw(BasketballHoopMode mode) => _maxYaw;

  static final double _maxYaw = math.atan(
        (BasketballHoopMode.moving.swing + BasketballCourt.spawnSpread) /
            BasketballCourt.hoopDistance,
      ) +
      0.03;

  /// Map a raw drag delta to a -1..1 aim, or null if it was too short to throw.
  ///
  /// Horizontal component only — a vertical flick throws nothing extra, which
  /// is the shipped behaviour and the reason power is not an input.
  static double? aimFromDrag(double dx, double dy) {
    if (math.sqrt(dx * dx + dy * dy) < BasketballCourt.dragDeadZone) {
      return null;
    }
    return (dx / BasketballCourt.fullDragPixels).clamp(-1.0, 1.0);
  }

  /// Launch velocity for a ball spawned at [from], aimed with [aim] (-1..1).
  static Vec3 launchVelocity({
    required Vec3 from,
    required double aim,
    required double speed,
    required BasketballHoopMode mode,
  }) {
    final yaw = maxYaw(mode) * aim.clamp(-1.0, 1.0);
    final up = speed * math.sin(BasketballCourt.loft);
    final along = speed * math.cos(BasketballCourt.loft);
    return Vec3(along * math.sin(yaw), up, along * math.cos(yaw));
  }

  /// The aim (-1..1) that points a ball at [from] straight at [target] — the
  /// perfect line, ignoring lead.
  static double aimAt(Vec3 from, Vec3 target, BasketballHoopMode mode) {
    final bearing = math.atan2(target.x - from.x, target.z - from.z);
    return (bearing / maxYaw(mode)).clamp(-1.0, 1.0);
  }

  /// Roughly how long a ball is in the air. Constant, because speed and arc
  /// are: it is how far ahead of a sliding rig you have to aim.
  static double flightTime(BasketballHoopMode mode) {
    final along = solveSpeed(mode) * math.cos(BasketballCourt.loft);
    return along < 1e-6 ? 0 : BasketballCourt.hoopDistance / along;
  }

  /// The aim that leads a (possibly sliding) rig for a ball spawned at
  /// [spawnX] and thrown at round time [now].
  static double leadAim(
    BasketballHoopMode mode,
    double spawnX,
    double now,
  ) {
    final from = Vec3(
      spawnX,
      BasketballCourt.spawnPoint.y,
      BasketballCourt.spawnZ,
    );
    final hoop = BasketballCourt.hoopCentreAt(mode, now + flightTime(mode));
    return aimAt(from, hoop, mode);
  }
}
