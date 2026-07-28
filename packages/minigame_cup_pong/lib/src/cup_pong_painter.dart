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
///
/// ## Lighting
///
/// There is exactly one light: [CupPongWorld.lamp], a warm pendant hanging over
/// the rack and off the top of the frame. Every shadow here is
/// [CupPongWorld.shadowOf] — a true projection of the object along the ray from
/// that lamp — and every bevel and highlight is oriented by the same vector.
/// Nothing in this file picks a shadow offset by eye.
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
  final ballColor = style.resolveBall(scheme);
  for (final cup in view.cups) {
    if (cup.removal >= 1) continue;
    scene.add(
      Vec3(cup.mouth.x, CupPongWorld.surfaceY, cup.mouth.z),
      (c, at) => _paintCup(c, camera, cup, cupColor, ballColor, style, at.depth),
    );
  }
  for (final b in view.restingBalls) {
    scene.add(b.position, (c, at) => _paintBall(c, b, ballColor, at, style));
  }
  if (ball != null) {
    scene.add(ball.position, (c, at) => _paintBall(c, ball, ballColor, at, style));
  }
  scene.paint(canvas);
  // Falloff last: the lamp is a bare pendant in a dim room, so the corners of
  // the frame are genuinely darker than the pool under it. Painted over the
  // scene rather than into each element so one gradient governs the whole
  // picture instead of ten opinions about it.
  _paintVignette(canvas, size, camera);
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

/// A stable pseudo-random in 0..1 for [i]. Deterministic on purpose: the grain
/// has to be identical between two renders of the same scene or the "nothing
/// marks the table" pixel test would fail on noise alone.
double _hash(int i) {
  final s = math.sin(i * 12.9898 + 78.233) * 43758.5453;
  return s - s.floorToDouble();
}

/// Screen position and pixels-per-metre of the lamp, or null when it falls
/// behind the camera. The lamp hangs above eye level so [Projected.screen] is
/// normally *above* the canvas — that is expected and is what makes the bloom
/// read as light spilling in from a fixture just out of shot.
Projected _lampAt(Camera3 camera) => camera.project(CupPongWorld.lamp);

/// The lamp's footprint on the table plane, in screen space.
Projected _lampPoolAt(Camera3 camera) => camera.project(
      Vec3(CupPongWorld.lamp.x, CupPongWorld.surfaceY, CupPongWorld.lamp.z),
    );

