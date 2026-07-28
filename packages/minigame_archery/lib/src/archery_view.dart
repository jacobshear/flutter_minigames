import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:minigames_3d/minigames_3d.dart';

import 'archery_game.dart';
import 'archery_shot.dart';
import 'archery_style.dart';

/// An arrow currently in the air.
class ArrowInFlight {
  final Vec3 position;

  /// Unit flight direction — the nose pitches down as the arrow drops, which
  /// is the cue that sells the arc.
  final Vec3 direction;

  /// A few recent positions, oldest first, for the motion streak.
  final List<Vec3> trail;

  const ArrowInFlight({
    required this.position,
    required this.direction,
    this.trail = const [],
  });
}

/// The one light on the range, and everything that obeys it.
///
/// A morning sun, high and to the **left**. Every shadow in the frame — the
/// butt's on the grass, the stand's legs, an arrow's on the ground, the crease
/// down the right of the straw — falls down and to the **right** of its caster,
/// and every lit edge faces up-left. Nothing in this file is allowed to
/// disagree with it.
abstract final class ArcheryLight {
  /// Unit direction the sunlight travels.
  static final Vec3 direction = const Vec3(0.42, -0.86, 0.29).normalized;

  /// Where the sun sits in the frame, as a fraction of the viewport.
  static const Offset sunAt = Offset(0.19, 0.10);

  /// Ground-shadow offset for a prop of unit height, in world metres.
  static const double shadowRun = 0.49;
}

/// An arrow that never reached the face, left where it finished.
///
/// A miss used to simply vanish when the flight animation ended, which quietly
/// told the player their arrow was never real. Now it stays: stuck in the turf
/// short of the butt, or sailing past and planting itself beyond it. Seeing
/// where it went is how you correct the next one.
@immutable
class StrayArrow {
  /// Where the point came to rest.
  final Vec3 position;

  /// Unit direction it was travelling — the angle it stands at.
  final Vec3 direction;

  /// True when it planted in the turf rather than passing out of the world.
  final bool inGround;

  const StrayArrow({
    required this.position,
    required this.direction,
    this.inGround = true,
  });
}

/// Everything [paintArcheryScene] needs, and nothing else.
///
/// Deliberately a plain immutable snapshot with no engine, controller or
/// `BuildContext` in it: the scene is a pure function of this value, so any
/// frame of the game can be reproduced — and snapshot-tested — from data alone.
class ArcheryView {
  /// Range and wind of the target being shot at.
  final TargetConditions conditions;

  /// Arrows already stuck in this target's face (this end only).
  final List<ArrowShot> stuckArrows;

  /// The arrow in the air, or null between shots.
  final ArrowInFlight? flight;

  /// Aim offsets from the solved centre line, radians (sway included).
  final double aimYaw;
  final double aimPitch;

  /// How far above the aimed line this draw will put the arrow, metres at the
  /// face — [ArcheryBallistics.drawBias] for the current hold.
  ///
  /// Folded straight into [aimPoint] so the sight picture is the *whole* truth
  /// about the shot, not just its angular part.
  final double drawBias;

  /// 0..1 draw — the bow coming to full stretch. Drives the zoom.
  final double drawProgress;

  /// 0..1 across the whole hold, draw *and* grace. Drives the draw meter, so
  /// the bar keeps moving through the window where the release is decided
  /// instead of pinning full the moment the bow is drawn.
  final double holdProgress;

  /// 0..1 focus break — the reticle shakes and swells as this rises.
  final double focusBreak;

  /// Whether the string is being drawn right now.
  final bool drawing;

  /// Whether an arrow is nocked and the sight picture is live. False during
  /// flight and behind the handoff cover — no reticle, no arrow on the string.
  final bool showReticle;

  /// 0..1 sight zoom. Tracks the draw while aiming and is *held* through the
  /// flight, so releasing does not snap the world back to wide angle.
  final double zoom;

  /// Angular wander of the hold, radians. Drives the reticle's radius, so the
  /// reticle is an honest readout of how steady the shot actually is.
  final double swayAmplitude;

  /// Free-running seconds for ambient motion (flag, grass).
  final double time;

  /// 0..1 impact wobble, decaying.
  ///
  /// Drives two things that are not the same: the whole butt rocking on its
  /// stand, and — through [_FaceDent] — a local **compression** of the straw
  /// around ([impactX], [impactY]), so the target visibly takes the arrow
  /// instead of merely shivering.
  final double targetWobble;

  /// Where the last arrow struck, metres from the face centre. Only meaningful
  /// while [targetWobble] is running.
  final double impactX;
  final double impactY;

  /// 0..1 decaying quiver of the arrow that just landed — 1 the instant it
  /// bites, 0 once the shaft has stopped ringing.
  final double arrowSettle;

  /// An arrow that missed the face and is lying in the range.
  final StrayArrow? stray;

  /// Arrows the shooter has left at this target.
  final int arrowsLeft;

  /// Current shooter's accent (fletching, flag, chip).
  final Color accent;

  const ArcheryView({
    required this.conditions,
    this.stuckArrows = const [],
    this.flight,
    this.aimYaw = 0,
    this.aimPitch = 0,
    this.drawBias = 0,
    this.drawProgress = 0,
    this.holdProgress = 0,
    this.focusBreak = 0,
    this.drawing = false,
    this.showReticle = true,
    this.zoom = 0,
    this.swayAmplitude = ArcheryDraw.maxSway,
    this.time = 0,
    this.targetWobble = 0,
    this.impactX = 0,
    this.impactY = 0,
    this.arrowSettle = 0,
    this.stray,
    this.arrowsLeft = ArcheryGame.arrowsPerTarget,
    this.accent = const Color(0xFFD8443C),
  });

  /// The live compression of the face, or null when the straw is at rest.
  _FaceDent? get dent => targetWobble <= 0
      ? null
      : _FaceDent(
          amount: targetWobble.clamp(0.0, 1.0),
          x: impactX,
          y: impactY,
        );

  ArcheryView copyWith({
    TargetConditions? conditions,
    List<ArrowShot>? stuckArrows,
    ArrowInFlight? flight,
    bool clearFlight = false,
    double? aimYaw,
    double? aimPitch,
    double? drawBias,
    double? drawProgress,
    double? holdProgress,
    double? focusBreak,
    bool? drawing,
    bool? showReticle,
    double? zoom,
    double? swayAmplitude,
    double? time,
    double? targetWobble,
    double? impactX,
    double? impactY,
    double? arrowSettle,
    StrayArrow? stray,
    bool clearStray = false,
    int? arrowsLeft,
    Color? accent,
  }) =>
      ArcheryView(
        conditions: conditions ?? this.conditions,
        stuckArrows: stuckArrows ?? this.stuckArrows,
        flight: clearFlight ? null : (flight ?? this.flight),
        aimYaw: aimYaw ?? this.aimYaw,
        aimPitch: aimPitch ?? this.aimPitch,
        drawBias: drawBias ?? this.drawBias,
        drawProgress: drawProgress ?? this.drawProgress,
        holdProgress: holdProgress ?? this.holdProgress,
        focusBreak: focusBreak ?? this.focusBreak,
        drawing: drawing ?? this.drawing,
        showReticle: showReticle ?? this.showReticle,
        zoom: zoom ?? this.zoom,
        swayAmplitude: swayAmplitude ?? this.swayAmplitude,
        time: time ?? this.time,
        targetWobble: targetWobble ?? this.targetWobble,
        impactX: impactX ?? this.impactX,
        impactY: impactY ?? this.impactY,
        arrowSettle: arrowSettle ?? this.arrowSettle,
        stray: clearStray ? null : (stray ?? this.stray),
        arrowsLeft: arrowsLeft ?? this.arrowsLeft,
        accent: accent ?? this.accent,
      );

  /// The world point the sight is on: the aim ray's meeting with the target
  /// plane, lifted by whatever the current draw is worth.
  ///
  /// **A release in still air lands exactly here** — the whole point of
  /// [drawBias] being in this expression. The reticle is a promise only the
  /// wind is allowed to break, which is what makes aiming off into the wind a
  /// skill rather than a guess about what else the game is hiding.
  Vec3 get aimPoint => Vec3(
        conditions.distance * math.tan(aimYaw),
        ArcheryBallistics.targetCentreHeight +
            conditions.distance * math.tan(aimPitch) +
            drawBias,
        conditions.distance,
      );
}

