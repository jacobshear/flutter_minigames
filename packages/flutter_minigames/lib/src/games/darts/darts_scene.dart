import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_minigames/src/engine3d/engine3d.dart';

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

/// The one light in the room, and everything that obeys it.
///
/// A single committed direction is what makes a painted scene read as lit
/// rather than as a pile of gradients: the oche lamp hangs above the board and
/// a little to the **left**, so every highlight in the frame is up-left and
/// every shadow — the cabinet on the wall, the wire on the beds, a dart on the
/// face, the skirting on the floor — falls **down-right**. Nothing in this file
/// is allowed to disagree with it.
abstract final class DartsLight {
  /// World position of the lamp — on a bracket just above the cabinet and a
  /// little left of the bull, which is where a real oche light hangs.
  static const Vec3 lamp = Vec3(-0.20, 1.315, 2.24);

  /// Unit direction the light travels.
  static final Vec3 direction = const Vec3(0.26, -0.92, 0.30).normalized;

  /// Where a shadow lands relative to its caster, as a board-face offset per
  /// metre of stand-off from the face. Right and down, from [direction].
  static const Offset faceShadow = Offset(0.30, -0.34);
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

  /// 1 the instant it arrives, decaying to 0 as it stops moving. Drives the
  /// shaft quiver — a dart that has just gone in is still vibrating, and that
  /// tremor is most of what makes the arrival read as an impact rather than as
  /// a sprite appearing.
  final double settle;

  /// 0..1 arrival speed, normalised over the throwable band. Scales how hard
  /// the shaft quivers and how far the beds are pushed, so a floated dart
  /// arrives softly and a rifled one bites.
  final double strength;

  const StuckDart({
    required this.boardX,
    required this.boardY,
    required this.direction,
    required this.color,
    required this.hit,
    this.settle = 0,
    this.strength = 1,
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
  ///
  /// This is a **displacement**, not a glow: while it runs, every point of the
  /// board face within reach of the contact point — beds, spider, numbers — is
  /// pushed along a radial ripple by [DartsBoardWarp], so the board visibly takes
  /// the hit. Nothing extra is drawn on the face to say so.
  final double wobble;
  final double wobbleX;
  final double wobbleY;

  /// 0..1 arrival speed of the dart that caused [wobble]. Scales the ripple's
  /// amplitude, so the board barely twitches for a floated dart.
  final double wobbleStrength;

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
    this.wobbleStrength = 1,
  });

  /// True while a throw swipe is being drawn.
  bool get dragging => swipeFrom != null && swipeTo != null;

  /// The live board displacement, or null when the board is at rest.
  ///
  /// Null at rest matters: with no warp the projection path is byte-for-byte
  /// the one it has always been, which is what keeps the resting board pixel
  /// identical frame to frame.
  DartsBoardWarp? get warp => wobble <= 0
      ? null
      : DartsBoardWarp(
          amount: wobble.clamp(0.0, 1.0),
          x: wobbleX,
          y: wobbleY,
          strength: wobbleStrength.clamp(0.0, 1.0),
        );
}

/// A decaying radial ripple in the board face, centred on a dart's contact
/// point.
///
/// Applied in [_boardPoint], which every piece of board art goes through — so
/// the beds, the spider, the ring wires and the numbers all shift together and
/// the board reads as one displaced surface instead of a decal with an effect
/// drawn over it.
@immutable
class DartsBoardWarp {
  /// 1 at the moment of impact, decaying to 0.
  final double amount;

  /// Contact point, board-face metres from the bullseye.
  final double x;
  final double y;

  /// 0..1 arrival speed.
  final double strength;

  const DartsBoardWarp({
    required this.amount,
    required this.x,
    required this.y,
    required this.strength,
  });

  /// How far the ripple reaches, metres. About four sector-widths at the
  /// treble — local enough that the far side of the board stays still.
  static const double reach = 0.16;

  /// Peak radial displacement at full strength, metres.
  static const double peak = 0.020;

