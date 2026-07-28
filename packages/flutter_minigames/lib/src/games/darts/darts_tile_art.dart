import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'darts_board_geometry.dart';

/// Launcher-tile miniature for Darts: a board seen face-on with a dart looping
/// in from the corner and sticking in the treble 20.
///
/// Face-on and flat on purpose — the tile is a 2-D emblem, not a scene, so it
/// draws the board directly rather than going through the camera. Every ring
/// ratio still comes from [DartsBoardGeometry], so the emblem and the game
/// cannot drift apart.
class DartsTileArt extends StatefulWidget {
  /// Loop phase offset (the launcher staggers tiles by phase).
  final double phase;

  const DartsTileArt({super.key, this.phase = 0});

  @override
  State<DartsTileArt> createState() => _DartsTileArtState();
}

class _DartsTileArtState extends State<DartsTileArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
  }

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
        painter: _DartsTilePainter(t: (_c.value + widget.phase) % 1.0),
      ),
    );
  }
}

class _DartsTilePainter extends CustomPainter {
  final double t;

  _DartsTilePainter({required this.t});

  static const _cream = Color(0xFFEBD9A8);
  static const _black = Color(0xFF17171A);
  static const _red = Color(0xFFC8392F);
  static const _green = Color(0xFF2E8B4F);
  static const _wire = Color(0xFFB9BEC6);

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.22),
    );
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF31384A), Color(0xFF1A1E28)],
        ).createShader(Offset.zero & size),
    );
    canvas.save();
    canvas.clipRRect(outer);

    final centre = Offset(size.width * 0.5, size.height * 0.47);
    final r = size.width * 0.36;

    // Surround.
    canvas.drawCircle(
      centre.translate(0, r * 0.08),
      r * DartsBoardGeometry.numberRingRatio,
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      centre,
      r * DartsBoardGeometry.numberRingRatio,
      Paint()..color = const Color(0xFF101014),
    );

    const span = DartsBoardGeometry.sectorSpan;
    // Canvas arcs measure from +x counter-clockwise-in-screen-space; the board
    // measures clockwise from 12 o'clock, so a sector centred at `a` starts at
    // screen angle `a - 90° - half`.
    for (var i = 0; i < 20; i++) {
      final start = i * span - math.pi / 2 - span / 2;
      final dark = i.isEven;
      final bed = dark ? _black : _cream;
      final ring = dark ? _red : _green;
      void band(double r0, double r1, Color color) {
        final path = Path()
          ..addArc(Rect.fromCircle(center: centre, radius: r1), start, span)
          ..arcTo(
            Rect.fromCircle(center: centre, radius: r0),
            start + span,
            -span,
            false,
          )
          ..close();
        canvas.drawPath(path, Paint()..color = color);
      }

      band(DartsBoardGeometry.outerBullRatio * r,
          DartsBoardGeometry.innerTrebleRatio * r, bed);
      band(DartsBoardGeometry.innerTrebleRatio * r,
          DartsBoardGeometry.outerTrebleRatio * r, ring);
      band(DartsBoardGeometry.outerTrebleRatio * r,
          DartsBoardGeometry.innerDoubleRatio * r, bed);
      band(DartsBoardGeometry.innerDoubleRatio * r, r, ring);
    }

    canvas.drawCircle(
      centre,
      DartsBoardGeometry.outerBullRatio * r,
      Paint()..color = _green,
    );
    canvas.drawCircle(
      centre,
      DartsBoardGeometry.innerBullRatio * r,
      Paint()..color = _red,
    );

    // Wire spider.
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, size.width * 0.006)
      ..color = _wire.withValues(alpha: 0.85);
    for (final ratio in const [
      DartsBoardGeometry.outerBullRatio,
      DartsBoardGeometry.innerTrebleRatio,
      DartsBoardGeometry.outerTrebleRatio,
      DartsBoardGeometry.innerDoubleRatio,
      1.0,
    ]) {
      canvas.drawCircle(centre, ratio * r, wire);
    }
    for (var i = 0; i < 20; i++) {
      final a = i * span - math.pi / 2 - span / 2;
      canvas.drawLine(
        centre +
            Offset(math.cos(a), math.sin(a)) *
                (DartsBoardGeometry.outerBullRatio * r),
        centre + Offset(math.cos(a), math.sin(a)) * r,
        wire,
      );
    }

    // A dart looping in to the treble 20 (top sector, red bed).
    final target = centre +
        Offset(
          -r * 0.06,
          -r *
              (DartsBoardGeometry.innerTrebleRatio +
                  DartsBoardGeometry.outerTrebleRatio) /
              2,
        );
    final travel = Curves.easeOutCubic.transform(
      ((t - 0.05) / 0.45).clamp(0.0, 1.0),
    );
    final rest = t > 0.5 ? 1.0 : travel;
    final from = Offset(size.width * 1.12, size.height * 1.05);
    final tip = Offset.lerp(from, target, rest)!;
    final dir = (target - from);
    final unit = dir / dir.distance;
    final len = size.width * (0.30 - 0.10 * rest);
    final tail = tip - unit * len;
    final perp = Offset(-unit.dy, unit.dx);

    canvas.drawLine(
      tail + unit * (len * 0.3),
      tip,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.4, size.width * 0.026)
        ..color = const Color(0xFFD3D8DF),
    );
    final finW = size.width * 0.055;
    final fin = Path()
      ..moveTo(tail.dx + perp.dx * finW, tail.dy + perp.dy * finW)
      ..lineTo(tail.dx + unit.dx * len * 0.34, tail.dy + unit.dy * len * 0.34)
      ..lineTo(tail.dx - perp.dx * finW, tail.dy - perp.dy * finW)
      ..lineTo(tail.dx, tail.dy)
      ..close();
    canvas.drawPath(fin, Paint()..color = const Color(0xFFF4B740));

    canvas.restore();
  }

  @override
  bool shouldRepaint(_DartsTilePainter old) => old.t != t;
}
