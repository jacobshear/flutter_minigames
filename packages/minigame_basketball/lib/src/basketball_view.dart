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

/// A stable pseudo-random in 0..1 for [i]. Deterministic so two renders of the
/// same frame are byte-identical — the floor's grain must not shimmer, and the
/// render tests compare frames.
double _hash(int i) {
  final s = math.sin(i * 12.9898 + 78.233) * 43758.5453;
  return s - s.floorToDouble();
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
    _paintFalloff();
  }

  /// Corner falloff. A gym is lit by fixtures over the court, so the edges of
  /// the room genuinely fall away — and it puts the value peak on the hoop,
  /// which is where the player is looking. Weak through the middle so it never
  /// eats the ball, the rim or a court line.
  void _paintFalloff() {
    final reach = math.sqrt(
          size.width * size.width + size.height * size.height,
        ) *
        0.62;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.15),
          radius: 1.0,
          colors: [
            const Color(0x00000000),
            const Color(0x00000000),
            Colors.black.withValues(alpha: 0.30),
          ],
          stops: const [0.0, 0.58, 1.0],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.5, size.height * 0.42),
            radius: reach,
          ),
        ),
    );
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
            Color.lerp(backdrop, Colors.black, 0.55)!,
            Color.lerp(backdrop, Colors.black, 0.18)!,
            Color.lerp(backdrop, Colors.white, 0.05)!,
          ],
          stops: const [0.0, 0.62, 1.0],
        ).createShader(Offset.zero & size),
    );

    final wallBase = camera.project(Vec3(0, 0, wallZ));
    if (!wallBase.visible) return;

    _paintGymWall();
    _paintBleachers();
    _paintCeilingLights();
  }

  /// The back wall: painted cinder block, a banner course, and the padded base
  /// every gym has where the wall meets the floor.
  ///
  /// Built from projected world coordinates rather than from fractions of
  /// [wallBase.scale], so the courses actually converge with the room instead of
  /// staying a stack of parallel screen-space bands.
  void _paintGymWall() {
    final wall = _quadPath([
      Vec3(-16, 0, wallZ),
      Vec3(16, 0, wallZ),
      Vec3(16, 11, wallZ),
      Vec3(-16, 11, wallZ),
    ]);
    if (wall == null) return;
    final base = camera.project(Vec3(0, 0, wallZ));
    final top = camera.project(Vec3(0, 11, wallZ));
    if (!base.visible || !top.visible) return;

    canvas.save();
    canvas.clipPath(wall);
    canvas.drawPaint(
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(backdrop, Colors.black, 0.40)!,
            Color.lerp(backdrop, Colors.white, 0.10)!,
            Color.lerp(backdrop, Colors.black, 0.22)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromLTRB(
          0,
          top.screen.dy,
          size.width,
          base.screen.dy,
        )),
    );

    // Block courses. 0.20 m courses, 0.40 m blocks, half-lap staggered — the
    // real bond, which is why the wall reads as masonry and not as graph paper.
    final mortar = Paint()
      ..strokeWidth = 1.0
      ..color = Colors.black.withValues(alpha: 0.22);
    final lit = Paint()
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.05);
    for (var c = 0; c < 46; c++) {
      final y = c * 0.20;
      if (y > 10.4) break;
      final a = camera.project(Vec3(-16, y, wallZ));
      final b = camera.project(Vec3(16, y, wallZ));
      if (!a.visible || !b.visible) continue;
      if ((a.screen.dy - base.screen.dy).abs() > size.height * 1.5) continue;
      canvas.drawLine(a.screen, b.screen, mortar);
      // The gym is lit from the ceiling, so it is the *upward* face of each
      // course that catches light. Same rule as every other bevel in here.
      canvas.drawLine(
        a.screen.translate(0, 1),
        b.screen.translate(0, 1),
        lit,
      );
      for (var k = -20; k <= 20; k++) {
        final x = k * 0.40 + (c.isEven ? 0 : 0.20);
        final j0 = camera.project(Vec3(x, y, wallZ));
        final j1 = camera.project(Vec3(x, y + 0.20, wallZ));
        if (!j0.visible || !j1.visible) continue;
        if (j0.screen.dx < -8 || j0.screen.dx > size.width + 8) continue;
        canvas.drawLine(j0.screen, j1.screen, mortar);
      }
    }

    // Banner course high on the wall.
    final banner = _quadPath([
      Vec3(-16, 6.1, wallZ - 0.02),
      Vec3(16, 6.1, wallZ - 0.02),
      Vec3(16, 7.0, wallZ - 0.02),
      Vec3(-16, 7.0, wallZ - 0.02),
    ]);
    if (banner != null) {
      canvas.drawPath(
        banner,
        Paint()..color = Color.lerp(backdrop, rimColor, 0.30)!,
      );
      final edge = camera.project(Vec3(0, 6.1, wallZ - 0.02));
      final l = camera.project(Vec3(-16, 6.1, wallZ - 0.02));
      final r = camera.project(Vec3(16, 6.1, wallZ - 0.02));
      if (edge.visible && l.visible && r.visible) {
        canvas.drawLine(
          l.screen,
          r.screen,
          Paint()
            ..strokeWidth = 2.0
            ..color = Colors.black.withValues(alpha: 0.30),
        );
      }
    }

    // Wall padding: the thick vinyl mat behind every baseline, with a lit top
    // edge and its own contact shadow on the floor.
    final pad = _quadPath([
      Vec3(-16, 0, wallZ - 0.06),
      Vec3(16, 0, wallZ - 0.06),
      Vec3(16, 1.85, wallZ - 0.06),
      Vec3(-16, 1.85, wallZ - 0.06),
    ]);
    if (pad != null) {
      canvas.drawPath(
        pad,
        Paint()..color = Color.lerp(backdrop, Colors.black, 0.42)!,
      );
      final pl = camera.project(Vec3(-16, 1.85, wallZ - 0.06));
      final pr = camera.project(Vec3(16, 1.85, wallZ - 0.06));
      if (pl.visible && pr.visible) {
        canvas.drawLine(
          pl.screen,
          pr.screen,
          Paint()
            ..strokeWidth = 2.2
            ..color = Colors.white.withValues(alpha: 0.10),
        );
      }
      // Vertical seams between pad sections.
      for (var k = -8; k <= 8; k++) {
        final s0 = camera.project(Vec3(k * 1.9, 0, wallZ - 0.06));
        final s1 = camera.project(Vec3(k * 1.9, 1.85, wallZ - 0.06));
        if (!s0.visible || !s1.visible) continue;
        canvas.drawLine(
          s0.screen,
          s1.screen,
          Paint()
            ..strokeWidth = 1.0
            ..color = Colors.black.withValues(alpha: 0.28),
        );
      }
    }
    canvas.restore();
  }

  /// Banked seating, built as real 3-D steps.
  ///
  /// Each row is a riser (the vertical face), a tread on top of it and a seat
  /// plank standing proud — all projected quads at real depths, so the rows
  /// occlude each other and the stand has a thickness. The previous version was
  /// seven full-width screen rectangles: no perspective, no occlusion, no
  /// depth.
  ///
  /// The camera pitch here is only 0.06 rad, which matters: horizontal surfaces
  /// at bleacher height project to a couple of pixels, so the tread cannot
  /// carry the read on its own. What sells it is the **vertical** geometry —
  /// riser vs seat-front value contrast, the shadow gap under each seat, and
  /// the stairways, which are the one thing up there that genuinely converges.
  void _paintBleachers() {
    const rows = 9;
    const rise = 0.40;
    const run = 0.74;
    final frontZ = wallZ - 0.35;

    // Dark void the whole stand sits in, so the rows have something to be
    // brighter than.
    final well = _quadPath([
      Vec3(-16, 0, frontZ - rows * run),
      Vec3(16, 0, frontZ - rows * run),
      Vec3(16, rows * rise + 0.6, frontZ - rows * run),
      Vec3(-16, rows * rise + 0.6, frontZ - rows * run),
    ]);
    if (well != null) {
      canvas.drawPath(
        well,
        Paint()..color = Color.lerp(backdrop, Colors.black, 0.52)!,
      );
    }

    // Far rows first: a nearer row must cover the one behind it.
    for (var i = rows - 1; i >= 0; i--) {
      final y = 0.30 + i * rise;
      final z = frontZ - i * run;
      final at = camera.project(Vec3(0, y, z));
      if (!at.visible) continue;

      // Riser — in shadow, because the light is straight overhead and this face
      // is vertical.
      final riser = _quadPath([
        Vec3(-16, y - rise, z),
        Vec3(16, y - rise, z),
        Vec3(16, y, z),
        Vec3(-16, y, z),
      ]);
      if (riser != null) {
        canvas.drawPath(
          riser,
          Paint()
            ..color =
                haze(Color.lerp(backdrop, Colors.black, 0.46)!, at.depth),
        );
      }

      // Tread — horizontal, so it takes the ceiling light square on and is the
      // brightest plane in the stand. Only a few pixels tall at this pitch, but
      // it is the highlight that separates one row from the next.
      final tread = _quadPath([
        Vec3(-16, y, z),
        Vec3(16, y, z),
        Vec3(16, y, z - run),
        Vec3(-16, y, z - run),
      ]);
      if (tread != null) {
        canvas.drawPath(
          tread,
          Paint()
            ..color = haze(
              Color.lerp(backdrop, Colors.white, 0.20 + i * 0.010)!,
              at.depth,
            ),
        );
      }

      // Seat plank standing on the tread, its front face catching a glancing
      // amount of light, with a hard shadow line where it meets the step.
      final seatFront = _quadPath([
        Vec3(-16, y, z - 0.22),
        Vec3(16, y, z - 0.22),
        Vec3(16, y + 0.16, z - 0.22),
        Vec3(-16, y + 0.16, z - 0.22),
      ]);
      if (seatFront != null) {
        canvas.drawPath(
          seatFront,
          Paint()
            ..color = haze(
              Color.lerp(backdrop, const Color(0xFF9A7745), 0.62)!,
              at.depth,
            ),
        );
      }
      final seatTop = _quadPath([
        Vec3(-16, y + 0.16, z - 0.22),
        Vec3(16, y + 0.16, z - 0.22),
        Vec3(16, y + 0.16, z - 0.62),
        Vec3(-16, y + 0.16, z - 0.62),
      ]);
      if (seatTop != null) {
        canvas.drawPath(
          seatTop,
          Paint()
            ..color = haze(
              Color.lerp(backdrop, const Color(0xFFD8B074), 0.68)!,
              at.depth,
            ),
        );
      }
    }

    // Stairways. At this pitch these are the only things in the stand that
    // visibly converge, and they are what turns a stack of bands into a raked
    // seating deck.
    for (final ax in const [-7.4, -2.6, 2.6, 7.4]) {
      for (var i = 0; i < rows; i++) {
        final y = 0.30 + i * rise;
        final z = frontZ - i * run;
        final step = _quadPath([
          Vec3(ax - 0.55, y + 0.165, z - 0.22),
          Vec3(ax + 0.55, y + 0.165, z - 0.22),
          Vec3(ax + 0.55, y + 0.165, z - run),
          Vec3(ax - 0.55, y + 0.165, z - run),
        ]);
        final at = camera.project(Vec3(ax, y, z));
        if (step == null || !at.visible) continue;
        canvas.drawPath(
          step,
          Paint()
            ..color = haze(
              Color.lerp(backdrop, Colors.black, 0.30)!,
              at.depth,
            ),
        );
      }
    }

    // Guard rail across the front of the stand.
    for (final y in const [1.55, 1.95]) {
      final a = camera.project(Vec3(-16, y, frontZ + 0.18));
      final b = camera.project(Vec3(16, y, frontZ + 0.18));
      if (!a.visible || !b.visible) continue;
      canvas.drawLine(
        a.screen,
        b.screen,
        Paint()
          ..strokeWidth = (a.scale * 0.05).clamp(1.0, 5.0)
          ..color = haze(Color.lerp(backdrop, Colors.white, 0.34)!, a.depth),
      );
    }
    for (var k = -8; k <= 8; k++) {
      final a = camera.project(Vec3(k * 1.9, 0.30, frontZ + 0.18));
      final b = camera.project(Vec3(k * 1.9, 1.95, frontZ + 0.18));
      if (!a.visible || !b.visible) continue;
      canvas.drawLine(
        a.screen,
        b.screen,
        Paint()
          ..strokeWidth = (a.scale * 0.04).clamp(0.8, 4.0)
          ..color = haze(Color.lerp(backdrop, Colors.white, 0.24)!, a.depth),
      );
    }
  }

  /// Ceiling fixtures. The committed key light for the whole scene: everything
  /// below is lit from straight above, which is why every ball shadow here is
  /// directly under its ball and every bevel is bright on its upper edge.
  void _paintCeilingLights() {
    for (final lx in const [-3.6, 0.0, 3.6]) {
      for (final lz in const [1.0, -4.2]) {
        final at = camera.project(Vec3(lx, 7.6, hoopZ + lz));
        if (!at.visible) continue;
        final w = 1.6 * at.scale;
        if (w < 4) continue;
        final rect = Rect.fromCenter(
          center: at.screen,
          width: w,
          height: w * 0.24,
        );
        // Housing, then the tube inside it, then the halo. Three passes is what
        // separates "a light fitting" from "a blurred white smudge".
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(w * 0.04), Radius.circular(w * 0.05)),
          Paint()..color = Color.lerp(backdrop, Colors.black, 0.45)!,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(w * 0.04)),
          Paint()..color = const Color(0xFFFFF6DE).withValues(alpha: 0.92),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(w * 0.10), Radius.circular(w * 0.1)),
          Paint()
            ..color = const Color(0xFFFFF3D6).withValues(alpha: 0.30)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.20),
        );
      }
    }
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

    // Planks running down-range: the single strongest convergence cue. Each
    // gets a dark seam and a lit edge, so the boards have a thickness.
    final plank = Paint()..style = PaintingStyle.stroke;
    const zNear = -0.4;
    for (var i = -10; i <= 10; i++) {
      final x = i * 0.78;
      final mid = camera.project(Vec3(x, 0, (zNear + wallZ) / 2));
      if (!mid.visible) continue;
      plank
        ..color = Colors.black.withValues(alpha: 0.13)
        ..strokeWidth = (mid.scale * 0.012).clamp(0.5, 3.0);
      _worldLine(Vec3(x, 0, zNear), Vec3(x, 0, wallZ), plank);
      plank
        ..color = Colors.white.withValues(alpha: 0.06)
        ..strokeWidth = (mid.scale * 0.008).clamp(0.5, 2.0);
      _worldLine(Vec3(x + 0.012, 0, zNear), Vec3(x + 0.012, 0, wallZ), plank);
    }

    // Grain within the planks: fine streaks at stable pseudo-random offsets,
    // alternating light and dark. Maple is figured, not flat, and this is the
    // difference between a wood floor and a brown ramp.
    final grain = Paint()..style = PaintingStyle.stroke;
    for (var i = 0; i < 70; i++) {
      final x = -7.8 + 15.6 * _hash(i);
      final ref = camera.project(Vec3(x, 0, (zNear + wallZ) / 2));
      if (!ref.visible) continue;
      final dark = _hash(i + 700) < 0.6;
      grain
        ..strokeWidth = (ref.scale * 0.004).clamp(0.4, 1.6)
        ..color = (dark ? Colors.black : Colors.white)
            .withValues(alpha: (dark ? 0.035 : 0.025) + _hash(i + 300) * 0.02);
      _worldLine(Vec3(x, 0, zNear), Vec3(x, 0, wallZ), grain);
    }

    // End-joints: boards are finite, and the staggered butt joints are what
    // stop the floor reading as one impossibly long stripe per plank.
    final joint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.black.withValues(alpha: 0.10);
    for (var i = -10; i <= 10; i++) {
      final x = i * 0.78;
      for (var k = 0; k < 5; k++) {
        final z = zNear + (wallZ - zNear) * ((k + _hash(i * 13 + k)) / 5);
        final a = camera.project(Vec3(x, 0, z));
        final b = camera.project(Vec3(x + 0.78, 0, z));
        if (!a.visible || !b.visible) continue;
        joint.strokeWidth = (a.scale * 0.006).clamp(0.4, 2.0);
        canvas.drawLine(a.screen, b.screen, joint);
      }
    }

    // Pools thrown by the ceiling fixtures, and the sheen the varnish returns.
    // Anchored on the real floor position under each light rather than painted
    // as a screen-space stripe, so they sit in the room and foreshorten with it.
    for (final lx in const [-3.6, 0.0, 3.6]) {
      for (final lz in const [1.0, -4.2]) {
        final at = camera.project(Vec3(lx, 0, hoopZ + lz));
        if (!at.visible) continue;
        final r = at.scale * 2.6;
        if (r < 6) continue;
        canvas.save();
        canvas.translate(at.screen.dx, at.screen.dy);
        // Squashed toward the horizon: a circular pool on the floor projects
        // to a conic, and a round blob is the tell that it was faked.
        canvas.scale(1.0, 0.34);
        canvas.drawCircle(
          Offset.zero,
          r,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = RadialGradient(
              colors: [
                const Color(0xFFFFF0D2).withValues(alpha: 0.16),
                const Color(0x00000000),
              ],
            ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
        );
        canvas.restore();
      }
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
      // Deliberately translucent. At 0.85 the paint buried every plank seam and
      // every streak of grain under it, and since the key covers most of the
      // visible floor from this eyeline, that alone made the court read as a
      // flat brown ramp. Court paint is a stain on wood, not a sheet over it.
      canvas.drawPath(
        keyPath,
        Paint()
          ..color = Color.lerp(wood, const Color(0xFF8E3A1E), 0.72)!
              .withValues(alpha: 0.48),
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

    // Lane hash marks — the blocks and the shooters' spaces down each side of
    // the key. Small, but they are the detail that says "a real key" rather
    // than "a painted rectangle".
    for (final side in const [-1.0, 1.0]) {
      for (final f in const [0.18, 0.40, 0.56, 0.72]) {
        final z = baselineZ - (baselineZ - laneFrontZ) * f;
        stroke(
          Vec3(side * laneHalf, 0, z),
          Vec3(side * (laneHalf + 0.22), 0, z),
          width: 0.04,
          alpha: 0.65,
        );
      }
      // The block: a solid rectangle just off the baseline.
      final block = _quadPath([
        Vec3(side * laneHalf, 0.002, baselineZ - 1.75),
        Vec3(side * (laneHalf + 0.22), 0.002, baselineZ - 1.75),
        Vec3(side * (laneHalf + 0.22), 0.002, baselineZ - 1.24),
        Vec3(side * laneHalf, 0.002, baselineZ - 1.24),
      ]);
      if (block != null) {
        canvas.drawPath(
          block,
          Paint()..color = lineColor.withValues(alpha: 0.85),
        );
      }
    }

    circle(Vec3(0, 0.004, laneFrontZ), 1.83, 0.75, 0.05);
    // Restricted-area arc under the basket.
    final restricted = _arcPath(
      Vec3(hx, 0.004, hoopZ),
      1.25,
      math.pi,
      2 * math.pi,
      segments: 26,
    );
    if (restricted != null) {
      final at = camera.project(Vec3(hx, 0.004, hoopZ));
      canvas.drawPath(
        restricted,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (at.scale * 0.04).clamp(0.8, 8.0)
          ..color = haze(lineColor, at.depth).withValues(alpha: 0.5),
      );
    }

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
      // Padded base first, so the pole stands *on* something. A post that
      // simply stops where the floor happens to be reads as a UI rule, not a
      // rig, and it was the one piece of this scene with no contact anywhere.
      final foot = _quadPath([
        Vec3(hx - 0.30, 0, poleZ + 0.10),
        Vec3(hx + 0.30, 0, poleZ + 0.10),
        Vec3(hx + 0.30, 0.34, poleZ + 0.10),
        Vec3(hx - 0.30, 0.34, poleZ + 0.10),
      ]);
      final footBounds = foot?.getBounds();
      if (foot != null && footBounds != null && footBounds.width > 0.5) {
        // Contact shade on the floor under the pad.
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(footBounds.center.dx, footBounds.bottom),
            width: footBounds.width * 1.5,
            height: footBounds.height * 0.5,
          ),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.28)
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              math.max(1.5, footBounds.width * 0.18),
            ),
        );
        canvas.drawPath(
          foot,
          Paint()
            ..shader = LinearGradient(
              colors: [
                haze(const Color(0xFF1B2430), at.depth),
                haze(const Color(0xFF2C3A4B), at.depth),
                haze(const Color(0xFF141B24), at.depth),
              ],
              stops: const [0.0, 0.38, 1.0],
            ).createShader(footBounds),
        );
      }

      final body = _quadPath([
        Vec3(hx - 0.11, 0, poleZ),
        Vec3(hx + 0.11, 0, poleZ),
        Vec3(hx + 0.11, 3.3, poleZ),
        Vec3(hx - 0.11, 3.3, poleZ),
      ]);
      if (body == null) return;
      final bounds = body.getBounds();
      // Across-the-pole falloff: dark edge, lit shoulder, dark edge. A flat
      // fill makes a cylinder read as a painted stripe on the backdrop.
      canvas.drawPath(
        body,
        bounds.width > 1.5
            ? (Paint()
              ..shader = LinearGradient(
                colors: [
                  haze(const Color(0xFF1E2836), at.depth),
                  haze(const Color(0xFF52657D), at.depth),
                  haze(const Color(0xFF39485B), at.depth),
                  haze(const Color(0xFF19212C), at.depth),
                ],
                stops: const [0.0, 0.30, 0.62, 1.0],
              ).createShader(bounds))
            : (Paint()..color = haze(const Color(0xFF39485B), at.depth)),
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
          Paint()..color = haze(const Color(0xFF56697F), at.depth),
        );
      }
    });
  }

  /// The backboard, as tempered glass in a frame rather than a painted panel.
  ///
  /// Order matters and is the whole trick: the glass is drawn **translucent**,
  /// so the bleachers and wall behind it show through and it stops reading as a
  /// white rectangle stuck on the backdrop. Then the sheet's own thickness (a
  /// visible edge quad at the bottom), then the frame, then the reflections,
  /// then the painted square on top.
  void _addBackboard(Scene3 scene) {
    const w = BasketballCourt.backboardWidth / 2;
    const yb = BasketballCourt.backboardBottom;
    const yt = yb + BasketballCourt.backboardHeight;
    const thick = 0.05;
    scene.add(Vec3(hx, (yb + yt) / 2, boardZ), (canvas, at) {
      final face = _quadPath([
        Vec3(hx - w, yb, boardZ),
        Vec3(hx + w, yb, boardZ),
        Vec3(hx + w, yt, boardZ),
        Vec3(hx - w, yt, boardZ),
      ]);
      if (face == null) return;
      final line = (at.scale * 0.03).clamp(0.8, 6.0);

      // Perspex: cool, cold, and mostly transparent. 0.30 keeps the room
      // legible through it; the sheet is sold by its edges and reflections,
      // not by its opacity.
      canvas.drawPath(
        face,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              haze(const Color(0xFFDDE9F4), at.depth).withValues(alpha: 0.40),
              haze(const Color(0xFF9FB6CA), at.depth).withValues(alpha: 0.22),
              haze(const Color(0xFFE8F1FA), at.depth).withValues(alpha: 0.34),
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(face.getBounds()),
      );

      // Two raking reflections across the sheet — the single clearest "this is
      // glass" cue there is, and free: they are just skewed bands.
      final bounds = face.getBounds();
      canvas.save();
      canvas.clipPath(face);
      for (final f in const [0.16, 0.52]) {
        final x0 = bounds.left + bounds.width * f;
        canvas.drawPath(
          Path()
            ..moveTo(x0, bounds.bottom)
            ..lineTo(x0 + bounds.width * 0.10, bounds.bottom)
            ..lineTo(x0 + bounds.width * 0.26, bounds.top)
            ..lineTo(x0 + bounds.width * 0.16, bounds.top)
            ..close(),
          Paint()..color = Colors.white.withValues(alpha: 0.10),
        );
      }
      canvas.restore();

      // The sheet's thickness, seen along the bottom edge because the camera is
      // below the board. Without it the glass is infinitely thin and the whole
      // rig reads as a decal.
      final edge = _quadPath([
        Vec3(hx - w, yb, boardZ),
        Vec3(hx + w, yb, boardZ),
        Vec3(hx + w, yb, boardZ - thick),
        Vec3(hx - w, yb, boardZ - thick),
      ]);
      if (edge != null) {
        canvas.drawPath(
          edge,
          Paint()..color = haze(const Color(0xFFB9C9D8), at.depth),
        );
      }

      // Frame: an aluminium channel round the sheet, with the padded bottom
      // rail every real board carries.
      canvas.drawPath(
        face,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = line * 1.6
          ..color = haze(const Color(0xFF5A6675), at.depth),
      );
      final padRail = _quadPath([
        Vec3(hx - w, yb, boardZ - thick - 0.01),
        Vec3(hx + w, yb, boardZ - thick - 0.01),
        Vec3(hx + w, yb + 0.09, boardZ - thick - 0.01),
        Vec3(hx - w, yb + 0.09, boardZ - thick - 0.01),
      ]);
      if (padRail != null) {
        canvas.drawPath(
          padRail,
          Paint()
            ..color =
                haze(Color.lerp(rimColor, Colors.black, 0.62)!, at.depth),
        );
      }
      // Lit top arris of the frame — the ceiling is the key light.
      final ft = camera.project(Vec3(hx - w, yt, boardZ));
      final fr = camera.project(Vec3(hx + w, yt, boardZ));
      if (ft.visible && fr.visible) {
        canvas.drawLine(
          ft.screen.translate(0, line * 0.6),
          fr.screen.translate(0, line * 0.6),
          Paint()
            ..strokeWidth = line * 0.7
            ..color = Colors.white.withValues(alpha: 0.35),
        );
      }

      // Shooter's square, sitting just above the rim.
      final inner = _quadPath([
        Vec3(hx - 0.30, 3.05, boardZ - 0.004),
        Vec3(hx + 0.30, 3.05, boardZ - 0.004),
        Vec3(hx + 0.30, 3.50, boardZ - 0.004),
        Vec3(hx - 0.30, 3.50, boardZ - 0.004),
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
      final width = (at.scale * BasketballCourt.rimThickness * 1.7)
          .clamp(1.4, 14.0)
          .toDouble();
      canvas.drawPath(
        path.shift(Offset(0, width * 0.55)),
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
        path.shift(Offset(0, -width * 0.30)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width * 0.34
          ..color = haze(Color.lerp(rimColor, Colors.white, 0.6)!, at.depth)
              .withValues(alpha: 0.85),
      );
    });
  }

  /// Net cord for one half of the ring.
  ///
  /// ## Why it is a mesh and not a fringe
  ///
  /// A basketball net is twelve cords hung from the ring and knotted to their
  /// neighbours, which makes a lattice of diamonds — and the diamonds are what
  /// a ball visibly *pushes through*. Twelve independent curves hanging in
  /// parallel read as a lampshade at rest and as nothing at all in motion. So
  /// the strands here cross: each cord spirals one way, and a mirrored set
  /// spirals the other, meeting at the knot courses.
  ///
  /// ## How it reacts
  ///
  /// [BasketballView.netWobble] rings from 1 to 0 after a ball passes through.
  /// It does three things at once, which together are what make the whip read:
  /// the cone gets **longer** (the net is dragged down), **wider at the mouth**
  /// (the ball forced it open on the way past), and the spiral **unwinds** —
  /// so the whole mesh visibly snaps and recovers rather than just changing
  /// size. The cords also thicken slightly under load, because a net under
  /// tension catches more light.
  void _addNetHalf(Scene3 scene, {required bool far}) {
    final centre = view.hoopCentre;
    final wobble = view.netWobble.clamp(0.0, 1.0);
    // A decaying ring rather than a straight ramp: the net overshoots, comes
    // back, and settles, which is the shape of a real one snapping back.
    final ring = wobble == 0
        ? 0.0
        : math.sin(wobble * math.pi * 1.6) * wobble;
    final depth = 0.40 * (1 + 0.50 * wobble);
    const rimR = BasketballCourt.rimRadius;
    final mouthR = rimR * (1 + 0.10 * ring.abs());
    final bottomR = rimR * (0.58 + 0.34 * wobble);
    final twist = 0.30 * (1 - 0.75 * ring);
    final anchor = Vec3(
      centre.x,
      centre.y - depth * 0.5,
      centre.z + (far ? 1 : -1) * rimR * 0.5,
    );

    scene.add(anchor, (canvas, at) {
      final width = (at.scale * 0.014).clamp(0.7, 4.5) * (1 + 0.25 * wobble);
      final cord = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..color = haze(Colors.white, at.depth)
            .withValues(alpha: 0.62 + 0.24 * wobble);
      // Cords are white nylon lit from directly above, so they carry a shadow
      // side. Drawing it first, offset down, gives the mesh a thickness.
      final cordShadow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..color = Colors.black.withValues(alpha: 0.22);

      const strands = 8;
      final a0 = far ? 0.0 : math.pi;

      /// One cord from the ring to the bottom hoop, spiralling by [dir].
      Path? cordPath(int i, double dir) {
        final a = a0 + math.pi * i / strands;
        final b = a + twist * dir;
        final m = (a + b) / 2;
        final top = Vec3(
          centre.x + math.cos(a) * mouthR,
          centre.y,
          centre.z + math.sin(a) * mouthR,
        );
        // Waist pinch: the net narrows fastest just under the ring.
        final mid = Vec3(
          centre.x + math.cos(m) * (rimR * 0.78),
          centre.y - depth * 0.5,
          centre.z + math.sin(m) * (rimR * 0.78),
        );
        final bottom = Vec3(
          centre.x + math.cos(b) * bottomR,
          centre.y - depth,
          centre.z + math.sin(b) * bottomR,
        );
        final pa = camera.project(top);
        final pm = camera.project(mid);
        final pb = camera.project(bottom);
        if (!pa.visible || !pm.visible || !pb.visible) return null;
        return Path()
          ..moveTo(pa.screen.dx, pa.screen.dy)
          ..quadraticBezierTo(
            pm.screen.dx * 2 - (pa.screen.dx + pb.screen.dx) / 2,
            pm.screen.dy * 2 - (pa.screen.dy + pb.screen.dy) / 2,
            pb.screen.dx,
            pb.screen.dy,
          );
      }

      for (final dir in const [1.0, -1.0]) {
        for (var i = 0; i <= strands; i++) {
          final path = cordPath(i, dir);
          if (path == null) continue;
          canvas.drawPath(path.shift(Offset(0, width * 0.5)), cordShadow);
        }
      }
      for (final dir in const [1.0, -1.0]) {
        for (var i = 0; i <= strands; i++) {
          final path = cordPath(i, dir);
          if (path == null) continue;
          canvas.drawPath(path, cord);
        }
      }

      // Knot courses: the horizontal rings the diamonds are tied off on. These
      // are what read as a cone rather than a fringe.
      final coursePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width * 0.9
        ..color = haze(Colors.white, at.depth)
            .withValues(alpha: 0.45 + 0.2 * wobble);
      for (final f in const [0.34, 0.66, 0.95]) {
        final r = rimR * 0.86 + (bottomR - rimR * 0.86) * f;
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