  /// Board-face point ([bx], [by]) displaced by the ripple.
  (double, double) apply(double bx, double by) {
    final dx = bx - x;
    final dy = by - y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 1e-6 || d > reach) return (bx, by);
    // Raised cosine: full at the contact point, zero (and flat) at the edge of
    // the reach, so the displaced region has no seam.
    final falloff = 0.5 * (1 + math.cos(math.pi * d / reach));
    // The crest travels outward as the wobble decays — a shock leaving the
    // dart, not the whole patch breathing in place. The quarter-cycle head
    // start is what puts the biggest displacement on the *first* frame after
    // contact, where the eye is looking, instead of two frames later.
    final phase = 1.6 + d / reach * 4.2 - (1 - amount) * 9.0;
    final disp =
        peak * (0.35 + 0.65 * strength) * amount * falloff * math.sin(phase);
    return (bx + dx / d * disp, by + dy / d * disp);
  }
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
  final warp = view.warp;

  // The board itself, anchored at its face.
  scene.add(
    Vec3(0, DartsWorld.boardCentreY, DartsWorld.boardZ),
    (c, at) => _paintBoard(c, camera, style, view, warp),
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
    // The tip rides the ripple: a dart standing in a board that is still
    // moving has to move with it, or the displacement reads as the board
    // sliding out from under a pinned decal.
    final (wx, wy) =
        warp?.apply(dart.boardX, dart.boardY) ?? (dart.boardX, dart.boardY);
    final tip = DartsWorld.boardPoint(wx, wy);
    final dir = _quivered(dart.direction, dart.settle, dart.strength);
    scene.add(
      tip - dir * (DartsWorld.dartLength * 0.5),
      (c, at) => _paintDart(c, camera, tip, dir, dart.color, onFace: true),
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

/// Deterministic 0..1 hash — the room's grain, plank tints and mottle all come
/// from this, so the oche is different everywhere and identical every frame.
double _hash01(int i, int salt) {
  var x = (i * 0x9E3779B1 + salt * 0x85EBCA77) & 0xFFFFFFFF;
  x = (x ^ (x >>> 16)) & 0xFFFFFFFF;
  x = (x * 0x7FEB352D) & 0xFFFFFFFF;
  x = (x ^ (x >>> 15)) & 0xFFFFFFFF;
  x = (x * 0x846CA68B) & 0xFFFFFFFF;
  x = (x ^ (x >>> 16)) & 0xFFFFFFFF;
  return x / 0x100000000;
}

/// Height of the dado rail — the top of the timber panelling, just under the
/// bottom of the board's surround so the panelling reads as a base the board
/// sits above rather than as a band across it.
const double _dadoY = 0.255;

/// A quad on the floor plane, projected. Null if any corner is behind the eye.
Path? _floorQuad(Camera3 camera, double x0, double x1, double z0, double z1) {
  final corners = [
    Vec3(x0, DartsWorld.floorY, z0),
    Vec3(x1, DartsWorld.floorY, z0),
    Vec3(x1, DartsWorld.floorY, z1),
    Vec3(x0, DartsWorld.floorY, z1),
  ];
  final path = Path();
  for (var i = 0; i < corners.length; i++) {
    final q = camera.project(corners[i]);
    if (!q.visible) return null;
    if (i == 0) {
      path.moveTo(q.screen.dx, q.screen.dy);
    } else {
      path.lineTo(q.screen.dx, q.screen.dy);
    }
  }
  return path..close();
}

/// A quad on the back wall (`z == wallZ`), projected.
Path? _wallQuad(Camera3 camera, double x0, double x1, double y0, double y1,
    {double z = DartsWorld.wallZ}) {
  final corners = [
    Vec3(x0, y0, z),
    Vec3(x1, y0, z),
    Vec3(x1, y1, z),
    Vec3(x0, y1, z),
  ];
  final path = Path();
  for (var i = 0; i < corners.length; i++) {
    final q = camera.project(corners[i]);
    if (!q.visible) return null;
    if (i == 0) {
      path.moveTo(q.screen.dx, q.screen.dy);
    } else {
      path.lineTo(q.screen.dx, q.screen.dy);
    }
  }
  return path..close();
}

void _paintRoom(Canvas canvas, Size size, Camera3 camera, DartsStyle style) {
  _paintWall(canvas, size, camera, style);
  _paintFloor(canvas, size, camera, style);
  _paintLamp(canvas, camera, style);
}

// ---------------------------------------------------------------------------
// Wall: plaster above a dado rail, tongue-and-groove panelling below it, and
// one lamp's worth of light pooled on the plaster behind the board.
// ---------------------------------------------------------------------------

void _paintWall(Canvas canvas, Size size, Camera3 camera, DartsStyle style) {
  final rect = Offset.zero & size;
  final plaster = style.wall;

  // Base: darker at the ceiling and in the corners, because the lamp is low
  // and pointed at the board.
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        [
          Color.lerp(plaster, Colors.black, 0.50)!,
          Color.lerp(plaster, Colors.black, 0.20)!,
          plaster,
        ],
        const [0.0, 0.30, 0.66],
      ),
  );

  // Plaster mottle: a handful of very soft blotches, so the wall has a surface
  // rather than a gradient. Deterministic, and far too faint to compete with
  // the board.
  for (var i = 0; i < 9; i++) {
    final cx = _hash01(i, 21) * size.width;
    final cy = _hash01(i, 22) * size.height * 0.72;
    final r = size.width * (0.10 + _hash01(i, 23) * 0.22);
    final light = _hash01(i, 24) < 0.5;
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          r,
          [
            (light ? Colors.white : Colors.black)
                .withValues(alpha: 0.035 + _hash01(i, 25) * 0.03),
            Colors.transparent,
          ],
        ),
    );
  }

  // The pool of light the lamp throws on the plaster. Centred a little above
  // the bull and a little left of it, which is where [DartsLight.lamp] is.
  final pool = camera.project(
      Vec3(-0.10, DartsWorld.boardCentreY + 0.30, DartsWorld.wallZ));
  if (pool.visible) {
    final glow = DartsWorld.surroundRadius * 4.2 * pool.scale;
    canvas.save();
    canvas.translate(pool.screen.dx, pool.screen.dy);
    // Squashed vertically: a lamp close to the wall pools an ellipse, not a
    // disc, and the ellipse is what says the light comes from above.
    canvas.scale(1.0, 0.78);
    canvas.drawCircle(
      Offset.zero,
      glow,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          glow,
          [
            const Color(0xFFFFF2D8).withValues(alpha: 0.26),
            const Color(0xFFFFE9C4).withValues(alpha: 0.09),
            Colors.transparent,
          ],
          const [0.0, 0.5, 1.0],
        ),
    );
    canvas.restore();
  }

  // Tongue-and-groove panelling below the dado rail.
  final panel = _wallQuad(camera, -6, 6, DartsWorld.floorY, _dadoY);
  if (panel != null) {
    final bounds = panel.getBounds();
    canvas.save();
    canvas.clipPath(panel);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(
          bounds.topCenter,
          bounds.bottomCenter,
          [
            Color.lerp(style.floor, Colors.black, 0.34)!,
            Color.lerp(style.floor, Colors.black, 0.58)!,
          ],
        ),
    );
    // Board joints, projected so they converge with the room.
    for (var i = -26; i <= 26; i++) {
      final x = i * 0.115;
      final top = camera.project(Vec3(x, _dadoY, DartsWorld.wallZ));
      final bottom =
          camera.project(Vec3(x, DartsWorld.floorY, DartsWorld.wallZ));
      if (!top.visible || !bottom.visible) continue;
      // Groove: a dark line with a lit lip on its up-left side.
      canvas.drawLine(
        top.screen,
        bottom.screen,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.45)
          ..strokeWidth = math.max(0.8, top.scale * 0.006),
      );
      canvas.drawLine(
        top.screen.translate(-1.1, 0),
        bottom.screen.translate(-1.1, 0),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.07)
          ..strokeWidth = math.max(0.6, top.scale * 0.004),
      );
    }
    canvas.restore();
  }

  // Dado rail: a real moulding with a lit top edge and a shadow beneath.
  final railTop = camera.project(Vec3(0, _dadoY + 0.035, DartsWorld.wallZ));
  final railBottom = camera.project(Vec3(0, _dadoY, DartsWorld.wallZ));
  if (railTop.visible && railBottom.visible) {
    final top = railTop.screen.dy;
    final bottom = railBottom.screen.dy;
    canvas.drawRect(
      Rect.fromLTRB(0, top, size.width, bottom),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, top),
          Offset(0, bottom),
          [
            Color.lerp(style.floor, Colors.white, 0.22)!,
            Color.lerp(style.floor, Colors.black, 0.45)!,
          ],
        ),
    );
    canvas.drawLine(
      Offset(0, top),
      Offset(size.width, top),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.16)
        ..strokeWidth = 1,
    );
    canvas.drawRect(
      Rect.fromLTRB(0, bottom, size.width, bottom + 3),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
  }
}

