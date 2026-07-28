import 'dart:math' as math;

import 'package:minigames_3d/minigames_3d.dart';

import 'darts_board_geometry.dart';

/// World layout for the darts room, in metres.
///
/// The axes are the harness convention: +x right, +y up, +z down-range. The
/// board hangs face-on in the vertical plane `z == boardZ`, so a throw scores
/// where it crosses that plane ([Surfaces.verticalPlaneHit]).
///
/// ## Staged, not surveyed
///
/// The throw distance is regulation (2.37 m oche-to-face) and every ring ratio
/// on the board is regulation. Two things are deliberately staged for the
/// camera:
///
/// * The board is **scaled up** ([boardRadius] 0.38 m against a real 0.17 m).
///   At true size and a field of view wide enough to show the room, the board
///   is 20 % of the frame and the treble ring is two pixels — unreadable and
///   unaimable on a phone. Scaling the board while keeping every ring *ratio*
///   regulation preserves everything the eye actually reads.
/// * The camera sits low ([DartsCamera.eye] at 0.62 m) with the board centred
///   at 0.80 m. Eye-level framing at 2.4 m puts the floor entirely out of
///   frame, which throws away the strongest depth cue there is. A low camera
///   buys back a band of receding floor under the board.
abstract final class DartsWorld {
  /// Depth of the board face (regulation oche-to-face distance).
  static const double boardZ = 2.37;

  /// The wall the board hangs on, just behind the face.
  static const double wallZ = 2.45;

  /// Height of the bullseye.
  static const double boardCentreY = 0.80;

  /// Outer edge of the double ring — the scoring radius. See the class doc for
  /// why this is not 0.17 m.
  static const double boardRadius = 0.36;

  /// Outer edge of the numbered wire ring around the scoring area.
  static double get surroundRadius =>
      boardRadius * DartsBoardGeometry.numberRingRatio;

  static const double floorY = 0.0;

  /// Half-width of the room (side walls), and ceiling height.
  static const double roomHalfWidth = 1.55;
  static const double ceilingY = 2.35;

  /// Where the dart leaves the hand — below and slightly right of the camera,
  /// so it flies up into frame the way a real throw does.
  static const Vec3 release = Vec3(0.09, 0.42, 0.15);

  /// Launch elevation. Flat enough to read as a dart throw, steep enough that
  /// every point on the board is reachable (the solver needs
  /// `z·tan(loft) > Δy`, and the top of the board is Δy = 0.75 m at 2.22 m).
  static const double loft = 0.52;

  /// Real gravity — a dart's visible drop over 2.4 m is part of the feel.
  static const ThrowConfig config = ThrowConfig(
    gravity: 9.81,
    drag: 0.12,
    fixedDt: 1 / 120,
    maxSteps: 900,
    restSpeed: 0.2,
  );

  /// Half-width of the speed band the flick is mapped into, around the solved
  /// speed. See [DartsAim] for why this is a band and not an absolute range.
  static const double speedBand = 0.055;

  /// Lateral miss at a fully sideways swipe, in metres on the board face.
  static const double maxLateralScatter = 0.20;

  /// Flick → 0..1 power. Only [ThrowAim.power] is used; the launch velocity
  /// comes from [LaunchSolver] instead (see [DartsAim]).
  ///
  /// [ThrowAim.fullPowerDrag] is long — most of a phone's play area — because
  /// with the reticle gone the swipe's *length* is the only thing setting the
  /// landing height. At the old 220 px a normal enthusiastic flick saturated
  /// and every throw pinned the top of the board.
  static const ThrowAim flick = ThrowAim(fullPowerDrag: 340, deadZone: 16);

  /// The shortest swipe that throws at all, as a fraction of full power.
  /// [DartsSwing] rescales the band above it back to 0..1, so the shortest
  /// throwing swipe reaches the bottom of the board and not a third of the way
  /// up it.
  static double get minPower => flick.deadZone / flick.fullPowerDrag;

  // -- Swipe → aim mapping. See [DartsSwing]. ---------------------------------

