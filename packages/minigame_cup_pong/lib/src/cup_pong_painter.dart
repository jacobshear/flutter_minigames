import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:minigames_3d/minigames_3d.dart';

import 'cup_pong_style.dart';
import 'cup_pong_world.dart';

/// Renders the first-person Cup Pong table.
///
/// A **pure function** of a [CupPongView] — no engine, no controllers, no
/// widget tree. That is deliberate: the board is a plain `CustomPaint`, so the
/// entire scene can be rendered headlessly to a PNG and inspected, which is how
/// the perspective was actually tuned.
///
/// Depth cues, in the order they matter:
/// 1. the table's rails converge toward [Camera3.horizonY];
/// 2. everything scales by [Projected.scale], so a thrown ball visibly shrinks;
/// 3. a projected shadow tracks the ball on the table, tightening and darkening
///    as it drops — this is what makes the arc readable;
/// 4. [Scene3] paints far-to-near so a near ball occludes a far cup;
/// 5. distance hazes everything toward the room colour.
void paintCupPongTable(
  Canvas canvas,
  Size size,
  CupPongView view,
  CupPongStyle style,
  ColorScheme scheme,
) {
  if (size.isEmpty) return;
  final camera = CupPongWorld.cameraFor(size);

  _paintRoom(canvas, size, camera, style);
  _paintTable(canvas, size, camera, style);

  // Shadows live on the table plane, under everything, so they are painted as
  // one pass before the depth-sorted props.
  for (final b in view.restingBalls) {
    _paintShadow(canvas, camera, b.position, b.radius);
  }
  final ball = view.ball;
  // A ball waiting in hand is 30 cm up and almost directly under the camera:
  // the patch of table beneath it is off the bottom of the canvas (the felt
  // only starts being visible around z = 0.06 at this pitch), so there is no
  // projected shadow to draw. It is grounded in `_paintBall` instead, with a
  // contact pool offset along the key light.
  if (ball != null && !ball.inHand) {
    _paintShadow(canvas, camera, ball.position, ball.radius);
  }

  final aim = view.aim;

  final scene = Scene3(camera);
  final cupColor = style.resolveCup(scheme);
  for (final cup in view.cups) {
    if (cup.removal >= 1) continue;
    scene.add(
      Vec3(cup.mouth.x, CupPongWorld.surfaceY, cup.mouth.z),
      (c, at) => _paintCup(c, camera, cup, cupColor, style, at.depth),
    );
  }
  for (final b in view.restingBalls) {
    scene.add(
      b.position,
      (c, at) => _paintBall(c, b, style.resolveBall(scheme), at, style),
    );
  }
  if (ball != null) {
    scene.add(
      ball.position,
      (c, at) => _paintBall(c, ball, style.resolveBall(scheme), at, style),
    );
  }
  scene.paint(canvas);
  // The swipe cue is screen-space and sits on top of everything — it belongs to
  // the finger, not to the scene. Nothing is ever painted onto the table or the
  // rack ahead of a throw.
  if (aim != null) _paintFlickCue(canvas, camera, aim);
}

// ---------------------------------------------------------------------------
// Depth helpers
// ---------------------------------------------------------------------------

/// Where haze starts and saturates, in camera-space depth.
const double _hazeNear = 0.7;
const double _hazeFar = 2.4;

double _hazeAt(double depth) =>
    ((depth - _hazeNear) / (_hazeFar - _hazeNear)).clamp(0.0, 1.0);

/// Fades [c] toward the room colour by distance — the cheapest atmospheric cue
/// there is, and the one that stops the far rack from looking pasted on.
Color _hazed(Color c, double depth, Color fog, {double strength = 0.42}) =>
    Color.lerp(c, fog, _hazeAt(depth) * strength)!;

// ---------------------------------------------------------------------------
// Room + table
// ---------------------------------------------------------------------------

void _paintRoom(Canvas canvas, Size size, Camera3 camera, CupPongStyle style) {
  final rect = Offset.zero & size;
  final room = style.roomColor;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        [
          Color.lerp(room, Colors.black, 0.45)!,
          room,
          Color.lerp(room, Colors.black, 0.35)!,
        ],
        const [0.0, 0.42, 1.0],
      ),
  );
  // A soft pool of light hanging over the far end, centred on the horizon.
  final horizon = camera.horizonY;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width / 2, horizon + size.height * 0.20),
        size.width * 0.85,
        [
          Color.lerp(room, Colors.white, 0.16)!,
          room.withValues(alpha: 0),
        ],
      ),
  );
}

