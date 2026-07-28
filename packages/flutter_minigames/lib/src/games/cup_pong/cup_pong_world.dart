import 'dart:ui' show Offset, Size;

import 'package:flutter_minigames/src/engine3d/engine3d.dart';

import 'cup_pong_game.dart';

/// Physical layout of the Cup Pong scene, in world metres.
///
/// Axes follow [minigames_3d]: **+x** right, **+y** up, **+z** down-range (away
/// from the shooter). The table surface is the plane `y == 0`; the shooter
/// stands behind `z == nearZ` and the defender's rack sits near `farZ`.
///
/// The table is deliberately shorter than a regulation 8-ft beer-pong table.
/// At true scale a 47 mm cup 2.4 m away projects to a handful of pixels on a
/// phone and the rack stops reading as a rack. These numbers keep real *cup*
/// proportions (a Solo cup is 120 mm tall, 94 mm across the mouth) and shorten
/// the throw instead, which is the same compromise GamePigeon makes.
class CupPongWorld {
  const CupPongWorld._();

  // --- Table -----------------------------------------------------------------

  /// Half the table width; the ball is out of play beyond ±this.
  static const double halfWidth = 0.40;

  /// Near and far table edges in z. The near edge sits behind the ball and
  /// projects far below the canvas, which is what gives the side rails their
  /// hard convergence toward [Camera3.horizonY].
  static const double nearZ = -0.24;
  static const double farZ = 1.24;

  /// The playing surface plane.
  static const double surfaceY = 0.0;

  /// How far the table apron hangs below the surface (drawn, not simulated).
  static const double apronDepth = 0.16;

  // --- The room --------------------------------------------------------------

  /// Floor of the bar, relative to the table surface — a table is ~76 cm high.
  /// Only a strip of it is ever visible, between the far rail and the wall.
  static const double roomFloorY = -0.76;

  /// Depth of the back wall. Chosen so its base lands just above the far rail:
  /// nearer and the wall/floor junction hides behind the table, further and the
  /// strip of floor grows until the table reads as marooned in a hangar.
  static const double wallZ = 4.2;

  /// **The one light in the room.** A warm pendant hanging over the rack,
  /// forward and to the left of it.
  ///
  /// Every shadow, bevel and highlight in the scene is derived from this point,
  /// not guessed per-object: [shadowOf] is a true point-light projection onto
  /// the table plane, and the cup-wall shading direction is the horizontal
  /// component of the lamp→rack vector (which is why it is the pair
  /// `(-0.55, -0.84)` in the painter and not a number somebody liked).
  ///
  /// It hangs above eye level, so the fixture itself is off the top of the
  /// frame at every supported canvas size — what reaches the player is its
  /// bloom bleeding in over the wall and the pool it throws on the felt.
  static const Vec3 lamp = Vec3(-0.18, 1.00, 0.62);

  /// Where the lamp throws [p]'s shadow on the table plane.
  ///
  /// A real point-light projection: the ray lamp→p continued to `y == 0`. Under
  /// the lamp a ball's shadow sits directly beneath it; out at the rails it
  /// stretches away, which is the cue that there is a *lamp* up there rather
  /// than an ambient wash.
  static Vec3 shadowOf(Vec3 p) {
    final dy = lamp.y - p.y;
    if (dy <= 1e-4) return Vec3(p.x, surfaceY, p.z);
    final t = lamp.y / dy;
    return Vec3(
      lamp.x + (p.x - lamp.x) * t,
      surfaceY,
      lamp.z + (p.z - lamp.z) * t,
    );
  }

  // --- Cups ------------------------------------------------------------------

  /// True Solo-cup proportions: 120 mm tall, 94 mm mouth, 74 mm base.
  static const double cupHeight = 0.120;
  static const double cupMouthRadius = 0.047;
  static const double cupBaseRadius = 0.037;

  /// Rack-unit → metres.
  ///
  /// Slightly looser than cups-touching (94 mm mouths at 110 mm centres, rows
  /// 125 mm apart rather than the 81 mm a packed triangle would give). A packed
  /// rack at this camera angle collapses into a single red blob — the back rows
  /// project only ~8 px above the front ones and vanish behind them. The gaps
  /// are what let all ten mouths read, and they buy depth spread for free.
  static const double cupSpacing = 0.110;
  static const double rowDepth = 0.125;

  /// World z of the rack apex (the single cup nearest the shooter).
  static const double rackApexZ = 0.60;

  /// Mouth-plane height (cups stand on the table).
  static const double cupMouthY = surfaceY + cupHeight;

  // --- Ball ------------------------------------------------------------------

  /// A 40 mm ping-pong ball.
  static const double ballRadius = 0.020;

  /// Where a throw starts — just in front of and below the camera, so the ball
  /// reads as being in the player's hand at the bottom of the frame.
  static const Vec3 launchPoint = Vec3(0, 0.30, -0.02);

