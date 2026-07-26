import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:minigames_3d/minigames_3d.dart';

import 'basketball_court.dart';
import 'basketball_style.dart';

/// One ball, as the painter needs it.
class BallView {
  /// World position of the ball's centre.
  final Vec3 position;

  /// Accumulated roll angle, radians — the ball visibly spins in flight.
  final double spin;

  /// 1 while fully present, ramping to 0 as a spent ball fades out.
  final double opacity;

  /// The ball sitting on the spawn line, waiting to be flicked.
  final bool ready;

  const BallView({
    required this.position,
    this.spin = 0,
    this.opacity = 1,
    this.ready = false,
  });
}

/// An immutable snapshot of everything on screen.
///
/// The whole scene is a pure function of this record — no engine, no widget
/// state, no ticker reachable from the painter. That is what makes the court
/// snapshot-testable: hand [paintBasketballCourt] a view and a canvas and you
/// get a deterministic frame.
class BasketballView {
  /// Hoop centre right now — slides laterally in a moving-hoop match.
  final Vec3 hoopCentre;

  /// Every ball on the court, in any order; the painter depth-sorts them.
  final List<BallView> balls;

  /// Recent positions of the newest live ball, oldest first, for the trail.
  final List<Vec3> trail;

  /// 0..1, non-zero just after a ball whipped the net.
  final double netWobble;

  final Vec3 cameraEye;
  final double pitch;
  final double fov;

  const BasketballView({
    required this.hoopCentre,
    required this.balls,
    this.trail = const [],
    this.netWobble = 0,
    this.cameraEye = BasketballCourt.cameraEye,
    this.pitch = BasketballCourt.cameraPitch,
    this.fov = BasketballCourt.cameraFov,
  });

  /// A ready-to-shoot view: one ball parked on the spawn line.
  factory BasketballView.ready({
    BasketballHoopMode mode = BasketballHoopMode.normal,
    double time = 0,
    double spawnX = 0,
  }) =>
      BasketballView(
        hoopCentre: BasketballCourt.hoopCentreAt(mode, time),
        balls: [
          BallView(
            position: Vec3(
              spawnX,
              BasketballCourt.spawnPoint.y,
              BasketballCourt.spawnPoint.z,
            ),
            ready: true,
          ),
        ],
      );

  Camera3 cameraFor(Size size) => Camera3(
        eye: cameraEye,
        viewport: size,
        pitch: pitch,
        fovY: fov,
      );
}

/// Paint the whole first-person court.
///
/// Depth reads, in the order they carry weight:
/// 1. the floor's plank and court lines converging on [Camera3.horizonY],
/// 2. each ball's radius shrinking with [Projected.scale] as it flies away,
/// 3. a projected floor shadow under every ball, tightening and darkening as it
///    descends,
/// 4. far-to-near paint order via [Scene3] — with the rim and net **split into
///    near and far halves** so a ball sorts *between* them and visibly drops
///    through the hoop,
/// 5. haze: everything desaturates toward the gym backdrop with distance.
void paintBasketballCourt(
  Canvas canvas,
  Size size,
  BasketballView view,
  BasketballStyle style,
  ColorScheme scheme,
) {
  if (size.width <= 0 || size.height <= 0) return;
  _CourtPainter(
    canvas: canvas,
    size: size,
    camera: view.cameraFor(size),
    view: view,
    style: style,
    scheme: scheme,
  ).paintAll();
}

class _CourtPainter {
  final Canvas canvas;
  final Size size;
  final Camera3 camera;
  final BasketballView view;
  final BasketballStyle style;
  final ColorScheme scheme;

  late final Color wood = style.resolveCourt(scheme);
  late final Color backdrop = style.resolveBackdrop(scheme);
  late final Color rimColor = style.resolveRim(scheme);
  late final Color lineColor = style.resolveLine(scheme);
  late final Color ballColor = style.resolveBall(scheme);

  _CourtPainter({
    required this.canvas,
    required this.size,
    required this.camera,
    required this.view,
    required this.style,
    required this.scheme,
  });

  double get hx => view.hoopCentre.x;
  double get hoopZ => BasketballCourt.hoopZ;
  double get wallZ => BasketballCourt.backWallZ;
  double get boardZ => BasketballCourt.backboardZ;

