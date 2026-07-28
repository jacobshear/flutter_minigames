import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_minigames/src/engine3d/engine3d.dart';

import 'mini_golf_camera.dart';
import 'mini_golf_course.dart';
import 'mini_golf_style.dart';
import 'mini_golf_view.dart';
import 'mini_golf_world.dart';

/// Renders a mini-golf hole in perspective.
///
/// A **pure function** of a [MiniGolfView] — no engine, no controllers, no
/// widget tree. That is deliberate: the board is a plain `CustomPaint`, so any
/// frame of any hole can be rendered headlessly to a PNG and inspected, which is
/// how the camera and the hole shapes were actually tuned. (The old Flame
/// `GameWidget` could not do this at all.)
///
/// Depth cues, in the order they matter:
/// 1. mow stripes and rails are parallel world lines converging on
///    [Camera3.horizonY];
/// 2. the rails are boxes with real thickness and a lit top face, not strokes;
/// 3. the cup is a true projected conic ([Camera3.horizontalCirclePath]) and the
///    flagstick shortens with depth;
/// 4. everything scales by [Projected.scale], so the ball visibly shrinks as it
///    rolls away, and a soft contact shadow keeps it pinned to the green;
/// 5. [Scene3] paints far-to-near, so a near rail occludes a ball behind it;
/// 6. distance hazes everything toward the rough colour.
void paintMiniGolfScene(
  Canvas canvas,
  Size size,
  MiniGolfView view,
  MiniGolfStyle style,
  ColorScheme scheme,
) {
  if (size.isEmpty) return;
  final course = view.course;
  final ball = view.ball;
  // The board owns the damped rig; a still without one gets a settled aim
  // framing so a one-off render needs no camera plumbing.
  final rig = view.rig ??
      MiniGolfCamera.settledOnTarget(
        viewport: size,
        course: course,
        ball: Offset(ball.position.x, ball.position.z),
      );
  final camera = rig.toCamera(size);

  final rough = style.resolveRough(scheme);
  final felt = style.resolveGreen(scheme);

  _paintSkyAndRough(canvas, size, camera, course, style, scheme);

  final green = _projectPolygon(camera, [
    for (final p in course.outline) MiniGolfWorld.at(p),
  ]);
  // A ball whose centre has gone below the green is *inside the cup*, so it is
  // drawn through the mouth (clipped by it, with the lip painted back over the
  // top) rather than as a prop floating above the hole.
  final sunk = ball.holed || ball.inCup;
  if (green != null) {
    _paintGreen(canvas, size, camera, course, green, felt, rough);
    // Ground decals live under everything and are clipped to the felt.
    canvas.save();
    canvas.clipPath(green);
    _paintCupMouth(
      canvas,
      camera,
      course,
      rough,
      style,
      scheme,
      ball: sunk ? ball : null,
    );
    if (!sunk) _paintBallShadow(canvas, camera, ball);
    for (final hit in view.impacts) {
      _paintScuff(canvas, camera, hit, felt);
    }
    final aim = view.aim;
    if (aim != null) _paintAim(canvas, camera, ball, aim, style, scheme);
    canvas.restore();
  }

  // --- depth-sorted props ---------------------------------------------------
  final scene = Scene3(camera);
  _addRails(scene, camera, course, style, scheme, rough, view.impacts);
  _addObstacles(scene, camera, course, style, scheme, rough);
  _addFlag(scene, camera, course, style, scheme, rough);
  if (!sunk) {
    scene.add(
      ball.position,
      (c, at) => _paintBall(c, ball, at, camera, style, scheme, rough),
    );
  }
  scene.paint(canvas);
}

// ---------------------------------------------------------------------------
// Depth helpers
// ---------------------------------------------------------------------------

const double _hazeNear = 6.0;
const double _hazeFar = 26.0;

double _hazeAt(double depth) =>
    ((depth - _hazeNear) / (_hazeFar - _hazeNear)).clamp(0.0, 1.0);

/// Fades [c] toward the surrounding rough by distance — the cheapest
/// atmospheric cue there is, and what stops the far end of a long hole from
/// looking pasted on.
Color _hazed(Color c, double depth, Color fog, {double strength = 0.45}) =>
    Color.lerp(c, fog, _hazeAt(depth) * strength)!;

/// Clips a world polygon against the camera's near plane, then projects it.
///
/// Load-bearing on a long hole: once the camera has followed the ball a few
/// units down-range the tee end of the green is *behind* the eye, and
/// projecting those vertices unclipped folds the whole green inside out.
/// Camera-space z is affine in world coordinates, so the crossing point is an
/// exact linear interpolation.
List<Vec3> _clipNear(Camera3 camera, List<Vec3> poly) {
  const eps = 0.08;
  final out = <Vec3>[];
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    final da = camera.toCameraSpace(a).z - eps;
    final db = camera.toCameraSpace(b).z - eps;
    if (da >= 0) out.add(a);
    if ((da >= 0) != (db >= 0)) {
      final t = da / (da - db);
      out.add(a + (b - a) * t);
    }
  }
  return out;
}

/// A world polygon as a screen [Path], or null when nothing survives clipping.
Path? _projectPolygon(Camera3 camera, List<Vec3> poly) {
  final clipped = _clipNear(camera, poly);
  if (clipped.length < 3) return null;
  final path = Path();
  for (var i = 0; i < clipped.length; i++) {
    final p = camera.project(clipped[i]);
    if (!p.visible) return null;
    if (i == 0) {
      path.moveTo(p.screen.dx, p.screen.dy);
    } else {
      path.lineTo(p.screen.dx, p.screen.dy);
    }
  }
  return path..close();
}

// ---------------------------------------------------------------------------
// Sky + rough
// ---------------------------------------------------------------------------