void _paintTable(Canvas canvas, Size size, Camera3 camera, CupPongStyle style) {
  const hw = CupPongWorld.halfWidth;
  const nz = CupPongWorld.nearZ;
  const fz = CupPongWorld.farZ;
  const y = CupPongWorld.surfaceY;

  Offset? p(double x, double z) {
    final pr = camera.project(Vec3(x, y, z));
    return pr.visible ? pr.screen : null;
  }

  final nl = p(-hw, nz), nr = p(hw, nz), fl = p(-hw, fz), fr = p(hw, fz);
  if (nl == null || nr == null || fl == null || fr == null) return;

  final surface = Path()
    ..moveTo(nl.dx, nl.dy)
    ..lineTo(nr.dx, nr.dy)
    ..lineTo(fr.dx, fr.dy)
    ..lineTo(fl.dx, fl.dy)
    ..close();

  final felt = style.resolveTable();
  canvas.save();
  canvas.clipPath(surface);
  canvas.drawPaint(
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(size.width / 2, fl.dy),
        Offset(size.width / 2, size.height),
        [
          Color.lerp(felt, style.roomColor, 0.45)!,
          felt,
          Color.lerp(felt, Colors.white, 0.10)!,
        ],
        const [0.0, 0.45, 1.0],
      ),
  );

  // Plank seams at constant x. These are the primary convergence cue: parallel
  // world lines meeting at the vanishing point on camera.horizonY.
  final seam = Paint()
    ..color = Colors.black.withValues(alpha: 0.16)
    ..strokeWidth = 1.2;
  for (var i = 1; i < 6; i++) {
    final x = -hw + 2 * hw * i / 6;
    final a = p(x, nz), b = p(x, fz);
    if (a == null || b == null) continue;
    canvas.drawLine(a, b, seam);
  }
  // Cross-grain lines at constant z. Even world spacing, but they bunch toward
  // the far edge — foreshortening you can literally count.
  final grain = Paint()
    ..color = Colors.white.withValues(alpha: 0.05)
    ..strokeWidth = 1.0;
  for (var i = 1; i < 12; i++) {
    final z = nz + (fz - nz) * i / 12;
    final a = p(-hw, z), b = p(hw, z);
    if (a == null || b == null) continue;
    canvas.drawLine(a, b, grain);
  }
  canvas.restore();

  // Rails: a bright lip on the far edge seats the table against the room, and
  // the side rails are the lines the eye follows to the vanishing point.
  final rail = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..color = Color.lerp(felt, Colors.white, 0.34)!.withValues(alpha: 0.75);
  canvas.drawLine(fl, fr, rail);
  canvas.drawLine(nl, fl, rail..strokeWidth = 1.6);
  canvas.drawLine(nr, fr, rail);
  canvas.drawLine(
    fl,
    fr,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.square,
  );
  canvas.drawLine(fl, fr, rail..strokeWidth = 1.8);
}

// ---------------------------------------------------------------------------
// Shadow
// ---------------------------------------------------------------------------

/// The single most important cue for reading a throw: a blob on the table
/// directly under the ball. It is projected, not faked — `project(x, 0, z)` —
/// so it slides down-range with the ball and meets it exactly on landing.
void _paintShadow(Canvas canvas, Camera3 camera, Vec3 ballPos, double radius) {
  if (ballPos.z < CupPongWorld.nearZ - 0.4 || ballPos.z > CupPongWorld.farZ) {
    return;
  }
  if (ballPos.x.abs() > CupPongWorld.halfWidth) return;

  final h = math.max(0.0, ballPos.y - radius);
  final t = (h / 0.40).clamp(0.0, 1.0);
  final ground = Vec3(ballPos.x, CupPongWorld.surfaceY, ballPos.z);
  final path = camera.horizontalCirclePath(
    ground,
    radius * (1 + 1.35 * t),
    segments: 18,
  );
  if (path == null) return;
  final at = camera.project(ground);
  if (!at.visible) return;
  // Kept dark and only moderately soft even at the top of the arc: a shadow
  // that fades to nothing is a shadow the player can no longer read the throw
  // from, which defeats the point of having one.
  canvas.drawPath(
    path,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.58 * (1 - 0.42 * t))
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 0.6 + 3.4 * t),
  );
}

