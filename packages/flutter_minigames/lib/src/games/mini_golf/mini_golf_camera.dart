import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_minigames/src/engine3d/engine3d.dart';

import 'mini_golf_course.dart';
import 'mini_golf_world.dart';

/// What the camera is doing right now.
enum MiniGolfCameraPhase {
  /// A short scripted reveal when a hole opens: the rig starts framed on the
  /// cup and eases back up the hole to the tee.
  preview,

  /// The player is lining up a putt.
  aim,

  /// The ball is rolling.
  flight,

  /// The ball has just stopped; ease back to aim framing rather than cutting.
  settle,
}

/// The camera rig: a damped 3/4 chase camera for a mini-golf hole.
///
/// ## Why a rig and not just a camera
///
/// A [Camera3] is a pose. What a follow camera actually needs is a *state that
/// eases toward a pose*, because the quality of a chase camera lives almost
/// entirely in how it moves. So this class holds five damped channels —
/// [focusX], [focusZ] (where it looks), [back] and [height] (how far away, i.e.
/// the zoom), and [frame] (where in the viewport the focus sits) — and derives
/// the pose from them in [toCamera].
///
/// ## Damping
///
/// Every channel uses **frame-rate-independent exponential damping**:
///
///     x += (target − x) · (1 − exp(−λ·dt))
///
/// A naive `lerp(x, target, k)` is not frame-rate independent: at 120 fps it
/// converges twice as fast as at 60 fps, so the camera feels different on
/// different devices. The exponential form composes exactly — sixty steps of
/// 1/60 s land on precisely the same value as one step of 1 s, which is what
/// the frame-rate-independence test asserts.
///
/// Channels are damped at **different rates** ([MiniGolfCameraLambdas]) so the rig doesn't
/// move as one rigid block: it turns to look faster than it dollies, which is
/// what stops a zoom from feeling like a shove.
///
/// ## Zoom is a dolly, never the field of view
///
/// [MiniGolfWorld.fovY] is a constant. Zoom is done by changing [back] and
/// [height]. Animating the field of view warps the perspective and is a
/// well-known way to make a follow camera nauseating.
///
/// ## Purity
///
/// Everything here is a pure function of `(course, ball, velocity, phase, dt)`
/// plus the rig's own previous value. There is no hidden mutable state, so a
/// whole putt's worth of camera motion can be replayed in a headless test.
class MiniGolfCamera {
  /// Ground point the camera looks at, world x.
  final double focusX;

  /// Ground point the camera looks at, world z.
  final double focusZ;

  /// Horizontal set-back of the eye behind the focus.
  final double back;

  /// Eye height above the green.
  final double height;

  /// Screen fraction (0 top, 1 bottom) the focus is placed at.
  final double frame;

  const MiniGolfCamera({
    required this.focusX,
    required this.focusZ,
    required this.back,
    required this.height,
    required this.frame,
  });

  // -- limits ----------------------------------------------------------------

  /// Hard floor on the set-back.
  ///
  /// This is the anti-degeneration clamp. The failure it exists to prevent is
  /// the one Golf With Your Friends is criticised for: with the ball tight
  /// against a rail the camera creeps in until the view is effectively first
  /// person and you can no longer tell which way you are aiming. The rig would
  /// otherwise be free to close right up on a short remaining shot.
  static const double minBack = 3.4;

  /// Ceiling on the set-back, so a monster hole can't push the ball to a dot.
  static const double maxBack = 14.0;

  /// Floor on eye height — the camera never drops to or below the green.
  static const double minHeight = 1.6;
  static const double maxHeight = 12.0;

  /// Pitch is clamped well inside `(0, π/2)`: the camera can neither look level
  /// (which loses the ground plane) nor invert.
  static const double minPitch = 0.22;
  static const double maxPitch = 1.05;

  // -- framing fractions -----------------------------------------------------

  /// AIM: the ground just behind the ball sits near the bottom edge and the far
  /// end of the visible stretch about a third down.
  static const double aimNearFraction = 0.93;
  static const double aimFarFraction = 0.30;