void _paintSkyAndRough(
  Canvas canvas,
  Size size,
  Camera3 camera,
  MiniGolfCourse course,
  MiniGolfStyle style,
  ColorScheme scheme,
) {
  final rect = Offset.zero & size;
  final rough = style.resolveRough(scheme);
  final sky = style.resolveSky(scheme);
  final horizon = camera.horizonY.clamp(0.0, size.height);

  // Sky above the horizon, rough below it. The horizon line is where the ground
  // plane converges — putting the real one there is what makes the ground read
  // as a plane rather than a backdrop.
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, math.max(1.0, horizon)),
        [Color.lerp(sky, Colors.black, 0.34)!, sky],
      ),
  );
  if (horizon < size.height) {
    canvas.drawRect(
      Rect.fromLTRB(0, horizon, size.width, size.height),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width / 2, horizon),
          Offset(size.width / 2, size.height),
          [
            Color.lerp(rough, sky, 0.42)!,
            rough,
            Color.lerp(rough, Colors.black, 0.32)!,
          ],
          const [0.0, 0.30, 1.0],
        ),
    );
  }

  // Constant-z bands on the ground plane. A horizontal world line projects to a
  // horizontal screen line, and even world spacing bunches toward the horizon —
  // foreshortening you can count.
  //
  // They alternate light and dark rather than only darkening: a mower leaves
  // stripes, and one direction of nap catches the light while the other does
  // not. At a single 5% black the far rough was a flat wash you could not read
  // depth off at all, which is most of why the top of the frame looked like
  // dead space rather than ground going away from you.
  //
  // The contrast fades out with distance. Near the horizon the bands compress
  // to a couple of pixels each, and at full strength that stops being stripes
  // and starts being moiré.
  final bandLitBase = Color.lerp(rough, Colors.white, 0.10)!;
  for (var i = 1; i <= 24; i++) {
    final z = camera.eye.z + 1.0 + 0.30 * i * i;
    final a = camera.project(Vec3(0, 0, z));
    final b = camera.project(Vec3(0, 0, z + 0.30 * i));
    if (!a.visible || !b.visible) continue;
    if (a.screen.dy <= horizon) break;
    final falloff = (1 - i / 18).clamp(0.15, 1.0);
    canvas.drawRect(
      Rect.fromLTRB(0, math.max(horizon, b.screen.dy), size.width, a.screen.dy),
      Paint()
        ..color = i.isEven
            ? bandLitBase.withValues(alpha: 0.16 * falloff)
            : Colors.black.withValues(alpha: 0.075 * falloff),
    );
  }

  // Scrubby patches of longer grass, scattered on the ground plane and drawn as
  // projected conics. Without them the rough is a vertical gradient, and a
  // vertical gradient behind a receding green reads as a painted backdrop
  // rather than ground the hole is sitting on. Positions are hashed off the
  // hole's seed, so they are stable frame to frame.
  final dark = Color.lerp(rough, Colors.black, 0.22)!;
  final pale = Color.lerp(rough, style.resolveGreen(scheme), 0.30)!;
  for (var i = 0; i < 54; i++) {
    final u = _hash(course.seed, i * 3 + 1);
    final v = _hash(course.seed, i * 3 + 2);
    final w = _hash(course.seed, i * 3 + 3);
    // Biased toward the far field: v*v alone stacked most of the patches near
    // the camera, leaving the deep rough — the part that fills the top of the
    // frame — bare.
    final z = camera.eye.z + 2.5 + 46 * math.pow(v, 1.4).toDouble();
    final x = camera.eye.x + (u - 0.5) * (10 + 2.2 * z.abs());
    final patch = camera.horizontalCirclePath(
      Vec3(x, 0, z),
      0.7 + 2.4 * w,
      segments: 12,
    );
    if (patch == null) continue;
    canvas.drawPath(
      patch,
      Paint()
        ..color = (w < 0.5 ? dark : pale).withValues(alpha: 0.42)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
    );
  }

  // Sun on the turf. One warm off-centre wash over the ground plane, so the
  // rough is lit from somewhere rather than being an even field of colour —
  // and the corners fall away, which stops the frame reading as a flat card.
  if (horizon < size.height) {
    canvas.drawRect(
      Rect.fromLTRB(0, horizon, size.width, size.height),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.26, horizon + size.height * 0.10),
          size.width * 1.25,
          [
            Color.lerp(rough, const Color(0xFFFFF3C4), 0.30)!
                .withValues(alpha: 0.30),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.22),
          ],
          const [0.0, 0.55, 1.0],
        ),
    );
  }

  // A fringe of half-cut grass hugging the green. The rough used to be a plain
  // vertical gradient, which reads as a painted backdrop the hole is pasted
  // onto; a band of intermediate green following the *actual outline* is what
  // seats it in the ground, and it costs one polygon.
  final fringe = _projectPolygon(camera, [
    for (final p in _outwardOffset(course.outline, 0.95)) MiniGolfWorld.at(p),
  ]);
  if (fringe != null) {
    canvas.drawPath(
      fringe,
      Paint()..color = Color.lerp(rough, style.resolveGreen(scheme), 0.44)!,
    );
    canvas.drawPath(
      fringe,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.black.withValues(alpha: 0.16)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
    );
  }

  // Tufts of longer grass standing up out of that fringe. Blurred colour
  // patches stay flat however many you draw — a few blades with real height are
  // what say the rough is *deeper* than the green, which is the whole reason to
  // stay out of it. Anchored to the outline, so they land where the rough is
  // actually on screen instead of somewhere off the bottom of the frame.
  final blade = Color.lerp(rough, Colors.black, 0.34)!;
  final n = course.outline.length;
  for (var i = 0; i < 90; i++) {
    final t = i / 90 * n;
    final a = course.outline[t.floor() % n];
    final b = course.outline[(t.floor() + 1) % n];
    final along = a + (b - a) * (t - t.floorToDouble());
    final edge = b - a;
    if (edge.distance < 1e-6) continue;
    final outward = Offset(edge.dy, -edge.dx) / edge.distance;
    final jitter = _hash(course.seed, 900 + i * 5);
    final spread = _hash(course.seed, 901 + i * 5);
    final tall = _hash(course.seed, 902 + i * 5);
    final lean = _hash(course.seed, 903 + i * 5) - 0.5;
    final at = along +
        outward * (0.30 + 1.35 * spread) +
        (edge / edge.distance) * (jitter - 0.5) * 0.8;
    final h = 0.11 + 0.22 * tall;
    final root = camera.project(MiniGolfWorld.at(at));
    final tip = camera.project(
      Vec3(at.dx + lean * h * 0.7, h, at.dy + lean * h * 0.3),
    );
    if (!root.visible || !tip.visible) continue;
    if (root.screen.dy <= horizon) continue;
    canvas.drawLine(
      root.screen,
      tip.screen,
      Paint()
        ..strokeWidth = math.max(0.7, 0.022 * root.scale)
        ..strokeCap = StrokeCap.round
        ..color = (tall < 0.45 ? pale : blade).withValues(alpha: 0.6),
    );
  }
}