  /// Where the shortest and the longest swipe **land**, as a fraction of
  /// [boardRadius]. The whole face, bottom double to top double: a swipe that
  /// barely clears the dead zone drops into the 3, a full-length one reaches
  /// the 20.
  /// The low end runs past the wire because [DartsSwing.bandDrop] is a fit, not
  /// an identity, and it under-drops the softest throws by about a centimetre —
  /// asking for slightly more than the board is what puts the bottom doubles
  /// genuinely in reach.
  static const double lowLandRatio = -1.00;
  static const double highLandRatio = 0.95;

  /// Radius the intended landing point is confined to, as a fraction of
  /// [boardRadius]. Just inside the wire, so the outer doubles stay reachable
  /// without a diagonal swipe sailing off the face.
  static const double aimReachRatio = 0.95;

  /// Sideways fraction of a swipe (|dx| ÷ length) that deflects the throw all
  /// the way to the edge of the board — about 33° off vertical.
  static const double fullDeflection = 0.55;

  /// Share of the lateral aim carried by the aim point itself. The remainder
  /// comes from [maxLateralScatter], so an angled swipe both points the throw
  /// across *and* launches it across, the way one gesture really would.
  static const double lateralAimShare = 0.5;

  /// Length of a dart, tail to tip. Scaled with the board (a real dart is
  /// ~0.15 m against a 0.17 m board radius; this keeps that proportion).
  static const double dartLength = 0.30;

  /// World point for a board-face offset ([bx] right, [by] up from the bull).
  static Vec3 boardPoint(double bx, double by) =>
      Vec3(bx, boardCentreY + by, boardZ);
}

/// Turns a flick into a launch velocity.
///
/// ## Why this bands the speed instead of mapping it
///
/// [LaunchSolver]'s doc explains the trap: at physical scale a throw game's
/// make window is around 1 %, so mapping a swipe onto an absolute speed range
/// misses essentially always. Darts is worse than most — the treble bed is
/// about 10 mm tall on a board 760 mm across.
///
/// So an aim point is solved for first, and the flick perturbs it:
///
/// 1. [LaunchSolver.speedToHit] solves the closed-form speed onto the aim,
/// 2. [LaunchSolver.refineForDrag] corrects it against the real integrator,
/// 3. [LaunchSolver.speedFromPower] maps the flick's 0..1 power through a
///    ±[DartsWorld.speedBand] window around that speed.
///
/// The aim itself comes from the swipe — see [DartsSwing], which is the whole
/// input model. Nothing else aims: there is no cursor to place.
abstract final class DartsAim {
  /// The point the dart is actually launched at, once the swipe's lateral
  /// component has been folded in as scatter.
  static Vec3 scatteredTarget({
    required double aimX,
    required double aimY,
    required double swipeDx,
  }) {
    final lateral = (swipeDx / DartsWorld.flick.fullPowerDrag)
            .clamp(-1.0, 1.0) *
        DartsWorld.maxLateralScatter;
    return DartsWorld.boardPoint(aimX + lateral, aimY);
  }

  /// The solved speed that lands a throw from [DartsWorld.release] on [target]
  /// (drag included). Null when the target is unreachable at the fixed loft.
  static double? solveSpeed(Vec3 target) {
    const from = DartsWorld.release;
    final dx = target.x - from.x;
    final dz = target.z - from.z;
    final horizontal = math.sqrt(dx * dx + dz * dz);
    final analytic = LaunchSolver.speedToHit(
      horizontalDistance: horizontal,
      heightDelta: target.y - from.y,
      loft: DartsWorld.loft,
      gravity: DartsWorld.config.gravity,
    );
    if (analytic == null) return null;
    return LaunchSolver.refineForDrag(
      from: from,
      target: target,
      loft: DartsWorld.loft,
      analyticSpeed: analytic,
      config: DartsWorld.config,
    );
  }