// ---------------------------------------------------------------------------
// Floor: boards, a rubber throw mat, and the lamp's spill.
// ---------------------------------------------------------------------------

void _paintFloor(Canvas canvas, Size size, Camera3 camera, DartsStyle style) {
  final junctionL =
      camera.project(Vec3(-6, DartsWorld.floorY, DartsWorld.wallZ));
  final junctionR =
      camera.project(Vec3(6, DartsWorld.floorY, DartsWorld.wallZ));
  if (!junctionL.visible || !junctionR.visible) return;
  final junctionY = (junctionL.screen.dy + junctionR.screen.dy) / 2;
  if (junctionY >= size.height) return;

  final floorRect = Rect.fromLTRB(0, junctionY, size.width, size.height);
  canvas.save();
  canvas.clipRect(floorRect);

  // Base wash — dark at the wall (the lamp does not reach the skirting), warm
  // through the middle where the spill lands, dark again at the near edge.
  canvas.drawRect(
    floorRect,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, junctionY),
        Offset(0, size.height),
        [
          Color.lerp(style.floor, Colors.black, 0.52)!,
          Color.lerp(style.floor, Colors.white, 0.16)!,
          Color.lerp(style.floor, Colors.black, 0.18)!,
        ],
        const [0.0, 0.42, 1.0],
      ),
  );

  const plankWidth = 0.26;
  const nearZ = 0.45;

  // Boards. Each is a projected quad with its own tint and a little grain, so
  // the floor is timber rather than a brown gradient with lines on it.
  for (var i = -9; i <= 8; i++) {
    final x0 = i * plankWidth;
    final quad = _floorQuad(camera, x0, x0 + plankWidth, nearZ, DartsWorld.wallZ);
    if (quad == null) continue;
    final tint = (_hash01(i, 31) - 0.5) * 0.16;
    canvas.drawPath(
      quad,
      Paint()
        ..color = Color.lerp(
          style.floor,
          tint > 0 ? Colors.white : Colors.black,
          tint.abs(),
        )!
            .withValues(alpha: 0.55),
    );
    // Grain: two off-centre streaks per board, running with the boards.
    for (var g = 0; g < 2; g++) {
      final fx = x0 + plankWidth * (0.25 + 0.5 * _hash01(i * 3 + g, 32));
      final near = camera.project(Vec3(fx, DartsWorld.floorY, nearZ));
      final far = camera.project(Vec3(fx, DartsWorld.floorY, DartsWorld.wallZ));
      if (!near.visible || !far.visible) continue;
      canvas.drawLine(
        near.screen,
        far.screen,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.06 + _hash01(i + g, 33) * 0.06)
          ..strokeWidth = math.max(0.7, size.width * 0.0022),
      );
    }
  }

  // Board joints: dark seam, lit lip on the up-left side (the lamp is left).
  for (var i = -9; i <= 9; i++) {
    final x = i * plankWidth;
    final near = camera.project(Vec3(x, DartsWorld.floorY, nearZ));
    final far = camera.project(Vec3(x, DartsWorld.floorY, DartsWorld.wallZ));
    if (!near.visible || !far.visible) continue;
    canvas.drawLine(
      near.screen,
      far.screen,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..strokeWidth = math.max(0.9, size.width * 0.0026),
    );
    canvas.drawLine(
      near.screen.translate(-1.4, 0),
      far.screen.translate(-0.5, 0),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.06)
        ..strokeWidth = math.max(0.7, size.width * 0.0018),
    );
  }

  // Butt joints between boards: real horizontal lines, so the spacing
  // compresses with depth on its own.
  for (var i = 0; i < 12; i++) {
    final z = 0.6 + i * 0.34;
    if (z > DartsWorld.wallZ) break;
    final l = camera.project(Vec3(-6, DartsWorld.floorY, z));
    final r = camera.project(Vec3(6, DartsWorld.floorY, z));
    if (!l.visible || !r.visible) continue;
    canvas.drawLine(
      l.screen,
      r.screen,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16)
        ..strokeWidth = math.max(0.7, size.width * 0.002),
    );
  }

  // The lamp's spill on the floor under the board — the other half of the
  // proof that there is one light in this room.
  final spill = camera.horizontalCirclePath(
    const Vec3(-0.08, DartsWorld.floorY + 0.001, 2.02),
    0.95,
    segments: 28,
  );
  if (spill != null) {
    final b = spill.getBounds();
    canvas.save();
    canvas.clipPath(spill);
    canvas.drawRect(
      b,
      Paint()
        ..shader = ui.Gradient.radial(
          b.center,
          b.longestSide / 2,
          [
            const Color(0xFFFFE9C4).withValues(alpha: 0.16),
            Colors.transparent,
          ],
        ),
    );
    canvas.restore();
  }

  _paintThrowMat(canvas, size, camera);

  canvas.restore();

  // Skirting: a board with height and a shadow line under it, not a stroke.
  final skirtTop = camera.project(Vec3(0, 0.055, DartsWorld.wallZ));
  if (skirtTop.visible) {
    final top = skirtTop.screen.dy;
    canvas.drawRect(
      Rect.fromLTRB(0, top, size.width, junctionY),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, top),
          Offset(0, junctionY),
          [
            Color.lerp(style.floor, Colors.black, 0.42)!,
            Color.lerp(style.floor, Colors.black, 0.70)!,
          ],
        ),
    );
    canvas.drawLine(
      Offset(0, top),
      Offset(size.width, top),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..strokeWidth = 1,
    );
    canvas.drawRect(
      Rect.fromLTRB(0, junctionY, size.width, junctionY + 4),
      Paint()..color = Colors.black.withValues(alpha: 0.34),
    );
  }
}

