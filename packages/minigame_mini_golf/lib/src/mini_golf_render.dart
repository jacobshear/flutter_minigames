import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:minigames_3d/minigames_3d.dart';

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
  if (green != null) {
    _paintGreen(canvas, size, camera, course, green, felt, rough);
    // Ground decals live under everything and are clipped to the felt.
    canvas.save();
    canvas.clipPath(green);
    _paintCupMouth(canvas, camera, course, rough);
    if (!ball.holed) _paintBallShadow(canvas, camera, ball);
    final aim = view.aim;
    if (aim != null) _paintAim(canvas, camera, ball, aim, style, scheme);
    canvas.restore();
  }

  // --- depth-sorted props ---------------------------------------------------
  final scene = Scene3(camera);
  _addRails(scene, camera, course, style, scheme, rough);
  _addObstacles(scene, camera, course, style, scheme, rough);
  _addFlag(scene, camera, course, style, scheme, rough);
  if (!ball.holed) {
    scene.add(
      ball.position,
      (c, at) => _paintBall(c, ball, at, style, scheme, rough),
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
  final band = Paint()..color = Colors.black.withValues(alpha: 0.05);
  for (var i = 1; i <= 24; i++) {
    final z = camera.eye.z + 1.0 + 0.30 * i * i;
    final a = camera.project(Vec3(0, 0, z));
    final b = camera.project(Vec3(0, 0, z + 0.30 * i));
    if (!a.visible || !b.visible) continue;
    if (a.screen.dy <= horizon) break;
    canvas.drawRect(
      Rect.fromLTRB(0, math.max(horizon, b.screen.dy), size.width, a.screen.dy),
      band,
    );
  }

  // Scrubby patches of longer grass, scattered on the ground plane and drawn as
  // projected conics. Without them the rough is a vertical gradient, and a
  // vertical gradient behind a receding green reads as a painted backdrop
  // rather than ground the hole is sitting on. Positions are hashed off the
  // hole's seed, so they are stable frame to frame.
  final dark = Color.lerp(rough, Colors.black, 0.22)!;
  final pale = Color.lerp(rough, style.resolveGreen(scheme), 0.30)!;
  for (var i = 0; i < 30; i++) {
    final u = _hash(course.seed, i * 3 + 1);
    final v = _hash(course.seed, i * 3 + 2);
    final w = _hash(course.seed, i * 3 + 3);
    final z = camera.eye.z + 2.5 + 34 * v * v;
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
        ..color = (w < 0.5 ? dark : pale).withValues(alpha: 0.30)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
    );
  }
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
  final span = b.maxX - b.minX;
  final stripes = (span / 0.85).round().clamp(4, 16);
  final light = Paint()..color = Colors.white.withValues(alpha: 0.055);
  for (var i = 0; i < stripes; i += 2) {
    final x0 = b.minX + span * i / stripes;
    final x1 = b.minX + span * (i + 1) / stripes;
    final quad = _projectPolygon(camera, [
      Vec3(x0, 0, b.minZ - 0.4),
      Vec3(x1, 0, b.minZ - 0.4),
      Vec3(x1, 0, b.maxZ + 0.4),
      Vec3(x0, 0, b.maxZ + 0.4),
    ]);
    if (quad != null) canvas.drawPath(quad, light);
  }

  // Cross-grain at constant z: even world spacing that visibly bunches away.
  final grain = Paint()
    ..color = Colors.black.withValues(alpha: 0.07)
    ..strokeWidth = 1.0;
  final steps = ((b.maxZ - b.minZ) / 1.1).round().clamp(3, 24);
  for (var i = 1; i < steps; i++) {
    final z = b.minZ + (b.maxZ - b.minZ) * i / steps;
    final l = camera.project(Vec3(b.minX - 0.5, 0, z));
    final r = camera.project(Vec3(b.maxX + 0.5, 0, z));
    if (!l.visible || !r.visible) continue;
    canvas.drawLine(l.screen, r.screen, grain);
  }
  canvas.restore();
}

// ---------------------------------------------------------------------------
// Cup + flag
// ---------------------------------------------------------------------------

