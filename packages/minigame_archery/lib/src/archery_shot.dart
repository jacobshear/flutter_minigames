import 'dart:math' as math;

import 'package:minigames_3d/minigames_3d.dart';

import 'archery_game.dart';

/// The ballistics layer: it turns a draw + an aim into an arrow flight and an
/// impact point. Headless, deterministic, and free of any Flutter dependency —
/// a whole shot can be simulated in a unit test.
///
/// ## Why the draw is banded around a solved launch
///
/// At true scale a 12 cm gold at 38 m is roughly a **1% window** over any
/// plausible absolute speed range; mapping the draw onto "30–70 m/s" would miss
/// essentially always. So every shot instead:
///
/// 1. solves the speed that puts an arrow **dead centre in still air**
///    ([solveSpeed]: [LaunchSolver.speedToHit] refined against the real
///    integrator with [LaunchSolver.refineForDrag]), then
/// 2. maps the draw through [LaunchSolver.speedFromPower] onto `v* ± 9%`.
///
/// The solve **zeroes the wind on purpose**. A perfect release in still air is
/// therefore dead centre, and every bit of wind must be answered by consciously
/// aiming off into it. That is the whole skill loop.
///
/// ## The reticle contract
///
/// Everything the draw does to the shot except the wind is *visible*. The band
/// above shifts an arrow vertically by a known amount ([drawBias]), and the
/// view adds exactly that to the sight picture, so
///
/// > **in still air the arrow lands where the reticle was pointing** — to the
/// > millimetre, at every range, for every draw.
///
/// Aim, sway and draw are therefore one readable channel rather than three, and
/// the only thing the reticle does not know is the wind. That is deliberate:
/// the wind is the part you are supposed to predict yourself.
///
/// ## Why the drop grows with range
///
/// [dropFor] deliberately lets an arrow's drop — and so its time of flight —
/// grow with distance instead of holding the launch angle constant. Wind is a
/// steady acceleration, so its drift is `½·a·t²`: a longer flight drifts
/// *quadratically* further. That is what makes the far targets a genuinely
/// different problem rather than the near one scaled up.
class ArcheryBallistics {
  const ArcheryBallistics._();

  /// Real gravity — the ranges here are real metres, so no fudge is needed.
  static const double gravity = 9.81;

  /// Linear drag on a slick arrow: small, but enough that the closed-form
  /// solution falls short and [LaunchSolver.refineForDrag] earns its keep.
  static const double drag = 0.03;

  /// Wind speed (m/s) → lateral acceleration (m/s²) on the shaft. Tuned so the
  /// gentlest target's breeze is nearly free and target four's gale pushes a
  /// perfectly aimed arrow most of a face-radius off centre.
  static const double windCoupling = 0.38;

  /// Height of the nocking point above the shooting line, metres.
  static const double bowHeight = 1.52;

  /// Eye height — the camera sits a little above the arrow, as it does when
  /// you look over your own bow hand.
  static const double eyeHeight = 1.62;

  /// Height of the centre of every target face, metres.
  static const double targetCentreHeight = 1.30;

  /// Half-width of the speed band the draw is mapped onto (±9% of the solve).
  static const double speedBand = 0.09;

  /// Integration step. 240 Hz keeps a ~60 m/s arrow inside 25 cm per step, and
  /// the swept plane test means even that cannot tunnel.
  static const double fixedDt = 1 / 240;

  /// Where the arrow leaves the bow.
  static const Vec3 bowOrigin = Vec3(0, bowHeight, 0);

  /// Centre of the face at [distance].
  static Vec3 targetCentre(double distance) =>
      Vec3(0, targetCentreHeight, distance);

  /// How far below the straight line of the launch the arrow must fall to
  /// arrive at the face, metres. Grows with range so the flight lasts longer
  /// the further you shoot (see the class doc on wind drift).
  static double dropFor(double distance) =>
      math.max(0.45, 0.90 + 0.052 * (distance - 15));