// ---------------------------------------------------------------------------
// Cups
// ---------------------------------------------------------------------------

const int _cupSegments = 24;

/// Radius of a tapered cup at height fraction [t] (0 = base, 1 = mouth).
double _cupRadiusAt(double t) =>
    CupPongWorld.cupBaseRadius +
    (CupPongWorld.cupMouthRadius - CupPongWorld.cupBaseRadius) * t;

/// Projected points of a horizontal ring, plus each point's world position.
({List<Offset> screen, List<Vec3> world})? _ring(
  Camera3 camera,
  double cx,
  double cz,
  double y,
  double radius,
) {
  final screen = <Offset>[];
  final world = <Vec3>[];
  for (var i = 0; i < _cupSegments; i++) {
    final a = 2 * math.pi * i / _cupSegments;
    final w = Vec3(cx + math.cos(a) * radius, y, cz + math.sin(a) * radius);
    final pr = camera.project(w);
    if (!pr.visible) return null;
    screen.add(pr.screen);
    world.add(w);
  }
  return (screen: screen, world: world);
}

/// Light direction in the horizontal plane — up and to the left, toward the
/// viewer. Only its x/z matter for shading a vertical cup wall.
const double _lightX = -0.55;
const double _lightZ = -0.84;

void _paintCup(
  Canvas canvas,
  Camera3 camera,
  CupView cup,
  Color base,
  CupPongStyle style,
  double depth,
) {
  final removal = cup.removal.clamp(0.0, 1.0);
  final alpha = (1 - removal).clamp(0.0, 1.0);
  if (alpha <= 0.01) return;

  // A sunk cup shrinks into the table and fades — reads as "removed" without
  // needing a physics body to knock it over.
  final shrink = 1 - 0.35 * removal;
  final drop = -removal * cup.height * 0.55;
  final cx = cup.mouth.x;
  final cz = cup.mouth.z;
  final baseY = CupPongWorld.surfaceY + drop;
  final mouthY = baseY + cup.height * shrink;
  final fog = style.roomColor;

  final contact = camera.horizontalCirclePath(
    Vec3(cx, CupPongWorld.surfaceY + 0.001, cz),
    CupPongWorld.cupBaseRadius * 1.55 * shrink,
    segments: 16,
  );
  if (contact != null) {
    canvas.drawPath(
      contact,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.34 * alpha)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
    );
  }

  final rings = <({List<Offset> screen, List<Vec3> world})>[];
  const bandTop = 1.0;
  const bandLow = 0.74;
  const heights = [bandTop, bandLow, 0.0];
  for (final t in heights) {
    final r = _ring(
      camera,
      cx,
      cz,
      baseY + (mouthY - baseY) * t,
      _cupRadiusAt(t) * shrink,
    );
    if (r == null) return;
    rings.add(r);
  }

  // Lateral surface as a strip of quads, painted far-segment-first so the near
  // wall correctly covers the far one. Per-segment shading gives the cylinder
  // its roundness for free.
  final order = List.generate(_cupSegments, (i) => i)
    ..sort((a, b) {
      final aw = rings[2].world[a];
      final bw = rings[2].world[b];
      return camera
          .toCameraSpace(bw)
          .z
          .compareTo(camera.toCameraSpace(aw).z);
    });

  for (final band in [0, 1]) {
    final top = rings[band];
    final bottom = rings[band + 1];
    final isLip = band == 0;
    for (final i in order) {
      final j = (i + 1) % _cupSegments;
      final a = 2 * math.pi * (i + 0.5) / _cupSegments;
      final lit =
          (0.5 + 0.5 * (math.cos(a) * _lightX + math.sin(a) * _lightZ))
              .clamp(0.0, 1.0);
      final shade = 0.20 + 0.80 * lit;
      final colour = isLip
          ? Color.lerp(const Color(0xFF7C7871), Colors.white, shade)!
          : Color.lerp(
              Color.lerp(base, Colors.black, 0.70)!,
              Color.lerp(base, Colors.white, 0.12)!,
              shade,
            )!;
      final quad = Path()
        ..moveTo(top.screen[i].dx, top.screen[i].dy)
        ..lineTo(top.screen[j].dx, top.screen[j].dy)
        ..lineTo(bottom.screen[j].dx, bottom.screen[j].dy)
        ..lineTo(bottom.screen[i].dx, bottom.screen[i].dy)
        ..close();
      canvas.drawPath(
        quad,
        Paint()
          ..color = _hazed(colour, depth, fog).withValues(alpha: alpha)
          ..isAntiAlias = false,
      );
    }
  }

  // The mouth. A horizontal circle projects to a conic whose aspect changes
  // with depth (open near, squashed far) — horizontalCirclePath computes that
  // instead of guessing a constant squash, and the variation across the rack is
  // exactly what sells the depth.
  final mouthCentre = Vec3(cx, mouthY, cz);
  final mouthPath = camera.horizontalCirclePath(
    mouthCentre,
    CupPongWorld.cupMouthRadius * shrink,
    segments: _cupSegments,
  );
  if (mouthPath == null) return;

  canvas.drawPath(
    mouthPath,
    Paint()
      ..color = _hazed(Color.lerp(base, Colors.black, 0.80)!, depth, fog)
          .withValues(alpha: alpha),
  );

  // Beer line, a little way down the inside.
  final liquidY = mouthY - cup.height * shrink * 0.30;
  final liquid = camera.horizontalCirclePath(
    Vec3(cx, liquidY, cz),
    _cupRadiusAt(0.70) * shrink,
    segments: _cupSegments,
  );
  if (liquid != null) {
    // Clipped to the mouth: the near lip is in front of the liquid surface, so
    // an unclipped disc spills over the rim and turns every cup into a donut.
    canvas.save();
    canvas.clipPath(mouthPath);
    canvas.drawPath(
      liquid,
      Paint()
        ..color = _hazed(const Color(0xFF9A6A22), depth, fog)
            .withValues(alpha: alpha * 0.95),
    );
    canvas.restore();
  }

  // Rim: a bright ring, plus a hotter near-side highlight.
  final rimWidth = math.max(1.0, 0.0055 * camera.focal / depth);
  canvas.drawPath(
    mouthPath,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rimWidth
      ..color = _hazed(Color.lerp(base, Colors.white, 0.52)!, depth, fog)
          .withValues(alpha: alpha),
  );

  if (cup.splash > 0) {
    final s = cup.splash.clamp(0.0, 1.0);
    final ring = camera.horizontalCirclePath(
      Vec3(cx, liquidY + 0.01, cz),
      _cupRadiusAt(0.70) * (0.35 + 1.5 * s),
      segments: _cupSegments,
    );
    if (ring != null) {
      canvas.drawPath(
        ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - s) + 0.5
          ..color = Colors.white.withValues(alpha: (1 - s) * 0.85),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Ball
// ---------------------------------------------------------------------------

void _paintBall(
  Canvas canvas,
  BallView ball,
  Color colour,
  Projected at,
  CupPongStyle style,
) {
  final r =
      ball.radius * at.scale * (ball.inHand ? CupPongWorld.heldDrawScale : 1.0);
  if (r < 0.4) return;
  final c = at.screen;
  final fog = style.roomColor;
  final lit = _hazed(colour, at.depth, fog, strength: 0.3);

  if (ball.inHand) {
    // Contact pool, offset down-and-right along the key light (-x, -z, up).
    // The held ball's true cast shadow is off-canvas, so this stands in for it:
    // without a dark edge somewhere the ball's lower hemisphere dissolves into
    // the felt and it reads as a flat sticker.
    canvas.drawCircle(
      c.translate(r * 0.16, r * 0.20),
      r * 1.10,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.34)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
    );
  }

  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = ui.Gradient.radial(
        c.translate(-r * 0.35, -r * 0.38),
        r * 1.35,
        [
          Color.lerp(lit, Colors.white, 0.7)!,
          lit,
          Color.lerp(lit, Colors.black, 0.42)!,
        ],
        const [0.0, 0.5, 1.0],
      ),
  );
  // Seam — an ellipse whose squash tracks the spin, so the ball visibly rolls.
  if (r > 2.5) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(0.55);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: r * 1.72,
        height: r * 1.72 * math.cos(ball.spin).abs(),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.7, r * 0.10)
        ..color = Colors.black.withValues(alpha: 0.16),
    );
    canvas.restore();
  }
  canvas.drawCircle(
    c.translate(-r * 0.3, -r * 0.34),
    r * 0.26,
    Paint()..color = Colors.white.withValues(alpha: 0.75),
  );

  if (ball.inHand) {
    // Rim light along the shaded edge. Cheap, and it is what separates a
    // sphere sitting in a room from a flat white disc.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.94),
      -0.5,
      2.2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, r * 0.08)
        ..color = Colors.white.withValues(alpha: 0.22),
    );
  }
}