/// The dim bar the table stands in: a block wall, a strip of floor between the
/// wall and the far rail, and the pendant's bloom washing down over both.
///
/// Everything here is projected from world coordinates rather than laid out in
/// fractions of the canvas, so the wall's base lands correctly against the far
/// rail at any aspect ratio instead of drifting when the board is resized.
void _paintRoom(Canvas canvas, Size size, Camera3 camera, CupPongStyle style) {
  final rect = Offset.zero & size;
  final room = style.roomColor;
  // Base fill, so an extreme aspect ratio that pushes the wall quad off-canvas
  // still gets a room-coloured backdrop rather than black.
  canvas.drawRect(rect, Paint()..color = Color.lerp(room, Colors.black, 0.62)!);

  Offset? at(double x, double y, double z) {
    final pr = camera.project(Vec3(x, y, z));
    return pr.visible ? pr.screen : null;
  }

  Path? quad(List<Vec3> corners) {
    final path = Path();
    for (var i = 0; i < corners.length; i++) {
      final pr = camera.project(corners[i]);
      if (!pr.visible) return null;
      if (i == 0) {
        path.moveTo(pr.screen.dx, pr.screen.dy);
      } else {
        path.lineTo(pr.screen.dx, pr.screen.dy);
      }
    }
    return path..close();
  }

  const wz = CupPongWorld.wallZ;
  const fy = CupPongWorld.roomFloorY;
  const wide = 9.0;

  // --- Back wall ------------------------------------------------------------
  final wall = quad(const [
    Vec3(-wide, fy, wz),
    Vec3(wide, fy, wz),
    Vec3(wide, 2.6, wz),
    Vec3(-wide, 2.6, wz),
  ]);
  final wallBase = at(0, fy, wz);
  if (wall != null && wallBase != null) {
    final top = camera.horizonY - size.height * 0.4;
    canvas.save();
    canvas.clipPath(wall);
    canvas.drawPaint(
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width / 2, top),
          Offset(size.width / 2, wallBase.dy),
          [
            Color.lerp(room, Colors.black, 0.42)!,
            Color.lerp(room, const Color(0xFF6B4230), 0.30)!,
            Color.lerp(room, Colors.black, 0.34)!,
          ],
          const [0.0, 0.62, 1.0],
        ),
    );

    // Breeze-block courses. Horizontal world lines on a vertical plane project
    // to straight screen lines, so these are exact, and their convergence
    // toward the wall's own vanishing points is free depth.
    const course = 0.19;
    const block = 0.39;
    final mortar = Paint()
      ..strokeWidth = 1.0
      ..color = Colors.black.withValues(alpha: 0.42);
    final lip = Paint()
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.075);
    for (var c = 0; c < 14; c++) {
      final y = fy + c * course;
      if (y > 1.0) break;
      final a = at(-wide, y, wz), b = at(wide, y, wz);
      if (a == null || b == null) continue;
      canvas.drawLine(a, b, mortar);
      // The lamp is above, so the upward-facing edge of each course catches it.
      canvas.drawLine(a.translate(0, 1), b.translate(0, 1), lip);
      // Staggered head joints.
      for (var k = -7; k <= 7; k++) {
        final x = k * block + (c.isEven ? 0 : block / 2);
        final j0 = at(x, y, wz), j1 = at(x, y + course, wz);
        if (j0 == null || j1 == null) continue;
        canvas.drawLine(j0, j1, mortar);
      }
    }

    // Dado rail and the darker panelling under it — the thing that stops a wall
    // reading as an infinite grey field.
    final dado = quad(const [
      Vec3(-wide, fy, wz),
      Vec3(wide, fy, wz),
      Vec3(wide, -0.26, wz),
      Vec3(-wide, -0.26, wz),
    ]);
    if (dado != null) {
      canvas.drawPath(
        dado,
        Paint()..color = Colors.black.withValues(alpha: 0.20),
      );
    }
    final railA = at(-wide, -0.26, wz), railB = at(wide, -0.26, wz);
    if (railA != null && railB != null) {
      canvas.drawLine(
        railA,
        railB,
        Paint()
          ..strokeWidth = 2.0
          ..color = Color.lerp(room, const Color(0xFF6B4A2E), 0.34)!,
      );
      canvas.drawLine(
        railA.translate(0, -1.6),
        railB.translate(0, -1.6),
        Paint()
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.07),
      );
    }
    canvas.restore();

    final skirtA = at(-wide, fy + 0.10, wz), skirtB = at(wide, fy + 0.10, wz);
    if (skirtA != null && skirtB != null) {
      canvas.drawRect(
        Rect.fromLTRB(0, skirtA.dy, size.width, wallBase.dy),
        Paint()..color = Color.lerp(room, Colors.black, 0.10)!,
      );
      canvas.drawLine(
        skirtA,
        skirtB,
        Paint()
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.10),
      );
    }
  }

  // --- Floor between the wall and the table --------------------------------
  final floor = quad(const [
    Vec3(-wide, fy, 0.9),
    Vec3(wide, fy, 0.9),
    Vec3(wide, fy, wz),
    Vec3(-wide, fy, wz),
  ]);
  if (floor != null && wallBase != null) {
    canvas.save();
    canvas.clipPath(floor);
    canvas.drawPaint(
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width / 2, wallBase.dy),
          Offset(size.width / 2, wallBase.dy + size.height * 0.25),
          [
            Color.lerp(room, const Color(0xFF4A3527), 0.70)!,
            Color.lerp(room, Colors.black, 0.30)!,
          ],
        ),
    );
    canvas.restore();
    // The table's own shadow, thrown back onto the floor by the pendant. It is
    // what keeps the table from hovering over the strip.
    final s0 = at(-CupPongWorld.halfWidth * 1.5, fy, CupPongWorld.farZ + 0.35);
    final s1 = at(CupPongWorld.halfWidth * 1.5, fy, CupPongWorld.farZ + 0.35);
    if (s0 != null && s1 != null) {
      canvas.drawRect(
        Rect.fromLTRB(s0.dx, s0.dy - 12, s1.dx, s0.dy + 8),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.42)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 9),
      );
    }
  }

  // --- The pendant's bloom --------------------------------------------------
  // The fixture itself hangs above eye level and is therefore off the top of
  // the frame at every canvas size; what the player sees is its halo bleeding
  // down over the wall, anchored on the real projected lamp position.
  final lamp = _lampAt(camera);
  if (lamp.visible) {
    final reach = math.max(size.width, size.height) * 0.80;
    // The fixture projects well above the canvas, so its halo would arrive as a
    // uniform smear. Anchored at the top edge instead, on the lamp's real screen
    // x — the light still comes from the right place, it just stops pretending
    // the falloff starts a screen-height away.
    final origin = Offset(
      lamp.screen.dx,
      math.max(lamp.screen.dy, camera.horizonY - size.height * 0.14),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          origin,
          reach,
          [
            const Color(0xFFFFC98A).withValues(alpha: 0.42),
            const Color(0xFFB4660F).withValues(alpha: 0.14),
            const Color(0x00000000),
          ],
          const [0.0, 0.35, 1.0],
        ),
    );
  }
}