  /// Launch elevation for [distance], radians. Chosen so the drop follows
  /// [dropFor]; it stays near 2.5° across the whole range, so the bow's
  /// silhouette does not visibly see-saw between targets.
  static double loftFor(double distance) {
    final heightDelta = targetCentreHeight - bowHeight;
    return math.atan((dropFor(distance) + heightDelta) / distance);
  }

  /// The steady wind acceleration for [conditions], as `ThrowConfig.wind`.
  static Vec3 windVector(TargetConditions conditions, {double scale = 1}) =>
      Vec3(
        conditions.crossComponent * windCoupling * scale,
        0,
        conditions.alongComponent * windCoupling * scale,
      );

  /// The integrator configuration, optionally with wind.
  static ThrowConfig config({Vec3 wind = Vec3.zero}) => ThrowConfig(
        gravity: gravity,
        drag: drag,
        wind: wind,
        fixedDt: fixedDt,
        maxSteps: 2400,
      );

  static final Map<int, double> _speedCache = {};

  /// The launch speed that puts an arrow **dead centre at [distance] in still
  /// air**, refined against the real integrator so drag is accounted for.
  ///
  /// Memoised on the (0.1 m-quantised) range: it is a pure function of the
  /// distance, and every shot at a target needs the same answer.
  static double solveSpeed(double distance) {
    final key = (distance * 10).round();
    final cached = _speedCache[key];
    if (cached != null) return cached;
    final loft = loftFor(distance);
    final analytic = LaunchSolver.speedToHit(
          horizontalDistance: distance,
          heightDelta: targetCentreHeight - bowHeight,
          loft: loft,
          gravity: gravity,
        ) ??
        // Unreachable at this loft should be impossible with loftFor(), but a
        // sane fallback beats a crash on a hand-built distance.
        distance * 2;
    final refined = LaunchSolver.refineForDrag(
      from: bowOrigin,
      target: targetCentre(distance),
      loft: loft,
      analyticSpeed: analytic,
      config: config(),
    );
    _speedCache[key] = refined;
    return refined;
  }

  /// How far above the aimed line a shot at [distance] drawn to [power] will
  /// land in still air, metres — positive is high.
  ///
  /// Closed form rather than a second integration. The arrow falls
  /// `drop = ½·g·(d/v_z)²` on the way to the face, so scaling the launch speed
  /// by `1 + k` scales the drop by `1/(1 + k)²`; the shortfall is what the
  /// draw is worth. Matches [fire] to about a millimetre at every range, which
  /// is what lets the sight picture promise the impact point honestly.
  ///
  /// This exists so the reticle can be drawn where the arrow will actually go.
  /// Before it, the draw moved the arrow up to a third of a metre vertically
  /// with nothing on screen to show for it, and the score stopped agreeing
  /// with the aim.
  static double drawBias(double distance, double power) {
    final k = speedBand * (2 * power.clamp(0.0, 1.0) - 1);
    return dropFor(distance) * (1 - 1 / ((1 + k) * (1 + k)));
  }

  /// The launch velocity for a shot at [distance] drawn to [power] and aimed
  /// [aimYaw] right / [aimPitch] up of the solved line, in radians.
  static Vec3 launchVelocity({
    required double distance,
    required double power,
    double aimYaw = 0,
    double aimPitch = 0,
  }) {
    final speed = LaunchSolver.speedFromPower(
      targetSpeed: solveSpeed(distance),
      power: power,
      band: speedBand,
    );
    final pitch = loftFor(distance) + aimPitch;
    return Vec3(
      math.sin(aimYaw) * math.cos(pitch) * speed,
      math.sin(pitch) * speed,
      math.cos(aimYaw) * math.cos(pitch) * speed,
    );
  }

