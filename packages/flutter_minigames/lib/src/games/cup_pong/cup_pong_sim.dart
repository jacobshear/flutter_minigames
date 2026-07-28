import 'dart:math' as math;

import 'package:flutter_minigames/src/engine3d/engine3d.dart';

import 'cup_pong_game.dart';
import 'cup_pong_world.dart';

/// Things that can happen during one simulation step, so the board can fire
/// sound/haptics from real physics rather than from a timer.
enum CupPongEvent {
  /// Bounced off the table surface.
  tableBounce,

  /// Rattled off a cup rim.
  rimBounce,

  /// Glanced off the outside of a cup.
  cupBounce,

  /// Dropped into a cup — the throw is over.
  made,

  /// Came to rest, rolled off the table, or timed out without scoring.
  missed,
}

/// The tuning that makes Cup Pong playable rather than a lottery.
///
/// Read [CupPongAim] before changing any of this — two of these numbers exist
/// specifically to fix measured defects, and the make-rate test in
/// `cup_pong_sim_test.dart` is the regression guard.
class CupPongTuning {
  /// Fixed launch elevation. Power does **not** change the arc shape; it
  /// modulates speed within the solved band, which is what makes the input
  /// legible.
  final double loft;

  /// Half-width of the speed band around the solved speed, as a fraction.
  /// `0.09` ⇒ the flick spans `v* · 0.91 … v* · 1.09`.
  ///
  /// Bigger = harder. This, not an absolute speed range, is the whole trick:
  /// at true scale the absolute make window is ~1% of the input space, so a
  /// linear map onto (say) 4.5–14 m/s scores approximately never.
  final double speedBand;

  /// How far a fully diagonal swipe can steer the aim ray, radians.
  ///
  /// Must cover the yaw to the outermost back-row cup (~0.164 rad at the
  /// shipped rack geometry) or those cups can never be selected — a smaller
  /// span silently makes four of the ten cups unaimable.
  final double aimSpan;

  /// Swipe angle (radians off vertical) → aim yaw multiplier.
  final double aimGain;

  /// How far the launch direction may deviate from a dead-straight line to the
  /// targeted cup, radians. Small on purpose: lateral is the assisted axis,
  /// depth (power) is the skill axis.
  final double residualYaw;

  /// Scoring radius as a multiple of the **drawn** mouth radius.
  ///
  /// The cup is painted its true size and scored bigger. This is the strongest
  /// playability lever there is, and it is invisible — a ball clipping the far
  /// lip still drops. Below ~1.3 the game feels broken; above ~2.0 the rack
  /// becomes one continuous target.
  final double acceptanceScale;

  /// Backspin imparted at launch, rad/s (cosmetic — drives the ball's seam).
  final double spinRate;

  /// Swipe length in logical pixels that reads as full power.
  final double fullPowerDrag;

  /// Shorter swipes than this do not throw.
  final double deadZone;

  /// Bounce energy kept off the table, a cup rim, and a cup wall.
  ///
  /// Deliberately dead. With lively values (0.5 / 0.34 / 0.4) a *third* of all
  /// makes were bounce-ins — a badly under- or over-powered throw would skip off
  /// the table and rattle into something, which flattened the whole power axis
  /// and made the make rate nearly independent of the flick. Killing the
  /// rebound is what restored power as the skill axis.
  ///
  /// [tableRestitution] sits at the top of the range that is *provably* safe:
  /// the fastest landing a solved throw can produce is about 4 m/s vertical, so
  /// even a perfect rebound apexes at `(0.30·4)²/2g ≈ 7 cm` above the felt —
  /// short of the 12 cm mouth plane, which is the only way a bounce could steal
  /// a make. Below this the ball reads as a beanbag; above it, the guard rates
  /// start to move.
  final double tableRestitution;
  final double rimRestitution;
  final double wallRestitution;

  /// Downward speed under which a table contact stops being a bounce and starts
  /// being a roll. Without this the ball micro-bounces every step forever, and
  /// [Projectile.bounce] scrubs [friction] on each one — which is precisely why
  /// a miss used to arrive, stop dead, and sit there.
  final double bounceThreshold;