  /// AIM fallback: where the middle of the stretch sits once a hole is too
  /// broad to fill the canvas vertically.
  static const double aimMidFraction = 0.60;

  /// FLIGHT: the ball itself is pinned here, low-ish in frame so most of the
  /// canvas is the direction of travel.
  static const double flightBallFraction = 0.64;

  /// FLIGHT: a fixed, comfortable tilt. Held constant while rolling so that
  /// speed changes read as distance changes and nothing else.
  static const double flightPitch = 0.48;

  // -- flight tuning ---------------------------------------------------------

  /// Eye height at a standstill, and how much it grows per unit of ball speed.
  /// This — with the ball pinned at [flightBallFraction] — is the "pull back as
  /// it speeds up" behaviour: a hard putt cannot outrun the frame.
  static const double flightHeightBase = 2.55;
  static const double flightHeightPerSpeed = 0.56;

  /// How far ahead of the ball the camera looks, per unit of speed, and the cap.
  /// Biasing the look-at point along the velocity is what makes the follow feel
  /// like it anticipates rather than trails.
  static const double lookAheadPerSpeed = 0.34;
  static const double lookAheadMax = 2.6;

  /// AIM dead zone: ball movement smaller than this does not move the camera,
  /// so a ball trickling to a halt doesn't make the rig jitter.
  static const double deadZonePosition = 0.14;
  static const double deadZoneDolly = 0.20;
  static const double deadZoneFrame = 0.012;

  // -- damping ---------------------------------------------------------------

  /// Frame-rate-independent exponential damping of one channel.
  ///
  /// Composes exactly: `damp` applied N times with `dt/N` equals one
  /// application with `dt`, because `(e^{−λ·dt/N})^N = e^{−λ·dt}`.
  static double damp(
    double current,
    double target,
    double lambda,
    double dt,
  ) {
    if (dt <= 0 || lambda <= 0) return current;
    return current + (target - current) * (1 - math.exp(-lambda * dt));
  }

  /// Per-phase damping rates, in nepers per second. Roughly: 95% of the way
  /// there takes `3 / λ` seconds.
  static MiniGolfCameraLambdas lambdasFor(MiniGolfCameraPhase phase) =>
      switch (phase) {
        // A slow, cinematic sweep — a bit over a second end to end.
        MiniGolfCameraPhase.preview =>
          const MiniGolfCameraLambdas(focus: 3.2, dolly: 3.0, frame: 3.2),
        MiniGolfCameraPhase.aim =>
          const MiniGolfCameraLambdas(focus: 6.0, dolly: 3.6, frame: 5.0),
        // Look fast, dolly slowly: the rig tracks the ball tightly while the
        // zoom breathes.
        MiniGolfCameraPhase.flight =>
          const MiniGolfCameraLambdas(focus: 9.0, dolly: 4.2, frame: 6.0),
        // ~0.5 s back to aim framing.
        MiniGolfCameraPhase.settle =>
          const MiniGolfCameraLambdas(focus: 8.0, dolly: 6.5, frame: 6.5),
      };

  /// One damped step toward [target]. Pure: same inputs, same output.
  ///
  /// [dt] is not clamped here — the maths is well behaved for any positive step
  /// (a huge `dt` simply lands on the target) and clamping would break the
  /// exact composition property. Callers that want to avoid a snap after a
  /// stalled frame should clamp before calling.
  MiniGolfCamera step(
    MiniGolfCamera target,
    MiniGolfCameraPhase phase,
    double dt,
  ) {
    if (dt <= 0) return this;
    // Dead zone: while aiming, ignore sub-threshold target movement entirely.
    if (phase == MiniGolfCameraPhase.aim && _within(target)) return this;

    final l = lambdasFor(phase);
    return MiniGolfCamera(
      focusX: damp(focusX, target.focusX, l.focus, dt),
      focusZ: damp(focusZ, target.focusZ, l.focus, dt),
      back: damp(back, target.back, l.dolly, dt)
          .clamp(minBack, maxBack)
          .toDouble(),
      height: damp(height, target.height, l.dolly, dt)
          .clamp(minHeight, maxHeight)
          .toDouble(),
      frame: damp(frame, target.frame, l.frame, dt),
    );
  }