/// The outline pushed [by] world units outward, using averaged edge normals.
///
/// Good enough for a soft fringe: a mitre that overshoots slightly on a sharp
/// concave corner is invisible under a blurred band, and it keeps the fringe
/// following the hole's real shape rather than a scaled bounding box (which on
/// a dogleg would sit half on the green and half in the next county).
List<Offset> _outwardOffset(List<Offset> outline, double by) {
  final n = outline.length;
  final out = <Offset>[];
  for (var i = 0; i < n; i++) {
    final prev = outline[(i - 1 + n) % n];
    final here = outline[i];
    final next = outline[(i + 1) % n];
    Offset normal(Offset a, Offset b) {
      final d = b - a;
      final len = d.distance;
      return len < 1e-9 ? Offset.zero : Offset(d.dy, -d.dx) / len;
    }

    var sum = normal(prev, here) + normal(here, next);
    final len = sum.distance;
    sum = len < 1e-9 ? Offset.zero : sum / len;
    out.add(here + sum * by);
  }
  return out;
}

/// Stable 0..1 hash, so scenery doesn't crawl between frames.
double _hash(int seed, int salt) {
  var x = (seed + 1) * 0x9E3779B97F4A7C15 + salt * 0xD1B54A32D192ED03;
  x &= 0x7fffffffffffffff;
  x = (x ^ (x >> 29)) * 0xBF58476D1CE4E5B9;
  x &= 0x7fffffffffffffff;
  x = x ^ (x >> 31);
  x &= 0x7fffffffffffffff;
  return (x % 100000) / 100000.0;
}

// ---------------------------------------------------------------------------
// Green
// ---------------------------------------------------------------------------

void _paintGreen(
  Canvas canvas,
  Size size,
  Camera3 camera,
  MiniGolfCourse course,
  Path green,
  Color felt,
  Color rough,
) {
  // A soft drop under the green so it sits *on* the rough rather than in it.
  canvas.drawPath(
    green,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.34)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 7),
  );

  canvas.save();
  canvas.clipPath(green);
  final b = course.bounds;
  final far = camera.project(Vec3(0, 0, b.maxZ));
  final farY = far.visible ? far.screen.dy : 0.0;
  canvas.drawPaint(
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(size.width / 2, farY),
        Offset(size.width / 2, size.height),
        [
          Color.lerp(felt, rough, 0.42)!,
          felt,
          Color.lerp(felt, Colors.white, 0.10)!,
        ],
        const [0.0, 0.5, 1.0],
      ),
  );

  // Mow stripes: alternating bands between constant-x world lines, which
  // converge on the vanishing point. The strongest single cue in the scene.
  //
  // Cut grass, not stripes of flat colour: a mower lays the blades toward you
  // on one pass and away on the next, so a light band is *warmer and paler* and
  // a dark band is cooler and deeper — and the boundary between them catches a
  // thin roller line. Painting them as two tints instead of one white overlay
  // is what stops the green reading as a striped carpet.
  final span = b.maxX - b.minX;
  final stripes = (span / 0.85).round().clamp(4, 16);
  final toward =
      Color.lerp(felt, const Color(0xFFE8F5C8), 0.16)!.withValues(alpha: 0.42);
  final away =
      Color.lerp(felt, const Color(0xFF0E3A1E), 0.22)!.withValues(alpha: 0.34);
  for (var i = 0; i < stripes; i++) {
    final x0 = b.minX + span * i / stripes;
    final x1 = b.minX + span * (i + 1) / stripes;
    final quad = _projectPolygon(camera, [
      Vec3(x0, 0, b.minZ - 0.4),
      Vec3(x1, 0, b.minZ - 0.4),
      Vec3(x1, 0, b.maxZ + 0.4),
      Vec3(x0, 0, b.maxZ + 0.4),
    ]);
    if (quad == null) continue;
    canvas.drawPath(quad, Paint()..color = i.isEven ? toward : away);
    // The roller line where the two passes meet.
    final a = camera.project(Vec3(x0, 0, b.minZ - 0.4));
    final c = camera.project(Vec3(x0, 0, b.maxZ + 0.4));
    if (a.visible && c.visible) {
      canvas.drawLine(
        a.screen,
        c.screen,
        Paint()
          ..strokeWidth = 1.0
          ..color = Colors.white.withValues(alpha: i.isEven ? 0.045 : 0.015),
      );
    }
  }

  // Cross-grain at constant z: even world spacing that visibly bunches away.
  final grain = Paint()
    ..color = Colors.black.withValues(alpha: 0.055)
    ..strokeWidth = 1.0;
  final steps = ((b.maxZ - b.minZ) / 1.1).round().clamp(3, 24);
  for (var i = 1; i < steps; i++) {
    final z = b.minZ + (b.maxZ - b.minZ) * i / steps;
    final l = camera.project(Vec3(b.minX - 0.5, 0, z));
    final r = camera.project(Vec3(b.maxX + 0.5, 0, z));
    if (!l.visible || !r.visible) continue;
    canvas.drawLine(l.screen, r.screen, grain);
  }

  // The rails throw a soft shadow onto the green, which is what stops the
  // fairway looking like a decal laid between two floating kerbs.
  canvas.drawPath(
    green,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..color = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 7),
  );
  canvas.restore();
}