  /// Rolling resistance, fraction of horizontal speed bled per second. Low: a
  /// ping-pong ball on varnished wood carries, and a miss that trundles to the
  /// rail and drops off the edge is worth more than one that parks.
  final double rollFriction;

  /// Horizontal speed under which a rolling ball is finally at rest.
  final double rollRestSpeed;

  final ThrowConfig config;

  const CupPongTuning({
    this.loft = 0.62,
    this.speedBand = 0.26,
    this.aimSpan = 0.20,
    this.aimGain = 0.34,
    this.residualYaw = 0.028,
    this.acceptanceScale = 1.40,
    this.spinRate = 16,
    this.fullPowerDrag = 190,
    this.deadZone = 16,
    this.tableRestitution = 0.30,
    this.rimRestitution = 0.18,
    this.wallRestitution = 0.22,
    this.bounceThreshold = 0.5,
    this.rollFriction = 1.5,
    this.rollRestSpeed = 0.11,
    this.config = const ThrowConfig(
      gravity: 9.81,
      drag: 0.05,
      restSpeed: 0.28,
      fixedDt: 1 / 240,
      maxSteps: 1800,
    ),
  });

  /// The radius the physics scores with, given the drawn mouth radius.
  double get acceptanceRadius => CupPongWorld.cupMouthRadius * acceptanceScale;

  CupPongTuning copyWith({
    double? loft,
    double? speedBand,
    double? aimSpan,
    double? aimGain,
    double? residualYaw,
    double? acceptanceScale,
  }) =>
      CupPongTuning(
        loft: loft ?? this.loft,
        speedBand: speedBand ?? this.speedBand,
        aimSpan: aimSpan ?? this.aimSpan,
        aimGain: aimGain ?? this.aimGain,
        residualYaw: residualYaw ?? this.residualYaw,
        acceptanceScale: acceptanceScale ?? this.acceptanceScale,
        spinRate: spinRate,
        fullPowerDrag: fullPowerDrag,
        deadZone: deadZone,
        tableRestitution: tableRestitution,
        rimRestitution: rimRestitution,
        wallRestitution: wallRestitution,
        bounceThreshold: bounceThreshold,
        rollFriction: rollFriction,
        rollRestSpeed: rollRestSpeed,
        config: config,
      );
}

/// A resolved aim: which cup the flick is solving for, and the velocity it
/// launches with.
class CupPongAimSolution {
  /// The cup the solver powered for.
  final CupPongCup target;

  /// Mouth centre of [target] in world space.
  final Vec3 targetMouth;

  /// Launch velocity for this flick.
  final Vec3 velocity;

  /// 0..1 flick power.
  final double power;

  /// The exact speed that lands in [target] (drag included).
  final double solvedSpeed;

  const CupPongAimSolution({
    required this.target,
    required this.targetMouth,
    required this.velocity,
    required this.power,
    required this.solvedSpeed,
  });
}

/// Turns a swipe into a throw.
///
/// ## Why this isn't `ThrowAim`
///
/// [ThrowAim] maps a flick onto an absolute speed range. That is the right
/// primitive for a free-aim game and the wrong one here: the cup is ~9 cm
/// across at 1.7 m, so the sliver of absolute speeds that score is narrower
/// than a pixel of swipe and the game becomes unplayable.
///
/// Instead, every flick is solved:
/// 1. the swipe's direction picks an **aim ray**, and the alive cup nearest
///    that ray becomes the target — so steering toward the back row makes the
///    solver power for the back row;
/// 2. [LaunchSolver.speedToHit] + [LaunchSolver.refineForDrag] give the exact
///    speed `v*` that drops into that cup;
/// 3. the flick's 0..1 power is mapped through
///    [LaunchSolver.speedFromPower] onto `v* · (1 ± band)`.
///
/// A medium flick is therefore roughly right and skill is fine modulation.
/// Difficulty still scales with distance for free: a fixed ± band is a tighter
/// *absolute* window the further the cup is, and the deep cups have no rack
/// behind the shooter's error to catch a long throw.
class CupPongAim {
  final CupPongTuning tuning;