  /// Launch velocity for a flick of [power] (0..1) and horizontal swipe
  /// [swipeDx] pixels, aiming at ([aimX], [aimY]) on the board face.
  ///
  /// Returns null only when the aim point is unreachable, which
  /// [DartsWorld.aimReachRatio] prevents in practice.
  static Vec3? launch({
    required double aimX,
    required double aimY,
    required double power,
    required double swipeDx,
  }) {
    final target =
        scatteredTarget(aimX: aimX, aimY: aimY, swipeDx: swipeDx);
    final solved = solveSpeed(target);
    if (solved == null) return null;
    final speed = LaunchSolver.speedFromPower(
      targetSpeed: solved,
      power: power,
      band: DartsWorld.speedBand,
    );
    const from = DartsWorld.release;
    final dx = target.x - from.x;
    final dz = target.z - from.z;
    final horizontal = math.sqrt(dx * dx + dz * dz);
    if (horizontal < 1e-9) return null;
    final along = speed * math.cos(DartsWorld.loft);
    return Vec3(
      along * dx / horizontal,
      speed * math.sin(DartsWorld.loft),
      along * dz / horizontal,
    );
  }
}

/// One swipe, read as a throw. **This is the entire input model.**
///
/// A dart is thrown by dragging up-screen and letting go. Two things about the
/// drag matter, and nothing else:
///
/// * **How long it is** → how high the dart lands. The length is
///   [ThrowAim.power] (dead zone and all), and that walks the landing height
///   from [DartsWorld.lowLandRatio] to [DartsWorld.highLandRatio].
/// * **How far off vertical it is** → how far across the dart lands. The
///   deflection is `dx ÷ length`, saturating at [DartsWorld.fullDeflection].
///
/// Length and angle are independent by construction — a short, steeply angled
/// swipe reaches the side of the board without also throwing hard — which is
/// what a raw `dx`/`dy` split cannot do, since `dx` inflates the length.
///
/// ## Why the throw is split between the aim and the launch
///
/// The lateral is carried partly by the aim point ([DartsWorld.lateralAimShare])
/// and partly by the launch scatter ([DartsWorld.maxLateralScatter]); the
/// height is carried by the aim, with the speed band riding it up or down
/// around that aim ([bandDrop]). One gesture pointing the throw *and*
/// colouring the launch is what a real throw does, and it keeps both the
/// solver band and the scatter live rather than reducing them to inert
/// constants behind a cursor.
///
/// The intended landing point is kept inside the face by taking the lateral
/// span at the landing height (the chord, not a box), so a hard diagonal swipe
/// reaches the top-corner double instead of sailing off the wire.
class DartsSwing {
  /// 0..1 flick length, past the dead zone.
  final double power;

  /// −1..1 sideways deflection of the swipe.
  final double deflection;

  /// Where the swipe says the dart should land, metres from the bullseye. This
  /// is the design intent; the dart lands within a couple of centimetres of it
  /// (see [bandDrop]), and that slack is the touch in the throw.
  final double landX;
  final double landY;

  /// The aim point on the board face, metres from the bullseye — [landX] and
  /// [landY] with the launch's own contribution backed out.
  final double aimX;
  final double aimY;

  /// Lateral pixels handed to [DartsAim.scatteredTarget]. Synthesised from
  /// [deflection] rather than taken raw, so the scatter tracks the swipe's
  /// *angle* like the aim does.
  final double swipeDx;

  const DartsSwing({
    required this.power,
    required this.deflection,
    required this.landX,
    required this.landY,
    required this.aimX,
    required this.aimY,
    required this.swipeDx,
  });

  /// Launch velocity for this swing, or null if the aim is unreachable.
  Vec3? get velocity => DartsAim.launch(
        aimX: aimX,
        aimY: aimY,
        power: power,
        swipeDx: swipeDx,
      );