  /// Simulates one arrow all the way to its impact.
  ///
  /// [power] is the 0..1 draw (0.5 = the solved centre shot), [aimYaw] and
  /// [aimPitch] are the aim offsets in radians **including sway**, and
  /// [windScale] exists so a test can fire the identical shot in dead air.
  static ArcheryShotResult fire({
    required TargetConditions conditions,
    required double power,
    double aimYaw = 0,
    double aimPitch = 0,
    double windScale = 1,
  }) {
    final distance = conditions.distance;
    final velocity = launchVelocity(
      distance: distance,
      power: power,
      aimYaw: aimYaw,
      aimPitch: aimPitch,
    );
    final projectile = Projectile(
      position: bowOrigin,
      velocity: velocity,
      config: config(wind: windVector(conditions, scale: windScale)),
    );

    final path = <Vec3>[bowOrigin];
    var elapsed = 0.0;
    var timeToImpact = 0.0;
    Vec3? impact;
    Vec3 impactVelocity = velocity;
    var struckFace = false;

    for (var i = 0; i < projectile.config.maxSteps; i++) {
      final from = projectile.step();
      elapsed += fixedDt;

      if (impact == null) {
        // Swept: the crossing is solved on the segment, so a fast arrow cannot
        // slip through the face between two frames.
        final hit = Surfaces.verticalPlaneHit(from, projectile.position, distance);
        if (hit != null) {
          impact = hit;
          impactVelocity = projectile.velocity;
          timeToImpact = elapsed;
          struckFace = ArcheryGame.onFace(hit.x, hit.y - targetCentreHeight);
          path.add(hit);
          if (struckFace) break; // stops dead in the butt
        }
      }

      if (i % 4 == 0) path.add(projectile.position);

      if (projectile.position.y <= 0) {
        // Skidded into the grass, short or long.
        path.add(Vec3(projectile.position.x, 0, projectile.position.z));
        break;
      }
    }

    final dx = impact?.x ?? 0;
    final dy = (impact?.y ?? 0) - targetCentreHeight;
    return ArcheryShotResult(
      path: path,
      flightSeconds: elapsed,
      timeToImpactSeconds: impact == null ? elapsed : timeToImpact,
      impact: impact,
      offsetX: struckFace ? dx : (impact?.x ?? 0),
      offsetY: struckFace ? dy : dy,
      onFace: struckFace,
      ring: struckFace ? ArcheryGame.ringValue(dx, dy) : 0,
      impactDirection: impactVelocity.normalized,
      launchVelocity: velocity,
    );
  }
}

/// Everything one arrow did: the flight to animate and the outcome to bank.
class ArcheryShotResult {
  /// Sampled positions along the flight, launch first. Feeds the animation and
  /// the travelling ground shadow.
  final List<Vec3> path;

  /// Total simulated flight, seconds (to the ground for a miss).
  final double flightSeconds;

  /// Time until the arrow reached the target plane, seconds.
  final double timeToImpactSeconds;

  /// Where it crossed the target plane, or null if it never got there.
  final Vec3? impact;

  /// Metres right of / above the face centre.
  final double offsetX;
  final double offsetY;

  /// Whether it stuck in the scoring face.
  final bool onFace;

  /// Points, by the pure ring rules.
  final int ring;

  /// Unit velocity at impact — the angle a stuck arrow sits at.
  final Vec3 impactDirection;

  final Vec3 launchVelocity;

  const ArcheryShotResult({
    required this.path,
    required this.flightSeconds,
    required this.timeToImpactSeconds,
    required this.impact,
    required this.offsetX,
    required this.offsetY,
    required this.onFace,
    required this.ring,
    required this.impactDirection,
    required this.launchVelocity,
  });

  bool get isBullseye => ring == 10;

  /// Distance from the centre of the face, metres.
  double get radius => math.sqrt(offsetX * offsetX + offsetY * offsetY);

  /// Position along [path] at [t] seconds, linearly interpolated.
  Vec3 positionAt(double t) {
    if (path.length < 2) return path.isEmpty ? ArcheryBallistics.bowOrigin : path.first;
    final span = flightSeconds <= 0 ? 1.0 : flightSeconds;
    final u = (t / span).clamp(0.0, 1.0) * (path.length - 1);
    final i = u.floor().clamp(0, path.length - 2);
    final f = u - i;
    return path[i] + (path[i + 1] - path[i]) * f;
  }