// ---------------------------------------------------------------------------
// Cup + flag
// ---------------------------------------------------------------------------

/// The cup: a real hole with a liner, a floor and walls — and, when [ball] is
/// given, the ball itself drawn *inside* it.
///
/// The occlusion is the whole point. A ball drawn as a prop over the hole reads
/// as sitting on a black sticker; a ball clipped to the mouth, with the near lip
/// painted back over the top of it, reads as having gone *in*. Everything the
/// drop does — shrinking with depth, being swallowed by the rim — happens here.
void _paintCupMouth(
  Canvas canvas,
  Camera3 camera,
  MiniGolfCourse course,
  Color rough,
  MiniGolfStyle style,
  ColorScheme scheme, {
  MiniGolfBallView? ball,
}) {
  const r = MiniGolfCourse.cupRadius;
  final centre = MiniGolfWorld.at(course.cup);
  final depth = camera.toCameraSpace(centre).z;

  // A ring of shorter, paler grass around the hole, the way a cup is cut.
  final collar = camera.horizontalCirclePath(
    Vec3(centre.x, 0.004, centre.z),
    r * 1.42,
    segments: 24,
  );
  if (collar != null) {
    canvas.drawPath(
      collar,
      Paint()
        ..color = _hazed(const Color(0xFFDDE7CF), depth, rough)
            .withValues(alpha: 0.42),
    );
  }

  final mouth = camera.horizontalCirclePath(centre, r, segments: 28);
  if (mouth == null) return;
  final floor = camera.horizontalCirclePath(
    Vec3(centre.x, -MiniGolfWorld.cupDepth, centre.z),
    r * 0.96,
    segments: 28,
  );

  canvas.save();
  canvas.clipPath(mouth);

  // Wall: dark at the mouth on the near side, catching a little light on the
  // far side where the sky reaches into the hole.
  canvas.drawPath(
    mouth,
    Paint()
      ..shader = ui.Gradient.linear(
        camera.project(Vec3(centre.x, 0, centre.z + r)).screen,
        camera.project(Vec3(centre.x, 0, centre.z - r)).screen,
        const [Color(0xFF3B3227), Color(0xFF120E09), Color(0xFF070704)],
        const [0.0, 0.55, 1.0],
      ),
  );
  // The white plastic liner, visible as a sliver on the far wall.
  final liner = camera.horizontalCirclePath(
    Vec3(centre.x, -0.035, centre.z),
    r * 0.99,
    segments: 28,
  );
  if (liner != null) {
    canvas.drawPath(
      liner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = const Color(0xFFD8D2C4).withValues(alpha: 0.30),
    );
  }
  if (floor != null) {
    canvas.drawPath(floor, Paint()..color = const Color(0xFF16130E));
  }

  // The ball, down the hole, under the lip.
  if (ball != null) {
    final at = camera.project(ball.position);
    if (at.visible) {
      _paintBall(canvas, ball, at, camera, style, scheme, rough,
          veil: _cupVeil(ball.position.y), shadow: false);
    }
  }
  canvas.restore();

  // The lip goes back on top: a hard shadowed edge with the cut turf above it.
  canvas.drawPath(
    mouth,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = Colors.black.withValues(alpha: 0.55),
  );
  canvas.drawPath(
    mouth,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.12),
  );
}

/// How much the cup swallows a ball at height [y]: none at the lip, almost
/// total on the floor.
double _cupVeil(double y) {
  final t = (-y / MiniGolfWorld.cupDepth).clamp(0.0, 1.0);
  return 0.80 * t;
}

/// A scuff of compressed paint/turf where the ball banked, fading with age.
void _paintScuff(
  Canvas canvas,
  Camera3 camera,
  MiniGolfImpactView hit,
  Color felt,
) {
  final fade = (1 - hit.age).clamp(0.0, 1.0);
  if (fade <= 0.01 || hit.strength <= 0.05) return;
  final n = hit.normal;
  final perp = Offset(-n.dy, n.dx);
  final half = MiniGolfCourse.ballRadius * (0.9 + 2.2 * hit.strength);
  final reach = MiniGolfCourse.ballRadius * (0.7 + 1.4 * hit.strength);
  final poly = _projectPolygon(camera, [
    MiniGolfWorld.at(hit.at + perp * half, 0.006),
    MiniGolfWorld.at(hit.at + n * reach + perp * half * 0.5, 0.006),
    MiniGolfWorld.at(hit.at + n * reach - perp * half * 0.5, 0.006),
    MiniGolfWorld.at(hit.at - perp * half, 0.006),
  ]);
  if (poly == null) return;
  canvas.drawPath(
    poly,
    Paint()
      ..color = Color.lerp(felt, Colors.white, 0.45)!
          .withValues(alpha: 0.30 * fade * (0.4 + 0.6 * hit.strength))
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2),
  );
}

