import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:minigames_3d/minigames_3d.dart';

/// The sow drop, as actual ballistics.
///
/// Sowing is a hand moving along the pits, opening once over each. The old
/// animation faked that with a screen-space sine arc and a snap into a slot;
/// this releases the stone into [Projectile], decides the landing beat with
/// [Surfaces.passesDownThroughDisc] against the pit mouth, and lets it bounce
/// off the scoop floor and roll into its place in the pile.
///
/// ## Why it is scale-free
///
/// Everything is measured in **pit diameters**, not pixels. The board's layout
/// is proportional, so one simulation is correct at every board size — and the
/// landing beat becomes a constant the sound cue can key off while still being
/// a real simulation event. It also means the whole thing runs headless: no
/// canvas, no widget tree, no frame clock.
///
/// ## World convention
///
/// `minigames_3d` is +x right, +y up, +z down-range. The board is seen from
/// above, so the mapping is:
/// * world **x** → board-plane x (screen x),
/// * world **z** → board-plane y (down the tray),
/// * world **y** → height above the board's face.
///
/// A stone's screen position is `ground - (0, height)`: altitude reads as an
/// up-screen offset, which is what a hop over a flat board looks like.
class SowPhysics {
  /// Gravity in pit-diameters/s². Real gravity at real pit scale empties a
  /// hand in ~50 ms per stone, which is three frames — legible motion needs it
  /// slowed, so this is tuned for a ~150 ms fall rather than taken from SI.
  final double gravity;

  /// Height above the board the hand carries stones at.
  final double handHeight;

  /// Depth of the scoop below the mouth plane.
  final double pitDepth;

  /// Radius of the pit mouth: the disc the stone must pass down through.
  final double mouthRadius;

  /// Fraction of the hop at which the hand arrives over the pit and opens.
  final double releaseAt;

  /// The hand's travel finishes at `releaseAt * handLead`, so it is still
  /// moving when it opens. That is what gives the stone forward carry — it
  /// arcs into the pit instead of being dropped straight down a shaft.
  final double handLead;

  /// Bounce off the scoop floor.
  final double restitution;

  const SowPhysics({
    this.gravity = 30,
    this.handHeight = 0.42,
    this.pitDepth = 0.11,
    this.mouthRadius = 0.46,
    this.releaseAt = 0.30,
    this.handLead = 1.35,
    this.restitution = 0.38,
  });

  /// Height the hand is actually at when it opens.
  double get releaseHeight => handHeight * _bob(releaseAt);

  /// Free-fall time from [releaseHeight] to the mouth plane, seconds.
  double get fallSeconds => math.sqrt(2 * releaseHeight / gravity);

  /// Fraction of a hop at which a released stone crosses the pit mouth.
  double mouthFraction(double hopSeconds) =>
      (releaseAt + fallSeconds / hopSeconds).clamp(0.0, 0.999);
}

/// One simulated drop, sampled at the integrator's fixed step.
class StoneDrop {
  /// Board-plane positions in pit-diameter units, relative to the hop's
  /// starting pit centre.
  final List<Offset> ground;

  /// Height above the board face at each sample (negative once in the scoop).
  final List<double> height;

  /// Integration step the samples were taken at.
  final double dt;

  /// Seconds from release to passing down through the pit mouth — detected by
  /// [Surfaces.passesDownThroughDisc], not assumed.
  final double mouthTime;

  /// Seconds from release to rest.
  final double totalTime;

  /// Sample index of the mouth crossing.
  final int mouthIndex;

  const StoneDrop({
    required this.ground,
    required this.height,
    required this.dt,
    required this.mouthTime,
    required this.totalTime,
    required this.mouthIndex,
  });

  double _f(double t) => (t / dt).clamp(0.0, (ground.length - 1).toDouble());

  /// Board-plane position (ignoring altitude) [t] seconds after release.
  Offset groundAt(double t) {
    if (ground.isEmpty) return Offset.zero;
    final x = _f(t);
    final i = x.floor();
    if (i >= ground.length - 1) return ground.last;
    return Offset.lerp(ground[i], ground[i + 1], x - i)!;
  }