  /// Cached `v*` per cup id — it depends only on the cup, not on the flick, so
  /// a drag can update at 60 Hz without re-running the drag refinement.
  final Map<int, double> _solved = {};

  CupPongAim({this.tuning = const CupPongTuning()});

  /// Drop cached solutions (call when the rack changes, e.g. a re-rack).
  void invalidate() => _solved.clear();

  /// 0..1 power for a swipe of ([dx], [dy]) pixels (screen space, y down).
  double power(double dx, double dy) {
    if (-dy <= 0) return 0; // must be an up-screen flick
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < tuning.deadZone) return 0;
    return (len / tuning.fullPowerDrag).clamp(0.0, 1.0);
  }

  /// The aim ray's yaw (radians, +right) for a swipe.
  double aimYaw(double dx, double dy) {
    if (dx == 0 && dy == 0) return 0;
    // Angle of the swipe off straight-up-screen.
    final off = math.atan2(dx, -dy);
    return (off * tuning.aimGain)
        .clamp(-tuning.aimSpan, tuning.aimSpan)
        .toDouble();
  }

  /// Yaw from the launch point to a cup.
  static double yawTo(Vec3 mouth) => math.atan2(
        mouth.x - CupPongWorld.launchPoint.x,
        mouth.z - CupPongWorld.launchPoint.z,
      );

  /// The alive cup nearest the aim ray, or null if the rack is empty.
  CupPongCup? targetFor(List<CupPongCup> cups, double yaw) {
    CupPongCup? best;
    var bestErr = double.infinity;
    for (final c in cups) {
      final err = (yawTo(CupPongWorld.mouthOf(c)) - yaw).abs();
      if (err < bestErr) {
        bestErr = err;
        best = c;
      }
    }
    return best;
  }

  /// The exact launch speed that drops into [cup], drag included. Cached.
  double solvedSpeedFor(CupPongCup cup) {
    final cached = _solved[cup.id];
    if (cached != null) return cached;
    final mouth = CupPongWorld.mouthOf(cup);
    final from = CupPongWorld.launchPoint;
    final dx = mouth.x - from.x;
    final dz = mouth.z - from.z;
    final horizontal = math.sqrt(dx * dx + dz * dz);
    final analytic = LaunchSolver.speedToHit(
          horizontalDistance: horizontal,
          heightDelta: mouth.y - from.y,
          loft: tuning.loft,
          gravity: tuning.config.gravity,
        ) ??
        6.0;
    final refined = LaunchSolver.refineForDrag(
      from: from,
      target: mouth,
      loft: tuning.loft,
      analyticSpeed: analytic,
      config: tuning.config,
    );
    _solved[cup.id] = refined;
    return refined;
  }

  /// Resolve a swipe into a throw, or null if it was too short to register or
  /// there is nothing to throw at.
  CupPongAimSolution? solve({
    required List<CupPongCup> cups,
    required double dx,
    required double dy,
  }) {
    if (cups.isEmpty) return null;
    final p = power(dx, dy);
    if (p <= 0) return null;
    final yaw = aimYaw(dx, dy);
    final target = targetFor(cups, yaw);
    if (target == null) return null;

    final mouth = CupPongWorld.mouthOf(target);
    final solved = solvedSpeedFor(target);
    final speed = LaunchSolver.speedFromPower(
      targetSpeed: solved,
      power: p,
      band: tuning.speedBand,
    );

    // Aim assist: the throw goes at the cup, offset by however far the swipe
    // pointed away from it, capped tight.
    final toTarget = yawTo(mouth);
    final residual = (yaw - toTarget)
        .clamp(-tuning.residualYaw, tuning.residualYaw)
        .toDouble();
    final launchYaw = toTarget + residual;

    final up = speed * math.sin(tuning.loft);
    final along = speed * math.cos(tuning.loft);
    return CupPongAimSolution(
      target: target,
      targetMouth: mouth,
      velocity: Vec3(
        along * math.sin(launchYaw),
        up,
        along * math.cos(launchYaw),
      ),
      power: p,
      solvedSpeed: solved,
    );
  }

  // NOTE: there is deliberately no `preview()` here. Simulating the throw
  // ahead of time to draw its arc down the table is a crosshair with extra
  // steps — it answers "where will this land?" before the player has committed,
  // which is the question the game is supposed to be about. The only forward
  // simulation that runs is CupPongThrowSim, after release.
}