/// The table: real wood, lit by the one lamp.
///
/// Built in passes rather than as one gradient — base tone, plank seams with a
/// lit bevel, fine grain along the planks, the lamp's pool, the sheen it throws
/// back, then falloff toward the rails. Each pass is cheap; together they are
/// the difference between "a brown quadrilateral" and a surface.
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
  final pool = _lampPoolAt(camera);
  canvas.save();
  canvas.clipPath(surface);
  canvas.drawPaint(
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(size.width / 2, fl.dy),
        Offset(size.width / 2, size.height),
        [
          Color.lerp(felt, style.roomColor, 0.40)!,
          Color.lerp(felt, Colors.white, 0.05)!,
          Color.lerp(felt, Colors.black, 0.26)!,
        ],
        const [0.0, 0.34, 1.0],
      ),
  );

  // --- Grain, running down-range with the planks ----------------------------
  // Fine streaks at pseudo-random x, each a straight world line and therefore a
  // straight screen line converging on the vanishing point. Alternating light
  // and dark, none of them strong: wood is texture, not stripes.
  for (var i = 0; i < 54; i++) {
    final x = -hw + 2 * hw * _hash(i);
    final a = p(x, nz), b = p(x, fz);
    if (a == null || b == null) continue;
    final dark = _hash(i + 900) < 0.62;
    canvas.drawLine(
      a,
      b,
      Paint()
        ..strokeWidth = 0.6 + _hash(i + 300) * 1.5
        ..color = (dark ? Colors.black : Colors.white).withValues(
          alpha: (dark ? 0.030 : 0.022) + _hash(i + 600) * 0.022,
        ),
    );
  }

  // --- Plank seams ----------------------------------------------------------
  // The primary convergence cue. Each gets a dark groove plus a lit edge on the
  // side the lamp is on, so the boards read as separate pieces of timber with a
  // thickness rather than as pinstripes.
  final litSide = CupPongWorld.lamp.x < 0 ? -1.0 : 1.0;
  for (var i = 1; i < 6; i++) {
    final x = -hw + 2 * hw * i / 6;
    final a = p(x, nz), b = p(x, fz);
    if (a == null || b == null) continue;
    canvas.drawLine(
      a,
      b,
      Paint()
        ..strokeWidth = 1.4
        ..color = Colors.black.withValues(alpha: 0.30),
    );
    canvas.drawLine(
      a.translate(litSide * 1.3, 0),
      b.translate(litSide * 0.8, 0),
      Paint()
        ..strokeWidth = 1.0
        ..color = Colors.white.withValues(alpha: 0.075),
    );
  }

  // Cross-grain at constant z: even world spacing that bunches toward the far
  // edge — foreshortening you can literally count.
  for (var i = 1; i < 12; i++) {
    final z = nz + (fz - nz) * i / 12;
    final a = p(-hw, z), b = p(hw, z);
    if (a == null || b == null) continue;
    canvas.drawLine(
      a,
      b,
      Paint()
        ..strokeWidth = 1.0
        ..color = Colors.white.withValues(alpha: 0.035),
    );
  }

  if (pool.visible) {
    // --- The lamp's pool ----------------------------------------------------
    final reach = pool.scale * 0.80;
    canvas.drawPaint(
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          pool.screen,
          reach,
          [
            const Color(0xFFFFD7A0).withValues(alpha: 0.30),
            const Color(0xFFC8802E).withValues(alpha: 0.10),
            const Color(0x00000000),
          ],
          const [0.0, 0.45, 1.0],
        ),
    );
    // --- Sheen --------------------------------------------------------------
    // Varnish specular: a soft streak elongated along the grain, offset from
    // the pool toward the camera because that is where the reflected ray goes.
    canvas.save();
    canvas.translate(pool.screen.dx, pool.screen.dy + pool.scale * 0.10);
    canvas.scale(1.0, 0.42);
    canvas.drawCircle(
      Offset.zero,
      pool.scale * 0.34,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = const Color(0xFFFFE9C6).withValues(alpha: 0.075)
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          math.max(4.0, pool.scale * 0.10),
        ),
    );
    canvas.restore();
    // --- Falloff toward the rails ------------------------------------------
    canvas.drawPaint(
      Paint()
        ..shader = ui.Gradient.radial(
          pool.screen,
          pool.scale * 1.70,
          [
            const Color(0x00000000),
            Colors.black.withValues(alpha: 0.36),
          ],
          const [0.38, 1.0],
        ),
    );
  }
  canvas.restore();

  // Rails: a bright lip on the far edge seats the table against the room, and
  // the side rails are the lines the eye follows to the vanishing point.
  final rail = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..color = Color.lerp(felt, Colors.white, 0.34)!.withValues(alpha: 0.75);
  canvas.drawLine(nl, fl, rail..strokeWidth = 1.6);
  canvas.drawLine(nr, fr, rail);
  canvas.drawLine(
    fl,
    fr,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.square,
  );
  // The top arris of the far rail, catching the pendant.
  canvas.drawLine(
    fl.translate(0, -0.6),
    fr.translate(0, -0.6),
    rail..strokeWidth = 2.0,
  );
}