/// The rubber throw mat running away from the player toward the board, with
/// its distance marking across it.
///
/// The regulation oche itself is 2.37 m back — behind the camera and out of
/// frame by construction — so what is drawn here is the mat the player is
/// standing on receding to the wall, which is the part of it you would
/// actually see from the throw.
void _paintThrowMat(Canvas canvas, Size size, Camera3 camera) {
  const halfWidth = 0.27;
  const nearZ = 1.05;
  const farZ = DartsWorld.wallZ - 0.03;

  final mat = _floorQuad(camera, -halfWidth, halfWidth, nearZ, farZ);
  if (mat == null) return;
  canvas.drawPath(
    mat,
    Paint()..color = const Color(0xFF1B1E24).withValues(alpha: 0.78),
  );

  // Lit up-left edge, shadowed down-right edge: the mat has thickness.
  final edges = [
    (-halfWidth, Colors.white.withValues(alpha: 0.12)),
    (halfWidth, Colors.black.withValues(alpha: 0.5)),
  ];
  for (final (x, color) in edges) {
    final near = camera.project(Vec3(x, DartsWorld.floorY, nearZ));
    final far = camera.project(Vec3(x, DartsWorld.floorY, farZ));
    if (!near.visible || !far.visible) continue;
    canvas.drawLine(
      near.screen,
      far.screen,
      Paint()
        ..color = color
        ..strokeWidth = math.max(1, size.width * 0.004),
    );
  }

  // The throw line: the mat's own marking, painted across it.
  const markZ = 1.62;
  final l = camera.project(
      const Vec3(-halfWidth + 0.06, DartsWorld.floorY, markZ));
  final r =
      camera.project(const Vec3(halfWidth - 0.06, DartsWorld.floorY, markZ));
  if (l.visible && r.visible) {
    canvas.drawLine(
      l.screen,
      r.screen,
      Paint()
        ..color = const Color(0xFFD8D2C2).withValues(alpha: 0.32)
        ..strokeWidth = math.max(1.2, l.scale * 0.008),
    );
  }
}