/// One thrown ball, simulated a fixed step at a time against the rack.
///
/// Deliberately stepped rather than run-to-completion so the board can drive it
/// from a ticker and render every frame of the arc — but it is equally happy
/// running headless, which is what the make-rate test does.
class CupPongThrowSim {
  final CupPongTuning tuning;

  /// The rack being thrown at (alive cups only).
  final List<CupPongCup> cups;

  final Projectile ball;

  /// Cached mouth positions, parallel to [cups].
  final List<Vec3> _mouths;

  int _steps = 0;
  bool _finished = false;
  int? _hitCupId;
  bool _atRest = false;
  bool _rolling = false;
  double _lastImpact = 0;

  CupPongThrowSim({
    required this.cups,
    required Vec3 velocity,
    this.tuning = const CupPongTuning(),
  })  : ball = Projectile(
          position: CupPongWorld.launchPoint,
          velocity: velocity,
          config: tuning.config,
          spinRate: tuning.spinRate,
        ),
        _mouths = [for (final c in cups) CupPongWorld.mouthOf(c)];

  bool get finished => _finished;
  int? get hitCupId => _hitCupId;
  Vec3 get position => ball.position;
  double get spin => ball.spin;
  int get steps => _steps;

  /// True once the ball has stopped **on the table**, as opposed to having gone
  /// over an edge or run out of patience. The board only leaves a ball lying in
  /// the scene when this is set — parking one wherever the sim happened to give
  /// up used to strand it in mid-air out past the rail.
  bool get atRest => _atRest;

  /// True while the ball is rolling on the felt rather than flying.
  bool get rolling => _rolling;

  /// Impact speed of the most recent contact, world units/s. Lets the board
  /// scale a cue to how hard the hit actually was instead of firing one flat
  /// sample for a skimming touch and a full-power slam alike.
  double get lastImpactSpeed => _lastImpact;

  /// Advance one fixed step, returning what happened (null = uneventful).
  CupPongEvent? step() {
    if (_finished) return null;
    _steps++;
    final from = ball.step();
    final to = ball.position;

    // 1. Did it drop in? Swept, descending-only, and fattened — see
    //    CupPongTuning.acceptanceScale. Nearest centre wins where the fattened
    //    discs of neighbouring cups overlap.
    final r = tuning.acceptanceRadius;
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < cups.length; i++) {
      if (!Surfaces.passesDownThroughDisc(from, to, _mouths[i], r)) continue;
      final t = Surfaces.descendingPlaneCrossing(from, to, _mouths[i].y)!;
      final at = Surfaces.lerp(from, to, t);
      final d = Surfaces.horizontalDistance(at, _mouths[i].x, _mouths[i].z);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best != null) {
      _hitCupId = cups[best].id;
      _finished = true;
      return CupPongEvent.made;
    }

    // 2. Rim rattle — only reachable outside the acceptance radius, so this is
    //    genuinely the "so close" bounce and never steals a make.
    for (var i = 0; i < cups.length; i++) {
      final n = Surfaces.rimContact(
        to,
        CupPongWorld.ballRadius,
        _mouths[i],
        r,
        CupPongWorld.ballRadius * 0.6,
      );
      if (n != null) {
        _lastImpact = ball.velocity.length;
        ball.bounce(n, restitution: tuning.rimRestitution, friction: 0.3);
        return CupPongEvent.rimBounce;
      }
    }