void _addFlag(
  Scene3 scene,
  Camera3 camera,
  MiniGolfCourse course,
  MiniGolfStyle style,
  ColorScheme scheme,
  Color rough,
) {
  final base = MiniGolfWorld.at(course.cup);
  final top = Vec3(base.x, MiniGolfWorld.flagHeight, base.z);
  scene.add(Vec3(base.x, MiniGolfWorld.flagHeight * 0.5, base.z), (canvas, at) {
    final b = camera.project(base);
    final t = camera.project(top);
    if (!b.visible || !t.visible) return;
    // The pole thins with depth exactly as its length shortens — a fixed stroke
    // width is the usual giveaway that a "3-D" scene is drawn in 2-D.
    final w = math.max(1.0, 0.030 * t.scale);

    // Shadow on the green, thrown away from the light (up-range and left).
    final shadowTip = camera.project(
      Vec3(base.x + MiniGolfWorld.flagHeight * 0.42, 0.004,
          base.z + MiniGolfWorld.flagHeight * 0.30),
    );
    if (shadowTip.visible) {
      canvas.drawLine(
        b.screen,
        shadowTip.screen,
        Paint()
          ..strokeWidth = math.max(1.0, w * 0.9)
          ..color = Colors.black.withValues(alpha: 0.22)
          ..strokeCap = StrokeCap.round
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 1.6),
      );
    }

    // The stick: a fibreglass pole with the black sighting bands a real pin
    // carries, and a lit edge down one side so it reads as a cylinder.
    final pole = _hazed(const Color(0xFFE9EDF0), at.depth, rough);
    canvas.drawLine(
      b.screen,
      t.screen,
      Paint()
        ..color = pole
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      b.screen.translate(-w * 0.26, 0),
      t.screen.translate(-w * 0.26, 0),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = w * 0.34,
    );
    for (final f in const [0.30, 0.52]) {
      final a = Offset.lerp(b.screen, t.screen, f)!;
      final c = Offset.lerp(b.screen, t.screen, f + 0.05)!;
      canvas.drawLine(
        a,
        c,
        Paint()
          ..color = _hazed(const Color(0xFF23282C), at.depth, rough)
          ..strokeWidth = w,
      );
    }
    // A ferrule where the pin meets the turf.
    canvas.drawLine(
      b.screen,
      Offset.lerp(b.screen, t.screen, 0.06)!,
      Paint()
        ..color = _hazed(const Color(0xFF9AA3A8), at.depth, rough)
        ..strokeWidth = w * 1.5,
    );

    // The pennant, with a fold: two panels at slightly different tints so the
    // cloth has a shape rather than being a flat triangle.
    final flagW = 0.52 * t.scale;
    final flagH = 0.30 * t.scale;
    final flag = _hazed(style.resolveFlag(scheme), at.depth, rough);
    final tip = Offset(t.screen.dx - flagW, t.screen.dy + flagH * 0.42);
    final fold = Offset(t.screen.dx - flagW * 0.52, t.screen.dy + flagH * 0.30);
    canvas.drawPath(
      Path()
        ..moveTo(t.screen.dx, t.screen.dy)
        ..lineTo(fold.dx, fold.dy)
        ..lineTo(t.screen.dx, t.screen.dy + flagH)
        ..close(),
      Paint()..color = flag,
    );
    canvas.drawPath(
      Path()
        ..moveTo(fold.dx, fold.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(t.screen.dx, t.screen.dy + flagH)
        ..close(),
      Paint()..color = Color.lerp(flag, Colors.black, 0.22)!,
    );
    canvas.drawPath(
      Path()
        ..moveTo(t.screen.dx, t.screen.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(t.screen.dx, t.screen.dy + flagH)
        ..close(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.black.withValues(alpha: 0.25),
    );
  });
}

// ---------------------------------------------------------------------------
// Rails
// ---------------------------------------------------------------------------

/// Boundary rails as real boxes: an inner face, a lit top face and an outer
/// face, each culled by whether it points at the eye.
///
/// Long edges are chopped into short segments so the painter's algorithm can
/// sort *pieces* of a rail around the ball — a single quad spanning near to far
/// would land entirely on one side of it.
void _addRails(
  Scene3 scene,
  Camera3 camera,
  MiniGolfCourse course,
  MiniGolfStyle style,
  ColorScheme scheme,
  Color rough,
  List<MiniGolfImpactView> impacts,
) {
  const h = MiniGolfCourse.railHeight;
  const t = MiniGolfCourse.railThickness;
  final wall = style.resolveWall(scheme);
  final n = course.outline.length;

  for (var i = 0; i < n; i++) {
    final a = course.outline[i];
    final b = course.outline[(i + 1) % n];
    final d = b - a;
    final len = d.distance;
    if (len < 1e-6) continue;
    // Outline is wound CCW, so this is the outward normal.
    final outward = Offset(d.dy, -d.dx) / len;
    final pieces = (len / 1.3).ceil().clamp(1, 24);

    for (var s = 0; s < pieces; s++) {
      final p0 = a + d * (s / pieces);
      final p1 = a + d * ((s + 1) / pieces);
      final q0 = p0 + outward * t;
      final q1 = p1 + outward * t;
      final anchor = Vec3(
        (p0.dx + p1.dx) / 2 + outward.dx * t / 2,
        h / 2,
        (p0.dy + p1.dy) / 2 + outward.dy * t / 2,
      );

      scene.add(anchor, (canvas, at) {
        final faces = <({List<Vec3> poly, Color colour, Vec3 normal})>[
          // Inner face (looks into the green).
          (
            poly: [
              Vec3(p0.dx, 0, p0.dy),
              Vec3(p1.dx, 0, p1.dy),
              Vec3(p1.dx, h, p1.dy),
              Vec3(p0.dx, h, p0.dy),
            ],
            colour: Color.lerp(wall, Colors.black, 0.30)!,
            normal: Vec3(-outward.dx, 0, -outward.dy),
          ),
          // Outer face.
          (
            poly: [
              Vec3(q0.dx, 0, q0.dy),
              Vec3(q1.dx, 0, q1.dy),
              Vec3(q1.dx, h, q1.dy),
              Vec3(q0.dx, h, q0.dy),
            ],
            colour: Color.lerp(wall, Colors.black, 0.46)!,
            normal: Vec3(outward.dx, 0, outward.dy),
          ),
          // Top face — the bright cap that gives the rail its thickness.
          (
            poly: [
              Vec3(p0.dx, h, p0.dy),
              Vec3(p1.dx, h, p1.dy),
              Vec3(q1.dx, h, q1.dy),
              Vec3(q0.dx, h, q0.dy),
            ],
            colour: Color.lerp(wall, Colors.white, 0.20)!,
            normal: const Vec3(0, 1, 0),
          ),
        ];
        for (final f in faces) {
          var centre = Vec3.zero;
          for (final p in f.poly) {
            centre = centre + p;
          }
          centre = centre * (1 / f.poly.length);
          if (f.normal.dot(camera.eye - centre) <= 0) continue; // back-facing
          final path = _projectPolygon(camera, f.poly);
          if (path == null) continue;
          canvas.drawPath(
              path, Paint()..color = _hazed(f.colour, at.depth, rough));
        }
        // Timber grain along the top cap — a plain flat band reads as plastic.
        final grainA = camera.project(Vec3(
            p0.dx + outward.dx * t * 0.35, h, p0.dy + outward.dy * t * 0.35));
        final grainB = camera.project(Vec3(
            p1.dx + outward.dx * t * 0.35, h, p1.dy + outward.dy * t * 0.35));
        if (grainA.visible && grainB.visible) {
          canvas.drawLine(
            grainA.screen,
            grainB.screen,
            Paint()
              ..strokeWidth = math.max(0.6, 0.012 * at.scale)
              ..color = Colors.black.withValues(alpha: 0.10),
          );
        }
        // Compression where a ball banked off this stretch of rail: a bright
        // smear on the inner face, right where it hit, sized by how hard.
        for (final hit in impacts) {
          final fade = (1 - hit.age).clamp(0.0, 1.0);
          if (fade <= 0.01 || hit.strength <= 0.05) continue;
          final along = (hit.at - p0);
          final unit = d / len;
          final proj = along.dx * unit.dx + along.dy * unit.dy;
          final seg = len / pieces;
          if (proj < -0.15 || proj > seg + 0.15) continue;
          if ((hit.at - (p0 + unit * proj)).distance > 0.25) continue;
          final half = 0.16 + 0.34 * hit.strength;
          final lo = p0 + unit * (proj - half);
          final hi = p0 + unit * (proj + half);
          final smear = _projectPolygon(camera, [
            Vec3(lo.dx, 0, lo.dy),
            Vec3(hi.dx, 0, hi.dy),
            Vec3(hi.dx, h * 0.72, hi.dy),
            Vec3(lo.dx, h * 0.72, lo.dy),
          ]);
          if (smear == null) continue;
          canvas.drawPath(
            smear,
            Paint()
              ..color = Colors.white
                  .withValues(alpha: 0.26 * fade * (0.35 + 0.65 * hit.strength))
              ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2.5),
          );
        }
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Obstacles
// ---------------------------------------------------------------------------

void _addObstacles(
  Scene3 scene,
  Camera3 camera,
  MiniGolfCourse course,
  MiniGolfStyle style,
  ColorScheme scheme,
  Color rough,
) {
  for (final o in course.obstacles) {
    final anchor = Vec3(o.centerX, o.height / 2, o.centerZ);
    scene.add(anchor, (canvas, at) {
      _paintContactShadow(canvas, camera, o);
      if (o.round) {
        _paintPost(canvas, camera, o, style, scheme, rough, at.depth);
      } else {
        _paintBlock(canvas, camera, o, style, scheme, rough, at.depth);
      }
    });
  }
}

void _paintContactShadow(Canvas canvas, Camera3 camera, MiniGolfObstacle o) {
  final path = camera.horizontalCirclePath(
    Vec3(o.centerX, 0.006, o.centerZ),
    math.max(o.halfWidth, o.halfDepth) * 1.12,
    segments: 16,
  );
  if (path == null) return;
  canvas.drawPath(
    path,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.24)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
  );
}

void _paintBlock(
  Canvas canvas,
  Camera3 camera,
  MiniGolfObstacle o,
  MiniGolfStyle style,
  ColorScheme scheme,
  Color rough,
  double depth,
) {
  final base = style.resolveObstacle(scheme);
  final h = o.height;
  final corners = <Offset>[
    Offset(o.left, o.near),
    Offset(o.right, o.near),
    Offset(o.right, o.far),
    Offset(o.left, o.far),
  ];
  final normals = <Vec3>[
    const Vec3(0, 0, -1),
    const Vec3(1, 0, 0),
    const Vec3(0, 0, 1),
    const Vec3(-1, 0, 0),
  ];
  // Sides, far ones first so a near face covers the one behind it.
  final order = List.generate(4, (i) => i)
    ..sort((x, y) {
      final cx = corners[x] + corners[(x + 1) % 4];
      final cy = corners[y] + corners[(y + 1) % 4];
      return camera
          .toCameraSpace(Vec3(cy.dx / 2, 0, cy.dy / 2))
          .z
          .compareTo(camera.toCameraSpace(Vec3(cx.dx / 2, 0, cx.dy / 2)).z);
    });
  for (final i in order) {
    final a = corners[i];
    final b = corners[(i + 1) % 4];
    final poly = [
      Vec3(a.dx, 0, a.dy),
      Vec3(b.dx, 0, b.dy),
      Vec3(b.dx, h, b.dy),
      Vec3(a.dx, h, a.dy),
    ];
    var centre = Vec3.zero;
    for (final p in poly) {
      centre = centre + p;
    }
    centre = centre * 0.25;
    if (normals[i].dot(camera.eye - centre) <= 0) continue;
    final path = _projectPolygon(camera, poly);
    if (path == null) continue;
    // Faces turned toward the light (up-range and to the viewer's left) are lit.
    final lit =
        (0.35 + 0.55 * (normals[i].x * -0.5 + normals[i].z * -0.85).abs())
            .clamp(0.0, 1.0);
    canvas.drawPath(
      path,
      Paint()
        ..color = _hazed(
          Color.lerp(Color.lerp(base, Colors.black, 0.5)!, base, lit)!,
          depth,
          rough,
        ),
    );
  }
  final top = _projectPolygon(camera, [
    for (final c in corners) Vec3(c.dx, h, c.dy),
  ]);
  if (top != null) {
    canvas.drawPath(
      top,
      Paint()
        ..color = _hazed(Color.lerp(base, Colors.white, 0.26)!, depth, rough),
    );
    canvas.drawPath(
      top,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.28),
    );
  }
}

void _paintPost(
  Canvas canvas,
  Camera3 camera,
  MiniGolfObstacle o,
  MiniGolfStyle style,
  ColorScheme scheme,
  Color rough,
  double depth,
) {
  const segments = 20;
  final base = style.resolveObstacle(scheme);
  final r = o.radius;
  final h = o.height;
  final cx = o.centerX;
  final cz = o.centerZ;

  Offset? at(double angle, double y) {
    final p = camera.project(
      Vec3(cx + math.cos(angle) * r, y, cz + math.sin(angle) * r),
    );
    return p.visible ? p.screen : null;
  }

  // Wall as a strip of quads, far segment first, shaded per segment so the
  // cylinder rounds itself.
  final order = List.generate(segments, (i) => i)
    ..sort((x, y) {
      final ax = 2 * math.pi * (x + 0.5) / segments;
      final ay = 2 * math.pi * (y + 0.5) / segments;
      return camera
          .toCameraSpace(Vec3(cx + math.cos(ay) * r, 0, cz + math.sin(ay) * r))
          .z
          .compareTo(camera
              .toCameraSpace(
                  Vec3(cx + math.cos(ax) * r, 0, cz + math.sin(ax) * r))
              .z);
    });
  for (final i in order) {
    final a0 = 2 * math.pi * i / segments;
    final a1 = 2 * math.pi * (i + 1) / segments;
    final p0 = at(a0, 0), p1 = at(a1, 0), p2 = at(a1, h), p3 = at(a0, h);
    if (p0 == null || p1 == null || p2 == null || p3 == null) continue;
    final mid = (a0 + a1) / 2;
    final lit = (0.5 + 0.5 * (math.cos(mid) * -0.55 + math.sin(mid) * -0.84))
        .clamp(0.0, 1.0);
    final quad = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(
      quad,
      Paint()
        ..color = _hazed(
          Color.lerp(
            Color.lerp(base, Colors.black, 0.58)!,
            Color.lerp(base, Colors.white, 0.08)!,
            lit,
          )!,
          depth,
          rough,
        )
        ..isAntiAlias = false,
    );
  }

  final cap =
      camera.horizontalCirclePath(Vec3(cx, h, cz), r, segments: segments);
  if (cap != null) {
    canvas.drawPath(
      cap,
      Paint()
        ..color = _hazed(Color.lerp(base, Colors.white, 0.30)!, depth, rough),
    );
    canvas.drawPath(
      cap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.25),
    );
  }
}

// ---------------------------------------------------------------------------
// Ball
// ---------------------------------------------------------------------------

void _paintBallShadow(Canvas canvas, Camera3 camera, MiniGolfBallView ball) {
  final ground = Vec3(ball.position.x, 0.004, ball.position.z);
  final lift = ((ball.position.y - MiniGolfWorld.ballY) / 0.4).clamp(0.0, 1.0);
  final path = camera.horizontalCirclePath(
    ground,
    ball.radius * (1.05 + 0.9 * lift),
    segments: 16,
  );
  if (path == null) return;
  canvas.drawPath(
    path,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.42 * (1 - 0.4 * lift))
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 1.2 + 3 * lift),
  );
}

/// Where a point on the ball's surface, in world direction [v], lands relative
/// to the ball's centre on screen — and whether it is on the visible hemisphere.
///
/// The camera only pitches, so this is exact: rotate the direction into camera
/// space, and the visible half is whatever ends up pointing back at the eye.
({Offset offset, bool front}) _onBall(Camera3 camera, Vec3 v) {
  final c = math.cos(camera.pitch);
  final s = math.sin(camera.pitch);
  final y = v.y * c + v.z * s;
  final z = -v.y * s + v.z * c;
  return (offset: Offset(v.x, -y), front: z < 0);
}

void _paintBall(
  Canvas canvas,
  MiniGolfBallView ball,
  Projected at,
  Camera3 camera,
  MiniGolfStyle style,
  ColorScheme scheme,
  Color rough, {
  double veil = 0,
  bool shadow = true,
}) {
  final r = ball.radius * at.scale;
  if (r < 0.5) return;
  final c = at.screen;
  final white = _hazed(const Color(0xFFF7F9F6), at.depth, rough, strength: 0.3);
  final accent = ball.accent ?? style.resolvePlayer1(scheme);

  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = ui.Gradient.radial(
        c.translate(-r * 0.34, -r * 0.38),
        r * 1.4,
        [
          Colors.white,
          white,
          Color.lerp(white, const Color(0xFF4A5A46), 0.55)!,
        ],
        const [0.0, 0.52, 1.0],
      ),
  );

  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));

  // The alignment stripe: a great circle about the ball's local Y axis, drawn
  // through the live orientation. Seen edge-on it is a bar across the face,
  // seen pole-on it curls to a ring near the rim — which is exactly the read
  // that tells you a ball is rolling rather than sliding, and it survives being
  // only a few pixels wide.
  if (r > 2.5) {
    final axis = ball.roll.ay;
    // Two unit vectors spanning the plane perpendicular to the stripe's axis.
    final helper =
        axis.x.abs() < 0.9 ? const Vec3(1, 0, 0) : const Vec3(0, 1, 0);
    final u = _norm(_cross(axis, helper));
    final v = _norm(_cross(axis, u));
    Path? run;
    for (var i = 0; i <= 40; i++) {
      final a = 2 * math.pi * i / 40;
      final p = u * math.cos(a) + v * math.sin(a);
      final s = _onBall(camera, p);
      if (!s.front) {
        run = null;
        continue;
      }
      final at2 = c + s.offset * r;
      if (run == null) {
        run = Path()..moveTo(at2.dx, at2.dy);
      } else {
        run.lineTo(at2.dx, at2.dy);
        canvas.drawPath(
          run,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.30
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = accent.withValues(alpha: 0.9),
        );
      }
    }
  }

  // Dimples carried on the surface, so they travel over the top and vanish
  // round the rim instead of pinwheeling about the screen axis.
  if (r > 4) {
    final dimple = Paint()..color = Colors.black.withValues(alpha: 0.13);
    for (final d in _dimpleDirections) {
      final w = ball.roll.ax * d.x + ball.roll.ay * d.y + ball.roll.az * d.z;
      final s = _onBall(camera, w);
      if (!s.front) continue;
      canvas.drawCircle(c + s.offset * r, r * 0.13, dimple);
    }
  }

  // Sphere shading over body and markings alike.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = ui.Gradient.radial(
        c.translate(-r * 0.34, -r * 0.38),
        r * 1.5,
        [
          Colors.white.withValues(alpha: 0.30),
          Colors.white.withValues(alpha: 0.0),
          Colors.black.withValues(alpha: 0.34),
        ],
        const [0.0, 0.45, 1.0],
      ),
  );
  if (veil > 0) {
    canvas.drawCircle(
      c,
      r,
      Paint()..color = Colors.black.withValues(alpha: veil.clamp(0.0, 1.0)),
    );
  }
  canvas.restore();

  canvas.drawCircle(
    c.translate(-r * 0.30, -r * 0.34),
    r * 0.24,
    Paint()..color = Colors.white.withValues(alpha: 0.85 * (1 - veil)),
  );
  // A thin dark rim keeps the silhouette against pale rails.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.7, r * 0.09)
      ..color = Colors.black.withValues(alpha: 0.26 * (1 - veil * 0.6)),
  );
  // `shadow` is the caller's business (a ball down the cup casts none) — the
  // contact shadow itself is drawn as a ground decal before the props.
  if (!shadow) return;
}