  /// Metres the speed band moves a dart off its aim, for a flick of [power]
  /// aiming at height [y] on the face.
  ///
  /// Fitted to the integrator rather than derived — a closed form would have
  /// to invert [LaunchSolver.refineForDrag]. The fit is linear in height (the
  /// band bites less high on the board, where the dart arrives steeper and
  /// converts a speed error into less height error) and the two halves of the
  /// band have their own slope, because a slow dart falls further short than a
  /// fast one overshoots. It is close, not exact — `darts_throw_test` holds the
  /// residual to 25 mm on a 720 mm board, worst at the softest throws.
  static double bandDrop(double power, double y) {
    final t = (power.clamp(0.0, 1.0) - 0.5) * 2; // -1..1 across the band
    return t * (t < 0 ? 0.108 - 0.123 * y : 0.091 - 0.103 * y);
  }

  /// Read a swipe of ([dx], [dy]) pixels (screen space, y down) as a throw.
  /// Null when it is not a throw at all: sideways-only, downward, or inside
  /// [ThrowAim.deadZone].
  static DartsSwing? read(double dx, double dy) {
    final power = DartsWorld.flick.power(dx, dy);
    if (power <= 0) return null;

    final length = math.sqrt(dx * dx + dy * dy);
    final deflection =
        (dx / length / DartsWorld.fullDeflection).clamp(-1.0, 1.0);

    // Where the swipe says the dart should land, then the aim that gets it
    // there once the band has had its say.
    final reachedPower = ((power - DartsWorld.minPower) /
            (1 - DartsWorld.minPower))
        .clamp(0.0, 1.0);
    final landY = DartsWorld.boardRadius *
        (DartsWorld.lowLandRatio +
            (DartsWorld.highLandRatio - DartsWorld.lowLandRatio) *
                reachedPower);
    final aimY = landY - bandDrop(power, landY);

    // Lateral room left at that height — the chord of the reachable disc, so
    // the reachable set is the board face rather than a box around it.
    final reach = DartsWorld.boardRadius * DartsWorld.aimReachRatio;
    final half = math.sqrt(math.max(0.0, reach * reach - landY * landY));
    final landX = deflection * half;

    final scatterMetres = landX * (1 - DartsWorld.lateralAimShare);
    return DartsSwing(
      power: power,
      deflection: deflection,
      landX: landX,
      landY: landY,
      aimX: landX * DartsWorld.lateralAimShare,
      aimY: aimY.clamp(-reach, reach),
      swipeDx: scatterMetres /
          DartsWorld.maxLateralScatter *
          DartsWorld.flick.fullPowerDrag,
    );
  }
}

/// Where a throw finished.
class DartsImpact {
  /// World point of the impact.
  final Vec3 point;

  /// Offset on the board face from the bullseye (x right, y up), metres.
  final double boardX;
  final double boardY;

  /// Score, via [DartsBoardGeometry.hitAt]. A dart that hit the wall or the
  /// floor is [DartHit.miss].
  final DartHit hit;

  /// True when the dart stuck in the scoring area rather than the surround.
  final bool onBoard;

  /// True when the dart hit the floor before ever reaching the board plane.
  final bool onFloor;

  /// Unit direction the dart was travelling at impact — the angle it sticks at.
  final Vec3 direction;

  /// Arrival speed, m/s. Pure presentation: how hard the thud is, how far the
  /// beds are pushed and how much the shaft rings. Nothing in the rules reads
  /// it.
  final double speed;

  /// True when the point landed on a wire and was kicked clear of it — see
  /// [DartsWire]. The score is the bed it was kicked *into*, which is the bed
  /// it is drawn sitting in.
  final bool deflected;

  const DartsImpact({
    required this.point,
    required this.boardX,
    required this.boardY,
    required this.hit,
    required this.onBoard,
    required this.onFloor,
    required this.direction,
    this.speed = 0,
    this.deflected = false,
  });

  /// Distance from the bullseye on the board face, metres.
  double get radius => math.sqrt(boardX * boardX + boardY * boardY);

  /// Arrival speed as 0..1 over the band a throw can actually produce. Used to
  /// scale the impact's whole presentation — sound, haptic, wobble, quiver.
  double get strength =>
      ((speed - DartsWire.softArrival) /
              (DartsWire.hardArrival - DartsWire.softArrival))
          .clamp(0.0, 1.0);
}