/// A local compression of the target face where an arrow just went in.
///
/// A butt is a bale of straw, not a plate: an arrow arriving at fifty metres a
/// second pushes it in and the ring lines around the hole are dragged toward
/// the shaft before the straw pushes back. Applied to the *face geometry*
/// itself — the rings are drawn through it — so the target absorbs the arrow
/// rather than having an effect drawn on top of it.
@immutable
class _FaceDent {
  /// 1 at the moment of contact, decaying to 0.
  final double amount;

  /// Contact point, metres from the centre of the face.
  final double x;
  final double y;

  const _FaceDent({required this.amount, required this.x, required this.y});

  /// How far out the straw is dragged in, metres — about a ring and a half.
  static const double reach = 0.21;

  /// Peak pull toward the hole, metres.
  static const double peak = 0.018;

  /// Face-relative offset ([dx], [dy]) pulled toward the impact point.
  ///
  /// The profile is a half-sine, not a bump: it is **zero at the hole itself**
  /// and peaks a ring out. That is not a detail — a profile that peaks at the
  /// centre drags points on the near side straight past the impact point and
  /// the face folds in on itself, which is what a dent must never look like.
  (double, double) apply(double dx, double dy) {
    final ox = dx - x;
    final oy = dy - y;
    final d = math.sqrt(ox * ox + oy * oy);
    if (d < 1e-6 || d > reach) return (dx, dy);
    final profile = math.sin(math.pi * d / reach);
    // Mostly a steady dent that relaxes, with a little ring in it: straw
    // absorbs, it does not resonate.
    final ringing = 0.82 + 0.18 * math.sin((1 - amount) * 16);
    final pull = peak * amount * profile * ringing;
    return (dx - ox / d * pull, dy - oy / d * pull);
  }
}

/// Builds the camera for a frame.
///
/// The view follows the aim at [followFactor], so half of an aim change swings
/// the world and half moves the reticle across the frame — you get both cues.
/// The swing is applied as a shifted principal point (a canvas translation),
/// which is an exact off-axis pinhole camera, not an approximation.
class ArcheryCamera {
  const ArcheryCamera._();

  static const double followFactor = 0.5;

  /// Widest the view ever gets.
  static const double fovWidest = 0.62;

  /// Field of view at full draw, radians — **range-aware**.
  ///
  /// A fixed FOV either wastes the frame at 14 m or reduces a 38 m face to a
  /// dozen pixels. Settling on a partial normalisation (`d^0.55`) keeps a far
  /// face readable without collapsing the perspective into a flat scope view,
  /// which is what a fully normalised zoom would do.
  static double fovDrawnAt(double distance) =>
      2 * math.atan(0.75 / math.pow(math.max(4.0, distance), 0.55));

  static double fovFor(ArcheryView view) {
    final drawn = fovDrawnAt(view.conditions.distance);
    final relaxed = math.min(fovWidest, drawn * 1.7);
    return relaxed + (drawn - relaxed) * view.zoom.clamp(0.0, 1.0);
  }

  static Camera3 of(Size size, ArcheryView view) {
    final d = math.max(1.0, view.conditions.distance);
    // Look slightly down: enough to see the ground converge, while the face
    // still sits a little above centre.
    final pitch =
        (ArcheryBallistics.eyeHeight - ArcheryBallistics.targetCentreHeight) / d +
            0.045;
    return Camera3(
      eye: const Vec3(0, ArcheryBallistics.eyeHeight, -0.15),
      viewport: size,
      pitch: pitch,
      fovY: fovFor(view),
    );
  }

  /// Canvas offset that swings the view toward the aim.
  static Offset shiftFor(Camera3 camera, ArcheryView view) => Offset(
        -camera.focal * math.tan(view.aimYaw * followFactor),
        camera.focal * math.tan(view.aimPitch * followFactor),
      );
}

/// Paints the whole first-person range: sky, converging ground, the butt with
/// its rings, arrows already stuck in the face, the arrow in flight with its
/// travelling shadow, the wind flag, the bow silhouette and the reticle.
///
/// A pure function of ([size], [view], [style], [scheme]) — no engine state, no
/// controllers, no clock of its own. That is what lets a widget test render an
/// exact frame to a PNG.
void paintArcheryScene(
  Canvas canvas,
  Size size,
  ArcheryView view,
  ArcheryStyle style,
  ColorScheme scheme,
) {
  if (size.isEmpty) return;
  final camera = ArcheryCamera.of(size, view);
  final shift = ArcheryCamera.shiftFor(camera, view);

  canvas.save();
  canvas.clipRect(Offset.zero & size);

  canvas.save();
  canvas.translate(shift.dx, shift.dy);
  _paintSky(canvas, size, camera, view, style, scheme, shift);
  _paintGround(canvas, size, camera, view, style, scheme, shift);
  _paintProps(canvas, size, camera, view, style, scheme);
  canvas.restore();

  final aim = camera.project(view.aimPoint);
  final reticle = aim.visible ? aim.screen + shift : null;
  _paintBow(canvas, size, view, style, scheme, reticle);
  if (view.showReticle && reticle != null) {
    _paintReticle(canvas, camera, view, reticle, scheme);
  }
  _paintHud(canvas, size, view, style, scheme);
  canvas.restore();
}

// ---------------------------------------------------------------------------
// Projection helpers
// ---------------------------------------------------------------------------

/// A circle standing upright in the plane `z == centre.z`, projected honestly
/// by sampling real points around it.
///
/// Not an ellipse with a guessed aspect: with the camera pitched, the top and
/// bottom of an upright circle sit at slightly different camera depths, so the
/// true projection is a conic. Sampling costs nothing and is always right.
Path? verticalCirclePath(
  Camera3 camera,
  Vec3 centre,
  double radius, {
  int segments = 48,
  _FaceDent? dent,
}) {
  final path = Path();
  for (var i = 0; i < segments; i++) {
    final a = 2 * math.pi * i / segments;
    final (ox, oy) = dent?.apply(math.cos(a) * radius, math.sin(a) * radius) ??
        (math.cos(a) * radius, math.sin(a) * radius);
    final p = camera.project(Vec3(centre.x + ox, centre.y + oy, centre.z));
    if (!p.visible) return null;
    if (i == 0) {
      path.moveTo(p.screen.dx, p.screen.dy);
    } else {
      path.lineTo(p.screen.dx, p.screen.dy);
    }
  }
  return path..close();
}

Path? _quadPath(Camera3 camera, List<Vec3> corners) {
  final path = Path();
  for (var i = 0; i < corners.length; i++) {
    final p = camera.project(corners[i]);
    if (!p.visible) return null;
    if (i == 0) {
      path.moveTo(p.screen.dx, p.screen.dy);
    } else {
      path.lineTo(p.screen.dx, p.screen.dy);
    }
  }
  return path..close();
}

/// Fades [color] toward the haze by depth — the cheapest honest depth cue
/// there is, and the one that stops a far target reading as a near sticker.
Color _hazed(Color color, double depth, Color haze, {double strength = 0.75}) {
  final t = (depth / 55).clamp(0.0, 1.0) * strength;
  return Color.lerp(color, haze, t)!;
}

double _hash01(int i, int salt) {
  var x = (i * 0x9E3779B1 + salt * 0x85EBCA77) & 0xFFFFFFFF;
  x = (x ^ (x >>> 16)) & 0xFFFFFFFF;
  x = (x * 0x7FEB352D) & 0xFFFFFFFF;
  x = (x ^ (x >>> 15)) & 0xFFFFFFFF;
  x = (x * 0x846CA68B) & 0xFFFFFFFF;
  x = (x ^ (x >>> 16)) & 0xFFFFFFFF;
  return x / 0x100000000;
}

// ---------------------------------------------------------------------------
// Sky and ground
// ---------------------------------------------------------------------------