  /// Presentation-only fattening of the ball while it waits in hand.
  ///
  /// The ball at rest is the one thing the player has to notice, and at true
  /// perspective size it projects to a ~19 px disc that reads as a decoration
  /// rather than as the object you flick. Drawing it 1.4x — as if held a
  /// little nearer the eye than the point the solver launches from — is purely
  /// visual: [launchPoint] and every speed derived from it are untouched, and
  /// the ball is moving fast enough one frame after release that the step down
  /// to true scale is invisible.
  static const double heldDrawScale = 1.4;

  // --- Camera ----------------------------------------------------------------

  /// Eye position: behind and above the near table edge.
  static const Vec3 eye = Vec3(0, 0.62, -0.30);

  /// Downward tilt. Steep enough that all four rack rows separate vertically
  /// and you can see into the cups, shallow enough that [Camera3.horizonY]
  /// stays just inside the top of the frame.
  static const double pitch = 0.52;

  /// Vertical field of view. Wide keeps the horizon on-canvas at this pitch and
  /// exaggerates the near/far size ratio (~1.3x across the rack alone).
  static const double fovY = 1.05;

  /// The camera for a given canvas size.
  static Camera3 cameraFor(Size size) => Camera3(
        eye: eye,
        viewport: size,
        pitch: pitch,
        fovY: fovY,
      );

  /// World position of a cup's **mouth centre** from its rack-local slot.
  static Vec3 mouthOf(CupPongCup cup) => Vec3(
        cup.x * cupSpacing,
        cupMouthY,
        rackApexZ + cup.z * rowDepth,
      );

  /// World position of a cup's **base centre**.
  static Vec3 baseOf(CupPongCup cup) => Vec3(
        cup.x * cupSpacing,
        surfaceY,
        rackApexZ + cup.z * rowDepth,
      );
}

/// One cup as the painter sees it: where its mouth is, how big it is, and how
/// far through its removal animation it has travelled.
class CupView {
  /// World position of the mouth centre.
  final Vec3 mouth;

  final double mouthRadius;
  final double baseRadius;
  final double height;

  /// Stable id — lets the board key animations to a cup across a re-rack.
  final int id;

  /// 0 = standing, 1 = fully removed. Drives the sink/fade-out.
  final double removal;

  /// 0 = no splash, 1 = peak ripple. Fires when the ball drops in.
  final double splash;

  /// A ball sinking into this cup: 0 = level with the rim, 1 = settled on the
  /// beer at the bottom. Null when nothing is dropping in.
  ///
  /// The ball is drawn *clipped to the mouth*, so the near lip cuts across it
  /// as it descends — which is the whole reason a made shot reads as going
  /// **in** rather than as a ball that stopped existing over a cup.
  final double? drop;

  /// Accumulated spin of the dropping ball, radians.
  final double dropSpin;

  const CupView({
    required this.id,
    required this.mouth,
    required this.mouthRadius,
    required this.baseRadius,
    required this.height,
    this.removal = 0,
    this.splash = 0,
    this.drop,
    this.dropSpin = 0,
  });
}

/// The ball as the painter sees it.
class CupPongBallView {
  final Vec3 position;
  final double radius;

  /// Accumulated spin, radians — drives the seam that rolls across the ball.
  final double spin;

  /// True while the ball is still waiting in hand: drawn at
  /// [CupPongWorld.heldDrawScale] with a key-light cast shadow, so it reads as
  /// a real ball sitting ready in the near foreground rather than a dot.
  final bool inHand;

  const CupPongBallView({
    required this.position,
    required this.radius,
    this.spin = 0,
    this.inHand = false,
  });
}

/// The swipe overlay while a drag is live.
///
/// Everything here hangs off the *ball*, and nothing is projected past it.
/// There is no target marker, and — deliberately — no predicted arc either: an
/// arc that runs down the table and stops at a cup mouth is a crosshair drawn
/// as a curve, and it makes the same promise a reticle does. The gesture gets
/// a readout, the table gets nothing, and where the ball goes is found out by
/// throwing it.
class CupPongAimView {
  /// 0..1 flick power, for the power ring around the ball.
  final double power;

  /// The live swipe delta in logical pixels (screen space, y down). Drives the
  /// throw arrow that grows out of the ball.
  final Offset flick;

  const CupPongAimView({required this.power, required this.flick});
}

/// Everything [paintCupPongTable] needs. A plain value object — no engine
/// state, no controllers — which is what makes the whole scene snapshot-testable
/// from a headless test.
class CupPongView {
  /// The defender's rack, including cups mid-removal.
  final List<CupView> cups;

  /// The live ball, or null between throws.
  final CupPongBallView? ball;

  /// Balls already thrown this turn that came to rest on the table.
  final List<CupPongBallView> restingBalls;

  /// Aim overlay, or null when not dragging.
  final CupPongAimView? aim;

  const CupPongView({
    required this.cups,
    this.ball,
    this.restingBalls = const [],
    this.aim,
  });

  static const empty = CupPongView(cups: []);
}
