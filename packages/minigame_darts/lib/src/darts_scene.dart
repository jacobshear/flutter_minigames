import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:minigames_3d/minigames_3d.dart';

import 'darts_board_geometry.dart';
import 'darts_style.dart';
import 'darts_throw.dart';

/// The first-person camera at the oche.
///
/// A single fixed camera — darts is a static viewpoint game, and keeping the
/// camera constant means [paintDartsScene] is a pure function of the view model
/// and the canvas size, so every frame is snapshot-testable.
abstract final class DartsCamera {
  /// Eye position. Low and a hand's width behind the oche. See [DartsWorld]
  /// for why the camera is staged low rather than at standing eye height.
  static const Vec3 eye = Vec3(0, 0.62, -0.32);

  /// Slight downward tilt: puts the horizon just above the middle of the frame
  /// and leaves a band of receding floor under the board.
  static const double pitch = 0.05;

  /// Vertical field of view. Wide enough for the room to have perspective,
  /// tight enough that the board fills ~40 % of the frame height.
  static const double fovY = 0.66;

  static Camera3 forSize(Size size) => Camera3(
        eye: eye,
        viewport: size,
        pitch: pitch,
        fovY: fovY,
      );

  /// Where a screen point lands on the board plane, as a board-face offset
  /// from the bullseye ([Offset.dx] right, [Offset.dy] **up**), in metres.
  ///
  /// [Camera3.screenToGround] does this for a horizontal plane; the board is
  /// vertical, so this is its `z == boardZ` twin. Same inverse rotation, solved
  /// for z instead of y.
  static Offset? screenToBoard(Camera3 camera, Offset screen) {
    final f = camera.focal;
    final cx = screen.dx - camera.viewport.width / 2;
    final cy = camera.viewport.height / 2 - screen.dy;
    final dirCam = Vec3(cx / f, cy / f, 1);
    final c = math.cos(camera.pitch);
    final s = math.sin(camera.pitch);
    final dir = Vec3(
      dirCam.x,
      dirCam.y * c - dirCam.z * s,
      dirCam.y * s + dirCam.z * c,
    );
    if (dir.z.abs() < 1e-9) return null;
    final t = (DartsWorld.boardZ - camera.eye.z) / dir.z;
    if (t <= 0) return null;
    final p = camera.eye + dir * t;
    return Offset(p.x, p.y - DartsWorld.boardCentreY);
  }
}

/// A dart left in the board for the rest of the visit.
class StuckDart {
  /// Board-face offset from the bullseye, metres.
  final double boardX;
  final double boardY;

  /// Unit direction of travel at impact — the angle it protrudes at.
  final Vec3 direction;

  /// Owner accent (the flight colour).
  final Color color;

  final DartHit hit;

  const StuckDart({
    required this.boardX,
    required this.boardY,
    required this.direction,
    required this.color,
    required this.hit,
  });
}

/// Everything [paintDartsScene] needs, and nothing else.
///
/// No controller, no ticker, no engine handle: the painter is a pure function
/// of this value, which is what makes the whole scene snapshot-testable.
@immutable
class DartsView {
  /// Darts currently stuck in the board (this visit).
  final List<StuckDart> stuck;

  /// The dart in flight, if any.
  final Vec3? dartPosition;
  final Vec3? dartVelocity;

  /// Accent of the dart in flight / about to be thrown.
  final Color dartColor;

  /// The live swipe, in canvas pixels: where the finger went down and where it
  /// is now. **Both null at rest** — nothing hovers on the board when nobody is
  /// touching the screen. There is no cursor in this game; the swipe is the aim.
  final Offset? swipeFrom;
  final Offset? swipeTo;

  /// 0..1 flick power while a throw drag is live.
  final double power;

  /// 0..1 decaying wobble after a stick, and where it is centred.
  final double wobble;
  final double wobbleX;
  final double wobbleY;

  const DartsView({
    this.stuck = const [],
    this.dartPosition,
    this.dartVelocity,
    this.dartColor = const Color(0xFFD8443C),
    this.swipeFrom,
    this.swipeTo,
    this.power = 0,
    this.wobble = 0,
    this.wobbleX = 0,
    this.wobbleY = 0,
  });

  /// True while a throw swipe is being drawn.
  bool get dragging => swipeFrom != null && swipeTo != null;
}