/// Corner falloff. Weak in the middle third so the ball, the rack and the score
/// pill are never the things it eats.
void _paintVignette(Canvas canvas, Size size, Camera3 camera) {
  final centre = Offset(size.width * 0.5, size.height * 0.46);
  final reach = math.sqrt(
        size.width * size.width + size.height * size.height,
      ) *
      0.62;
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = ui.Gradient.radial(
        centre,
        reach,
        [
          const Color(0x00000000),
          const Color(0x00000000),
          Colors.black.withValues(alpha: 0.32),
        ],
        const [0.0, 0.60, 1.0],
      ),
  );
}

// ---------------------------------------------------------------------------
// Shadow
// ---------------------------------------------------------------------------

/// The single most important cue for reading a throw: a blob on the table under
/// the ball. It is the **lamp's** projection of the ball — [CupPongWorld
/// .shadowOf] traces the ray from the pendant through the ball down to the
/// table plane — so it slides down-range with the ball, meets it exactly on
/// landing, and drifts away from directly-underneath as the ball leaves the
/// pool, which is the cue that the light is a fixture and not an ambient wash.
void _paintShadow(Canvas canvas, Camera3 camera, Vec3 ballPos, double radius) {
  final ground = CupPongWorld.shadowOf(ballPos);
  if (ground.z < CupPongWorld.nearZ - 0.4 || ground.z > CupPongWorld.farZ) {
    return;
  }
  if (ground.x.abs() > CupPongWorld.halfWidth) return;

  final h = math.max(0.0, ballPos.y - radius);
  final t = (h / 0.40).clamp(0.0, 1.0);
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

/// Horizontal light direction for a vertical cup wall: the unit vector a lit
/// face's outward normal points along.
///
/// **Derived, not chosen.** It is the normalised horizontal component of the
/// vector from the middle of the rack back to [CupPongWorld.lamp]'s footprint —
/// a wall facing the lamp is lit, a wall facing away is not. Move the lamp and
/// this moves with it, so the cups can never end up lit from a different place
/// than the shadows, the felt pool and the wall bloom.
final ({double x, double z}) _light = () {
  const rackMidZ = CupPongWorld.rackApexZ + 1.5 * CupPongWorld.rowDepth;
  final dx = CupPongWorld.lamp.x - 0.0;
  final dz = CupPongWorld.lamp.z - rackMidZ;
  final len = math.sqrt(dx * dx + dz * dz);
  return len < 1e-6 ? (x: 0.0, z: -1.0) : (x: dx / len, z: dz / len);
}();

/// Vertical profile of a Solo cup, base (0) → mouth (1), with the radius jog at
/// each step as a multiplier on the plain taper.
///
/// The two pairs of close-together heights are the moulded reinforcing rings —
/// the thing that makes a party cup instantly recognisable and that a plain
/// truncated cone does not have. The topmost pair is the rolled lip, which
/// bulges *outside* the mouth radius.
const List<({double t, double bulge})> _cupProfile = [
  (t: 1.000, bulge: 1.000), // mouth
  (t: 0.962, bulge: 1.052), // rolled lip, under-curl
  (t: 0.905, bulge: 0.995), // neck under the lip
  (t: 0.660, bulge: 1.000),
  (t: 0.618, bulge: 0.968), // upper reinforcing step
  (t: 0.392, bulge: 1.000),
  (t: 0.350, bulge: 0.966), // lower reinforcing step
  (t: 0.000, bulge: 1.000), // base
];

void _paintCup(
  Canvas canvas,
  Camera3 camera,
  CupView cup,
  Color base,
  Color ballColour,
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

  // Contact shadow, thrown by the one lamp rather than parked underneath: the
  // ellipse is the cup's silhouette projected from the pendant, so cups off to
  // the side cast away from it and the whole rack agrees about where the light
  // is. It also tightens with distance for free — the projected `scale` is what
  // sets the blur, so a far cup gets a small hard shadow and a near one a
  // broad soft pool, which is what stops the back row looking pasted on.
  final shadowCentre = CupPongWorld.shadowOf(Vec3(cx, mouthY * 0.45, cz));
  final shadowAt = camera.project(shadowCentre);
  final contact = camera.horizontalCirclePath(
    Vec3(shadowCentre.x, CupPongWorld.surfaceY + 0.001, shadowCentre.z),
    CupPongWorld.cupBaseRadius * 1.7 * shrink,
    segments: 16,
  );
  if (contact != null && shadowAt.visible) {
    canvas.drawPath(
      contact,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55 * alpha)
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          (shadowAt.scale * 0.0075).clamp(0.8, 5.0),
        ),
    );
  }

  final rings = <({List<Offset> screen, List<Vec3> world})>[];
  for (final band in _cupProfile) {
    final r = _ring(
      camera,
      cx,
      cz,
      baseY + (mouthY - baseY) * band.t,
      _cupRadiusAt(band.t) * band.bulge * shrink,
    );
    if (r == null) return;
    rings.add(r);
  }

  // Lateral surface as a strip of quads, painted far-segment-first so the near
  // wall correctly covers the far one. Per-segment shading gives the cylinder
  // its roundness for free.
  final order = List.generate(_cupSegments, (i) => i)
    ..sort((a, b) {
      final aw = rings.last.world[a];
      final bw = rings.last.world[b];
      return camera
          .toCameraSpace(bw)
          .z
          .compareTo(camera.toCameraSpace(aw).z);
    });

  // A lit saturated red is not a *whiter* red — lerping toward white is what
  // turned the whole rack salmon. The base colour IS the fully-lit wall; the
  // ramp runs downward from it into shadow, and the plastic's sheen is added
  // back as a tight specular rather than by bleaching the diffuse.
  final wallLit = Color.lerp(base, Colors.white, 0.06)!;
  final wallShadow = Color.lerp(base, const Color(0xFF1A0705), 0.72)!;
  // The rolled lip curls over, so it catches noticeably more of an overhead
  // lamp than the wall under it.
  final lipLit = Color.lerp(base, Colors.white, 0.26)!;
  final lipShadow = Color.lerp(base, const Color(0xFF1A0705), 0.52)!;
  for (var band = 0; band < rings.length - 1; band++) {
    final top = rings[band];
    final bottom = rings[band + 1];
    // Band 0 is the outside of the rolled lip; it curls over, so it catches the
    // light much harder than the wall below and is the brightest thing on the
    // cup at every angle.
    final isLip = band == 0;
    // The two step bands are recessed grooves — darkened rather than modelled,
    // which at these sizes is indistinguishable and a great deal cheaper.
    final isGroove = band == 3 || band == 5;
    for (final i in order) {
      final j = (i + 1) % _cupSegments;
      final a = 2 * math.pi * (i + 0.5) / _cupSegments;
      final nx = math.cos(a);
      final nz = math.sin(a);
      final lit = (0.5 + 0.5 * (nx * _light.x + nz * _light.z)).clamp(0.0, 1.0);
      // Vertical fluting: a party cup is a ribbed extrusion, not a smooth cone.
      // 12 ribs against 24 segments means each segment is one rib face, so the
      // modulation lands on the geometry instead of shimmering across it.
      final rib = 0.5 + 0.5 * math.cos(a * 12);
      var shade = (0.18 + 0.82 * lit) * (0.90 + 0.14 * rib);
      if (isGroove) shade *= 0.70;
      final s = shade.clamp(0.0, 1.0);
      var colour = isLip
          ? Color.lerp(lipShadow, lipLit, s)!
          : Color.lerp(wallShadow, wallLit, s)!;
      // Specular: polypropylene is glossy, and a tight warm hot-spot on the
      // lamp's side is what says "plastic" instead of "matte paint". Exponent
      // 7 keeps it to two or three segments, so it never becomes a wash.
      final spec = math.pow(lit, 7.0).toDouble() * (isLip ? 0.42 : 0.26);
      if (spec > 0.01) {
        colour = Color.lerp(colour, const Color(0xFFFFE0BE), spec)!;
      }
      final quad = Path()
        ..moveTo(top.screen[i].dx, top.screen[i].dy)
        ..lineTo(top.screen[j].dx, top.screen[j].dy)
        ..lineTo(bottom.screen[j].dx, bottom.screen[j].dy)
        ..lineTo(bottom.screen[i].dx, bottom.screen[i].dy)
        ..close();
      canvas.drawPath(
        quad,
        Paint()
          ..color = _hazed(colour, depth, fog, strength: 0.26)
              .withValues(alpha: alpha)
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
      ..color = _hazed(Color.lerp(base, Colors.black, 0.84)!, depth, fog)
          .withValues(alpha: alpha),
  );

  // Beer line, a little way down the inside.
  final liquidY = mouthY - cup.height * shrink * 0.22;
  final liquid = camera.horizontalCirclePath(
    Vec3(cx, liquidY, cz),
    _cupRadiusAt(0.70) * shrink,
    segments: _cupSegments,
  );
  // Clipped to the mouth for everything inside the cup: the near lip is in
  // front of the liquid surface (and of a ball falling past it), so an
  // unclipped disc spills over the rim and turns every cup into a donut.
  if (liquid != null) {
    canvas.save();
    canvas.clipPath(mouthPath);
    canvas.drawPath(
      liquid,
      Paint()
        ..color = _hazed(const Color(0xFFB07E28), depth, fog, strength: 0.3)
            .withValues(alpha: alpha * 0.95),
    );
    // A meniscus catching the pendant, so the beer is a surface and not a disc.
    canvas.drawPath(
      liquid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.7, 0.0035 * camera.focal / depth)
        ..color = const Color(0xFFF2C878).withValues(alpha: alpha * 0.30),
    );
    canvas.restore();
  }

  // The ball dropping in, drawn inside the cup and clipped to the mouth so the
  // near lip cuts across it as it sinks. This is the whole make animation: the
  // ball does not vanish over the rack, it goes *in*.
  if (cup.drop != null) {
    _paintCupDrop(
      canvas,
      camera,
      cup,
      mouthPath,
      mouthY: mouthY,
      liquidY: liquidY,
      shrink: shrink,
      ballColour: ballColour,
    );
  }

  // Rim: the top face of the rolled lip. Bright all the way round because it is
  // horizontal and the lamp is overhead, hotter on the lamp's side.
  final rimWidth = math.max(1.0, 0.0065 * camera.focal / depth);
  canvas.drawPath(
    mouthPath,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rimWidth
      ..color = _hazed(Color.lerp(base, Colors.white, 0.44)!, depth, fog,
              strength: 0.26)
          .withValues(alpha: alpha),
  );

  if (cup.splash > 0) {
    _paintSplash(
      canvas,
      camera,
      cup,
      mouthPath,
      liquidY: liquidY,
      shrink: shrink,
      alpha: alpha,
    );
  }
}