void _paintSky(
  Canvas canvas,
  Size size,
  Camera3 camera,
  ArcheryView view,
  ArcheryStyle style,
  ColorScheme scheme,
  Offset shift,
) {
  final horizon = camera.horizonY;
  final top = -shift.dy - size.height;
  final rect = Rect.fromLTRB(-size.width, top, size.width * 2, horizon + 1);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          style.resolveSkyTop(scheme),
          Color.lerp(style.resolveSkyTop(scheme),
              style.resolveSkyHorizon(scheme), 0.55)!,
          style.resolveSkyHorizon(scheme),
        ],
        stops: const [0, 0.55, 1],
      ).createShader(rect),
  );

  // The sun, up and to the left — the thing every shadow in the frame points
  // away from. Drawn as glow rather than a disc: a disc in the corner of a
  // sports scene reads as a sticker.
  final sun = Offset(
    ArcheryLight.sunAt.dx * size.width,
    -shift.dy + ArcheryLight.sunAt.dy * size.height,
  );
  final sunR = size.width * 0.62;
  canvas.drawCircle(
    sun,
    sunR,
    Paint()
      ..shader = ui.Gradient.radial(
        sun,
        sunR,
        [
          const Color(0xFFFFF6DC).withValues(alpha: 0.55),
          const Color(0xFFFFEFC8).withValues(alpha: 0.16),
          Colors.transparent,
        ],
        const [0.0, 0.22, 1.0],
      ),
  );

  // Clouds, in two banks: high and small near the top, flatter and hazier as
  // they approach the horizon, which is the whole of aerial perspective in a
  // sky.
  for (var i = 0; i < 9; i++) {
    final depth = _hash01(i, 12); // 0 = high overhead, 1 = on the horizon
    final cx = (_hash01(i, 11) * 1.7 - 0.35) * size.width;
    final cy = horizon - size.height * (0.06 + (1 - depth) * 0.58);
    final w = size.width * (0.14 + _hash01(i, 13) * 0.26) * (1 - depth * 0.45);
    final h = w * (0.30 - depth * 0.16);
    final lit = Colors.white.withValues(alpha: 0.30 + (1 - depth) * 0.42);
    final shade = Color.lerp(style.resolveHaze(scheme), Colors.white, 0.35)!
        .withValues(alpha: 0.30 + (1 - depth) * 0.3);
    // Shaded underside first, lit crown offset up-left over it.
    for (final (dx, dy, color) in [
      (0.0, h * 0.16, shade),
      (-w * 0.05, -h * 0.10, lit),
    ]) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx + dx, cy + dy), width: w, height: h),
        Paint()..color = color,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + dx + w * 0.20, cy + dy - h * 0.34),
          width: w * 0.58,
          height: h * 1.0,
        ),
        Paint()..color = color,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + dx - w * 0.24, cy + dy - h * 0.18),
          width: w * 0.44,
          height: h * 0.8,
        ),
        Paint()..color = color,
      );
    }
  }

  // Far hills, then a treeline in front of them, then a band of haze pooled at
  // their feet. Three planes at three haze strengths is what stops the far end
  // of the range reading as a painted backdrop a metre behind the butt.
  void ridge({
    required double height,
    required double roughness,
    required double hazeMix,
    required double phase,
    required double lift,
  }) {
    final path = Path()..moveTo(-size.width, horizon + 2);
    const steps = 120;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = -size.width + t * size.width * 3;
      final n = math.sin(t * 9.1 + phase) * 0.5 +
          math.sin(t * 21 + phase * 1.7) * 0.3 * roughness +
          math.sin(t * 47 + phase * 0.4) * 0.2 * roughness;
      path.lineTo(x, horizon - size.height * height * (lift + n));
    }
    path
      ..lineTo(size.width * 2, horizon + 2)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Color.lerp(
          style.resolveGrassFar(scheme),
          style.resolveHaze(scheme),
          hazeMix,
        )!,
    );
  }

  ridge(height: 0.090, roughness: 0.12, hazeMix: 0.82, phase: 0.0, lift: 0.85);
  ridge(height: 0.052, roughness: 0.70, hazeMix: 0.60, phase: 2.4, lift: 1.0);

  // Individual crowns along the near treeline, so it is trees rather than a
  // wavy silhouette.
  final crown = Paint()
    ..color = Color.lerp(
      style.resolveGrassFar(scheme),
      style.resolveHaze(scheme),
      0.5,
    )!;
  for (var i = 0; i < 46; i++) {
    final x = -size.width + _hash01(i, 61) * size.width * 3;
    final h = size.height * (0.018 + _hash01(i, 62) * 0.030);
    final w = h * (0.9 + _hash01(i, 63) * 0.8);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(x, horizon - h * 0.55), width: w, height: h * 1.5),
      crown,
    );
  }

  // Haze pooled along the base of the treeline.
  final hazeBand = Rect.fromLTRB(
      -size.width, horizon - size.height * 0.030, size.width * 2, horizon + 2);
  canvas.drawRect(
    hazeBand,
    Paint()
      ..shader = ui.Gradient.linear(
        hazeBand.topCenter,
        hazeBand.bottomCenter,
        [
          style.resolveHaze(scheme).withValues(alpha: 0.0),
          style.resolveHaze(scheme).withValues(alpha: 0.85),
        ],
      ),
  );
}