/// Paints the whole first-person scene.
///
/// Pure: same [size] + [view] + [style] always produce the same pixels. Order
/// is the painter's algorithm — the room, then everything with a world anchor
/// sorted far-to-near through [Scene3].
void paintDartsScene(
  Canvas canvas,
  Size size,
  DartsView view,
  DartsStyle style,
  ColorScheme scheme,
) {
  if (size.width <= 0 || size.height <= 0) return;
  final camera = DartsCamera.forSize(size);

  canvas.save();
  canvas.clipRect(Offset.zero & size);

  _paintRoom(canvas, size, camera, style);

  final scene = Scene3(camera);

  // The board itself, anchored at its face.
  scene.add(
    Vec3(0, DartsWorld.boardCentreY, DartsWorld.boardZ),
    (c, at) => _paintBoard(c, camera, style, view),
  );

  // Floor shadow of the dart in flight — on the floor plane, so it sorts with
  // the room rather than with the dart.
  final flying = view.dartPosition;
  if (flying != null) {
    scene.add(
      Vec3(flying.x, DartsWorld.floorY, flying.z),
      (c, at) => _paintShadow(c, camera, flying),
    );
  }

  for (final dart in view.stuck) {
    final tip = DartsWorld.boardPoint(dart.boardX, dart.boardY);
    scene.add(
      tip - dart.direction * (DartsWorld.dartLength * 0.5),
      (c, at) => _paintDart(c, camera, tip, dart.direction, dart.color),
    );
  }

  if (flying != null) {
    final dir = (view.dartVelocity ?? const Vec3(0, 0, 1)).normalized;
    scene.add(
      flying,
      (c, at) => _paintDart(c, camera, flying, dir, view.dartColor),
    );
  }

  scene.paint(canvas);

  // Swipe feedback, and only while a swipe is live.
  if (view.dragging) {
    _paintSwipeArrow(canvas, view);
    _paintPowerMeter(canvas, size, view);
  }

  canvas.restore();
}

// ---------------------------------------------------------------------------
// Room
// ---------------------------------------------------------------------------

void _paintRoom(Canvas canvas, Size size, Camera3 camera, DartsStyle style) {
  final rect = Offset.zero & size;

  // Back wall fills the frame; the floor is painted over its lower part.
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        [
          Color.lerp(style.wall, Colors.black, 0.45)!,
          style.wall,
          Color.lerp(style.wall, Colors.black, 0.25)!,
        ],
        const [0.0, 0.42, 1.0],
      ),
  );

  // Pool of light on the wall behind the board.
  final boardCentre =
      camera.project(Vec3(0, DartsWorld.boardCentreY, DartsWorld.wallZ));
  if (boardCentre.visible) {
    final glow = DartsWorld.surroundRadius * 3.4 * boardCentre.scale;
    canvas.drawCircle(
      boardCentre.screen,
      glow,
      Paint()
        ..shader = ui.Gradient.radial(
          boardCentre.screen,
          glow,
          [
            Colors.white.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.0),
          ],
          const [0.0, 0.55, 1.0],
        ),
    );
  }

  // Floor: the quad from the wall/floor junction down to the bottom of frame.
  final junctionL =
      camera.project(Vec3(-6, DartsWorld.floorY, DartsWorld.wallZ));
  final junctionR =
      camera.project(Vec3(6, DartsWorld.floorY, DartsWorld.wallZ));
  if (junctionL.visible && junctionR.visible) {
    final junctionY = (junctionL.screen.dy + junctionR.screen.dy) / 2;
    if (junctionY < size.height) {
      final floorRect = Rect.fromLTRB(0, junctionY, size.width, size.height);
      canvas.save();
      canvas.clipRect(floorRect);
      canvas.drawRect(
        floorRect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, junctionY),
            Offset(0, size.height),
            [
              Color.lerp(style.floor, style.wall, 0.5)!,
              Color.lerp(style.floor, Colors.white, 0.12)!,
              style.floor,
            ],
            const [0.0, 0.45, 1.0],
          ),
      );

      // Plank seams running down-range: parallel in the world, converging on
      // the vanishing point on screen. This is the depth cue that sells the
      // room, so the lines are projected rather than fanned by eye.
      final seam = Paint()
        ..color = Colors.black.withValues(alpha: 0.42)
        ..strokeWidth = math.max(0.8, size.width * 0.0025)
        ..style = PaintingStyle.stroke;
      for (var i = -8; i <= 8; i++) {
        final x = i * 0.26;
        final near = camera.project(Vec3(x, DartsWorld.floorY, -0.2));
        final far =
            camera.project(Vec3(x, DartsWorld.floorY, DartsWorld.wallZ));
        if (!near.visible || !far.visible) continue;
        canvas.drawLine(near.screen, far.screen, seam);
      }
      // Cross seams: real horizontal lines, so their spacing compresses with
      // depth on its own.
      for (var i = 0; i < 12; i++) {
        final z = 0.1 + i * 0.34;
        if (z > DartsWorld.wallZ) break;
        final l = camera.project(Vec3(-6, DartsWorld.floorY, z));
        final r = camera.project(Vec3(6, DartsWorld.floorY, z));
        if (!l.visible || !r.visible) continue;
        canvas.drawLine(
          l.screen,
          r.screen,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.07)
            ..strokeWidth = math.max(0.7, size.width * 0.002),
        );
      }
      canvas.restore();

      // Skirting board at the junction.
      canvas.drawLine(
        Offset(0, junctionY),
        Offset(size.width, junctionY),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.5)
          ..strokeWidth = math.max(1.2, size.height * 0.006),
      );
    }
  }

  // Haze: a thin veil of wall colour over the far half of the frame, so depth
  // reads even where geometry is sparse.
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, camera.horizonY - size.height * 0.25),
        Offset(0, size.height),
        [
          style.wall.withValues(alpha: 0.22),
          style.wall.withValues(alpha: 0.0),
        ],
      ),
  );
}