    // 3. Glancing off the outside of a cup body.
    for (var i = 0; i < cups.length; i++) {
      final m = _mouths[i];
      final n = Surfaces.cylinderWallContact(
        to,
        CupPongWorld.ballRadius,
        m.x,
        m.z,
        (CupPongWorld.cupMouthRadius + CupPongWorld.cupBaseRadius) / 2,
        CupPongWorld.surfaceY,
        CupPongWorld.cupMouthY,
      );
      if (n != null) {
        _lastImpact = ball.velocity.length;
        ball.bounce(n, restitution: tuning.wallRestitution, friction: 0.24);
        // Push clear so the next step doesn't re-trigger the same wall.
        final clear =
            (CupPongWorld.cupMouthRadius + CupPongWorld.cupBaseRadius) / 2;
        final horiz = Surfaces.horizontalDistance(ball.position, m.x, m.z);
        final want = clear + CupPongWorld.ballRadius + 1e-4;
        if (horiz < want && horiz > 1e-9) {
          ball.position = Vec3(
            m.x + (ball.position.x - m.x) / horiz * want,
            ball.position.y,
            m.z + (ball.position.z - m.z) / horiz * want,
          );
        }
        return CupPongEvent.cupBounce;
      }
    }

    // 4. Table surface — bounce, then roll, then rest.
    //
    // The two branches are the whole reason a miss now reads as a miss. The old
    // code bounced on *every* grounded step, and [Projectile.bounce] scrubs its
    // friction each time, so once the ball settled it lost 20% of its horizontal
    // speed 240 times a second and stopped dead within a few frames of landing.
    // Splitting "still falling" from "now rolling" gives the arrival its weight
    // back and lets the ball carry to the rail — or over it.
    final onTable = ball.position.z >= CupPongWorld.nearZ &&
        ball.position.z <= CupPongWorld.farZ &&
        ball.position.x.abs() <= CupPongWorld.halfWidth;
    if (onTable && ball.position.y - CupPongWorld.ballRadius <= 0) {
      ball.position = Vec3(
        ball.position.x,
        CupPongWorld.ballRadius,
        ball.position.z,
      );
      final vy = ball.velocity.y;
      var bounced = false;
      if (vy < -tuning.bounceThreshold) {
        _lastImpact = ball.velocity.length;
        ball.bounce(
          const Vec3(0, 1, 0),
          restitution: tuning.tableRestitution,
          friction: 0.2,
        );
        bounced = true;
      } else if (vy < 0) {
        // Too slow to bounce: from here it is rolling, not falling.
        ball.velocity = Vec3(ball.velocity.x, 0, ball.velocity.z);
      }

      if (!bounced) {
        _rolling = true;
        final dt = tuning.config.fixedDt;
        final damp = (1 - tuning.rollFriction * dt).clamp(0.0, 1.0);
        ball.velocity = Vec3(
          ball.velocity.x * damp,
          ball.velocity.y,
          ball.velocity.z * damp,
        );
        // Spin from travel: a rolling ball turns at v/r, so the seam keeps pace
        // with the felt instead of coasting on whatever backspin it launched
        // with.
        ball.spinRate =
            ball.velocity.horizontalLength / CupPongWorld.ballRadius;
        if (ball.velocity.horizontalLength < tuning.rollRestSpeed) {
          ball.velocity = Vec3.zero;
          ball.spinRate = 0;
          _finished = true;
          _atRest = true;
          return CupPongEvent.missed;
        }
      } else {
        _rolling = false;
      }
      if (bounced) return CupPongEvent.tableBounce;
    } else {
      _rolling = false;
    }

    // 5. Off the table, or out of patience.
    if (ball.position.y < -CupPongWorld.apronDepth * 2 ||
        _steps >= tuning.config.maxSteps) {
      _finished = true;
      return CupPongEvent.missed;
    }
    return null;
  }

  /// Run to completion headlessly. Returns the resolved event.
  CupPongEvent run() {
    var last = CupPongEvent.missed;
    while (!_finished) {
      final e = step();
      if (e != null && (e == CupPongEvent.made || e == CupPongEvent.missed)) {
        last = e;
      }
    }
    return last;
  }
}