  /// Desaturate toward the gym backdrop with distance. Cheap aerial
  /// perspective — the far rim reads as further than the near rim even where
  /// they overlap.
  Color haze(Color c, double depth) {
    final t = (((depth - 2.0) / 12.0).clamp(0.0, 1.0)) * 0.30;
    return Color.lerp(c, backdrop, t)!;
  }

  void paintAll() {
    _paintBackdrop();
    _paintFloor();
    _paintCourtLines();
    for (final ball in view.balls) {
      _paintShadow(ball);
    }

    final scene = Scene3(camera);
    _addStanchion(scene);
    _addBackboard(scene);
    _addRimHalf(scene, far: true);
    _addNetHalf(scene, far: true);
    for (final ball in view.balls) {
      _addBall(scene, ball);
    }
    _addNetHalf(scene, far: false);
    _addRimHalf(scene, far: false);
    scene.paint(canvas);
  }

  // ---------------------------------------------------------------- backdrop

  void _paintBackdrop() {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(backdrop, Colors.black, 0.5)!,
            backdrop,
            Color.lerp(backdrop, Colors.white, 0.07)!,
          ],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(Offset.zero & size),
    );

    final wallBase = camera.project(Vec3(0, 0, wallZ));
    if (!wallBase.visible) return;
    final baseY = wallBase.screen.dy;
    final scale = wallBase.scale;

    // Ceiling lights, hung high over the court. Drawn here (behind everything)
    // because they are the furthest thing in the room.
    for (final lx in const [-2.4, 2.4]) {
      final at = camera.project(Vec3(lx, 7.6, hoopZ + 1.0));
      if (!at.visible) continue;
      final w = 1.5 * at.scale;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: at.screen, width: w, height: w * 0.26),
          Radius.circular(w * 0.1),
        ),
        Paint()
          ..color = const Color(0xFFFFF3D6).withValues(alpha: 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.22),
      );
    }

    // Bleachers: shallow rows of seating banked against the wall. Cheap, and
    // they stop the upper half of the frame reading as an empty void.
    for (var i = 0; i < 7; i++) {
      final top = baseY - (0.42 + i * 0.34) * scale;
      final h = 0.26 * scale;
      if (h < 0.6) break;
      canvas.drawRect(
        Rect.fromLTWH(0, top, size.width, h),
        Paint()
          ..color = Color.lerp(backdrop, Colors.white, 0.045 + i * 0.013)!,
      );
    }

    // High windows: a row of dim panels gives the wall a believable size.
    final winTop = baseY - 5.4 * scale;
    final winH = 1.5 * scale;
    if (winH > 2) {
      for (var i = -3; i <= 3; i++) {
        final cx = size.width / 2 + i * 2.6 * scale;
        final rect = Rect.fromLTWH(cx - 0.9 * scale, winTop, 1.8 * scale, winH);
        if (rect.right < 0 || rect.left > size.width) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(winH * 0.08)),
          Paint()..color = Color.lerp(backdrop, Colors.white, 0.16)!,
        );
      }
    }

    // Banner stripe.
    final stripeTop = baseY - 3.1 * scale;
    final stripeH = 0.55 * scale;
    if (stripeH > 1) {
      canvas.drawRect(
        Rect.fromLTWH(0, stripeTop, size.width, stripeH),
        Paint()..color = Color.lerp(backdrop, rimColor, 0.34)!,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, stripeTop + stripeH, size.width, stripeH * 0.22),
        Paint()..color = Colors.black.withValues(alpha: 0.25),
      );
    }

    // Skirting where wall meets floor.
    canvas.drawRect(
      Rect.fromLTWH(0, baseY - 0.28 * scale, size.width, 0.28 * scale),
      Paint()..color = Color.lerp(backdrop, Colors.black, 0.4)!,
    );
  }

  // ------------------------------------------------------------------- floor

  Rect get _floorRect {
    final far = camera.project(Vec3(0, 0, wallZ));
    final top = far.visible ? far.screen.dy : size.height * 0.5;
    return Rect.fromLTRB(0, top, size.width, size.height);
  }

  void _paintFloor() {
    final rect = _floorRect;
    if (rect.height <= 0) return;
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            // The far end of the floor sits in the gym's haze.
            Color.lerp(wood, backdrop, 0.5)!,
            Color.lerp(wood, Colors.black, 0.14)!,
            wood,
            Color.lerp(wood, Colors.white, 0.12)!,
          ],
          stops: const [0.0, 0.16, 0.6, 1.0],
        ).createShader(rect),
    );

    // Planks running down-range: the single strongest convergence cue.
    final plank = Paint()..style = PaintingStyle.stroke;
    const zNear = -0.4;
    for (var i = -10; i <= 10; i++) {
      final x = i * 0.78;
      final mid = camera.project(Vec3(x, 0, (zNear + wallZ) / 2));
      if (!mid.visible) continue;
      plank
        ..color = Colors.black.withValues(alpha: 0.10)
        ..strokeWidth = (mid.scale * 0.012).clamp(0.5, 3.0);
      _worldLine(Vec3(x, 0, zNear), Vec3(x, 0, wallZ), plank);
    }

    // A static overhead-lighting stripe washing down the middle of the court.
    // Purely decorative — it is scenery, not an aim guide.
    final glow = _quadPath([
      Vec3(-1.5, 0.002, 0.2),
      Vec3(1.5, 0.002, 0.2),
      Vec3(0.85, 0.002, wallZ),
      Vec3(-0.85, 0.002, wallZ),
    ]);
    if (glow != null) {
      canvas.drawPath(
        glow,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.055)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }
    canvas.restore();
  }

  void _paintCourtLines() {
    final rect = _floorRect;
    canvas.save();
    canvas.clipRect(rect);

    // Court paint is fixed to the floor at x = 0. When the rig slides, the
    // paint does not move with it — only the hoop does.
    final baselineZ = hoopZ + 1.2;
    final laneFrontZ = baselineZ - 5.8;
    const laneHalf = 2.45;
    const sideline = 7.2;

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    void stroke(Vec3 a, Vec3 b, {double width = 0.05, double alpha = 0.8}) {
      final mid = camera.project((a + b) * 0.5);
      if (!mid.visible) return;
      line
        ..color = haze(lineColor, mid.depth).withValues(alpha: alpha)
        ..strokeWidth = (mid.scale * width).clamp(0.8, 10.0);
      _worldLine(a, b, line);
    }

    // Painted key — a flat wash reads as floor, not as a wall.
    final keyPath = _quadPath([
      Vec3(-laneHalf, 0.001, laneFrontZ),
      Vec3(laneHalf, 0.001, laneFrontZ),
      Vec3(laneHalf, 0.001, baselineZ),
      Vec3(-laneHalf, 0.001, baselineZ),
    ]);
    if (keyPath != null) {
      canvas.drawPath(
        keyPath,
        Paint()
          ..color = Color.lerp(wood, const Color(0xFF9A4423), 0.55)!
              .withValues(alpha: 0.85),
      );
    }

    stroke(Vec3(-sideline, 0, baselineZ), Vec3(sideline, 0, baselineZ));
    stroke(Vec3(-sideline, 0, -0.4), Vec3(-sideline, 0, baselineZ), alpha: 0.5);
    stroke(Vec3(sideline, 0, -0.4), Vec3(sideline, 0, baselineZ), alpha: 0.5);
    stroke(Vec3(-laneHalf, 0, laneFrontZ), Vec3(-laneHalf, 0, baselineZ));
    stroke(Vec3(laneHalf, 0, laneFrontZ), Vec3(laneHalf, 0, baselineZ));
    stroke(Vec3(-laneHalf, 0, laneFrontZ), Vec3(laneHalf, 0, laneFrontZ));

    // A horizontal circle projects to a conic whose aspect changes with depth,
    // so these use `horizontalCirclePath` (real projected points) rather than
    // an ellipse with a guessed squash — that variation IS the depth cue.
    void circle(Vec3 centre, double radius, double alpha, double width) {
      final path = camera.horizontalCirclePath(centre, radius, segments: 40);
      if (path == null) return;
      final at = camera.project(centre);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (at.scale * width).clamp(0.8, 8.0)
          ..color = haze(lineColor, at.depth).withValues(alpha: alpha),
      );
    }

    circle(Vec3(0, 0.004, laneFrontZ), 1.83, 0.75, 0.05);
    circle(Vec3(0, 0.004, hoopZ), 1.25, 0.5, 0.04);

    // Three-point arc, drawn from real projected points along the real arc.
    final arc = Path();
    var started = false;
    for (var i = 0; i <= 56; i++) {
      final a = math.pi * (0.05 + 0.90 * i / 56);
      final p = camera.project(
        Vec3(math.cos(a) * 7.24, 0.004, hoopZ - math.sin(a) * 7.24),
      );
      if (!p.visible) {
        started = false;
        continue;
      }
      if (!started) {
        arc.moveTo(p.screen.dx, p.screen.dy);
        started = true;
      } else {
        arc.lineTo(p.screen.dx, p.screen.dy);
      }
    }
    final arcRef = camera.project(Vec3(0, 0, hoopZ - 7.24));
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth =
            (arcRef.visible ? arcRef.scale * 0.05 : 2.0).clamp(0.8, 8.0)
        ..color = haze(lineColor, arcRef.visible ? arcRef.depth : 6)
            .withValues(alpha: 0.7),
    );

    canvas.restore();
  }

  // ------------------------------------------------------------------ shadow

  /// Floor shadow under a ball. Its footprint tightens and darkens as the ball
  /// descends, which is what makes the height of an arc readable at all —
  /// without it a ball at 4 m and a ball at 2 m look identical on screen.
  void _paintShadow(BallView ball) {
    if (ball.opacity <= 0) return;
    final height = (ball.position.y - BasketballCourt.ballRadius)
        .clamp(0.0, 6.0)
        .toDouble();
    final radius = BasketballCourt.ballRadius * (1.0 + height * 0.30);
    final alpha =
        (0.46 / (1.0 + height * 0.55)).clamp(0.05, 0.46) * ball.opacity;
    final path = camera.horizontalCirclePath(
      Vec3(ball.position.x, 0.012, ball.position.z),
      radius,
      segments: 24,
    );
    if (path == null) return;
    final at = camera.project(Vec3(ball.position.x, 0, ball.position.z));
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          (at.visible ? at.scale * radius * 0.24 : 2.0).clamp(1.0, 20.0),
        ),
    );
  }

  // ------------------------------------------------------------ scene pieces

  void _addStanchion(Scene3 scene) {
    final poleZ = wallZ - 1.1;
    scene.add(Vec3(hx, 1.6, poleZ), (canvas, at) {
      final body = _quadPath([
        Vec3(hx - 0.11, 0, poleZ),
        Vec3(hx + 0.11, 0, poleZ),
        Vec3(hx + 0.11, 3.3, poleZ),
        Vec3(hx - 0.11, 3.3, poleZ),
      ]);
      if (body == null) return;
      canvas.drawPath(
        body,
        Paint()..color = haze(const Color(0xFF39485B), at.depth),
      );
      final arm = _quadPath([
        Vec3(hx - 0.07, 3.22, poleZ),
        Vec3(hx + 0.07, 3.22, poleZ),
        Vec3(hx + 0.07, 3.34, boardZ + 0.04),
        Vec3(hx - 0.07, 3.34, boardZ + 0.04),
      ]);
      if (arm != null) {
        canvas.drawPath(
          arm,
          Paint()..color = haze(const Color(0xFF46586D), at.depth),
        );
      }
    });
  }

  void _addBackboard(Scene3 scene) {
    const w = BasketballCourt.backboardWidth / 2;
    const yb = BasketballCourt.backboardBottom;
    const yt = yb + BasketballCourt.backboardHeight;
    scene.add(Vec3(hx, (yb + yt) / 2, boardZ), (canvas, at) {
      final face = _quadPath([
        Vec3(hx - w, yb, boardZ),
        Vec3(hx + w, yb, boardZ),
        Vec3(hx + w, yt, boardZ),
        Vec3(hx - w, yt, boardZ),
      ]);
      if (face == null) return;
      final glass = haze(const Color(0xFFE2EBF3), at.depth);
      canvas.drawPath(face, Paint()..color = glass.withValues(alpha: 0.92));
      canvas.drawPath(
        face,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (at.scale * 0.055).clamp(1.0, 8.0)
          ..color = haze(rimColor, at.depth),
      );
      // Shooter's square, sitting just above the rim.
      final inner = _quadPath([
        Vec3(hx - 0.30, 3.05, boardZ - 0.002),
        Vec3(hx + 0.30, 3.05, boardZ - 0.002),
        Vec3(hx + 0.30, 3.50, boardZ - 0.002),
        Vec3(hx - 0.30, 3.50, boardZ - 0.002),
      ]);
      if (inner != null) {
        canvas.drawPath(
          inner,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (at.scale * 0.042).clamp(1.0, 6.0)
            ..color = haze(rimColor, at.depth),
        );
      }
    });
  }

  /// One half of the rim. Splitting the ring into two [Scene3] items with their
  /// own anchors is what lets a ball sort *between* them: a single hoop
  /// drawable would land entirely in front of or behind the ball, and the drop
  /// through the net would never read.
  void _addRimHalf(Scene3 scene, {required bool far}) {
    final centre = view.hoopCentre;
    final anchor = Vec3(
      centre.x,
      centre.y,
      centre.z + (far ? 1 : -1) * BasketballCourt.rimRadius * 0.6,
    );
    // Angles are measured so sin(a) > 0 is the far side of the ring.
    final a0 = far ? 0.0 : math.pi;
    final a1 = far ? math.pi : 2 * math.pi;
    scene.add(anchor, (canvas, at) {
      final path = _arcPath(centre, BasketballCourt.rimRadius, a0, a1);
      if (path == null) return;
      final width = (at.scale * BasketballCourt.rimThickness * 2.6)
          .clamp(1.6, 22.0)
          .toDouble();
      canvas.drawPath(
        path.shift(Offset(0, width * 0.42)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..color = haze(Color.lerp(rimColor, Colors.black, 0.55)!, at.depth),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..color = haze(rimColor, at.depth),
      );
      canvas.drawPath(
        path.shift(Offset(0, -width * 0.24)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width * 0.34
          ..color = haze(Color.lerp(rimColor, Colors.white, 0.6)!, at.depth)
              .withValues(alpha: 0.85),
      );
    });
  }

  /// Net strands for one half of the ring, tapering to a smaller circle below.
  void _addNetHalf(Scene3 scene, {required bool far}) {
    final centre = view.hoopCentre;
    final wobble = view.netWobble.clamp(0.0, 1.0);
    final depth = 0.42 * (1 + 0.45 * wobble);
    final bottomR = BasketballCourt.rimRadius * (0.60 + 0.32 * wobble);
    final anchor = Vec3(
      centre.x,
      centre.y - depth * 0.5,
      centre.z + (far ? 1 : -1) * BasketballCourt.rimRadius * 0.5,
    );
    scene.add(anchor, (canvas, at) {
      final strandPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = (at.scale * 0.013).clamp(0.7, 4.0)
        ..color = haze(Colors.white, at.depth).withValues(alpha: 0.72);

      const strands = 12;
      for (var i = 0; i <= strands; i++) {
        final a = (far ? 0.0 : math.pi) + math.pi * i / strands;
        // Strands twist as they descend — real nets are braided.
        final b = a + 0.26;
        final top = Vec3(
          centre.x + math.cos(a) * BasketballCourt.rimRadius,
          centre.y,
          centre.z + math.sin(a) * BasketballCourt.rimRadius,
        );
        final mid = Vec3(
          centre.x + math.cos((a + b) / 2) * BasketballCourt.rimRadius * 0.84,
          centre.y - depth * 0.5,
          centre.z + math.sin((a + b) / 2) * BasketballCourt.rimRadius * 0.84,
        );
        final bottom = Vec3(
          centre.x + math.cos(b) * bottomR,
          centre.y - depth,
          centre.z + math.sin(b) * bottomR,
        );
        final pa = camera.project(top);
        final pm = camera.project(mid);
        final pb = camera.project(bottom);
        if (!pa.visible || !pm.visible || !pb.visible) continue;
        canvas.drawPath(
          Path()
            ..moveTo(pa.screen.dx, pa.screen.dy)
            ..quadraticBezierTo(
              pm.screen.dx * 2 - (pa.screen.dx + pb.screen.dx) / 2,
              pm.screen.dy * 2 - (pa.screen.dy + pb.screen.dy) / 2,
              pb.screen.dx,
              pb.screen.dy,
            ),
          strandPaint,
        );
      }

      // Two horizontal courses, which is what actually reads as a cone rather
      // than a fringe.
      final coursePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strandPaint.strokeWidth
        ..color = haze(Colors.white, at.depth).withValues(alpha: 0.5);
      for (final f in const [0.45, 0.92]) {
        final r = BasketballCourt.rimRadius +
            (bottomR - BasketballCourt.rimRadius) * f;
        final course = _arcPath(
          Vec3(centre.x, centre.y - depth * f, centre.z),
          r,
          far ? 0.0 : math.pi,
          far ? math.pi : 2 * math.pi,
        );
        if (course != null) canvas.drawPath(course, coursePaint);
      }
    });
  }

  void _addBall(Scene3 scene, BallView ball) {
    if (ball.opacity <= 0) return;
    scene.add(ball.position, (canvas, at) {
      final r = BasketballCourt.ballRadius * at.scale;
      if (r <= 0.4) return;
      final c = at.screen;
      final alpha = ball.opacity.clamp(0.0, 1.0);

      // Motion trail on the ball currently being watched.
      if (ball.ready == false && view.trail.length > 1 && alpha > 0.99) {
        final head = view.trail.last;
        final isTrailed = (head - ball.position).lengthSquared < 1e-6;
        if (isTrailed) {
          for (var i = 0; i < view.trail.length - 1; i++) {
            final p = camera.project(view.trail[i]);
            if (!p.visible) continue;
            final f = (i + 1) / view.trail.length;
            canvas.drawCircle(
              p.screen,
              BasketballCourt.ballRadius * p.scale * (0.34 + 0.5 * f),
              Paint()
                ..color = haze(ballColor, p.depth)
                    .withValues(alpha: 0.04 + 0.10 * f),
            );
          }
        }
      }

      final base = haze(ballColor, at.depth);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.38, -0.42),
            colors: [
              Color.lerp(base, Colors.white, 0.5)!.withValues(alpha: alpha),
              base.withValues(alpha: alpha),
              Color.lerp(base, Colors.black, 0.45)!.withValues(alpha: alpha),
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );

      // Seams. Rolling them with `spin` is what sells the ball as a solid
      // object travelling away rather than a flat disc shrinking.
      final seam = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(0.7, r * 0.075)
        ..color = haze(const Color(0xFF33200D), at.depth)
            .withValues(alpha: 0.72 * alpha);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(ball.spin);
      canvas.drawCircle(Offset.zero, r * 0.99, seam);
      canvas.drawLine(Offset(0, -r), Offset(0, r), seam);
      for (final s in const [-1.0, 1.0]) {
        canvas.drawPath(
          Path()
            ..moveTo(0, -r)
            ..quadraticBezierTo(s * r * 1.3, 0, 0, r),
          seam,
        );
      }
      canvas.restore();

      // Contact light so the ball separates from a dark backdrop.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.6, r * 0.05)
          ..color = Colors.white.withValues(alpha: 0.16 * alpha),
      );
    });
  }

  // ------------------------------------------------------------------ utils

  void _worldLine(Vec3 a, Vec3 b, Paint paint) {
    final pa = camera.project(a);
    final pb = camera.project(b);
    if (!pa.visible || !pb.visible) return;
    canvas.drawLine(pa.screen, pb.screen, paint);
  }

  /// A planar quad through four world points (planar quads project to quads,
  /// so straight edges are exact).
  Path? _quadPath(List<Vec3> corners) {
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

  /// An arc of a horizontal circle, built from real projected points — the
  /// partial-sweep sibling of [Camera3.horizontalCirclePath]. Never an ellipse:
  /// a horizontal circle projects to a conic whose aspect changes with depth,
  /// and faking that with a fixed squash is exactly what stops a scene reading
  /// as 3-D.
  Path? _arcPath(
    Vec3 centre,
    double radius,
    double a0,
    double a1, {
    int segments = 18,
  }) {
    final path = Path();
    var started = false;
    for (var i = 0; i <= segments; i++) {
      final a = a0 + (a1 - a0) * i / segments;
      final p = camera.project(Vec3(
        centre.x + math.cos(a) * radius,
        centre.y,
        centre.z + math.sin(a) * radius,
      ));
      if (!p.visible) continue;
      if (!started) {
        path.moveTo(p.screen.dx, p.screen.dy);
        started = true;
      } else {
        path.lineTo(p.screen.dx, p.screen.dy);
      }
    }
    return started ? path : null;
  }
}