  /// Altitude [t] seconds after release.
  double heightAt(double t) {
    if (height.isEmpty) return 0;
    final x = _f(t);
    final i = x.floor();
    if (i >= height.length - 1) return height.last;
    final f = x - i;
    return height[i] * (1 - f) + height[i + 1] * f;
  }

  /// Screen-space position: altitude read as an up-screen offset.
  ///
  /// Interpolated between fixed-step samples, so the stone follows the same
  /// path and lands at the same instant at 30, 60 or 120 fps. The simulation
  /// never sees the frame clock.
  Offset at(double t) => groundAt(t) - Offset(0, heightAt(t));

  /// True once the stone is inside the pit.
  bool landed(double t) => t >= mouthTime;
}

/// Smoothstep. A hand accelerates away from one pit and decelerates over the
/// next; an ease-out alone snaps it to the destination in the first few frames
/// and there is no visible travel left to read.
double _ease(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

/// Gentle bob across a hop, 1.0 at both ends.
///
/// The hand never returns to the board between pits — it carries the stones
/// along above them — so its height must match at the seam of consecutive hops
/// or it snaps down half a pit-diameter on every stone.
double _bob(double u) => 1 + 0.18 * math.sin(math.pi * u.clamp(0.0, 1.0));

/// The hand's altitude at [u] through a hop.
double handHeightAt(double u, SowPhysics p) => p.handHeight * _bob(u);

/// The hand's board-plane position at [u] through a hop, in pit-diameter units.
///
/// It settles over the pit shortly *after* it opens ([SowPhysics.handLead]) and
/// stays there — it does not sail on toward the next pit, because a hand that
/// drops a stone behind itself looks wrong.
Offset handGroundAt(Offset from, Offset to, double u, SowPhysics p) =>
    Offset.lerp(from, to, _ease(u / (p.releaseAt * p.handLead)))!;

/// Screen-space hand position (ground minus altitude).
Offset handAt(Offset from, Offset to, double u, SowPhysics p) =>
    handGroundAt(from, to, u, p) - Offset(0, handHeightAt(u, p));

/// Simulate one stone from the hand into [rest].
///
/// [to] is the target pit centre and [rest] the stone's slot in the pile, both
/// in pit-diameter units relative to the hop's starting pit centre. [hopSeconds]
/// is the wall clock of the whole hop, which is what is left for the drop after
/// [SowPhysics.releaseAt].
StoneDrop simulateDrop({
  required Offset from,
  required Offset to,
  required Offset rest,
  required double hopSeconds,
  SowPhysics physics = const SowPhysics(),
}) {
  final p = physics;
  final cfg = ThrowConfig(
    gravity: p.gravity,
    // Vacuum. A stone the size of a marble falling two centimetres has no
    // meaningful drag, and dropping the term makes the launch solve exact —
    // the stone provably reaches the mouth rather than approximately.
    drag: 0,
    fixedDt: 1 / 240,
    restSpeed: 0.02,
    maxSteps: 3000,
  );

  // Release: the hand is short of the pit and still moving, so the stone leaves
  // it with real forward carry.
  final gNow = handGroundAt(from, to, p.releaseAt, p);

  final tFall = p.fallSeconds;
  // Aim the fall at the mouth plane directly over the stone's slot. Drag-free,
  // so this is an exact solve rather than a guess that mostly works — the
  // launch velocity *is* the hand's carry, since the hand's position at release
  // is what makes that velocity point forward at all.
  final aim = (rest - gNow) / tFall;
  final vy = (0.5 * cfg.gravity * tFall * tFall - p.handHeight) / tFall;

  final ball = Projectile(
    position: Vec3(gNow.dx, p.handHeight, gNow.dy),
    velocity: Vec3(aim.dx, vy, aim.dy),
    config: cfg,
  );

  final mouth = Vec3(to.dx, 0, to.dy);
  final ground = <Offset>[Offset(ball.position.x, ball.position.z)];
  final height = <double>[ball.position.y];
  var mouthIndex = -1;
  var mouthTime = 0.0;
  final floorY = -p.pitDepth;
  final total = math.max(tFall + 0.02, (1 - p.releaseAt) * hopSeconds);
  final steps = (total / cfg.fixedDt).ceil();

  for (var i = 0; i < steps; i++) {
    final before = ball.step();
    // The "went in" test: a swept crossing of the mouth disc while descending.
    // Swept rather than point-in-disc so a fast stone cannot tunnel past it.
    if (mouthIndex < 0 &&
        Surfaces.passesDownThroughDisc(
          before,
          ball.position,
          mouth,
          p.mouthRadius,
        )) {
      mouthIndex = i + 1;
      mouthTime = mouthIndex * cfg.fixedDt;
    }

    if (ball.position.y <= floorY && ball.velocity.y < 0) {
      ball.position = Vec3(ball.position.x, floorY, ball.position.z);
      ball.bounce(
        const Vec3(0, 1, 0),
        restitution: p.restitution,
        friction: 0.34,
      );
      // Roll: a grounded stone steers toward its slot instead of sliding on.
      ball.velocity = Vec3(
        ball.velocity.x * 0.55 + (rest.dx - ball.position.x) * 5.5,
        ball.velocity.y,
        ball.velocity.z * 0.55 + (rest.dy - ball.position.z) * 5.5,
      );
    }

    ground.add(Offset(ball.position.x, ball.position.z));
    height.add(ball.position.y);
  }

  // Converge the tail onto the exact slot. The pile's geometry is what the
  // next stone aims at, so a stone must finish precisely where the layout says
  // it is; the blend only runs over the last stretch, well after the bounce
  // has done its visible work.
  final blendFrom = math.max(mouthIndex + 1, (ground.length * 0.74).round());
  for (var i = blendFrom; i < ground.length; i++) {
    final k = (i - blendFrom) / math.max(1, ground.length - 1 - blendFrom);
    final e = k * k * (3 - 2 * k);
    ground[i] = Offset.lerp(ground[i], rest, e)!;
    height[i] = height[i] * (1 - e) + (-p.pitDepth) * e;
  }
  ground[ground.length - 1] = rest;
  height[height.length - 1] = -p.pitDepth;

  if (mouthIndex < 0) {
    // Unreachable with the exact solve above, but a drop that somehow missed
    // still needs a defined landing beat rather than a null one.
    mouthIndex = (tFall / cfg.fixedDt).round().clamp(0, ground.length - 1);
    mouthTime = mouthIndex * cfg.fixedDt;
  }

  return StoneDrop(
    ground: ground,
    height: height,
    dt: cfg.fixedDt,
    mouthTime: mouthTime,
    totalTime: (ground.length - 1) * cfg.fixedDt,
    mouthIndex: mouthIndex,
  );
}

final Map<String, StoneDrop> _dropCache = {};

/// Cached [simulateDrop]. The sow replays a handful of geometries over and
/// over and the simulation is pure, so there is no reason to integrate twice.
StoneDrop dropFor({
  required Offset from,
  required Offset to,
  required Offset rest,
  required double hopSeconds,
  SowPhysics physics = const SowPhysics(),
}) {
  String k(Offset o) =>
      '${o.dx.toStringAsFixed(3)},${o.dy.toStringAsFixed(3)}';
  final key = '${k(from)}|${k(to)}|${k(rest)}|${hopSeconds.toStringAsFixed(3)}';
  final hit = _dropCache[key];
  if (hit != null) return hit;
  final made = simulateDrop(
    from: from,
    to: to,
    rest: rest,
    hopSeconds: hopSeconds,
    physics: physics,
  );
  if (_dropCache.length > 400) _dropCache.clear();
  _dropCache[key] = made;
  return made;
}