void _paintGround(
  Canvas canvas,
  Size size,
  Camera3 camera,
  ArcheryView view,
  ArcheryStyle style,
  ColorScheme scheme,
  Offset shift,
) {
  final horizon = camera.horizonY;
  final bottom = size.height * 2 - shift.dy;
  final rect = Rect.fromLTRB(-size.width, horizon, size.width * 2, bottom);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(style.resolveGrassFar(scheme), style.resolveHaze(scheme),
              0.62)!,
          style.resolveGrassFar(scheme),
          style.resolveGrassNear(scheme),
        ],
        stops: const [0, 0.22, 1],
      ).createShader(rect),
  );

  final far = view.conditions.distance + 14;

  // Mown stripes: bands of grass across the range. Every edge is a projected
  // world line, so they converge on their own — no fake perspective.
  for (var z = 2.0; z < far; z += 4) {
    final band = _quadPath(camera, [
      Vec3(-14, 0, z),
      Vec3(14, 0, z),
      Vec3(14, 0, z + 2),
      Vec3(-14, 0, z + 2),
    ]);
    if (band == null) continue;
    canvas.drawPath(
      band,
      Paint()
        ..color = Colors.white
            .withValues(alpha: 0.05 * (1 - (z / far).clamp(0.0, 1.0) * 0.6)),
    );
  }

  // The shooting lane: a lighter mown strip running to the butt.
  final lane = _quadPath(camera, [
    Vec3(-2.3, 0, 1),
    Vec3(2.3, 0, 1),
    Vec3(2.3, 0, far),
    Vec3(-2.3, 0, far),
  ]);
  if (lane != null) {
    canvas.drawPath(
      lane,
      Paint()..color = Colors.white.withValues(alpha: 0.07),
    );
  }
  for (final x in [-2.3, 2.3]) {
    final a = camera.project(Vec3(x, 0.01, 1.2));
    final b = camera.project(Vec3(x, 0.01, far));
    if (!a.visible || !b.visible) continue;
    canvas.drawLine(
      a.screen,
      b.screen,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..strokeWidth = 1.4,
    );
  }

  // The shooting line at the archer's feet — the near anchor the whole
  // convergence is measured against.
  final lineA = camera.project(const Vec3(-2.3, 0.01, 1.15));
  final lineB = camera.project(const Vec3(2.3, 0.01, 1.15));
  if (lineA.visible && lineB.visible) {
    canvas.drawLine(
      lineA.screen,
      lineB.screen,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = math.max(2, lineA.scale * 0.05),
    );
  }

  // Patchiness: broad worn and lush areas across the turf, projected as real
  // ground ellipses so they shrink with depth like everything else. A mown
  // field is not one green.
  for (var i = 0; i < 26; i++) {
    final z = 2.0 + _hash01(i, 71) * (far - 2.0);
    final x = (_hash01(i, 72) - 0.5) * 18;
    final radius = 1.2 + _hash01(i, 73) * 3.4;
    final patch = camera.horizontalCirclePath(Vec3(x, 0.005, z), radius,
        segments: 14);
    if (patch == null) continue;
    final worn = _hash01(i, 74) < 0.45;
    canvas.drawPath(
      patch,
      Paint()
        ..color = _hazed(
          Color.lerp(
            style.resolveGrassNear(scheme),
            worn ? const Color(0xFFB6A96A) : Colors.black,
            worn ? 0.30 : 0.16,
          )!
              .withValues(alpha: 0.16),
          camera.project(Vec3(x, 0, z)).depth,
          style.resolveHaze(scheme),
        ),
    );
  }

  // Grass tufts. Each is a real world position, so it shrinks with depth —
  // the densest depth cue in the frame. Sampled with a square bias toward the
  // camera so the near ground is not a bare gradient.
  //
  // Three species' worth of variation — height, blade count, colour and lean —
  // because a field of identical marks reads as a texture, and a texture has
  // no depth. The colour is hazed by its own depth, so the far tufts fade into
  // the treeline rather than staying crisp at forty metres.
  final lean = view.conditions.crossComponent * 0.02;
  final tuftPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final near = style.resolveGrassNear(scheme);
  for (var i = 0; i < 420; i++) {
    final u = _hash01(i, 5);
    final z = 1.15 + u * u * (far - 1.15);
    final side = _hash01(i, 3) < 0.5 ? -1 : 1;
    // A third of the tufts grow inside the lane, close to the archer.
    final inLane = _hash01(i, 7) < 0.34;
    final x =
        side * (inLane ? 0.45 + _hash01(i, 4) * 1.8 : 2.5 + _hash01(i, 4) * 11);
    final base = camera.project(Vec3(x, 0, z));
    if (!base.visible) continue;
    final tall = _hash01(i, 8);
    final h = (inLane
            ? 0.04 + tall * 0.07
            : 0.11 + tall * tall * 0.30) *
        base.scale;
    if (h < 0.7) continue;
    final sway = math.sin(view.time * 1.6 + i) * 0.12 + lean;
    final shade = _hash01(i, 9);
    tuftPaint
      ..color = _hazed(
        Color.lerp(
          near,
          shade < 0.5 ? Colors.black : const Color(0xFFC9DE8E),
          shade < 0.5 ? 0.10 + shade * 0.32 : 0.10 + (shade - 0.5) * 0.5,
        )!
            .withValues(alpha: 0.42 + tall * 0.28),
        base.depth,
        style.resolveHaze(scheme),
      )
      ..strokeWidth = math.max(0.8, base.scale * 0.011);
    // Wider tufts near the camera get a fifth blade; distant ones get three,
    // which is all that survives at a couple of pixels anyway.
    final blades = h > 6 ? 2 : 1;
    for (var k = -blades; k <= blades; k++) {
      final spread = k * 0.30;
      canvas.drawLine(
        base.screen,
        base.screen +
            Offset((spread + sway) * h, -h * (1 - k.abs() * 0.12)),
        tuftPaint,
      );
    }
  }

  // Foreground vignette — seats the bow and stops the near grass reading as a
  // flat wash.
  final vignette = Rect.fromLTWH(
    -size.width,
    size.height * 0.72,
    size.width * 3,
    size.height * 1.3,
  );
  canvas.drawRect(
    vignette,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0),
          Colors.black.withValues(alpha: 0.26),
        ],
      ).createShader(vignette),
  );

  // Range markers every 10 m, so distance is legible, not just felt.
  for (var m = 10; m < view.conditions.distance - 2; m += 10) {
    for (final x in [-2.8, 2.8]) {
      final base = camera.project(Vec3(x, 0, m.toDouble()));
      final top = camera.project(Vec3(x, 0.34, m.toDouble()));
      if (!base.visible || !top.visible) continue;
      canvas.drawLine(
        base.screen,
        top.screen,
        Paint()
          ..color = _hazed(Colors.white.withValues(alpha: 0.7), base.depth,
              style.resolveHaze(scheme))
          ..strokeWidth = math.max(1, base.scale * 0.02)
          ..strokeCap = StrokeCap.round,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Depth-sorted props
// ---------------------------------------------------------------------------

void _paintProps(
  Canvas canvas,
  Size size,
  Camera3 camera,
  ArcheryView view,
  ArcheryStyle style,
  ColorScheme scheme,
) {
  final scene = Scene3(camera);
  final d = view.conditions.distance;

  scene.add(Vec3(0, 0, d + 0.4), (c, at) => _paintButt(c, camera, view, style, scheme));
  scene.add(Vec3(1.15, 0, d - 0.6),
      (c, at) => _paintWindFlag(c, camera, view, style, scheme));

  final dent = view.dent;
  for (var i = 0; i < view.stuckArrows.length; i++) {
    final shot = view.stuckArrows[i];
    if (!shot.onFace) continue;
    // Only the arrow that just went in is still ringing; the earlier ones in
    // this end are dead still.
    final settle =
        i == view.stuckArrows.length - 1 ? view.arrowSettle : 0.0;
    final (ox, oy) =
        dent?.apply(shot.offsetX, shot.offsetY) ?? (shot.offsetX, shot.offsetY);
    scene.add(
      Vec3(ox, ArcheryBallistics.targetCentreHeight + oy, d - 0.35),
      (c, at) => _paintStuckArrow(
          c, camera, view, shot, style, scheme, ox, oy, settle),
    );
  }

  // An arrow that missed and is lying in the range. Sorted with everything
  // else, so one short of the butt is drawn in front of it and one long is
  // drawn behind.
  final stray = view.stray;
  if (stray != null) {
    scene.add(
      stray.position,
      (c, at) => _paintStrayArrow(c, camera, view, stray, style, scheme),
    );
  }

  final flight = view.flight;
  if (flight != null) {
    scene.add(
      Vec3(flight.position.x, 0.02, flight.position.z),
      (c, at) => _paintFlightShadow(c, camera, flight, style, scheme),
    );
    scene.add(
      flight.position,
      (c, at) => _paintFlyingArrow(c, camera, view, flight, style, scheme),
    );
  }

  scene.paint(canvas);
}

void _paintButt(
  Canvas canvas,
  Camera3 camera,
  ArcheryView view,
  ArcheryStyle style,
  ColorScheme scheme,
) {
  final d = view.conditions.distance;
  final haze = style.resolveHaze(scheme);
  final depth = camera.project(Vec3(0, 1.3, d)).depth;
  final scale = camera.project(Vec3(0, ArcheryBallistics.targetCentreHeight, d))
      .scale;
  const buttTop = 2.24;
  const buttBottom = 0.34;
  const buttHalf = 0.88;
  final faceZ = d;
  final buttZ = d + 0.12;

  // Ground shadow. Thrown down-**right** of the butt by the sun's own run, not
  // parked under it: a shadow that sits symmetrically under a prop is the
  // fastest way to make a scene look unlit.
  final shadowRun = ArcheryLight.shadowRun * buttTop;
  final shadow = camera.horizontalCirclePath(
    Vec3(shadowRun * 0.45, 0.02, buttZ + 0.30),
    1.15,
    segments: 24,
  );
  if (shadow != null) {
    canvas.drawPath(
      shadow,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1, scale * 0.02)),
    );
  }

  final wobble = view.targetWobble;
  canvas.save();
  if (wobble > 0) {
    // The whole butt rocks on its stand. Small — the readable part of the
    // impact is the compression at the hole, not the target jumping.
    final amp = wobble * wobble * 2.6;
    canvas.translate(
        math.sin(view.time * 34) * amp, math.sin(view.time * 41) * amp * 0.5);
  }

  _paintStand(canvas, camera, style, scheme, d, depth);

  // The straw bale itself.
  final butt = _quadPath(camera, [
    Vec3(-buttHalf, buttBottom, buttZ),
    Vec3(buttHalf, buttBottom, buttZ),
    Vec3(buttHalf, buttTop, buttZ),
    Vec3(-buttHalf, buttTop, buttZ),
  ]);
  if (butt != null) {
    final straw = _hazed(style.resolveButt(scheme), depth, haze);
    final bounds = butt.getBounds();
    canvas.drawPath(
      butt,
      Paint()
        ..shader = ui.Gradient.linear(
          bounds.topLeft,
          bounds.bottomRight,
          [
            Color.lerp(straw, Colors.white, 0.16)!,
            straw,
            Color.lerp(straw, Colors.black, 0.24)!,
          ],
          const [0.0, 0.45, 1.0],
        ),
    );

    // Coiled straw courses. A butt is rope-bound bales stacked flat, so it is
    // built as **bands with their own tone**, not as ruled lines over a flat
    // fill: every course was baled from different straw, and that unevenness
    // is the whole difference between straw and a tan rectangle.
    canvas.save();
    canvas.clipPath(butt);
    const bandHeight = 0.155;
    var band = 0;
    for (var y = buttBottom; y < buttTop; y += bandHeight, band++) {
      final quad = _quadPath(camera, [
        Vec3(-buttHalf - 0.03, y, buttZ),
        Vec3(buttHalf + 0.03, y, buttZ),
        Vec3(buttHalf + 0.03, y + bandHeight, buttZ),
        Vec3(-buttHalf - 0.03, y + bandHeight, buttZ),
      ]);
      if (quad == null) continue;
      final tone = _hash01(band, 81) - 0.5;
      canvas.drawPath(
        quad,
        Paint()
          ..color = Color.lerp(
            straw,
            tone > 0 ? const Color(0xFFF3E0AA) : const Color(0xFF8E6F38),
            tone.abs() * 1.3,
          )!
              .withValues(alpha: 0.75),
      );

      // Course seam. Sampled as a **wavy** polyline rather than drawn as a
      // ruled line: a perfectly straight seam is what makes stacked straw read
      // as floorboards, and no amount of colour work undoes it.
      final seam = Path();
      final lip = Path();
      var started = false;
      double? w;
      for (var k = 0; k <= 14; k++) {
        final fx = -buttHalf - 0.03 + (2 * buttHalf + 0.06) * k / 14;
        final wob = (_hash01(band * 31 + k, 87) - 0.5) * 0.028;
        final p = camera.project(Vec3(fx, y + wob, buttZ));
        if (!p.visible) {
          started = false;
          continue;
        }
        w ??= math.max(0.7, p.scale * 0.011);
        if (!started) {
          seam.moveTo(p.screen.dx, p.screen.dy);
          lip.moveTo(p.screen.dx, p.screen.dy - w * 1.4);
          started = true;
        } else {
          seam.lineTo(p.screen.dx, p.screen.dy);
          lip.lineTo(p.screen.dx, p.screen.dy - w * 1.4);
        }
      }
      if (w == null) continue;
      canvas.drawPath(
        seam,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 1.5
          ..color = Colors.black.withValues(alpha: 0.26),
      );
      canvas.drawPath(
        lip,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.8
          ..color = Colors.white.withValues(alpha: 0.22),
      );
    }
    // Fibre: straw ends poking out of the courses, leaning the way they were
    // packed. Short, faint, and never horizontal — a horizontal stroke here
    // just reinforces the banding and turns the bale back into planks.
    final fibre = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 260; i++) {
      final fx = (_hash01(i, 82) * 2 - 1) * buttHalf;
      final fy = buttBottom + _hash01(i, 83) * (buttTop - buttBottom);
      final len = 0.04 + _hash01(i, 84) * 0.10;
      // Mostly steep: straw ends stick out across the courses, and a shallow
      // stroke just reinforces the banding.
      final tilt = (_hash01(i, 85) - 0.5) * 2.6 + math.pi / 2;
      final p0 = camera.project(Vec3(fx, fy, buttZ));
      final p1 = camera.project(
          Vec3(fx + len * math.cos(tilt), fy + len * math.sin(tilt), buttZ));
      if (!p0.visible || !p1.visible) continue;
      fibre
        ..color = (_hash01(i, 86) < 0.45 ? Colors.black : Colors.white)
            .withValues(alpha: 0.09 + _hash01(i, 88) * 0.07)
        ..strokeWidth = math.max(0.6, p0.scale * 0.005);
      canvas.drawLine(p0.screen, p1.screen, fibre);
    }
    canvas.restore();

    // Binding ropes across the bale, and the edge lit up-left / dark down-right.
    for (final y in const [0.72, 1.86]) {
      final a = camera.project(Vec3(-buttHalf, y, buttZ - 0.01));
      final b = camera.project(Vec3(buttHalf, y, buttZ - 0.01));
      if (!a.visible || !b.visible) continue;
      canvas.drawLine(
        a.screen.translate(0, math.max(1, a.scale * 0.012)),
        b.screen.translate(0, math.max(1, a.scale * 0.012)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.28)
          ..strokeWidth = math.max(1.2, a.scale * 0.018),
      );
      canvas.drawLine(
        a.screen,
        b.screen,
        Paint()
          ..color = _hazed(const Color(0xFF9C7B44), a.depth, haze)
          ..strokeWidth = math.max(1.2, a.scale * 0.018),
      );
    }
    canvas.drawPath(
      butt,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, scale * 0.012)
        ..color = _hazed(const Color(0xFF7A5C2E), depth, haze),
    );
  }

  // The face: five equal rings, every one a truly projected circle, drawn
  // through the live compression so the straw takes the arrow.
  final dent = view.dent;
  final centre = Vec3(0, ArcheryBallistics.targetCentreHeight, faceZ);
  final segments = dent == null ? 48 : 120;
  for (var i = ArcheryStyle.ringColors.length - 1; i >= 0; i--) {
    final radius = ArcheryGame.ringWidth * (i + 1);
    final path = verticalCirclePath(camera, centre, radius,
        segments: segments, dent: dent);
    if (path == null) continue;
    canvas.drawPath(
      path,
      Paint()
        ..color =
            _hazed(ArcheryStyle.ringColors[i], depth, haze, strength: 0.55),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.7, scale * 0.006)
        ..color = ArcheryStyle.ringLine,
    );
  }
  // Paper curl: the face is pinned paper, so the sun catches its up-left edge.
  final rim = verticalCirclePath(camera, centre, ArcheryGame.faceRadius,
      segments: segments, dent: dent);
  if (rim != null) {
    canvas.drawPath(
      rim.shift(Offset(-scale * 0.004, -scale * 0.004)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.7, scale * 0.005)
        ..color = Colors.white.withValues(alpha: 0.35),
    );
  }
  // Inner ten-ring mark.
  final inner = verticalCirclePath(
      camera, centre, ArcheryGame.ringWidth * 0.42,
      segments: segments, dent: dent);
  if (inner != null) {
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, scale * 0.005)
        ..color = Colors.black.withValues(alpha: 0.35),
    );
  }
  canvas.restore();
}