void _paintCupMouth(
  Canvas canvas,
  Camera3 camera,
  MiniGolfCourse course,
  Color rough,
) {
  final centre = MiniGolfWorld.at(course.cup);
  final depth = camera.toCameraSpace(centre).z;
  final collar = camera.horizontalCirclePath(
    Vec3(centre.x, 0.004, centre.z),
    MiniGolfCourse.cupRadius * 1.34,
    segments: 24,
  );
  if (collar != null) {
    canvas.drawPath(
      collar,
      Paint()
        ..color = _hazed(const Color(0xFFDDE7CF), depth, rough)
            .withValues(alpha: 0.55),
    );
  }
  // The hole itself: the mouth conic, plus a disc set down inside it so the
  // near lip reads as an overhang rather than a sticker.
  final inner = camera.horizontalCirclePath(
    Vec3(centre.x, -0.22, centre.z),
    MiniGolfCourse.cupRadius * 0.94,
    segments: 24,
  );
  final mouth = camera.horizontalCirclePath(
    centre,
    MiniGolfCourse.cupRadius,
    segments: 24,
  );
  if (mouth == null) return;
  canvas.drawPath(mouth, Paint()..color = const Color(0xFF10180F));
  if (inner != null) {
    canvas.save();
    canvas.clipPath(mouth);
    canvas.drawPath(inner, Paint()..color = const Color(0xFF2A2118));
    canvas.restore();
  }
  canvas.drawPath(
    mouth,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black.withValues(alpha: 0.55),
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
    canvas.drawLine(
      b.screen,
      t.screen,
      Paint()
        ..color = _hazed(const Color(0xFFE9EDF0), at.depth, rough)
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round,
    );
    final flagW = 0.52 * t.scale;
    final flagH = 0.30 * t.scale;
    final pennant = Path()
      ..moveTo(t.screen.dx, t.screen.dy)
      ..lineTo(t.screen.dx - flagW, t.screen.dy + flagH * 0.42)
      ..lineTo(t.screen.dx, t.screen.dy + flagH)
      ..close();
    canvas.drawPath(
      pennant,
      Paint()..color = _hazed(style.resolveFlag(scheme), at.depth, rough),
    );
    canvas.drawPath(
      pennant,
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
          canvas.drawPath(path, Paint()..color = _hazed(f.colour, at.depth, rough));
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
    final lit = (0.35 +
            0.55 * (normals[i].x * -0.5 + normals[i].z * -0.85).abs())
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
      Paint()..color = _hazed(Color.lerp(base, Colors.white, 0.26)!, depth, rough),
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
      Paint()..color = _hazed(Color.lerp(base, Colors.white, 0.30)!, depth, rough),
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

void _paintBall(
  Canvas canvas,
  MiniGolfBallView ball,
  Projected at,
  MiniGolfStyle style,
  ColorScheme scheme,
  Color rough,
) {
  final r = ball.radius * at.scale;
  if (r < 0.5) return;
  final c = at.screen;
  final white = _hazed(const Color(0xFFF7F9F6), at.depth, rough, strength: 0.3);

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
  // Dimples that roll with the ball, so the roll is legible even when the ball
  // is only a few pixels across.
  if (r > 3) {
    final dimple = Paint()..color = Colors.black.withValues(alpha: 0.10);
    for (var i = 0; i < 5; i++) {
      final a = ball.spin * 0.6 + i * (2 * math.pi / 5);
      canvas.drawCircle(
        c.translate(math.cos(a) * r * 0.42, math.sin(a) * r * 0.30),
        r * 0.15,
        dimple,
      );
    }
  }
  canvas.drawCircle(
    c.translate(-r * 0.30, -r * 0.34),
    r * 0.24,
    Paint()..color = Colors.white.withValues(alpha: 0.85),
  );
  // A thin accent ring keeps whose ball it is readable at distance.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, r * 0.14)
      ..color = (ball.accent ?? style.resolvePlayer1(scheme))
          .withValues(alpha: 0.85),
  );
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
      canvas.drawPath(ring, Paint()..color = Colors.white.withValues(alpha: 0.7));
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
