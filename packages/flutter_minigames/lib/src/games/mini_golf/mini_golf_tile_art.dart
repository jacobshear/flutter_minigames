import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/classic_game_tile_art.dart' show tileSilhouette;

/// Launcher-tile miniature for Mini Golf: a striped green receding into the
/// distance between raised rails, a flag in the cup at the far end, and a ball
/// rolling away up the hole.
///
/// Drawn in the same perspective language as the game itself, but with a
/// hand-rolled projective mapping rather than [Camera3] — a launcher grid paints
/// twenty of these every frame, and the real scene builder (dozens of
/// depth-sorted rail segments per hole) is far too much work for an 80-pixel
/// thumbnail.
class MiniGolfTileArt extends StatefulWidget {
  /// Loop phase offset (the launcher staggers tiles by phase).
  final double phase;

  const MiniGolfTileArt({super.key, this.phase = 0});

  @override
  State<MiniGolfTileArt> createState() => _MiniGolfTileArtState();
}

class _MiniGolfTileArtState extends State<MiniGolfTileArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        painter: _MiniGolfTilePainter(t: (_c.value + widget.phase) % 1.0),
      ),
    );
  }
}

class _MiniGolfTilePainter extends CustomPainter {
  final double t;

  _MiniGolfTilePainter({required this.t});

  // Depth range of the visible strip of green, in arbitrary camera units.
  static const double _dNear = 1.0;
  static const double _dFar = 3.2;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Course/ball/cup metrics scale by the short side so a wide card window
    // reads as the square scene with a panoramic sky and rough, not a
    // stretched fairway. Identical on square tiles (s == w).
    final s = size.shortestSide;
    final outer = tileSilhouette(size);
    final horizon = h * 0.30;

    // Projective mapping: screen y and half-width both go as 1/depth, which is
    // what makes the rails converge and the ball shrink as it rolls away.
    final ay = (h * 0.98 - horizon) * _dNear;
    final bx = s * 0.42 * _dNear;
    double yAt(double d) => horizon + ay / d;
    double xAt(double u, double d) => w / 2 + u * bx / d;
    Offset at(double u, double d) => Offset(xAt(u, d), yAt(d));

    canvas.save();
    canvas.clipRRect(outer);