/// The made ball sinking below the rim.
///
/// Two beats, both driven by the same 0..1 the board ticks off a real clock:
/// the ball falls to the beer with a small ease-in (gravity, not a linear
/// slide), then bobs once and settles. It is clipped to [mouthPath] throughout,
/// so it is progressively eaten by the near lip on the way down — which is the
/// only cue that actually says "inside".
void _paintCupDrop(
  Canvas canvas,
  Camera3 camera,
  CupView cup,
  Path mouthPath, {
  required double mouthY,
  required double liquidY,
  required double shrink,
  required Color ballColour,
}) {
  final t = cup.drop!.clamp(0.0, 1.0);
  // Fall, then a single damped bob on the surface.
  final fall = t < 0.55 ? math.pow(t / 0.55, 1.7).toDouble() : 1.0;
  final bob = t < 0.55
      ? 0.0
      : math.sin((t - 0.55) / 0.45 * math.pi * 2.2) *
          (1 - (t - 0.55) / 0.45) *
          0.22;
  final restY = liquidY - CupPongWorld.ballRadius * 0.35;
  final y = mouthY + CupPongWorld.ballRadius * 0.9 -
      (mouthY + CupPongWorld.ballRadius * 0.9 - restY) * fall +
      bob * CupPongWorld.ballRadius;

  final at = camera.project(Vec3(cup.mouth.x, y, cup.mouth.z));
  if (!at.visible) return;
  final r = CupPongWorld.ballRadius * at.scale * shrink;
  if (r < 0.4) return;

  canvas.save();
  canvas.clipPath(mouthPath);
  // Inside a cup the ball is in shadow — the lamp is straight overhead and the
  // wall is between it and everything below the rim. Lighting it as brightly as
  // the one in the player's hand is what would make the drop read as a sticker.
  final shaded = Color.lerp(ballColour, const Color(0xFF3A2410), 0.30 + 0.24 * fall)!;
  canvas.drawCircle(
    at.screen,
    r,
    Paint()
      ..shader = ui.Gradient.radial(
        at.screen.translate(-r * 0.3, -r * 0.42),
        r * 1.4,
        [
          Color.lerp(shaded, Colors.white, 0.42)!,
          shaded,
          Color.lerp(shaded, Colors.black, 0.5)!,
        ],
        const [0.0, 0.5, 1.0],
      ),
  );
  _paintBallSeams(canvas, at.screen, r, cup.dropSpin, alpha: 0.20);
  canvas.restore();
}