/// The stand: two splayed timber legs with a cross-brace, each casting its own
/// shadow down-right onto the grass.
void _paintStand(
  Canvas canvas,
  Camera3 camera,
  ArcheryStyle style,
  ColorScheme scheme,
  double d,
  double depth,
) {
  final haze = style.resolveHaze(scheme);
  final timber = _hazed(const Color(0xFF6B4B2E), depth, haze);
  final lit = _hazed(const Color(0xFF8E6941), depth, haze);

  for (final side in [-1.0, 1.0]) {
    final footAt = Vec3(side * 0.82, 0, d + 0.62);
    final topAt = Vec3(side * 0.36, 0.92, d + 0.14);
    final foot = camera.project(footAt);
    final top = camera.project(topAt);
    if (!foot.visible || !top.visible) continue;
    final width = math.max(1.4, foot.scale * 0.055);

    // Shadow of the leg, cast along the sun's run.
    final shadowTop = camera.project(
        Vec3(topAt.x + ArcheryLight.shadowRun * 0.92, 0.01, topAt.z + 0.30));
    if (shadowTop.visible) {
      canvas.drawLine(
        foot.screen,
        shadowTop.screen,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.20)
          ..strokeWidth = width * 0.9
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.drawLine(
      foot.screen,
      top.screen,
      Paint()
        ..color = timber
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
    // Lit edge up-left of the leg.
    canvas.drawLine(
      foot.screen.translate(-width * 0.3, 0),
      top.screen.translate(-width * 0.3, 0),
      Paint()
        ..color = lit.withValues(alpha: 0.7)
        ..strokeWidth = width * 0.3
        ..strokeCap = StrokeCap.round,
    );
  }

  // Cross-brace between the legs.
  final braceL = camera.project(Vec3(-0.62, 0.36, d + 0.42));
  final braceR = camera.project(Vec3(0.62, 0.36, d + 0.42));
  if (braceL.visible && braceR.visible) {
    canvas.drawLine(
      braceL.screen,
      braceR.screen,
      Paint()
        ..color = timber
        ..strokeWidth = math.max(1.2, braceL.scale * 0.038)
        ..strokeCap = StrokeCap.round,
    );
  }
}

void _paintWindFlag(
  Canvas canvas,
  Camera3 camera,
  ArcheryView view,
  ArcheryStyle style,
  ColorScheme scheme,
) {
  final c = view.conditions;
  // Pinned just beside the butt. Anywhere further forward and the sight zoom
  // — which is deliberately tight at long range — crops it out of the frame
  // exactly when the wind matters most.
  final z = c.distance - 0.6;
  const x = 1.15;
  final base = camera.project(Vec3(x, 0, z));
  final top = camera.project(Vec3(x, 2.25, z));
  if (!base.visible || !top.visible) return;
  final haze = style.resolveHaze(scheme);

  canvas.drawLine(
    base.screen,
    top.screen,
    Paint()
      ..color = _hazed(const Color(0xFFEFEFEF), base.depth, haze)
      ..strokeWidth = math.max(1.2, base.scale * 0.025)
      ..strokeCap = StrokeCap.round,
  );

  // The flag streams the way the wind blows, and hangs limp when it doesn't.
  final strength = (c.windSpeed / 9).clamp(0.0, 1.0);
  final length = 0.22 + 0.34 * strength;
  final dir = Vec3(math.cos(c.windAngle), 0, math.sin(c.windAngle));
  final droop = 0.42 * (1 - strength);
  final wave = math.sin(view.time * (2 + strength * 6)) * 0.12 * strength;
  final tip = Vec3(
    x + dir.x * length,
    2.25 - droop * 0.6 + wave * 0.5,
    z + dir.z * length,
  );
  final mid = Vec3(
    x + dir.x * length * 0.55,
    2.25 - droop * 0.2 - wave * 0.5,
    z + dir.z * length * 0.55,
  );
  final tipP = camera.project(tip);
  final midP = camera.project(mid);
  final lowP = camera.project(Vec3(x, 2.25 - 0.22, z));
  if (!tipP.visible || !midP.visible || !lowP.visible) return;
  final flag = Path()
    ..moveTo(top.screen.dx, top.screen.dy)
    ..quadraticBezierTo(
        midP.screen.dx, midP.screen.dy, tipP.screen.dx, tipP.screen.dy)
    ..lineTo(lowP.screen.dx, lowP.screen.dy)
    ..close();
  canvas.drawPath(
    flag,
    Paint()..color = _hazed(view.accent, base.depth, haze, strength: 0.5),
  );
}

/// A stuck arrow, drawn in perspective: the shaft runs from the face back
/// toward the viewer, so it foreshortens on its own, and the fletching sits at
/// the near end. Seeing your last two arrows is how you correct — this is a
/// mechanic, not decoration.
void _paintStuckArrow(
  Canvas canvas,
  Camera3 camera,
  ArcheryView view,
  ArrowShot shot,
  ArcheryStyle style,
  ColorScheme scheme,
  double offsetX,
  double offsetY,
  double settle,
) {
  final d = view.conditions.distance;
  final head = Vec3(
    offsetX,
    ArcheryBallistics.targetCentreHeight + offsetY,
    d,
  );
  // Back along the line it came in on, still ringing if it has only just
  // arrived.
  final incoming = _quivered(
    (head - ArcheryBallistics.bowOrigin).normalized,
    settle,
  );
  final tail = head - incoming * 0.66;
  _paintShaft(
    canvas,
    camera,
    head,
    tail,
    view.accent,
    style,
    scheme,
    thickness: 0.012,
  );
}

/// The arrow's axis, still ringing.
///
/// The shaft whips about the point for a few hundred milliseconds after it
/// bites and then stands still. Rotating the *axis* rather than shaking the
/// whole sprite pins the vibration at the point, which is what an arrow in a
/// butt actually does — the nock describes a small ellipse and the head does
/// not move at all.
Vec3 _quivered(Vec3 direction, double settle) {
  if (settle <= 0) return direction;
  final s = settle.clamp(0.0, 1.0);
  // Squared decay: nearly gone by halfway, then just settling.
  final amp = 0.085 * s * s;
  final t = (1 - s) * 24;
  final up = direction.y.abs() > 0.95
      ? const Vec3(1, 0, 0)
      : const Vec3(0, 1, 0);
  final u = _cross(direction, up).normalized;
  final v = _cross(direction, u).normalized;
  return (direction +
          u * (amp * math.sin(t)) +
          v * (amp * 0.6 * math.sin(t * 1.37 + 0.9)))
      .normalized;
}

Vec3 _cross(Vec3 a, Vec3 b) => Vec3(
      a.y * b.z - a.z * b.y,
      a.z * b.x - a.x * b.z,
      a.x * b.y - a.y * b.x,
    );

/// An arrow that missed the face: planted in the turf where it finished, with
/// its own shadow on the grass.
void _paintStrayArrow(
  Canvas canvas,
  Camera3 camera,
  ArcheryView view,
  StrayArrow stray,
  ArcheryStyle style,
  ColorScheme scheme,
) {
  final head = stray.position;
  final tail = head - stray.direction * 0.72;

  // Shadow, along the sun's run, so a stray reads as lying *on* the range and
  // not floating over it.
  if (stray.inGround) {
    final groundHead = camera.project(Vec3(head.x, 0.01, head.z));
    final groundTail = camera.project(Vec3(
      tail.x + ArcheryLight.shadowRun * tail.y,
      0.01,
      tail.z + ArcheryLight.shadowRun * tail.y * 0.6,
    ));
    if (groundHead.visible && groundTail.visible) {
      canvas.drawLine(
        groundHead.screen,
        groundTail.screen,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.22)
          ..strokeWidth = math.max(1.2, groundHead.scale * 0.02)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  _paintShaft(
    canvas,
    camera,
    head,
    tail,
    view.accent,
    style,
    scheme,
    thickness: 0.013,
  );
}

void _paintFlyingArrow(
  Canvas canvas,
  Camera3 camera,
  ArcheryView view,
  ArrowInFlight flight,
  ArcheryStyle style,
  ColorScheme scheme,
) {
  // Motion streak along the recent path.
  if (flight.trail.length > 1) {
    for (var i = 1; i < flight.trail.length; i++) {
      final a = camera.project(flight.trail[i - 1]);
      final b = camera.project(flight.trail[i]);
      if (!a.visible || !b.visible) continue;
      canvas.drawLine(
        a.screen,
        b.screen,
        Paint()
          ..color = Colors.white
              .withValues(alpha: 0.26 * (i / flight.trail.length))
          ..strokeWidth = math.max(2.0, a.scale * 0.035)
          ..strokeCap = StrokeCap.round,
      );
    }
  }
  final head = flight.position;
  final tail = head - flight.direction * 0.95;
  _paintShaft(canvas, camera, head, tail, view.accent, style, scheme,
      thickness: 0.034, minWidth: 4, outline: true);
}

void _paintShaft(
  Canvas canvas,
  Camera3 camera,
  Vec3 head,
  Vec3 tail,
  Color accent,
  ArcheryStyle style,
  ColorScheme scheme, {
  required double thickness,
  double minWidth = 1.1,
  bool outline = false,
}) {
  final h = camera.project(head);
  final t = camera.project(tail);
  if (!h.visible || !t.visible) return;
  final haze = style.resolveHaze(scheme);
  final width = math.max(minWidth, t.scale * thickness);

  if (outline) {
    canvas.drawLine(
      t.screen,
      h.screen,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..strokeWidth = width + 2
        ..strokeCap = StrokeCap.round,
    );
  }
  canvas.drawLine(
    t.screen,
    h.screen,
    Paint()
      ..color = _hazed(const Color(0xFFF1E6D2), h.depth, haze, strength: 0.5)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round,
  );
  // Point.
  canvas.drawCircle(
    h.screen,
    width * 0.75,
    Paint()..color = _hazed(const Color(0xFF6E6E76), h.depth, haze, strength: 0.5),
  );

  // Fletching: three vanes at the nock end, drawn perpendicular to the shaft
  // on screen. When the arrow points at you the shaft collapses and the vanes
  // are all you see — exactly right.
  //
  // Three, not two, and each with its own tone: two hen vanes in the accent
  // and a **cock feather** in white standing off the shaft. In flight the
  // arrow is a few pixels of shaft and the fletching is the only part big
  // enough to read, so it has to say "arrow" on its own — a symmetric pair of
  // flat triangles reads as a paper dart.
  final axis = h.screen - t.screen;
  final len = axis.distance;
  final dir = len < 1e-3 ? const Offset(0, -1) : axis / len;
  final normal = Offset(-dir.dy, dir.dx);
  // Clamped: an arrow a few metres from the eye is genuinely large, but past
  // a point it stops reading as an arrow and starts covering the target.
  final vane = math.min(
    outline ? 30.0 : 13.0,
    math.max(outline ? 7.0 : 2.6, t.scale * (outline ? 0.075 : 0.044)),
  );
  final hen = _hazed(accent, t.depth, haze, strength: 0.45);
  final cock = _hazed(
      Color.lerp(accent, Colors.white, 0.42)!, t.depth, haze,
      strength: 0.45);

  /// One vane: a swept quadrilateral from the nock forward along the shaft,
  /// rather than a triangle, so it has a leading edge and a trailing corner.
  void fletch(double side, double reach, Color color) {
    final root = t.screen + Offset(dir.dx, dir.dy) * (vane * 0.1);
    final tipOut = root +
        normal * (vane * reach * side * 0.72) +
        Offset(dir.dx, dir.dy) * (vane * 0.5);
    final trail = t.screen - Offset(dir.dx, dir.dy) * (vane * 0.24) +
        normal * (vane * reach * side * 0.42);
    final front = t.screen + Offset(dir.dx, dir.dy) * (vane * 1.9);
    canvas.drawPath(
      Path()..addPolygon([front, tipOut, trail, root], true),
      Paint()..color = color,
    );
    canvas.drawPath(
      Path()..addPolygon([front, tipOut, trail, root], true),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.5, width * 0.18)
        ..color = Colors.black.withValues(alpha: 0.28),
    );
  }

  fletch(-1, 1.0, hen);
  fletch(1, 1.0, hen);
  // The cock feather sits square to the other two; edge-on it collapses to a
  // sliver down the shaft, which is exactly what it does on a real arrow.
  fletch(1, 0.34, cock);

  // Nock: a dark cup at the very end, and the shaft's own bright tail behind.
  canvas.drawCircle(
    t.screen,
    width * 0.7,
    Paint()..color = const Color(0xFF23201C),
  );
}

void _paintFlightShadow(
  Canvas canvas,
  Camera3 camera,
  ArrowInFlight flight,
  ArcheryStyle style,
  ColorScheme scheme,
) {
  final ground = Vec3(flight.position.x, 0.02, flight.position.z);
  final path = camera.horizontalCirclePath(ground, 0.22, segments: 16);
  if (path == null) return;
  final height = flight.position.y.clamp(0.0, 6.0);
  canvas.drawPath(
    path,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.26 * (1 - height / 8))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
  );
}

// ---------------------------------------------------------------------------
// Foreground: bow, reticle, HUD
// ---------------------------------------------------------------------------

/// A point on a cubic Bézier — used to sample the bow's spine so the limb, the
/// laminate stripe and the string tips are all built from one curve.
Offset _bezier3(Offset a, Offset b, Offset c, Offset d, double t) {
  final u = 1 - t;
  return a * (u * u * u) +
      b * (3 * u * u * t) +
      c * (3 * u * t * t) +
      d * (t * t * t);
}

/// A closed outline around [spine], [halfWidth] pixels either side at each
/// sample — a stroke with a taper, which `Paint.strokeWidth` cannot do.
Path _taperedBody(List<Offset> spine, double Function(int) halfWidth) {
  final left = <Offset>[];
  final right = <Offset>[];
  for (var i = 0; i < spine.length; i++) {
    final prev = spine[math.max(0, i - 1)];
    final next = spine[math.min(spine.length - 1, i + 1)];
    var dir = next - prev;
    final len = dir.distance;
    dir = len < 1e-6 ? const Offset(0, -1) : dir / len;
    final normal = Offset(-dir.dy, dir.dx) * halfWidth(i);
    left.add(spine[i] + normal);
    right.add(spine[i] - normal);
  }
  return Path()
    ..addPolygon([...left, ...right.reversed], true);
}

void _paintBow(
  Canvas canvas,
  Size size,
  ArcheryView view,
  ArcheryStyle style,
  ColorScheme scheme,
  Offset? reticle,
) {
  final w = size.width;
  final h = size.height;
  final draw = Curves.easeOut.transform(view.drawProgress.clamp(0.0, 1.0));
  final shake = view.focusBreak > 0
      ? math.sin(view.time * 26) * view.focusBreak * w * 0.012
      : 0.0;

  // The bow frames the lower-left corner rather than bisecting the view: you
  // are looking *past* your bow hand at the target, not at your own equipment.
  final gripX = w * 0.20 + shake;
  final gripY = h * 0.80;
  final limbTopY = h * 0.30;

  // The limb, as a **tapered solid** rather than a constant stroke. A recurve
  // is deep at the fade and narrow at the tip, and that taper is most of what
  // separates a bow from a bent line. The spine is sampled from the same
  // curve the string is nocked against, so the two can never disagree.
  final spine = <Offset>[
    for (var i = 0; i <= 26; i++)
      _bezier3(
        Offset(gripX - w * 0.070, limbTopY - h * 0.030),
        Offset(gripX - w * 0.115, h * 0.44),
        Offset(gripX - w * 0.030, h * 0.66),
        Offset(gripX, gripY),
        i / 26,
      ),
    for (var i = 1; i <= 20; i++)
      _bezier3(
        Offset(gripX, gripY),
        Offset(gripX + w * 0.055, h * 0.95),
        Offset(gripX + w * 0.075, h * 1.06),
        Offset(gripX + w * 0.010, h * 1.17),
        i / 20,
      ),
  ];
  // Deep through the middle third, tapering to the tips.
  double halfWidth(int i) {
    final t = i / (spine.length - 1);
    final belly = math.sin(math.pi * t.clamp(0.0, 1.0));
    return w * (0.006 + 0.020 * math.pow(belly, 0.65));
  }

  final limb = _taperedBody(spine, halfWidth);
  canvas.drawPath(
    limb,
    Paint()..color = const Color(0xFF2E2013),
  );
  // Laminate: a paler core stripe down the belly of the limb, then the sun's
  // edge up-left of it.
  canvas.drawPath(
    _taperedBody(spine, (i) => halfWidth(i) * 0.42),
    Paint()..color = const Color(0xFF6B4A2A),
  );
  canvas.drawPath(
    _taperedBody(
      [for (final p in spine) p.translate(-w * 0.009, 0)],
      (i) => halfWidth(i) * 0.16,
    ),
    Paint()..color = Colors.white.withValues(alpha: 0.22),
  );

  // Riser: a shaped block with an arrow shelf and a sight window cut out of it.
  final riser = RRect.fromRectAndRadius(
    Rect.fromCenter(
        center: Offset(gripX, gripY), width: w * 0.060, height: h * 0.165),
    Radius.circular(w * 0.020),
  );
  canvas.drawRRect(riser, Paint()..color = const Color(0xFF241809));
  canvas.drawRRect(
    riser.deflate(w * 0.010),
    Paint()..color = const Color(0xFF3E2B17),
  );
  // Arrow shelf: the ledge the shaft rests over, catching the light.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(gripX + w * 0.008, gripY - h * 0.036, w * 0.048,
          h * 0.012),
      Radius.circular(w * 0.006),
    ),
    Paint()..color = const Color(0xFF6B4A2A),
  );

  // Leather grip, and the bow hand wrapped round it.
  final grip = RRect.fromRectAndRadius(
    Rect.fromCenter(
        center: Offset(gripX, gripY + h * 0.012),
        width: w * 0.052,
        height: h * 0.072),
    Radius.circular(w * 0.020),
  );
  canvas.drawRRect(grip, Paint()..color = const Color(0xFF4A3018));
  for (var i = 0; i < 5; i++) {
    final y = gripY - h * 0.020 + i * h * 0.016;
    canvas.drawLine(
      Offset(gripX - w * 0.024, y),
      Offset(gripX + w * 0.024, y - h * 0.004),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..strokeWidth = math.max(0.8, w * 0.003),
    );
  }
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(gripX + w * 0.030, gripY + h * 0.010),
          width: w * 0.082,
          height: h * 0.066),
      Radius.circular(w * 0.028),
    ),
    Paint()..color = const Color(0xFFD9A277),
  );
  // Knuckles, lit up-left.
  for (var i = 0; i < 3; i++) {
    canvas.drawCircle(
      Offset(gripX + w * 0.016, gripY - h * 0.012 + i * h * 0.021),
      w * 0.012,
      Paint()..color = const Color(0xFFE8B98D),
    );
  }

  // The nock travels toward the viewer as the string is drawn: on screen that
  // reads as the nock sliding down-right and the fletching swelling.
  final nockRest = Offset(gripX + w * 0.05, gripY - h * 0.03);
  final nockFull = Offset(gripX + w * 0.22, gripY + h * 0.055);
  final nock = Offset.lerp(nockRest, nockFull, draw)! + Offset(shake, 0);

  // String: from limb tips through the nock. Drawn as a dark core under a pale
  // edge so it has thickness — a one-pixel white hairline reads as a scratch on
  // the screen rather than as sixteen strands of Dacron.
  final tipTop = spine.first;
  final tipBottom = spine.last;
  for (final (width, color) in [
    (math.max(1.8, w * 0.0075), const Color(0xFF2A2622)),
    (math.max(1.0, w * 0.0038), const Color(0xFFE9E4D8)),
  ]) {
    final string = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawLine(tipTop, nock, string);
    canvas.drawLine(nock, tipBottom, string);
  }
  // Centre serving: the thicker wrap the arrow nocks onto.
  canvas.drawLine(
    Offset.lerp(nock, tipTop, 0.11)!,
    Offset.lerp(nock, tipBottom, 0.11)!,
    Paint()
      ..strokeWidth = math.max(2.0, w * 0.009)
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF8A8F98),
  );

  // No arrow on the string once it has been loosed.
  if (!view.showReticle) return;

  // The arrow: from the nock to the sight picture. Its point *is* the reticle,
  // which is what makes the aim read as the arrow's own line.
  final point = reticle ?? Offset(w * 0.5, h * 0.42);
  canvas.drawLine(
    nock,
    point,
    Paint()
      ..strokeWidth = math.max(1.6, w * 0.007)
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFF1E6D2),
  );
  canvas.drawLine(
    nock,
    point,
    Paint()
      ..strokeWidth = math.max(0.7, w * 0.0025)
      ..color = Colors.black.withValues(alpha: 0.16),
  );

  // Fletching at the nock.
  final axis = point - nock;
  final len = axis.distance;
  final dir = len < 1e-3 ? const Offset(0, -1) : axis / len;
  final normal = Offset(-dir.dy, dir.dx);
  final vane = w * 0.026;
  for (final s in [-1.0, 1.0]) {
    final path = Path()
      ..moveTo(nock.dx, nock.dy)
      ..lineTo(nock.dx + normal.dx * vane * s, nock.dy + normal.dy * vane * s)
      ..lineTo(nock.dx + dir.dx * vane * 2.1, nock.dy + dir.dy * vane * 2.1)
      ..close();
    canvas.drawPath(path, Paint()..color = view.accent);
  }
  canvas.drawCircle(nock, w * 0.009, Paint()..color = const Color(0xFF23201C));
}