// ---------------------------------------------------------------------------
// Board
// ---------------------------------------------------------------------------

/// Project a point on the board face (metres from the bullseye) to the canvas.
Offset? _boardPoint(Camera3 camera, double bx, double by) {
  final p = camera.project(DartsWorld.boardPoint(bx, by));
  return p.visible ? p.screen : null;
}

/// Pixels per metre at the board face.
double _boardScale(Camera3 camera) {
  final p = camera.project(
      Vec3(0, DartsWorld.boardCentreY, DartsWorld.boardZ));
  return p.visible ? p.scale : 0;
}

/// A circle on the board face, projected honestly (never an ellipse with a
/// guessed aspect — see [Camera3.horizontalCirclePath] for the same discipline
/// on the horizontal plane).
Path? _boardCircle(Camera3 camera, double radius, {int segments = 72}) {
  final path = Path();
  for (var i = 0; i < segments; i++) {
    final a = 2 * math.pi * i / segments;
    final p = _boardPoint(camera, math.sin(a) * radius, math.cos(a) * radius);
    if (p == null) return null;
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

/// An annular wedge between radii [r0]..[r1] spanning clockwise angles
/// [a0]..[a1] (radians from 12 o'clock).
Path? _boardWedge(
  Camera3 camera,
  double r0,
  double r1,
  double a0,
  double a1, {
  int segments = 8,
}) {
  final path = Path();
  var first = true;
  for (var i = 0; i <= segments; i++) {
    final a = a0 + (a1 - a0) * i / segments;
    final p = _boardPoint(camera, math.sin(a) * r1, math.cos(a) * r1);
    if (p == null) return null;
    if (first) {
      path.moveTo(p.dx, p.dy);
      first = false;
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  for (var i = segments; i >= 0; i--) {
    final a = a0 + (a1 - a0) * i / segments;
    final p = _boardPoint(camera, math.sin(a) * r0, math.cos(a) * r0);
    if (p == null) return null;
    path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

void _paintBoard(
  Canvas canvas,
  Camera3 camera,
  DartsStyle style,
  DartsView view,
) {
  final r = DartsWorld.boardRadius;
  final scale = _boardScale(camera);
  if (scale <= 0) return;

  // Surround (the black ring the numbers sit on) + a cabinet shadow.
  final surround = _boardCircle(camera, DartsWorld.surroundRadius);
  if (surround != null) {
    canvas.drawPath(
      surround.shift(Offset(0, DartsWorld.boardRadius * 0.06 * scale)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.03 * scale),
    );
    canvas.drawPath(surround, Paint()..color = style.surround);
    canvas.drawPath(
      surround,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, 0.006 * scale)
        ..color = Colors.white.withValues(alpha: 0.12),
    );
  }

  // Scoring beds. Every sector gets four bands: inner single, treble, outer
  // single, double.
  const half = DartsBoardGeometry.sectorSpan / 2;
  for (var i = 0; i < 20; i++) {
    final centre = DartsBoardGeometry.sectorCentreAngle(i);
    final a0 = centre - half;
    final a1 = centre + half;
    final darkBed = i.isEven;
    final bed = darkBed ? style.black : style.cream;
    final ring = darkBed ? style.red : style.green;

    void band(double from, double to, Color color) {
      final path = _boardWedge(camera, from * r, to * r, a0, a1);
      if (path != null) canvas.drawPath(path, Paint()..color = color);
    }

    band(DartsBoardGeometry.outerBullRatio, DartsBoardGeometry.innerTrebleRatio, bed);
    band(DartsBoardGeometry.innerTrebleRatio, DartsBoardGeometry.outerTrebleRatio, ring);
    band(DartsBoardGeometry.outerTrebleRatio, DartsBoardGeometry.innerDoubleRatio, bed);
    band(DartsBoardGeometry.innerDoubleRatio, 1.0, ring);
  }

  // Bulls.
  final outerBull = _boardCircle(camera, DartsBoardGeometry.outerBullRatio * r, segments: 40);
  if (outerBull != null) canvas.drawPath(outerBull, Paint()..color = style.green);
  final innerBull = _boardCircle(camera, DartsBoardGeometry.innerBullRatio * r, segments: 32);
  if (innerBull != null) canvas.drawPath(innerBull, Paint()..color = style.red);

  // Wire spider: ring wires + the radial separators.
  final wire = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.9, 0.0035 * scale)
    ..color = style.wire.withValues(alpha: 0.9);
  for (final ratio in const [
    DartsBoardGeometry.outerBullRatio,
    DartsBoardGeometry.innerBullRatio,
    DartsBoardGeometry.innerTrebleRatio,
    DartsBoardGeometry.outerTrebleRatio,
    DartsBoardGeometry.innerDoubleRatio,
    1.0,
  ]) {
    final circle = _boardCircle(camera, ratio * r, segments: 64);
    if (circle != null) canvas.drawPath(circle, wire);
  }
  for (var i = 0; i < 20; i++) {
    final a = DartsBoardGeometry.sectorCentreAngle(i) - half;
    final inner =
        _boardPoint(camera, math.sin(a) * DartsBoardGeometry.outerBullRatio * r,
            math.cos(a) * DartsBoardGeometry.outerBullRatio * r);
    final outer = _boardPoint(camera, math.sin(a) * r, math.cos(a) * r);
    if (inner == null || outer == null) continue;
    canvas.drawLine(inner, outer, wire);
  }

  // Number ring.
  final numberRadius = (1.0 + DartsBoardGeometry.numberRingRatio) / 2 * r;
  for (var i = 0; i < 20; i++) {
    final a = DartsBoardGeometry.sectorCentreAngle(i);
    final at = _boardPoint(
      camera,
      math.sin(a) * numberRadius,
      math.cos(a) * numberRadius,
    );
    if (at == null) continue;
    _text(
      canvas,
      at,
      '${DartsBoardGeometry.sectorOrder[i]}',
      math.max(7, 0.052 * scale),
      Colors.white.withValues(alpha: 0.92),
    );
  }

  // Wire wobble: a shiver of light on the spider where the dart just landed.
  if (view.wobble > 0) {
    final centre = _boardPoint(camera, view.wobbleX, view.wobbleY);
    if (centre != null) {
      final t = view.wobble.clamp(0.0, 1.0);
      final ringR = (0.03 + 0.10 * (1 - t)) * scale;
      canvas.drawCircle(
        centre,
        ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, 0.006 * scale * t)
          ..color = Colors.white.withValues(alpha: 0.5 * t),
      );
    }
  }

  // Board-face lighting: a soft top-left highlight and a bottom vignette.
  final face = _boardCircle(camera, r, segments: 48);
  if (face != null) {
    final bounds = face.getBounds();
    canvas.save();
    canvas.clipPath(face);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.radial(
          bounds.center.translate(-bounds.width * 0.28, -bounds.height * 0.3),
          bounds.width * 0.9,
          [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.22),
          ],
          const [0.0, 0.5, 1.0],
        ),
    );
    canvas.restore();
  }
}

// ---------------------------------------------------------------------------
// Darts
// ---------------------------------------------------------------------------

void _paintShadow(Canvas canvas, Camera3 camera, Vec3 dart) {
  final height = (dart.y - DartsWorld.floorY).clamp(0.0, 3.0);
  final radius = 0.035 + height * 0.02;
  final path = camera.horizontalCirclePath(
    Vec3(dart.x, DartsWorld.floorY + 0.001, dart.z),
    radius,
    segments: 20,
  );
  if (path == null) return;
  final alpha = (0.42 - height * 0.09).clamp(0.08, 0.42);
  canvas.drawPath(
    path,
    Paint()
      ..color = Colors.black.withValues(alpha: alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
  );
}

/// A unit vector perpendicular to [v] — the first axis of the dart's flight.
Vec3 _anyPerpendicular(Vec3 v) {
  // Cross with world-up unless the dart is (nearly) vertical, in which case
  // cross with +x instead so the result never degenerates to zero.
  final ref = v.y.abs() > 0.95 ? const Vec3(1, 0, 0) : const Vec3(0, 1, 0);
  return _cross(v, ref).normalized;
}

Vec3 _cross(Vec3 a, Vec3 b) => Vec3(
      a.y * b.z - a.z * b.y,
      a.z * b.x - a.x * b.z,
      a.x * b.y - a.y * b.x,
    );

/// Draws one dart: a point, a barrel, a shaft and a four-vane flight.
///
/// The flight is built in **world space** — four vanes at 90° around the dart's
/// own axis — and then projected. That matters here more than anywhere else in
/// the scene: a dart thrown down-range is seen almost point-on, so a
/// screen-space fin drawn as a flat triangle collapses to a smear. Projecting
/// real vanes makes a receding dart read as a shrinking cross of flights, which
/// is exactly what a dart flying away from you looks like.
void _paintDart(
  Canvas canvas,
  Camera3 camera,
  Vec3 tip,
  Vec3 direction,
  Color color,
) {
  final dir = direction.normalized;
  final tail = tip - dir * DartsWorld.dartLength;
  final pTip = camera.project(tip);
  final pTail = camera.project(tail);
  if (!pTip.visible || !pTail.visible) return;

  final scale = pTail.scale;

  // Flight geometry, in world units, at the tail.
  const vaneRadius = DartsWorld.dartLength * 0.105;
  const vaneLength = DartsWorld.dartLength * 0.30;
  final u = _anyPerpendicular(dir);
  final v = _cross(dir, u).normalized;
  final vaneBase = tail + dir * vaneLength;
  final pBase = camera.project(vaneBase);
  if (!pBase.visible) return;

  final barrelW = math.max(1.2, 0.014 * scale);

  // Shaft: tail through to where the barrel starts.
  canvas.drawLine(
    pTail.screen,
    Offset.lerp(pTail.screen, pTip.screen, 0.45)!,
    Paint()
      ..strokeWidth = math.max(0.9, barrelW * 0.9)
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF23262B),
  );

  // Barrel.
  final barrelStart = Offset.lerp(pTail.screen, pTip.screen, 0.42)!;
  final barrelEnd = Offset.lerp(pTail.screen, pTip.screen, 0.82)!;
  canvas.drawLine(
    barrelStart,
    barrelEnd,
    Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barrelW * 2.2
      ..shader = ui.Gradient.linear(
        barrelStart,
        barrelEnd == barrelStart ? barrelStart + const Offset(0, 1) : barrelEnd,
        [const Color(0xFFEDF1F6), const Color(0xFF8B929C)],
      ),
  );

  // Point.
  canvas.drawLine(
    barrelEnd,
    pTip.screen,
    Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.7, barrelW * 0.7)
      ..color = const Color(0xFFC8CDD4),
  );

  // Four vanes, projected.
  final outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.5, 0.0025 * scale)
    ..color = Colors.black.withValues(alpha: 0.5);
  final tips = <Vec3>[u, v, -u, -v];
  final corners = <Offset>[];
  for (final t in tips) {
    final p = camera.project(tail + t * vaneRadius);
    if (p.visible) corners.add(p.screen);
  }
  // Membrane across the four vane tips. Seen point-on — which is most of a
  // throw — four edge-on vanes project to four hairlines and read as a bug;
  // the membrane gives the flight the solid silhouette the eye expects. Side-on
  // it collapses to a sliver at the tail and costs nothing.
  if (corners.length == 4) {
    final membrane = Path()..addPolygon(corners, true);
    canvas.drawPath(
      membrane,
      Paint()..color = Color.lerp(color, Colors.black, 0.18)!,
    );
  }
  for (var i = 0; i < 4; i++) {
    final outer = camera.project(tail + tips[i] * vaneRadius);
    if (!outer.visible) continue;
    final vane = Path()
      ..moveTo(pTail.screen.dx, pTail.screen.dy)
      ..lineTo(outer.screen.dx, outer.screen.dy)
      ..lineTo(pBase.screen.dx, pBase.screen.dy)
      ..close();
    // Alternate shading so the four vanes separate even when nearly edge-on.
    canvas.drawPath(
      vane,
      Paint()
        ..color =
            i.isEven ? color : Color.lerp(color, Colors.black, 0.3)!,
    );
    canvas.drawPath(vane, outline);
  }
  // Nock highlight so the very tail keeps a readable point at any angle.
  canvas.drawCircle(
    pTail.screen,
    math.max(0.8, 0.006 * scale),
    Paint()..color = Color.lerp(color, Colors.white, 0.5)!,
  );
}