/// The oche lamp: a shaded bar on a bracket above the board, and the cone it
/// throws down onto the face.
void _paintLamp(Canvas canvas, Camera3 camera, DartsStyle style) {
  final lamp = DartsLight.lamp;
  final left = camera.project(Vec3(lamp.x - 0.24, lamp.y, lamp.z));
  final right = camera.project(Vec3(lamp.x + 0.24, lamp.y, lamp.z));
  final anchor = camera.project(Vec3(lamp.x, lamp.y + 0.16, DartsWorld.wallZ));
  if (!left.visible || !right.visible || !anchor.visible) return;

  // Cone of light down onto the board. Drawn before the board, so the board's
  // own art sits inside the light rather than under a wash.
  final spreadL =
      camera.project(Vec3(-DartsWorld.surroundRadius * 1.5, DartsWorld.boardCentreY - 0.42, DartsWorld.wallZ));
  final spreadR =
      camera.project(Vec3(DartsWorld.surroundRadius * 1.5, DartsWorld.boardCentreY - 0.42, DartsWorld.wallZ));
  if (spreadL.visible && spreadR.visible) {
    final cone = Path()
      ..moveTo(left.screen.dx, left.screen.dy)
      ..lineTo(right.screen.dx, right.screen.dy)
      ..lineTo(spreadR.screen.dx, spreadR.screen.dy)
      ..lineTo(spreadL.screen.dx, spreadL.screen.dy)
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = ui.Gradient.linear(
          left.screen,
          spreadL.screen,
          [
            const Color(0xFFFFF0D2).withValues(alpha: 0.13),
            Colors.transparent,
          ],
        ),
    );
  }

  // Bracket back to the wall.
  canvas.drawLine(
    anchor.screen,
    Offset((left.screen.dx + right.screen.dx) / 2, left.screen.dy - 3),
    Paint()
      ..color = const Color(0xFF1A1D22)
      ..strokeWidth = math.max(1.4, left.scale * 0.014)
      ..strokeCap = StrokeCap.round,
  );

  // Shade: dark on top, blazing along the bottom lip.
  final height = math.max(4.0, left.scale * 0.040);
  final shade = Rect.fromLTRB(
    left.screen.dx,
    left.screen.dy - height,
    right.screen.dx,
    left.screen.dy,
  );
  canvas.drawRRect(
    RRect.fromRectAndCorners(
      shade,
      topLeft: Radius.circular(height * 0.5),
      topRight: Radius.circular(height * 0.5),
    ),
    Paint()
      ..shader = ui.Gradient.linear(
        shade.topCenter,
        shade.bottomCenter,
        [const Color(0xFF2C3038), const Color(0xFF14161A)],
      ),
  );
  canvas.drawLine(
    shade.bottomLeft,
    shade.bottomRight,
    Paint()
      ..color = const Color(0xFFFFF3DA)
      ..strokeWidth = math.max(1.4, height * 0.28)
      ..strokeCap = StrokeCap.round,
  );
}

// ---------------------------------------------------------------------------
// Board
// ---------------------------------------------------------------------------