  bool _within(MiniGolfCamera t) =>
      (t.focusX - focusX).abs() < deadZonePosition &&
      (t.focusZ - focusZ).abs() < deadZonePosition &&
      (t.back - back).abs() < deadZoneDolly &&
      (t.height - height).abs() < deadZoneDolly &&
      (t.frame - frame).abs() < deadZoneFrame;

  /// Whether the rig has effectively arrived at [other] — used to park the
  /// driving ticker instead of spinning a repaint forever.
  bool settledOn(MiniGolfCamera other, {double epsilon = 0.02}) =>
      (other.focusX - focusX).abs() < epsilon &&
      (other.focusZ - focusZ).abs() < epsilon &&
      (other.back - back).abs() < epsilon &&
      (other.height - height).abs() < epsilon &&
      (other.frame - frame).abs() < epsilon * 0.5;

  // -- pose ------------------------------------------------------------------

  /// The eye position implied by this rig.
  Vec3 get eye => Vec3(focusX, height, focusZ - back);

  /// The downward tilt that puts the focus at [frame].
  ///
  /// Derived rather than stored, so the focus lands exactly where it was asked
  /// to for whatever set-back and height the damper has currently reached — the
  /// framing can never drift out of step with the zoom mid-transition.
  double get pitch {
    final tanY = math.tan(MiniGolfWorld.fovY / 2);
    final r = (0.5 - frame) * 2 * tanY;
    final tau = back / math.max(1e-6, height);
    final denom = tau - r;
    final raw = denom.abs() < 1e-6 ? maxPitch : math.atan2(1 + r * tau, denom);
    return raw.clamp(minPitch, maxPitch);
  }

  /// The projection this rig produces on a canvas of [viewport].
  Camera3 toCamera(Size viewport) => Camera3(
        eye: eye,
        viewport: viewport,
        pitch: pitch,
        fovY: MiniGolfWorld.fovY,
      );

  // -- targets ---------------------------------------------------------------

  /// The framing this phase wants, given where the ball is and how fast it is
  /// going. Pure.
  static MiniGolfCamera targetFor({
    required Size viewport,
    required MiniGolfCourse course,
    required Offset ball,
    required MiniGolfCameraPhase phase,
    Offset velocity = Offset.zero,
  }) =>
      switch (phase) {
        // Preview eases to the same place aim does — it is the *rate* that
        // differs (see [lambdasFor]) and the fact that it starts from
        // [previewStart] down at the cup.
        MiniGolfCameraPhase.preview ||
        MiniGolfCameraPhase.aim ||
        MiniGolfCameraPhase.settle =>
          _aimRig(viewport, course, ball, aimInterest(course, ball)),
        MiniGolfCameraPhase.flight =>
          _flightRig(viewport, course, ball, velocity),
      };

  /// Where the hole-opening reveal starts: framed tight on the cup. Easing from
  /// here to the aim framing sweeps the camera back up the hole, which shows the
  /// player the whole layout without needing a free-look camera.
  static MiniGolfCamera previewStart({
    required Size viewport,
    required MiniGolfCourse course,
  }) =>
      _aimRig(viewport, course, course.cup, course.cup);

  /// A rig already sitting on its target — the frame a hole opens on.
  static MiniGolfCamera settledOnTarget({
    required Size viewport,
    required MiniGolfCourse course,
    required Offset ball,
    MiniGolfCameraPhase phase = MiniGolfCameraPhase.aim,
    Offset velocity = Offset.zero,
  }) =>
      targetFor(
        viewport: viewport,
        course: course,
        ball: ball,
        phase: phase,
        velocity: velocity,
      );