/// Beer displaced by the ball: a ring spreading to the wall, a brightening of
/// the surface, and a few droplets thrown clear of the rim.
void _paintSplash(
  Canvas canvas,
  Camera3 camera,
  CupView cup,
  Path mouthPath, {
  required double liquidY,
  required double shrink,
  required double alpha,
}) {
  final s = cup.splash.clamp(0.0, 1.0);
  canvas.save();
  canvas.clipPath(mouthPath);
  for (final ring in const [0.0, 0.35]) {
    final rs = ((s - ring) / (1 - ring)).clamp(0.0, 1.0);
    if (rs <= 0) continue;
    final path = camera.horizontalCirclePath(
      Vec3(cup.mouth.x, liquidY + 0.004, cup.mouth.z),
      _cupRadiusAt(0.70) * shrink * (0.22 + 1.35 * rs),
      segments: _cupSegments,
    );
    if (path == null) continue;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 * (1 - rs) + 0.6
        ..color = Colors.white.withValues(alpha: (1 - rs) * 0.75 * alpha),
    );
  }
  canvas.restore();

  // Droplets clearing the rim. Deliberately outside the clip — this is the part
  // of a splash that leaves the cup.
  if (s < 0.7) {
    final up = (s / 0.7).clamp(0.0, 1.0);
    for (var i = 0; i < 6; i++) {
      final a = 2 * math.pi * (_hash(i + cup.id * 31) + i / 6);
      final spread = _cupRadiusAt(1.0) * (0.4 + 1.5 * up);
      final rise = 0.055 * math.sin(up * math.pi);
      final at = camera.project(Vec3(
        cup.mouth.x + math.cos(a) * spread,
        liquidY + rise,
        cup.mouth.z + math.sin(a) * spread,
      ));
      if (!at.visible) continue;
      canvas.drawCircle(
        at.screen,
        math.max(0.7, CupPongWorld.ballRadius * at.scale * 0.16),
        Paint()
          ..color = const Color(0xFFE9C68A)
              .withValues(alpha: (1 - up) * 0.8 * alpha),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Ball
// ---------------------------------------------------------------------------

/// The ping-pong ball's moulding seam, rolled by [spin].
///
/// Two great circles a quarter-turn apart, each drawn as an ellipse whose
/// squash is `cos` of its own phase — so as the ball turns, one seam narrows to
/// a line and flips while the other opens out. A single seam reads as a pulsing
/// hoop; the pair reads as a sphere rotating, which is what "spin from travel"
/// has to look like to be worth computing.
void _paintBallSeams(
  Canvas canvas,
  Offset c,
  double r,
  double spin, {
  double alpha = 0.17,
}) {
  if (r <= 2.5) return;
  canvas.save();
  canvas.translate(c.dx, c.dy);
  // Tilted axis: a ball thrown down-range spins about an axis across the frame,
  // not about the screen normal.
  canvas.rotate(0.55);
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.7, r * 0.09);
  for (final phase in const [0.0, math.pi / 2]) {
    final squash = math.cos(spin + phase);
    final open = squash.abs();
    // Fade the seam out as it goes edge-on. Held flat it collapses to a single
    // hard chord across the ball, which on a large in-hand ball reads as a
    // crack in the plastic rather than a moulding line.
    paint.color =
        Colors.black.withValues(alpha: alpha * (0.15 + 0.85 * open));
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: r * 1.86,
        height: r * 1.86 * open,
      ),
      paint,
    );
  }
  canvas.restore();
}

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

  // Form, not brightness. A white ball under a white key with a white
  // specular has nowhere left to go: every stop reads as paper. The core is
  // held well off pure white and the terminator is pulled inward and taken
  // much darker, so there is an actual light-to-shade run across the sphere.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = ui.Gradient.radial(
        c.translate(-r * 0.35, -r * 0.38),
        r * 1.35,
        [
          Color.lerp(lit, Colors.white, 0.40)!,
          Color.lerp(lit, const Color(0xFFAEB6C0), 0.13)!,
          Color.lerp(lit, const Color(0xFF2A2016), 0.62)!,
        ],
        const [0.0, 0.56, 1.0],
      ),
  );
  // Bounce off the felt: the lower-right limb picks the table's own warmth
  // back up. Without it the shaded side goes neutral grey and the ball reads
  // as lit by nothing in particular.
  canvas.drawArc(
    Rect.fromCircle(center: c, radius: r * 0.90),
    0.35,
    2.0,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, r * 0.16)
      ..color = const Color(0xFFC98A4B).withValues(alpha: 0.30)
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, r * 0.12),
  );
  _paintBallSeams(canvas, c, r, ball.spin);
  // Specular. A hard-edged disc reads as a sticker on a flat circle; the same
  // highlight with a falloff reads as gloss on a curved surface, and that
  // difference is most of what sells the in-hand ball as a ball.
  final hi = c.translate(-r * 0.32, -r * 0.36);
  canvas.drawCircle(
    hi,
    r * 0.22,
    Paint()
      ..shader = ui.Gradient.radial(
        hi,
        r * 0.34,
        [
          Colors.white.withValues(alpha: 0.92),
          Colors.white.withValues(alpha: 0.42),
          Colors.white.withValues(alpha: 0.0),
        ],
        const [0.0, 0.45, 1.0],
      ),
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