/// Project a point on the board face (metres from the bullseye) to the canvas,
/// through the live impact ripple.
///
/// **Every** piece of board art goes through here — beds, spider, ring wires,
/// numbers, and the tip of a stuck dart — which is what makes a wobble read as
/// the surface being displaced rather than as an effect drawn over a static
/// picture. With no [warp] the arithmetic is exactly what it always was.
Offset? _boardPoint(Camera3 camera, double bx, double by, [DartsBoardWarp? warp]) {
  final (x, y) = warp?.apply(bx, by) ?? (bx, by);
  final p = camera.project(DartsWorld.boardPoint(x, y));
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
Path? _boardCircle(Camera3 camera, double radius,
    {int segments = 72, DartsBoardWarp? warp}) {
  final path = Path();
  for (var i = 0; i < segments; i++) {
    final a = 2 * math.pi * i / segments;
    final p =
        _boardPoint(camera, math.sin(a) * radius, math.cos(a) * radius, warp);
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
  DartsBoardWarp? warp,
}) {
  final path = Path();
  var first = true;
  for (var i = 0; i <= segments; i++) {
    final a = a0 + (a1 - a0) * i / segments;
    final p = _boardPoint(camera, math.sin(a) * r1, math.cos(a) * r1, warp);
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
    final p = _boardPoint(camera, math.sin(a) * r0, math.cos(a) * r0, warp);
    if (p == null) return null;
    path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

/// Radius of the cabinet the board is hung in, as a fraction of the surround.
const double _cabinetRatio = 1.115;

void _paintBoard(
  Canvas canvas,
  Camera3 camera,
  DartsStyle style,
  DartsView view,
  DartsBoardWarp? warp,
) {
  final r = DartsWorld.boardRadius;
  final scale = _boardScale(camera);
  if (scale <= 0) return;

  _paintCabinet(canvas, camera, style, scale);
  _paintSurround(canvas, camera, style, scale, warp);
  _paintBeds(canvas, camera, style, r, scale, warp);
  _paintSpider(canvas, camera, style, r, scale, warp);
  _paintNumbers(canvas, camera, r, scale, warp);
  _paintFaceLight(canvas, camera, r, warp);
}

/// The cabinet: a wooden ring the board is bolted into, with a visible edge and
/// its shadow thrown onto the plaster down-right of it.
void _paintCabinet(
  Canvas canvas,
  Camera3 camera,
  DartsStyle style,
  double scale,
) {
  final cabinetR = DartsWorld.surroundRadius * _cabinetRatio;
  final face = _boardCircle(camera, cabinetR, segments: 64);
  if (face == null) return;

  // Shadow on the wall. Down-right, because the lamp is up-left.
  canvas.drawPath(
    face.shift(Offset(0.055 * scale, 0.045 * scale)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.42)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.035 * scale),
  );

  // The cabinet's own thickness: the same disc pushed away from the light, so
  // its rim shows on the shadow side and the board stands off the wall.
  canvas.drawPath(
    face.shift(Offset(0.016 * scale, 0.013 * scale)),
    Paint()..color = const Color(0xFF241A12),
  );

  final bounds = face.getBounds();
  canvas.drawPath(
    face,
    Paint()
      ..shader = ui.Gradient.radial(
        bounds.center.translate(-bounds.width * 0.3, -bounds.height * 0.34),
        bounds.width * 0.95,
        [
          const Color(0xFF6B4A2E),
          const Color(0xFF4A3220),
          const Color(0xFF2B1D13),
        ],
        const [0.0, 0.55, 1.0],
      ),
  );
  // Lit lip up-left, dark lip down-right — the bevel that gives it depth.
  canvas.drawPath(
    face,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, 0.007 * scale)
      ..color = Colors.white.withValues(alpha: 0.10),
  );
  canvas.drawPath(
    face.shift(Offset(0.006 * scale, 0.005 * scale)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, 0.006 * scale)
      ..color = Colors.black.withValues(alpha: 0.45),
  );
}

/// The black number ring, as pressed steel rather than a flat fill: a graded
/// face, a bevel that obeys the lamp, and a wire around its rim.
void _paintSurround(
  Canvas canvas,
  Camera3 camera,
  DartsStyle style,
  double scale,
  DartsBoardWarp? warp,
) {
  final surround = _boardCircle(camera, DartsWorld.surroundRadius,
      segments: warp == null ? 72 : 144, warp: warp);
  if (surround == null) return;
  final bounds = surround.getBounds();

  // Recess shadow where the board sits down inside the cabinet.
  canvas.drawPath(
    surround.shift(Offset(-0.008 * scale, -0.007 * scale)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.012 * scale),
  );

  canvas.drawPath(
    surround,
    Paint()
      ..shader = ui.Gradient.radial(
        bounds.center.translate(-bounds.width * 0.26, -bounds.height * 0.30),
        bounds.width * 0.85,
        [
          Color.lerp(style.surround, Colors.white, 0.16)!,
          Color.lerp(style.surround, Colors.white, 0.04)!,
          style.surround,
        ],
        const [0.0, 0.5, 1.0],
      ),
  );

  // Rim wire: the steel band round the numbers, lit on its up-left arc.
  canvas.drawPath(
    surround,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, 0.0055 * scale)
      ..color = Color.lerp(style.wire, Colors.black, 0.45)!,
  );
  canvas.drawPath(
    surround.shift(Offset(-0.0035 * scale, -0.003 * scale)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, 0.0028 * scale)
      ..color = Color.lerp(style.wire, Colors.white, 0.45)!
          .withValues(alpha: 0.75),
  );
}