  /// What the player needs to see besides the ball.
  ///
  /// The cup when there is a clear line to it *and* it is within a putt's
  /// reach; otherwise the bend, gate or stretch of fairway the ball is actually
  /// going to be played into. Framing that instead of the cup is what lets a
  /// dogleg be planned without a free-look camera, and — just as important —
  /// what stops the camera from hauling all the way back to show a cup three
  /// putts away, shrinking the ball to a speck for a shot that can only travel
  /// [MiniGolfCourse.maxPuttReach].
  static Offset aimInterest(MiniGolfCourse course, Offset ball) {
    const reach = MiniGolfCourse.maxPuttReach;
    final toCup = course.cup - ball;
    final distance = toCup.distance;
    if (distance < 1e-6) return course.cup;
    final direct = toCup / distance;
    if (_freeRun(course, ball, direct, distance) >= distance - 0.4) {
      return distance <= reach * 1.05 ? course.cup : ball + direct * reach;
    }

    // Blocked. Sweep headings either side of the cup direction and take the one
    // with the longest clear run, preferring runs that make progress toward the
    // cup so the camera doesn't turn to admire a dead end.
    var bestScore = -1.0;
    var best = ball + direct * math.min(distance, MiniGolfCourse.maxPuttReach);
    for (var i = -6; i <= 6; i++) {
      final angle = i * 0.22; // ±76°
      final heading = _rotate(direct, angle);
      final run = _freeRun(course, ball, heading, MiniGolfCourse.maxPuttReach);
      final progress = heading.dx * direct.dx + heading.dy * direct.dy;
      final score = run * (0.6 + 0.4 * progress);
      if (score > bestScore) {
        bestScore = score;
        best = ball + heading * math.max(2.0, run - 0.3);
      }
    }
    return best;
  }

  // -- aim solve -------------------------------------------------------------