    // Sky above the horizon, rough below.
    canvas.drawRect(
      Rect.fromLTRB(0, 0, w, horizon + 1),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6E9FC4), Color(0xFFA8CFE8)],
        ).createShader(Rect.fromLTRB(0, 0, w, horizon + 1)),
    );
    canvas.drawRect(
      Rect.fromLTRB(0, horizon, w, h),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C5E38), Color(0xFF16351F)],
        ).createShader(Rect.fromLTRB(0, horizon, w, h)),
    );

    // The green: a trapezoid between the rails.
    final green = Path()
      ..moveTo(xAt(-1, _dNear), yAt(_dNear))
      ..lineTo(xAt(1, _dNear), yAt(_dNear))
      ..lineTo(xAt(1, _dFar), yAt(_dFar))
      ..lineTo(xAt(-1, _dFar), yAt(_dFar))
      ..close();
    canvas.drawPath(
      green,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2F8348), Color(0xFF3FA45A), Color(0xFF54B96C)],
          stops: [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTRB(0, yAt(_dFar), w, h)),
    );

    // Mow stripes, converging on the vanishing point.
    canvas.save();
    canvas.clipPath(green);
    final stripe = Paint()..color = Colors.white.withValues(alpha: 0.07);
    for (var i = 0; i < 6; i += 2) {
      final u0 = -1 + 2 * i / 6;
      final u1 = -1 + 2 * (i + 1) / 6;
      canvas.drawPath(
        Path()
          ..moveTo(xAt(u0, _dNear), yAt(_dNear))
          ..lineTo(xAt(u1, _dNear), yAt(_dNear))
          ..lineTo(xAt(u1, _dFar), yAt(_dFar))
          ..lineTo(xAt(u0, _dFar), yAt(_dFar))
          ..close(),
        stripe,
      );
    }
    canvas.restore();

    // Rails: an inner face plus a lit top cap, so they read as boxes with
    // thickness rather than as outlines.
    final railH = h * 0.10 * _dNear;
    for (final side in [-1.0, 1.0]) {
      final inNear = at(side, _dNear);
      final inFar = at(side, _dFar);
      final outNear = at(side * 1.16, _dNear);
      final outFar = at(side * 1.16, _dFar);
      Offset lift(Offset p, double d) => p.translate(0, -railH / d);
      canvas.drawPath(
        Path()
          ..moveTo(inNear.dx, inNear.dy)
          ..lineTo(inFar.dx, inFar.dy)
          ..lineTo(lift(inFar, _dFar).dx, lift(inFar, _dFar).dy)
          ..lineTo(lift(inNear, _dNear).dx, lift(inNear, _dNear).dy)
          ..close(),
        Paint()..color = const Color(0xFFA69C82),
      );
      canvas.drawPath(
        Path()
          ..moveTo(lift(inNear, _dNear).dx, lift(inNear, _dNear).dy)
          ..lineTo(lift(inFar, _dFar).dx, lift(inFar, _dFar).dy)
          ..lineTo(lift(outFar, _dFar).dx, lift(outFar, _dFar).dy)
          ..lineTo(lift(outNear, _dNear).dx, lift(outNear, _dNear).dy)
          ..close(),
        Paint()..color = const Color(0xFFEDE3CA),
      );
    }

    // Back rail, so the hole ends rather than being cut off.
    final backNear = at(-1.16, _dFar);
    final backFar = at(1.16, _dFar);
    final backLift = railH / _dFar;
    canvas.drawPath(
      Path()
        ..moveTo(backNear.dx, backNear.dy)
        ..lineTo(backFar.dx, backFar.dy)
        ..lineTo(backFar.dx, backFar.dy - backLift)
        ..lineTo(backNear.dx, backNear.dy - backLift)
        ..close(),
      Paint()..color = const Color(0xFFC9BE9F),
    );

    // Cup near the far end, drawn as a squashed ellipse — a horizontal circle in
    // perspective.
    const cupD = 2.85;
    final cup = at(0.05, cupD);
    final cupR = s * 0.085 / cupD * _dNear;
    canvas.drawOval(
      Rect.fromCenter(center: cup, width: cupR * 2, height: cupR * 0.85),
      Paint()..color = const Color(0xFF0C1F13),
    );

    // Flag: pole and pennant, both scaled by depth.
    final poleH = h * 0.55 / cupD * _dNear;
    final poleTop = cup.translate(0, -poleH);
    canvas.drawLine(
      cup,
      poleTop,
      Paint()
        ..color = const Color(0xFFE9EDF0)
        ..strokeWidth = math.max(1.0, s * 0.018 / cupD)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      Path()
        ..moveTo(poleTop.dx, poleTop.dy)
        ..lineTo(poleTop.dx - s * 0.15 / cupD, poleTop.dy + poleH * 0.16)
        ..lineTo(poleTop.dx, poleTop.dy + poleH * 0.32)
        ..close(),
      Paint()..color = const Color(0xFFE23B32),
    );

    // The ball rolls away up the hole, shrinking as it goes.
    final roll = Curves.easeInOut.transform(t.clamp(0.0, 1.0));
    final ballD = _dNear + 0.15 + (cupD - _dNear - 0.35) * roll;
    final ballPos = at(0.05 * roll - 0.10, ballD);
    final ballR = s * 0.068 / ballD * _dNear;
    canvas.drawOval(
      Rect.fromCenter(
        center: ballPos.translate(0, ballR * 0.55),
        width: ballR * 2.1,
        height: ballR * 0.9,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      ballPos,
      ballR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: const [Colors.white, Color(0xFFC7CED3)],
        ).createShader(Rect.fromCircle(center: ballPos, radius: ballR)),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MiniGolfTilePainter old) => old.t != t;
}