/// The scoring beds, with the sisal's grain in them.
void _paintBeds(
  Canvas canvas,
  Camera3 camera,
  DartsStyle style,
  double r,
  double scale,
  DartsBoardWarp? warp,
) {
  const half = DartsBoardGeometry.sectorSpan / 2;
  for (var i = 0; i < 20; i++) {
    final centre = DartsBoardGeometry.sectorCentreAngle(i);
    final a0 = centre - half;
    final a1 = centre + half;
    final darkBed = i.isEven;
    final bed = darkBed ? style.black : style.cream;
    final ring = darkBed ? style.red : style.green;

    // A displaced bed needs more segments than a flat one: the ripple is
    // finer than an eight-step arc, and under-sampling it turns a smooth bow
    // into a visible kink. It only costs anything for the half second a
    // wobble is running.
    final segments = warp == null ? 8 : 26;

    void band(double from, double to, Color color) {
      final path = _boardWedge(camera, from * r, to * r, a0, a1,
          segments: segments, warp: warp);
      if (path != null) canvas.drawPath(path, Paint()..color = color);
    }

    band(DartsBoardGeometry.outerBullRatio,
        DartsBoardGeometry.innerTrebleRatio, bed);
    band(DartsBoardGeometry.innerTrebleRatio,
        DartsBoardGeometry.outerTrebleRatio, ring);
    band(DartsBoardGeometry.outerTrebleRatio,
        DartsBoardGeometry.innerDoubleRatio, bed);
    band(DartsBoardGeometry.innerDoubleRatio, 1.0, ring);
  }

  // Sisal grain: compressed fibre runs outward from the bull, so the hairlines
  // are radial. They are deliberately kept off the sector centre lines — the
  // middle of a bed is where the eye aims and where the scorer is sampled, and
  // neither wants a stripe through it.
  const offsets = [-0.40, -0.24, 0.17, 0.33];
  final grain = Paint()
    ..strokeWidth = math.max(0.6, 0.0016 * scale)
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 20; i++) {
    final centre = DartsBoardGeometry.sectorCentreAngle(i);
    for (var k = 0; k < offsets.length; k++) {
      final a = centre + offsets[k] * DartsBoardGeometry.sectorSpan;
      final h = _hash01(i * 7 + k, 41);
      final from = (0.20 + h * 0.16) * r;
      final to = (0.86 + _hash01(i * 7 + k, 42) * 0.13) * r;
      final p0 = _boardPoint(camera, math.sin(a) * from, math.cos(a) * from, warp);
      final p1 = _boardPoint(camera, math.sin(a) * to, math.cos(a) * to, warp);
      if (p0 == null || p1 == null) continue;
      final light = _hash01(i * 7 + k, 43) < 0.5;
      grain.color = (light ? Colors.white : Colors.black)
          .withValues(alpha: light ? 0.05 : 0.045);
      canvas.drawLine(p0, p1, grain);
    }
  }

  // Bulls, painted after the grain — they are a separate cut of sisal.
  final outerBull = _boardCircle(
      camera, DartsBoardGeometry.outerBullRatio * r,
      segments: warp == null ? 40 : 96, warp: warp);
  if (outerBull != null) {
    canvas.drawPath(outerBull, Paint()..color = style.green);
  }
  final innerBull = _boardCircle(
      camera, DartsBoardGeometry.innerBullRatio * r,
      segments: 32, warp: warp);
  if (innerBull != null) {
    canvas.drawPath(innerBull, Paint()..color = style.red);
  }
}

/// The spider: ring wires and radial separators, drawn as wire that stands
/// proud of the beds — a shadow on its down-right side, a steel body, and a
/// specular line along its up-left edge.
void _paintSpider(
  Canvas canvas,
  Camera3 camera,
  DartsStyle style,
  double r,
  double scale,
  DartsBoardWarp? warp,
) {
  const half = DartsBoardGeometry.sectorSpan / 2;
  final body = math.max(0.9, 0.0032 * scale);
  final lift = math.max(0.7, 0.0022 * scale);

  final shadow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = body
    ..color = Colors.black.withValues(alpha: 0.5);
  final steel = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = body
    ..color = Color.lerp(style.wire, Colors.black, 0.18)!;
  final gleam = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.6, body * 0.42)
    ..color = Color.lerp(style.wire, Colors.white, 0.65)!
        .withValues(alpha: 0.85);

  const ratios = [
    DartsBoardGeometry.outerBullRatio,
    DartsBoardGeometry.innerBullRatio,
    DartsBoardGeometry.innerTrebleRatio,
    DartsBoardGeometry.outerTrebleRatio,
    DartsBoardGeometry.innerDoubleRatio,
    1.0,
  ];
  for (final ratio in ratios) {
    final circle =
        _boardCircle(camera, ratio * r, segments: warp == null ? 64 : 160, warp: warp);
    if (circle == null) continue;
    canvas.drawPath(circle.shift(Offset(lift * 0.8, lift * 0.7)), shadow);
    canvas.drawPath(circle, steel);
    canvas.drawPath(circle.shift(Offset(-lift * 0.5, -lift * 0.45)), gleam);
  }

  for (var i = 0; i < 20; i++) {
    final a = DartsBoardGeometry.sectorCentreAngle(i) - half;
    const bull = DartsBoardGeometry.outerBullRatio;
    final inner = _boardPoint(
        camera, math.sin(a) * bull * r, math.cos(a) * bull * r, warp);
    final outer = _boardPoint(camera, math.sin(a) * r, math.cos(a) * r, warp);
    if (inner == null || outer == null) continue;
    final drop = Offset(lift * 0.8, lift * 0.7);
    final rise = Offset(-lift * 0.5, -lift * 0.45);
    canvas.drawLine(inner + drop, outer + drop, shadow);
    canvas.drawLine(inner, outer, steel);
    canvas.drawLine(inner + rise, outer + rise, gleam);
  }
}