  /// Frames [ball] and [interest] with the near end of the visible stretch at
  /// [aimNearFraction] and the far end at [aimFarFraction].
  ///
  /// The set-back and eye height are **solved**, not guessed. For a ground
  /// point at depth `dz` below an eye of height `h`, the projected screen
  /// fraction depends only on `τ = dz / h`; inverting that for the two
  /// fractions gives `τ` at each end, their difference fixes `h` (the depth
  /// span is known), and `τ_near` then fixes the set-back.
  ///
  /// [Camera3] has no yaw, so lateral framing is done by sliding the eye in x
  /// and by widening the set-back until everything projects inside the frame.
  static MiniGolfCamera _aimRig(
    Size viewport,
    MiniGolfCourse course,
    Offset ball,
    Offset interest,
  ) {
    final nearZ = ball.dy - 1.2;
    final farZ = math.max(interest.dy, ball.dy) + 1.4;
    final span = math.max(5.0, farZ - nearZ);

    // Shorter views tip further over the top; long ones flatten out so the far
    // end doesn't crush into the horizon.
    final pitch = (0.62 - 0.012 * span).clamp(0.40, 0.62);
    final c = math.cos(pitch);
    final s = math.sin(pitch);
    final tanY = math.tan(MiniGolfWorld.fovY / 2);

    double tauFor(double u) {
      final r = (0.5 - u) * 2 * tanY;
      final denom = s - r * c;
      return denom.abs() < 1e-6 ? 1.0 : (r * s + c) / denom;
    }

    final tauNear = tauFor(aimNearFraction);
    final tauFar = tauFor(aimFarFraction);
    final tauMid = tauFor(aimMidFraction);
    final spread = math.max(0.5, tauFar - tauNear);

    final aspect =
        viewport.height <= 0 ? 1.0 : viewport.width / viewport.height;
    final tanX = math.max(0.30, aspect * tanY);

    // Everything that has to stay on canvas: the ball, the point it's being
    // played toward, and the rails of the corridor between them.
    //
    // Deliberately *not* every vertex in the depth window. On a wide S-bend the
    // far arm's outer wall is metres off the line being played, and fitting it
    // hauls the camera back until the ball is a speck — a lot of pull-back
    // spent on fairway the player isn't using.
    final points = <Offset>[ball, interest];
    for (final p in course.outline) {
      if (p.dy < nearZ - 1 || p.dy > farZ + 1) continue;
      if (_distanceToSegment(p, ball, interest) > 3.2) continue;
      points.add(p);
    }
    var lo = double.infinity, hi = -double.infinity;
    for (final p in points) {
      lo = math.min(lo, p.dx);
      hi = math.max(hi, p.dx);
    }
    // Centre on that stretch, weighted toward the ball, then slide toward the
    // open side of the fairway when the ball is tucked against a rail.
    final eyeX =
        ball.dx * 0.4 + ((lo + hi) / 2) * 0.6 + _openBias(course, ball);

    // Bottom-anchored while the hole fills the canvas, centred once it can't —
    // otherwise a broad hole leaves a slab of dead rough at one end.
    double heightFor(double setBack) =>
        math.min(setBack / tauNear, (setBack + span / 2) / tauMid);

    var back = math.max(minBack, tauNear * (span / spread));
    var height = heightFor(back);
    for (var pass = 0; pass < 5; pass++) {
      height = heightFor(back);
      final eyeZ = nearZ - back;
      var widened = back;
      for (final p in points) {
        final camZ = (p.dy - eyeZ) * c + height * s;
        final want = ((p.dx - eyeX).abs() + 0.7) / tanX;
        if (want > camZ) {
          widened = math.max(widened, back + (want - camZ) / c);
        }
      }
      if (widened <= back + 1e-6) break;
      back = widened;
    }
    back = back.clamp(minBack, maxBack).toDouble();
    height = heightFor(back).clamp(minHeight, maxHeight).toDouble();

    // Which anchor won decides where the focus sits and at what fraction; both
    // describe the same eye, so the pose is identical either way.
    final bottomAnchored = back / tauNear <= (back + span / 2) / tauMid;
    return MiniGolfCamera(
      focusX: eyeX,
      focusZ: bottomAnchored ? nearZ : nearZ + span / 2,
      back: bottomAnchored ? back : back + span / 2,
      height: height,
      frame: bottomAnchored ? aimNearFraction : aimMidFraction,
    );
  }

  // -- flight solve ----------------------------------------------------------

  /// Follows a rolling ball: fixed tilt, the ball pinned at
  /// [flightBallFraction], the eye pulled back in proportion to speed, and the
  /// look-at point biased ahead along the velocity.
  static MiniGolfCamera _flightRig(
    Size viewport,
    MiniGolfCourse course,
    Offset ball,
    Offset velocity,
  ) {
    final speed = velocity.distance;
    final heading = speed < 1e-6 ? const Offset(0, 1) : velocity / speed;
    final lookAhead = math.min(lookAheadMax, speed * lookAheadPerSpeed);
    final focus = ball + heading * lookAhead;

    const pitch = flightPitch;
    final c = math.cos(pitch);
    final s = math.sin(pitch);
    final tanY = math.tan(MiniGolfWorld.fovY / 2);
    final rBall = (0.5 - flightBallFraction) * 2 * tanY;
    final tauBall = (rBall * s + c) / (s - rBall * c);

    final aspect =
        viewport.height <= 0 ? 1.0 : viewport.width / viewport.height;
    final tanX = math.max(0.30, aspect * tanY);

    final focusX = focus.dx + _openBias(course, ball);

    // Zoom: eye height rises with speed, and the ball's fixed screen fraction
    // turns that directly into set-back. Enforce the minimum here so no amount
    // of slowing down can collapse the rig into the ball.
    var height = math.max(
      minBack / tauBall,
      flightHeightBase + flightHeightPerSpeed * speed,
    );

    // Widen (by raising the eye, which keeps the ball's fraction fixed) until
    // the ball and the look-at point both project inside the frame.
    for (var pass = 0; pass < 5; pass++) {
      final eyeZ = ball.dy - tauBall * height;
      var wanted = height;
      for (final p in [ball, focus]) {
        final camZ = (p.dy - eyeZ) * c + height * s;
        final want = ((p.dx - focusX).abs() + 0.9) / tanX;
        if (want > camZ) {
          // camZ grows by (tauBall·c + s) per unit of height.
          wanted = math.max(
            wanted,
            height + (want - camZ) / math.max(0.1, tauBall * c + s),
          );
        }
      }
      if (wanted <= height + 1e-6) break;
      height = wanted;
    }
    height = height.clamp(minHeight, maxHeight).toDouble();

    final eyeZ = ball.dy - tauBall * height;
    final back = (focus.dy - eyeZ).clamp(minBack, maxBack).toDouble();

    // The focus sits wherever that set-back puts it; report the fraction so the
    // damper has something meaningful to interpolate against the aim framing.
    final tauFocus = back / math.max(1e-6, height);
    final rFocus = (tauFocus * s - c) / (s + tauFocus * c);
    final frame = 0.5 - rFocus / (2 * tanY);

    return MiniGolfCamera(
      focusX: focusX,
      focusZ: eyeZ + back,
      back: back,
      height: height,
      frame: frame,
    );
  }