  /// Flight direction at [t] seconds — the arrow's nose, which pitches down as
  /// it drops.
  Vec3 directionAt(double t) {
    if (path.length < 2) return const Vec3(0, 0, 1);
    final span = flightSeconds <= 0 ? 1.0 : flightSeconds;
    final u = (t / span).clamp(0.0, 1.0) * (path.length - 1);
    final i = u.floor().clamp(0, path.length - 2);
    final d = path[i + 1] - path[i];
    return d.lengthSquared < 1e-12 ? const Vec3(0, 0, 1) : d.normalized;
  }
}

/// The draw: how holding maps to power, how the reticle settles, and how focus
/// breaks if you hold too long. Pure so the whole feel is unit-testable.
///
/// Timeline of a hold, in seconds:
/// ```
/// 0 ────────── 1.05 ────── 1.43 ────── 1.90 ─────────────── 3.10
/// │  drawing    │ settling  │  ripe     │  focus breaking    │ gone
/// │ reticle     │ shot still│ the shot  │ reticle shakes and │
/// │ contracting │ low, sight│ is centred│ expands, shot weak │
/// │             │ climbing  │ — loose   │                    │
/// ```
///
/// ## Why the sweet spot moved into the hold
///
/// It used to sit at 80% of the *draw* — 0.84 s, before the bow was even at
/// full stretch — while everything on screen (the reticle contracting, the
/// zoom settling) said "now" at 1.05 s and later. Anyone who did what the game
/// showed them released at the top of the band and threw every arrow high:
/// measured across the whole steady window, the gold rate was 4.6% at 15 m and
/// **0% at 22, 30 and 38 m**. The draw is now a slow ripening that crosses the
/// solved centre shot in the *middle* of the steady window, so settling into
/// the hold is what the sight picture already told you it was.
class ArcheryDraw {
  const ArcheryDraw._();

  /// Time to reach full draw.
  static const double fullDrawSeconds = 1.05;

  /// How long a full draw can be held rock-steady.
  static const double focusGraceSeconds = 0.85;

  /// How long after the grace before focus is fully gone.
  static const double focusFadeSeconds = 1.2;

  /// Warn this long before the grace runs out.
  static const double focusWarnSeconds = 0.35;

  /// Power the bow has at full stretch, before the hold ripens it. Under 0.5,
  /// so an arrow snatched the instant the draw completes still lands low.
  static const double drawnPower = 0.30;

  /// Power at the end of the grace, once the hold has been carried as far as
  /// it can be. Over 0.5, so sitting on the shot throws it high.
  static const double ripePower = 0.75;

  /// Hold at which the shot is exactly the solved centre speed — the fraction
  /// of the grace where [power] crosses 0.5.
  static const double _ripeFraction =
      (0.5 - drawnPower) / (ripePower - drawnPower);

  /// The hold, in seconds, that produces the dead-centre shot. Sits inside the
  /// steady window, which is where every on-screen cue already points.
  static const double sweetHoldSeconds =
      fullDrawSeconds + focusGraceSeconds * _ripeFraction;

  /// The steadiest the bow ever gets, radians.
  ///
  /// Sized against the gold, not against zero: 7.5 mrad puts the wander at
  /// roughly 0.9x the gold's angular radius at 15 m and 2.3x at 38 m, so the
  /// sight genuinely has to be *held* on the gold rather than parked there.
  /// At the old 1.6 mrad it was welded to the middle and a bullseye cost
  /// nothing.
  static const double minSway = 0.0075;

  /// How much a totally undrawn bow wanders, radians.
  static const double maxSway = 0.020;

  /// Extra wander once focus has completely broken, radians.
  static const double brokenSway = 0.045;

  /// Multiplier on the sway's base frequencies. The wander used to cycle at
  /// 0.37 and 0.59 Hz — slow enough that a 0.2 s reaction cost nothing and the
  /// release instant was free. At 2x it runs at a realistic 0.73 and 1.18 Hz,
  /// so *when* you loose is a decision.
  static const double swayRate = 2.0;

  /// 0..1 draw for a hold of [heldSeconds]. Reaches 1 at full stretch and
  /// stays there — it is the *bow*, not the shot.
  static double progress(double heldSeconds) =>
      (heldSeconds / fullDrawSeconds).clamp(0.0, 1.0);