/// The spider, as an obstacle rather than as paint.
///
/// A dart cannot come to rest balanced on a wire: it is thrown off into one of
/// the two beds the wire divides. Before this, a point that landed on a wire
/// silently resolved to whichever bed the floating-point angle happened to fall
/// in — the dart was drawn sitting *on* the wire while the scoreboard quietly
/// claimed the bed next to it. Now the point is kicked clear first and the
/// score is read afterwards, so the dart is always in the bed it scored.
///
/// The scoring geometry itself is untouched: [DartsBoardGeometry.hitAt] still
/// decides everything, it is simply asked about a point no dart could balance
/// on.
abstract final class DartsWire {
  /// Half the spider's thickness, in board-face metres. A dart whose point
  /// lands inside this band of a wire has struck the wire.
  static const double halfWidth = 0.0012;

  /// How far clear of the wire's centre line a deflected dart ends up. Wide
  /// enough that the dart is visibly beside the wire rather than under it.
  static const double clearance = 0.0052;

  /// Arrival speeds that read as a floated dart and as a rifled one, m/s.
  static const double softArrival = 5.4;
  static const double hardArrival = 7.4;

  /// The ring wires, as fractions of the scoring radius.
  static const List<double> ringRatios = [
    DartsBoardGeometry.innerBullRatio,
    DartsBoardGeometry.outerBullRatio,
    DartsBoardGeometry.innerTrebleRatio,
    DartsBoardGeometry.outerTrebleRatio,
    DartsBoardGeometry.innerDoubleRatio,
    1.0,
  ];

  /// ([x], [y]) kicked clear of any wire it landed on, plus whether it was.
  ///
  /// Deterministic: a point sitting exactly on a wire goes to the outer /
  /// clockwise side every time, so the same throw always scores the same. The
  /// outermost ring wire is the one exception — it always kicks *inward*,
  /// because a dart deflected off the outer edge of the double stays in the
  /// board rather than being promoted to a miss.
  static (double, double, bool) deflect(double x, double y,
      {required double boardRadius}) {
    if (boardRadius <= 0) return (x, y, false);
    var px = x;
    var py = y;
    var hit = false;

    final r = math.sqrt(px * px + py * py);
    if (r > 1e-9 && r <= boardRadius + halfWidth) {
      for (final ratio in ringRatios) {
        final wire = ratio * boardRadius;
        final d = r - wire;
        if (d.abs() >= halfWidth) continue;
        final outward = ratio >= 1.0 ? -1.0 : (d >= 0 ? 1.0 : -1.0);
        final target = wire + outward * clearance;
        px *= target / r;
        py *= target / r;
        hit = true;
        break;
      }
    }

    // Sector wires only exist outside the outer bull — inside it the board is
    // one continuous bed and there is nothing to strike.
    final r2 = math.sqrt(px * px + py * py);
    final bull = DartsBoardGeometry.outerBullRatio * boardRadius;
    if (r2 > bull && r2 <= boardRadius) {
      const span = DartsBoardGeometry.sectorSpan;
      final angle = math.atan2(px, py);
      // Wires sit at the half-sector offsets, so they are the integers of this.
      final n = (angle / span - 0.5).roundToDouble();
      final wireAngle = (n + 0.5) * span;
      final delta = angle - wireAngle;
      if ((delta * r2).abs() < halfWidth) {
        final side = delta >= 0 ? 1.0 : -1.0;
        final kicked = wireAngle + side * clearance / r2;
        px = math.sin(kicked) * r2;
        py = math.cos(kicked) * r2;
        hit = true;
      }
    }
    return (px, py, hit);
  }
}

/// One dart in flight: a fixed-step [Projectile] plus swept board detection.
///
/// Headless and deterministic — [simulate] runs a whole throw in a unit test,
/// and the widget drives the very same code with [advance].
class DartsFlight {
  final Projectile _projectile;

  /// Seconds since launch (fixed-step accumulated, not wall clock).
  double elapsed = 0;

  DartsImpact? _impact;
  double _accumulator = 0;
  int _steps = 0;