void _paintReticle(
  Canvas canvas,
  Camera3 camera,
  ArcheryView view,
  Offset at,
  ColorScheme scheme,
) {
  // Radius IS the sway: the reticle is a readout of the shot's real spread,
  // not a decorative ring that happens to shrink.
  // 1.5x the amplitude: the wander peaks at exactly `amplitude`, so the ring
  // reads a shade wide of the true spread and no wider. It was 2.6x back when
  // the amplitude was small enough that an honest ring would have been a dot.
  final radius = math.max(9.0, view.swayAmplitude * camera.focal * 1.5);
  final warn = view.focusBreak;
  final color = Color.lerp(
    Colors.white,
    const Color(0xFFE2483C),
    warn.clamp(0.0, 1.0),
  )!;
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = color.withValues(alpha: view.drawing ? 0.95 : 0.6);

  canvas.drawCircle(at, radius, stroke);
  canvas.drawCircle(
    at,
    radius * 0.06 + 1.4,
    Paint()..color = color.withValues(alpha: 0.9),
  );
  for (var i = 0; i < 4; i++) {
    final a = math.pi / 2 * i;
    final dir = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(
      at + dir * (radius * 0.45),
      at + dir * (radius * 0.92),
      stroke,
    );
  }
  if (view.drawing) {
    canvas.drawCircle(
      at,
      radius + 5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.18),
    );
  }
}