const _dimpleDirections = <Vec3>[
  Vec3(0.57735, 0.57735, 0.57735),
  Vec3(-0.57735, 0.57735, 0.57735),
  Vec3(0.57735, -0.57735, 0.57735),
  Vec3(0.57735, 0.57735, -0.57735),
  Vec3(-0.57735, -0.57735, 0.57735),
  Vec3(-0.57735, 0.57735, -0.57735),
  Vec3(0.57735, -0.57735, -0.57735),
  Vec3(-0.57735, -0.57735, -0.57735),
  Vec3(1, 0, 0),
  Vec3(-1, 0, 0),
  Vec3(0, 1, 0),
  Vec3(0, -1, 0),
  Vec3(0, 0, 1),
  Vec3(0, 0, -1),
];

Vec3 _cross(Vec3 a, Vec3 b) => Vec3(
      a.y * b.z - a.z * b.y,
      a.z * b.x - a.x * b.z,
      a.x * b.y - a.y * b.x,
    );

Vec3 _norm(Vec3 v) {
  final l = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
  return l < 1e-9 ? const Vec3(0, 0, 1) : Vec3(v.x / l, v.y / l, v.z / l);
}

// ---------------------------------------------------------------------------
// Aim
// ---------------------------------------------------------------------------

/// The slingshot overlay, drawn **on the green** rather than on the glass: a
/// rubber band back to where you've pulled to, and a tapering arrow along the
/// line the ball will set off on, whose length is the power.
void _paintAim(
  Canvas canvas,
  Camera3 camera,
  MiniGolfBallView ball,
  MiniGolfAimView aim,
  MiniGolfStyle style,
  ColorScheme scheme,
) {
  final accent = ball.accent ?? style.resolvePlayer1(scheme);
  final origin = Offset(ball.position.x, ball.position.z);
  final dir = aim.direction.distance < 1e-6
      ? const Offset(0, 1)
      : aim.direction / aim.direction.distance;
  final perp = Offset(-dir.dy, dir.dx);
  final power = aim.power.clamp(0.0, 1.0);
  final len = 0.9 + 5.4 * power;

  final tip = origin + dir * len;
  final neck = origin + dir * math.max(0.35, len - 0.85);
  const w = 0.085;
  const hw = 0.30;

  final shaft = _projectPolygon(camera, [
    MiniGolfWorld.at(origin + perp * w, 0.01),
    MiniGolfWorld.at(neck + perp * w, 0.01),
    MiniGolfWorld.at(neck - perp * w, 0.01),
    MiniGolfWorld.at(origin - perp * w, 0.01),
  ]);
  final head = _projectPolygon(camera, [
    MiniGolfWorld.at(neck + perp * hw, 0.01),
    MiniGolfWorld.at(tip, 0.01),
    MiniGolfWorld.at(neck - perp * hw, 0.01),
  ]);
  final fill = Paint()..color = accent.withValues(alpha: 0.55 + 0.35 * power);
  if (shaft != null) canvas.drawPath(shaft, fill);
  if (head != null) canvas.drawPath(head, fill);

  // Power pips along the shaft.
  final pips = (power * 6).round();
  for (var i = 1; i <= pips; i++) {
    final p = origin + dir * (len * i / 7);
    final ring = camera.horizontalCirclePath(
      MiniGolfWorld.at(p, 0.012),
      0.05,
      segments: 10,
    );
    if (ring != null) {
      canvas.drawPath(
          ring, Paint()..color = Colors.white.withValues(alpha: 0.7));
    }
  }

  // The rubber band back to the drag point.
  final a = camera.project(MiniGolfWorld.at(origin, 0.02));
  final b = camera.project(MiniGolfWorld.at(aim.pullTo, 0.02));
  if (a.visible && b.visible) {
    canvas.drawLine(
      a.screen,
      b.screen,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }
}