// ---------------------------------------------------------------------------
// Swipe feedback
//
// Two pieces, both alive only while a finger is down, and **both anchored to
// the gesture rather than to the target**:
//
// * the **arrow** — the raw drag, drawn from the touch origin to the thumb, so
//   the direction/length mapping is visible in the same place it is performed;
// * the **power bar** — a magnitude readout that survives the thumb covering
//   the arrowhead.
//
// ## Nothing is ever drawn on the board face
//
// Not a reticle, not a landing prediction, not a flight ghost. All three were
// built and cut. A predicted landing point is a crosshair whatever its
// lifetime — it puts a thing on the board to line up with, and that is the
// mental model this input is trying to get rid of. As with a real throw, the
// only mark on the board is a dart that has already arrived. The player learns
// the mapping by throwing, with the arrow and the bar as the feedback.
// ---------------------------------------------------------------------------

/// The drag itself: origin ring, tapering trail, arrowhead.
void _paintSwipeArrow(Canvas canvas, DartsView view) {
  final from = view.swipeFrom!;
  final to = view.swipeTo!;
  final delta = to - from;
  final length = delta.distance;
  if (length < 1) return;

  final dir = delta / length;
  final tint = Color.lerp(Colors.white, view.dartColor, view.power * 0.75)!;
  final width = 3.0 + 5.0 * view.power.clamp(0.0, 1.0);

  // Trail. Tapers from a hairline at the origin to full width at the thumb, so
  // it reads as motion in one direction rather than as a drawn line.
  canvas.drawPath(
    Path()
      ..addPolygon([
        from + Offset(-dir.dy, dir.dx) * 1.0,
        to + Offset(-dir.dy, dir.dx) * width,
        to + Offset(dir.dy, -dir.dx) * width,
        from + Offset(dir.dy, -dir.dx) * 1.0,
      ], true),
    Paint()..color = tint.withValues(alpha: 0.34),
  );
  canvas.drawLine(
    from,
    to,
    Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.0
      ..color = tint.withValues(alpha: 0.85),
  );

  // Origin ring — where the swipe started, so its length is measurable by eye.
  canvas.drawCircle(
    from,
    9,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.5),
  );

  // Head.
  final head = width * 2.4;
  final side = Offset(-dir.dy, dir.dx) * head * 0.62;
  canvas.drawPath(
    Path()
      ..addPolygon([to + dir * head, to - dir * head * 0.35 + side,
        to - dir * head * 0.35 - side], true),
    Paint()..color = tint.withValues(alpha: 0.95),
  );
}

void _paintPowerMeter(Canvas canvas, Size size, DartsView view) {
  final w = size.width * 0.5;
  final h = math.max(5.0, size.height * 0.012);
  final left = (size.width - w) / 2;
  // Sits in the floor band just under the board, clear of the visit strip.
  final top = size.height * 0.78;
  final track = RRect.fromRectAndRadius(
    Rect.fromLTWH(left, top, w, h),
    Radius.circular(h),
  );
  canvas.drawRRect(track, Paint()..color = Colors.black.withValues(alpha: 0.45));
  final p = view.power.clamp(0.0, 1.0);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w * p, h),
      Radius.circular(h),
    ),
    Paint()..color = Color.lerp(Colors.white, view.dartColor, 0.35)!,
  );
}

void _text(Canvas canvas, Offset centre, String text, double size, Color color) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
}
