import 'dart:math' as math;

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
  final double targetWobble;

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
    this.arrowsLeft = ArcheryGame.arrowsPerTarget,
    this.accent = const Color(0xFFD8443C),
  });

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
}) {
  final path = Path();
  for (var i = 0; i < segments; i++) {
    final a = 2 * math.pi * i / segments;
    final p = camera.project(
      Vec3(centre.x + math.cos(a) * radius, centre.y + math.sin(a) * radius,
          centre.z),
    );
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

  // A couple of soft clouds, parked (the camera never travels).
  final cloud = Paint()..color = Colors.white.withValues(alpha: 0.55);
  for (var i = 0; i < 4; i++) {
    final cx = (_hash01(i, 11) * 1.6 - 0.3) * size.width;
    final cy = horizon - size.height * (0.18 + _hash01(i, 12) * 0.42);
    final w = size.width * (0.16 + _hash01(i, 13) * 0.2);
    final h = w * 0.26;
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
        cloud);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx + w * 0.18, cy - h * 0.35),
          width: w * 0.6,
          height: h * 0.95),
      cloud,
    );
  }

  // Hazy treeline sitting on the horizon.
  final tree = Path()..moveTo(-size.width, horizon + 1);
  const steps = 96;
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final x = -size.width + t * size.width * 3;
    final n = math.sin(t * 21) * 0.4 +
        math.sin(t * 7.3 + 1.2) * 0.4 +
        math.sin(t * 47 + 0.4) * 0.2;
    tree.lineTo(x, horizon - size.height * 0.012 * (1.2 + n));
  }
  tree
    ..lineTo(size.width * 2, horizon + 1)
    ..close();
  canvas.drawPath(
    tree,
    Paint()
      ..color = Color.lerp(
        style.resolveGrassFar(scheme),
        style.resolveHaze(scheme),
        0.55,
      )!,
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

  // Grass tufts. Each is a real world position, so it shrinks with depth —
  // the densest depth cue in the frame. Sampled with a square bias toward the
  // camera so the near ground is not a bare gradient.
  final lean = view.conditions.crossComponent * 0.02;
  final tuftPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 260; i++) {
    final u = _hash01(i, 5);
    final z = 1.2 + u * u * (far - 1.2);
    final side = _hash01(i, 3) < 0.5 ? -1 : 1;
    // A third of the tufts grow inside the lane, close to the archer.
    final inLane = _hash01(i, 7) < 0.34;
    final x = side * (inLane ? 0.5 + _hash01(i, 4) * 1.7 : 2.5 + _hash01(i, 4) * 11);
    final base = camera.project(Vec3(x, 0, z));
    if (!base.visible) continue;
    final h = (inLane ? 0.05 + _hash01(i, 6) * 0.06 : 0.16 + _hash01(i, 6) * 0.16) *
        base.scale;
    if (h < 0.7) continue;
    final sway = math.sin(view.time * 1.6 + i) * 0.12 + lean;
    tuftPaint
      ..color = _hazed(
        Color.lerp(style.resolveGrassNear(scheme), Colors.black, 0.18)!
            .withValues(alpha: 0.55),
        base.depth,
        style.resolveHaze(scheme),
      )
      ..strokeWidth = math.max(0.8, base.scale * 0.012);
    for (var k = -1; k <= 1; k++) {
      canvas.drawLine(
        base.screen,
        base.screen + Offset((k * 0.35 + sway) * h, -h),
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

  for (var i = 0; i < view.stuckArrows.length; i++) {
    final shot = view.stuckArrows[i];
    if (!shot.onFace) continue;
    scene.add(
      Vec3(shot.offsetX, ArcheryBallistics.targetCentreHeight + shot.offsetY,
          d - 0.35),
      (c, at) => _paintStuckArrow(c, camera, view, shot, style, scheme),
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

  // Ground shadow — an honest projected circle, so it flattens correctly.
  final shadow = camera.horizontalCirclePath(Vec3(0, 0.02, d + 0.25), 1.05);
  if (shadow != null) {
    canvas.drawPath(
      shadow,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
  }

  final wobble = view.targetWobble;
  canvas.save();
  if (wobble > 0) {
    final amp = wobble * 3.2;
    canvas.translate(math.sin(view.time * 34) * amp, math.sin(view.time * 41) * amp * 0.5);
  }

  // Tripod legs.
  final legPaint = Paint()
    ..color = _hazed(const Color(0xFF6B4B2E), depth, haze)
    ..strokeCap = StrokeCap.round;
  for (final side in [-1.0, 1.0]) {
    final foot = camera.project(Vec3(side * 0.78, 0, d + 0.55));
    final top = camera.project(Vec3(side * 0.34, 0.85, d + 0.16));
    if (!foot.visible || !top.visible) continue;
    legPaint.strokeWidth = math.max(1.2, foot.scale * 0.05);
    canvas.drawLine(foot.screen, top.screen, legPaint);
  }

  // Straw butt behind the face.
  final butt = _quadPath(camera, [
    Vec3(-0.88, 0.34, d + 0.12),
    Vec3(0.88, 0.34, d + 0.12),
    Vec3(0.88, 2.24, d + 0.12),
    Vec3(-0.88, 2.24, d + 0.12),
  ]);
  if (butt != null) {
    canvas.drawPath(
      butt,
      Paint()..color = _hazed(style.resolveButt(scheme), depth, haze),
    );
    canvas.drawPath(
      butt,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _hazed(const Color(0xFF8B6C3A), depth, haze),
    );
    // Straw striations.
    for (var y = 0.46; y < 2.24; y += 0.15) {
      final a = camera.project(Vec3(-0.86, y, d + 0.12));
      final b = camera.project(Vec3(0.86, y, d + 0.12));
      if (!a.visible || !b.visible) continue;
      canvas.drawLine(
        a.screen,
        b.screen,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.07)
          ..strokeWidth = math.max(0.6, a.scale * 0.01),
      );
    }
  }

  // The face: five equal rings, every one a truly projected circle.
  final centre = Vec3(0, ArcheryBallistics.targetCentreHeight, d);
  for (var i = ArcheryStyle.ringColors.length - 1; i >= 0; i--) {
    final radius = ArcheryGame.ringWidth * (i + 1);
    final path = verticalCirclePath(camera, centre, radius);
    if (path == null) continue;
    canvas.drawPath(
      path,
      Paint()..color = _hazed(ArcheryStyle.ringColors[i], depth, haze, strength: 0.55),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.7, camera.project(centre).scale * 0.006)
        ..color = ArcheryStyle.ringLine,
    );
  }
  // Inner ten-ring mark.
  final inner = verticalCirclePath(camera, centre, ArcheryGame.ringWidth * 0.42);
  if (inner != null) {
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, camera.project(centre).scale * 0.005)
        ..color = Colors.black.withValues(alpha: 0.35),
    );
  }
  canvas.restore();
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
) {
  final d = view.conditions.distance;
  final head = Vec3(
    shot.offsetX,
    ArcheryBallistics.targetCentreHeight + shot.offsetY,
    d,
  );
  // Back along the line it came in on.
  final incoming =
      (head - ArcheryBallistics.bowOrigin).normalized;
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
              .withValues(alpha: 0.16 * (i / flight.trail.length))
          ..strokeWidth = math.max(1.4, a.scale * 0.03)
          ..strokeCap = StrokeCap.round,
      );
    }
  }
  final head = flight.position;
  final tail = head - flight.direction * 0.95;
  _paintShaft(canvas, camera, head, tail, view.accent, style, scheme,
      thickness: 0.03, minWidth: 3, outline: true);
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
  final axis = h.screen - t.screen;
  final len = axis.distance;
  final dir = len < 1e-3 ? const Offset(0, -1) : axis / len;
  final normal = Offset(-dir.dy, dir.dx);
  // Clamped: an arrow a few metres from the eye is genuinely large, but past
  // a point it stops reading as an arrow and starts covering the target.
  final vane = math.min(
    outline ? 26.0 : 16.0,
    math.max(2.6, t.scale * (outline ? 0.06 : 0.055)),
  );
  final vanePaint = Paint()
    ..color = _hazed(accent, t.depth, haze, strength: 0.45);
  for (final s in [-1.0, 1.0]) {
    final path = Path()
      ..moveTo(t.screen.dx, t.screen.dy)
      ..lineTo(
        t.screen.dx + normal.dx * vane * s + dir.dx * vane * 0.2,
        t.screen.dy + normal.dy * vane * s + dir.dy * vane * 0.2,
      )
      ..lineTo(
        t.screen.dx + dir.dx * vane * 1.5,
        t.screen.dy + dir.dy * vane * 1.5,
      )
      ..close();
    canvas.drawPath(path, vanePaint);
  }
  canvas.drawCircle(
    t.screen,
    width * 0.55,
    Paint()..color = Colors.black.withValues(alpha: 0.45),
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

  final limb = Path()
    ..moveTo(gripX - w * 0.075, limbTopY - h * 0.028)
    ..quadraticBezierTo(
        gripX - w * 0.045, limbTopY - h * 0.02, gripX - w * 0.02, limbTopY)
    ..quadraticBezierTo(gripX - w * 0.11, h * 0.55, gripX, gripY)
    ..quadraticBezierTo(gripX + w * 0.09, h * 1.02, gripX + w * 0.01, h * 1.16);
  canvas.drawPath(
    limb,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.022
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF3B2A1C),
  );
  canvas.drawPath(
    limb,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.008
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.12),
  );

  // Riser + bow hand.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(gripX, gripY), width: w * 0.045, height: h * 0.13),
      Radius.circular(w * 0.018),
    ),
    Paint()..color = const Color(0xFF2C1E13),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(gripX + w * 0.026, gripY + h * 0.008),
          width: w * 0.075,
          height: h * 0.062),
      Radius.circular(w * 0.026),
    ),
    Paint()..color = const Color(0xFFD9A277),
  );

  // The nock travels toward the viewer as the string is drawn: on screen that
  // reads as the nock sliding down-right and the fletching swelling.
  final nockRest = Offset(gripX + w * 0.05, gripY - h * 0.03);
  final nockFull = Offset(gripX + w * 0.22, gripY + h * 0.055);
  final nock = Offset.lerp(nockRest, nockFull, draw)! + Offset(shake, 0);

  // String: from limb tips through the nock.
  final tipTop = Offset(gripX - w * 0.02, limbTopY);
  final tipBottom = Offset(gripX + w * 0.01, h * 1.15);
  final string = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.1, w * 0.0035)
    ..color = Colors.white.withValues(alpha: 0.55);
  canvas.drawLine(tipTop, nock, string);
  canvas.drawLine(nock, tipBottom, string);

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