void _paintHud(
  Canvas canvas,
  Size size,
  ArcheryView view,
  ArcheryStyle style,
  ColorScheme scheme,
) {
  final c = view.conditions;
  final pad = size.width * 0.045;

  // Wind: an arrow you read at a glance plus the number you plan with.
  final badgeCentre = Offset(size.width - pad - 26, pad + 26);
  canvas.drawCircle(
    badgeCentre,
    26,
    Paint()..color = Colors.black.withValues(alpha: 0.32),
  );
  final strength = (c.windSpeed / 9).clamp(0.0, 1.0);
  // +x is right on screen, +z (down-range) is up-screen.
  final angle = math.atan2(-c.alongComponent, c.crossComponent);
  final windColor = Color.lerp(
    Colors.white,
    const Color(0xFFFFC44D),
    strength,
  )!;
  canvas.save();
  canvas.translate(badgeCentre.dx, badgeCentre.dy);
  canvas.rotate(angle);
  final len = 9 + 9 * strength;
  final arrow = Path()
    ..moveTo(-len, 0)
    ..lineTo(len * 0.35, 0)
    ..moveTo(len, 0)
    ..lineTo(len * 0.3, -6)
    ..moveTo(len, 0)
    ..lineTo(len * 0.3, 6);
  canvas.drawPath(
    arrow,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = windColor,
  );
  canvas.drawLine(
    Offset(-len, 0),
    Offset(len * 0.35, 0),
    Paint()
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = windColor,
  );
  canvas.restore();
  _text(
    canvas,
    '${c.windSpeed.toStringAsFixed(1)} m/s',
    Offset(badgeCentre.dx, badgeCentre.dy + 34),
    size: 12,
    color: windColor,
    align: TextAlign.center,
  );

  // Range readout.
  _text(
    canvas,
    'TARGET ${c.index + 1}',
    Offset(pad, pad + 2),
    size: 11,
    color: Colors.white.withValues(alpha: 0.75),
    align: TextAlign.left,
  );
  _text(
    canvas,
    '${c.distance.toStringAsFixed(0)} m',
    Offset(pad, pad + 16),
    size: 20,
    color: Colors.white,
    align: TextAlign.left,
    weight: FontWeight.w800,
  );

  // Arrows left in the quiver for this end.
  for (var i = 0; i < ArcheryGame.arrowsPerTarget; i++) {
    final live = i < view.arrowsLeft;
    final at = Offset(pad + 6 + i * 13, pad + 46);
    canvas.drawCircle(
      at,
      4,
      Paint()
        ..color = live
            ? view.accent
            : Colors.white.withValues(alpha: 0.22),
    );
  }

  // Draw meter — the anticipation made legible: a bar filling across the whole
  // hold, a marker at the perfect release, and a red zone once focus goes.
  // It tracks holdProgress rather than drawProgress: the shot ripens *during*
  // the steady hold, and a bar that stopped at full stretch was pointing at a
  // sweet spot the player had already sailed past.
  final barW = size.width * 0.5;
  final bar = Rect.fromLTWH(
    (size.width - barW) / 2,
    size.height - pad - 12,
    barW,
    7,
  );
  final rr = RRect.fromRectAndRadius(bar, const Radius.circular(4));
  canvas.drawRRect(rr, Paint()..color = Colors.black.withValues(alpha: 0.3));
  final fill = view.holdProgress.clamp(0.0, 1.0);
  final fillColor = view.focusBreak > 0
      ? Color.lerp(const Color(0xFFFFC44D), const Color(0xFFE2483C),
          view.focusBreak)!
      : Color.lerp(Colors.white70, const Color(0xFF9BE07A), fill)!;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(bar.left, bar.top, bar.width * fill, bar.height),
      const Radius.circular(4),
    ),
    Paint()..color = fillColor,
  );
  final sweetX = bar.left + bar.width * ArcheryDraw.sweetMeterFraction;
  canvas.drawLine(
    Offset(sweetX, bar.top - 4),
    Offset(sweetX, bar.bottom + 4),
    Paint()
      ..strokeWidth = 2
      ..color = Colors.white,
  );
}

void _text(
  Canvas canvas,
  String text,
  Offset at, {
  double size = 12,
  Color color = Colors.white,
  TextAlign align = TextAlign.left,
  FontWeight weight = FontWeight.w700,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: 0.4,
        shadows: const [
          Shadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
  )..layout();
  final dx = switch (align) {
    TextAlign.center => at.dx - tp.width / 2,
    TextAlign.right => at.dx - tp.width,
    _ => at.dx,
  };
  tp.paint(canvas, Offset(dx, at.dy));
}

/// The `CustomPainter` wrapper. Keeping [paintArcheryScene] a free function and
/// this a thin shell means a test can call the painter directly on a recorder.
class ArcheryScenePainter extends CustomPainter {
  final ArcheryView view;
  final ArcheryStyle style;
  final ColorScheme scheme;

  const ArcheryScenePainter({
    required this.view,
    required this.style,
    required this.scheme,
  });

  @override
  void paint(Canvas canvas, Size size) =>
      paintArcheryScene(canvas, size, view, style, scheme);

  @override
  bool shouldRepaint(ArcheryScenePainter old) => true;
}
