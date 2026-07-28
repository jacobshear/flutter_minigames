import 'dart:ui' show Color, Offset;

import 'package:minigames_3d/minigames_3d.dart';

import 'mini_golf_camera.dart';
import 'mini_golf_course.dart';
import 'mini_golf_world.dart';

/// The ball as the painter sees it.
class MiniGolfBallView {
  /// World position of the ball's centre.
  final Vec3 position;

  /// Radius in world units.
  final double radius;

  /// Accumulated roll angle, radians — kept for anything that just wants a
  /// scalar; the markings are drawn through [roll].
  final double spin;

  /// The ball's 3-D orientation, integrated from its travel. This is what makes
  /// it read as rolling rather than sliding.
  final BallRoll roll;

  /// True once the ball has dropped: it is drawn sunk in the cup.
  final bool holed;

  /// The acting player's colour, used for the ball's ring and the aim arrow.
  /// Null falls back to the style's player-1 accent.
  final Color? accent;

  const MiniGolfBallView({
    required this.position,
    this.radius = MiniGolfCourse.ballRadius,
    this.spin = 0,
    this.roll = BallRoll.identity,
    this.holed = false,
    this.accent,
  });

  /// True when the ball's centre has dropped below the green — it is inside the
  /// cup and must be drawn *through* the mouth so the near lip covers it.
  bool get inCup => position.y < MiniGolfCourse.ballRadius * 0.35;
}

/// A strike on a rail or a solid, still fresh enough to show.
///
/// Purely presentational: the simulation already resolved the bounce, this only
/// records where to scuff the paint and how hard.
class MiniGolfImpactView {
  /// Contact point, world `(x, z)`.
  final Offset at;

  /// Unit surface normal in the ground plane, pointing back at the ball.
  final Offset normal;

  /// 0..1 severity — how fast the ball went into the surface.
  final double strength;

  /// 0 = the instant it happened, 1 = fully faded.
  final double age;

  const MiniGolfImpactView({
    required this.at,
    required this.normal,
    required this.strength,
    required this.age,
  });
}

/// The slingshot aim overlay while a drag is live.
class MiniGolfAimView {
  /// Unit `(x, z)` direction the ball will set off in.
  final Offset direction;

  /// 0..1 power.
  final double power;

  /// Where the ball is being pulled back to, world `(x, z)` — the rubber band
  /// is drawn from the ball to here.
  final Offset pullTo;

  const MiniGolfAimView({
    required this.direction,
    required this.power,
    required this.pullTo,
  });
}

/// Everything [paintMiniGolfScene] needs.
///
/// A plain value object — no engine state, no controllers — which is what makes
/// the whole scene renderable headlessly to a PNG from a unit test. The camera
/// rides along as a [MiniGolfCamera] so the painter never derives its own pose:
/// the board owns the damped rig, and the frame you see is the frame the rig
/// was in.
class MiniGolfView {
  final MiniGolfCourse course;
  final MiniGolfBallView ball;

  /// Aim overlay, or null when not dragging.
  final MiniGolfAimView? aim;

  /// The camera rig for this frame. Null falls back to a settled aim framing on
  /// the ball, which is what a one-off still wants.
  final MiniGolfCamera? rig;

  /// Rail and obstacle strikes still fading.
  final List<MiniGolfImpactView> impacts;

  const MiniGolfView({
    required this.course,
    required this.ball,
    this.aim,
    this.rig,
    this.impacts = const [],
  });

  /// A view of [course] with the ball parked on the tee — the frame a hole
  /// opens on.
  factory MiniGolfView.onTee(
    MiniGolfCourse course, {
    Color? accent,
    MiniGolfCamera? rig,
  }) =>
      MiniGolfView(
        course: course,
        ball: MiniGolfBallView(
          position: MiniGolfWorld.ballAt(course.tee),
          accent: accent,
        ),
        rig: rig,
      );
}