/// The numbers, pressed into the ring: a shadow away from the lamp under a
/// bright face, so they read as embossed rather than printed.
void _paintNumbers(
  Canvas canvas,
  Camera3 camera,
  double r,
  double scale,
  DartsBoardWarp? warp,
) {
  final numberRadius = (1.0 + DartsBoardGeometry.numberRingRatio) / 2 * r;
  final size = math.max(7.0, 0.052 * scale);
  for (var i = 0; i < 20; i++) {
    final a = DartsBoardGeometry.sectorCentreAngle(i);
    final at = _boardPoint(
      camera,
      math.sin(a) * numberRadius,
      math.cos(a) * numberRadius,
      warp,
    );
    if (at == null) continue;
    final label = '${DartsBoardGeometry.sectorOrder[i]}';
    _text(canvas, at.translate(size * 0.06, size * 0.06), label, size,
        Colors.black.withValues(alpha: 0.75));
    _text(canvas, at, label, size, const Color(0xFFF2EFE8));
  }
}

/// The lamp on the face: a highlight up-left of the bull, falling away to a
/// vignette down-right. The only board-wide lighting there is, and it points
/// the same way as everything else in the room.
void _paintFaceLight(
    Canvas canvas, Camera3 camera, double r, DartsBoardWarp? warp) {
  final face =
      _boardCircle(camera, r, segments: warp == null ? 48 : 144, warp: warp);
  if (face == null) return;
  final bounds = face.getBounds();
  canvas.save();
  canvas.clipPath(face);
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = ui.Gradient.radial(
        bounds.center.translate(-bounds.width * 0.28, -bounds.height * 0.32),
        bounds.width * 0.92,
        [
          const Color(0xFFFFF6E4).withValues(alpha: 0.13),
          Colors.white.withValues(alpha: 0.0),
          Colors.black.withValues(alpha: 0.26),
        ],
        const [0.0, 0.48, 1.0],
      ),
  );
  canvas.restore();
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

/// The dart's axis, still ringing.
///
/// A dart that has just gone in is not a static object: the shaft whips about
/// the point for a few hundred milliseconds and then stands still. Rotating the
/// *axis* rather than shaking the whole sprite is what makes it read as a
/// vibration pinned at the tip — the flight describes a small ellipse and the
/// point never moves, which is exactly what a dart in a board does.
Vec3 _quivered(Vec3 direction, double settle, double strength) {
  if (settle <= 0) return direction;
  final s = settle.clamp(0.0, 1.0);
  final k = 0.5 + 0.5 * strength.clamp(0.0, 1.0);
  // Squared decay: the whip is nearly gone by halfway, then it just settles.
  final amp = 0.185 * k * s * s;
  final t = (1 - s) * 27;
  final u = _anyPerpendicular(direction);
  final v = _cross(direction, u).normalized;
  return (direction +
          u * (amp * math.sin(t)) +
          v * (amp * 0.62 * math.sin(t * 1.31 + 1.1)))
      .normalized;
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
  Color color, {
  bool onFace = false,
}) {
  final dir = direction.normalized;
  final tail = tip - dir * DartsWorld.dartLength;
  final pTip = camera.project(tip);
  final pTail = camera.project(tail);
  if (!pTip.visible || !pTail.visible) return;

  final scale = pTail.scale;

  // The dart's shadow on the sisal — a real ray from the lamp through the tail
  // onto the board plane, not a nudge down-right. Without it a stuck dart is a
  // sticker; with it, it is standing out of the board.
  if (onFace) {
    final l = DartsLight.direction;
    final t = (DartsWorld.boardZ - tail.z) / l.z;
    if (t > 0) {
      final cast = camera.project(tail + l * t);
      if (cast.visible) {
        canvas.drawLine(
          pTip.screen,
          cast.screen,
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(1.6, 0.022 * scale)
            ..color = Colors.black.withValues(alpha: 0.32)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.012 * scale),
        );
      }
    }
  }

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