// ---------------------------------------------------------------------------
// Swipe overlay
//
// Nothing here is drawn on the table, on the rack, or anywhere down-range —
// only on and immediately around the ball. A ring parked on a cup mouth is a
// cursor; so is a predicted arc that runs down the table and stops at one. Both
// tell the player they are steering a marker when what they are doing is
// flicking a ball, and both were removed. What is left is a readout of the
// gesture itself: a power ring wrapped around the ball and a short arrow in the
// swipe direction, neither of which reaches past the foreground.
// ---------------------------------------------------------------------------

/// Where the ball waiting in hand lands on the canvas — the anchor every swipe
/// cue is drawn from.
({Offset centre, double radius})? _heldBallOnScreen(Camera3 camera) {
  final at = camera.project(CupPongWorld.launchPoint);
  if (!at.visible) return null;
  return (
    centre: at.screen,
    radius: CupPongWorld.ballRadius * at.scale * CupPongWorld.heldDrawScale,
  );
}

/// Warm accent at full power, so "wound all the way up" is a colour, not just
/// a length the player has to estimate.
Color _powerColour(double power) =>
    Color.lerp(Colors.white, const Color(0xFFF4B740), power)!;

void _paintFlickCue(Canvas canvas, Camera3 camera, AimView aim) {
  final held = _heldBallOnScreen(camera);
  if (held == null) return;
  final c = held.centre;
  final r = held.radius;
  final power = aim.power.clamp(0.0, 1.0);
  final len = aim.flick.distance;
  if (len < 1e-3) return;
  final dir = Offset(aim.flick.dx / len, aim.flick.dy / len);
  final tint = _powerColour(power);

  // --- Power ring around the ball ------------------------------------------
  final track = Rect.fromCircle(center: c, radius: r * 1.75);
  canvas.drawArc(
    track,
    0,
    2 * math.pi,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: 0.16),
  );
  canvas.drawArc(
    track,
    -math.pi / 2,
    2 * math.pi * power,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.4
      ..color = tint.withValues(alpha: 0.55 + 0.45 * power),
  );

  // --- Throw trail ----------------------------------------------------------
  // Anchored on the ball and pointing the way the swipe is going, because the
  // finger itself may have started anywhere on the board — a line drawn to the
  // touch point would float free of the thing being thrown.
  //
  // Kept deliberately short, and shortened again when the predicted arc was
  // removed rather than grown to fill the gap. Scaled to the ball rather than
  // to the canvas, the whole cue stays inside ~2.7 ball radii: a stroke long
  // enough to land near a cup is a pointer, and a pointer is the reticle again.
  // At full power straight up the tip still clears the apex cup by ~30 px.
  final start = c + dir * (r * 1.45);
  final reach = r * (0.25 + 0.65 * power);
  const steps = 14;
  for (var i = 0; i < steps; i++) {
    final a = start + dir * (reach * i / steps);
    final b = start + dir * (reach * (i + 1) / steps);
    final f = i / steps;
    canvas.drawLine(
      a,
      b,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.4 - 1.6 * f
        ..color = tint.withValues(alpha: (0.70 - 0.34 * f).clamp(0.0, 1.0)),
    );
  }
  // Arrowhead.
  final tip = start + dir * (reach + r * 0.30);
  final normal = Offset(-dir.dy, dir.dx);
  final wing = math.max(3.5, r * 0.28);
  final head = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(
      tip.dx - dir.dx * wing * 1.8 + normal.dx * wing,
      tip.dy - dir.dy * wing * 1.8 + normal.dy * wing,
    )
    ..lineTo(
      tip.dx - dir.dx * wing * 1.8 - normal.dx * wing,
      tip.dy - dir.dy * wing * 1.8 - normal.dy * wing,
    )
    ..close();
  canvas.drawPath(head, Paint()..color = tint.withValues(alpha: 0.85));
}