  /// The whole hold — draw plus grace — as 0..1. What the draw meter shows,
  /// because [progress] tops out at full stretch and then stops moving, which
  /// left the meter pinned and useless for the entire window in which the
  /// release actually matters.
  static double holdProgress(double heldSeconds) =>
      (heldSeconds / (fullDrawSeconds + focusGraceSeconds)).clamp(0.0, 1.0);

  /// Where the perfect release sits on that meter, 0..1.
  static double get sweetMeterFraction => holdProgress(sweetHoldSeconds);

  /// 0..1 focus break for a hold of [heldSeconds] — 0 while steady, 1 once the
  /// shot is a lost cause.
  static double focusBreak(double heldSeconds) {
    final over = heldSeconds - fullDrawSeconds - focusGraceSeconds;
    if (over <= 0) return 0;
    return (over / focusFadeSeconds).clamp(0.0, 1.0);
  }

  /// True while the shot is still clean but the break is imminent — the cue to
  /// flash a warning.
  static bool isWarning(double heldSeconds) {
    final t = heldSeconds - fullDrawSeconds;
    return t > focusGraceSeconds - focusWarnSeconds && focusBreak(heldSeconds) <= 0;
  }

  /// Power (for [LaunchSolver.speedFromPower]) for a hold of [heldSeconds].
  /// [sweetHoldSeconds] maps to exactly 0.5 — the solved, dead-centre shot.
  ///
  /// Two segments that meet continuously at full draw: the draw itself brings
  /// the bow up to [drawnPower], then the hold ripens it linearly to
  /// [ripePower] across the grace. Fatigue scales the whole thing down.
  static double power(double heldSeconds) {
    final base = heldSeconds < fullDrawSeconds
        ? drawnPower * progress(heldSeconds)
        : drawnPower +
            (ripePower - drawnPower) *
                ((heldSeconds - fullDrawSeconds) / focusGraceSeconds)
                    .clamp(0.0, 1.0);
    // Fatigue lets the string creep forward: a broken-focus shot is weak.
    return base * (1 - 0.55 * focusBreak(heldSeconds));
  }

  /// Angular wander of the aim, radians, for a hold of [heldSeconds].
  static double swayAmplitude(double heldSeconds) {
    final settle = math.pow(1 - progress(heldSeconds), 1.6).toDouble();
    final broken = math.pow(focusBreak(heldSeconds), 1.5).toDouble();
    return minSway + maxSway * settle + brokenSway * broken;
  }

  /// The aim offset (yaw, pitch) sway contributes at [heldSeconds] into a hold,
  /// for the arrow identified by [shotSeed].
  ///
  /// Deterministic: two identical holds on the same arrow wander identically,
  /// so a shot can be replayed and a test can pin the number.
  static (double, double) swayOffset({
    required double heldSeconds,
    required int shotSeed,
  }) {
    final amp = swayAmplitude(heldSeconds);
    final p0 = _phase(shotSeed, 1);
    final p1 = _phase(shotSeed, 2);
    final p2 = _phase(shotSeed, 3);
    final p3 = _phase(shotSeed, 4);
    final t = heldSeconds * swayRate;
    final yaw = amp *
        (0.62 * math.sin(2.3 * t + p0) + 0.38 * math.sin(3.7 * t + p1));
    final pitch = amp *
        (0.55 * math.sin(2.9 * t + p2) + 0.45 * math.sin(4.3 * t + p3));
    return (yaw, pitch);
  }

  static double _phase(int seed, int salt) {
    var x = (seed * 0x9E3779B1 + salt * 0x85EBCA77) & 0xFFFFFFFF;
    x = (x ^ (x >>> 16)) & 0xFFFFFFFF;
    x = (x * 0x7FEB352D) & 0xFFFFFFFF;
    x = (x ^ (x >>> 15)) & 0xFFFFFFFF;
    return (x & 0xFFFF) / 0x10000 * 2 * math.pi;
  }
}