  DartsFlight({required Vec3 velocity, Vec3 origin = DartsWorld.release})
      : _projectile = Projectile(
          position: origin,
          velocity: velocity,
          config: DartsWorld.config,
        );

  Vec3 get position => _projectile.position;
  Vec3 get velocity => _projectile.velocity;

  /// The impact, once the dart has landed.
  DartsImpact? get impact => _impact;
  bool get done => _impact != null;

  /// Advance by [dt] wall-clock seconds in fixed physics steps. Stops the
  /// instant the dart crosses the board plane (or the floor).
  void advance(double dt) {
    if (done) return;
    _accumulator += dt.clamp(0.0, 0.1);
    final step = DartsWorld.config.fixedDt;
    while (_accumulator >= step && !done) {
      _accumulator -= step;
      _stepOnce();
    }
  }

  void _stepOnce() {
    final from = _projectile.step();
    elapsed += DartsWorld.config.fixedDt;
    _steps++;
    final to = _projectile.position;

    // Swept board-plane crossing: a fast dart cannot tunnel past the face.
    final cross = Surfaces.verticalPlaneHit(from, to, DartsWorld.boardZ);
    if (cross != null) {
      _impact = _impactAt(cross, onFloor: false);
      return;
    }
    // Fell short and hit the floor.
    if (to.y <= DartsWorld.floorY) {
      final t = Surfaces.descendingPlaneCrossing(from, to, DartsWorld.floorY);
      final at = t == null ? to : Surfaces.lerp(from, to, t);
      _impact = _impactAt(at, onFloor: true);
      return;
    }
    if (_steps >= DartsWorld.config.maxSteps) {
      _impact = _impactAt(to, onFloor: true);
    }
  }

  DartsImpact _impactAt(Vec3 at, {required bool onFloor}) {
    var bx = at.x;
    var by = at.y - DartsWorld.boardCentreY;
    var deflected = false;
    if (!onFloor) {
      // The wire gets its say before the scorer does: a dart never rests on a
      // wire, so the point handed to [DartsBoardGeometry.hitAt] is one a dart
      // could actually be standing on.
      final (dx, dy, kicked) =
          DartsWire.deflect(bx, by, boardRadius: DartsWorld.boardRadius);
      bx = dx;
      by = dy;
      deflected = kicked;
    }
    final hit = onFloor
        ? DartHit.miss
        : DartsBoardGeometry.hitAt(bx, by, radius: DartsWorld.boardRadius);
    return DartsImpact(
      point: onFloor ? at : Vec3(bx, by + DartsWorld.boardCentreY, at.z),
      boardX: bx,
      boardY: by,
      hit: hit,
      onBoard: !onFloor && !hit.isMiss,
      onFloor: onFloor,
      direction: _projectile.velocity.normalized,
      speed: _projectile.velocity.length,
      deflected: deflected,
    );
  }

  /// Run a whole throw headlessly and return where it landed.
  ///
  /// The drag preview calls this on every move event, so the landing ring is
  /// the real integrator's answer rather than a decorative guess.
  static DartsImpact simulate(Vec3 velocity) {
    final flight = DartsFlight(velocity: velocity);
    while (!flight.done) {
      flight._stepOnce();
    }
    return flight._impact!;
  }

  /// Convenience: read a swipe and fly it. Null when the swipe is not a throw
  /// (dead zone, downward, sideways-only).
  static DartsImpact? simulateSwipe(double dx, double dy) {
    final v = DartsSwing.read(dx, dy)?.velocity;
    return v == null ? null : simulate(v);
  }

  /// Convenience: aim, flick, and simulate in one call. Used by the physics
  /// tests to measure the grouping a tuned flick produces.
  static DartsImpact? simulateFlick({
    required double aimX,
    required double aimY,
    required double power,
    double swipeDx = 0,
  }) {
    final v = DartsAim.launch(
      aimX: aimX,
      aimY: aimY,
      power: power,
      swipeDx: swipeDx,
    );
    return v == null ? null : simulate(v);
  }
}