  // -- fairway probing -------------------------------------------------------

  /// How far the eye slides toward the open side of the fairway.
  ///
  /// With the ball hard against a rail the naive answer is to close in, which
  /// degenerates into a near-first-person view where you cannot read your own
  /// aim. Instead the rig steps sideways into the open part of the hole, so the
  /// ball stays framed *and* the line stays legible.
  static double _openBias(MiniGolfCourse course, Offset ball) {
    const probe = 2.6;
    final left = _freeRun(course, ball, const Offset(-1, 0), probe);
    final right = _freeRun(course, ball, const Offset(1, 0), probe);
    return ((right - left) * 0.42).clamp(-1.15, 1.15).toDouble();
  }

  /// Distance the ball's centre can travel from [from] along [direction] before
  /// it would leave the green or hit a solid, capped at [maxDistance].
  static double _freeRun(
    MiniGolfCourse course,
    Offset from,
    Offset direction,
    double maxDistance,
  ) {
    const step = 0.22;
    var travelled = 0.0;
    while (travelled < maxDistance) {
      final next = math.min(travelled + step, maxDistance);
      if (!_clear(course, from + direction * next)) return travelled;
      travelled = next;
    }
    return maxDistance;
  }

  /// Whether the ball's centre could sit at [p].
  static bool _clear(MiniGolfCourse course, Offset p) {
    if (!course.containsWorld(p)) return false;
    const margin = MiniGolfCourse.ballRadius;
    for (final o in course.obstacles) {
      if (o.round) {
        if ((p - Offset(o.centerX, o.centerZ)).distance <= o.radius + margin) {
          return false;
        }
      } else {
        final cx = p.dx.clamp(o.left, o.right);
        final cz = p.dy.clamp(o.near, o.far);
        if ((p - Offset(cx, cz)).distance <= margin) return false;
      }
    }
    return true;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (l2 < 1e-12) return (p - a).distance;
    final t =
        ((((p - a).dx * ab.dx) + ((p - a).dy * ab.dy)) / l2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  static Offset _rotate(Offset v, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  @override
  String toString() => 'MiniGolfCamera(focus ${focusX.toStringAsFixed(2)},'
      '${focusZ.toStringAsFixed(2)} back ${back.toStringAsFixed(2)} '
      'height ${height.toStringAsFixed(2)} frame ${frame.toStringAsFixed(3)})';
}

/// Damping rates for the rig's three channel groups.
class MiniGolfCameraLambdas {
  /// Where it looks — the fastest channel, so aim reads immediately.
  final double focus;

  /// How far away it is (the zoom) — the slowest, so distance changes breathe.
  final double dolly;

  /// Where in the viewport the focus sits.
  final double frame;

  const MiniGolfCameraLambdas({
    required this.focus,
    required this.dolly,
    required this.frame,
  });
}
