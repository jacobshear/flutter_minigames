import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Paints an X or O as animated, stroke-drawn ink — the visual signature of the
/// game. [progress] (0..1) sweeps the stroke on: an O arcs into being, an X
/// draws its two diagonals in sequence. A soft blurred underlay gives the ink
/// depth without a hard drop shadow.
class MarkPainter extends CustomPainter {
  /// True paints an X, false an O.
  final bool isX;
  final Color color;

  /// 0 = nothing drawn, 1 = fully drawn.
  final double progress;

  /// Relative stroke thickness multiplier.
  final double thickness;

  const MarkPainter({
    required this.isX,
    required this.color,
    required this.progress,
    this.thickness = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final s = size.shortestSide;
    final inset = s * 0.24;
    final width = s * 0.11 * thickness;

    final glow = Paint()
      ..color = color.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.045);
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (isX) {
      _paintX(canvas, s, inset, glow);
      _paintX(canvas, s, inset, ink);
    } else {
      _paintO(canvas, s, inset, glow);
      _paintO(canvas, s, inset, ink);
    }
  }

  void _paintX(Canvas canvas, double s, double inset, Paint paint) {
    final a1 = Offset(inset, inset);
    final a2 = Offset(s - inset, s - inset);
    final b1 = Offset(s - inset, inset);
    final b2 = Offset(inset, s - inset);
    // First diagonal draws over [0, 0.55], second over [0.45, 1] (slight overlap).
    final t1 = (progress / 0.55).clamp(0.0, 1.0);
    final t2 = ((progress - 0.45) / 0.55).clamp(0.0, 1.0);
    if (t1 > 0) {
      canvas.drawLine(a1, Offset.lerp(a1, a2, Curves.easeOut.transform(t1))!, paint);
    }
    if (t2 > 0) {
      canvas.drawLine(b1, Offset.lerp(b1, b2, Curves.easeOut.transform(t2))!, paint);
    }
  }

  void _paintO(Canvas canvas, double s, double inset, Paint paint) {
    final rect = Rect.fromLTRB(inset, inset, s - inset, s - inset);
    final sweep = 2 * math.pi * Curves.easeOut.transform(progress);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, paint);
  }

  @override
  bool shouldRepaint(MarkPainter old) =>
      old.progress != progress || old.color != color || old.isX != isX;
}

/// A small, fully-drawn [MarkPainter] for use in labels / turn banners.
class TicTacToeGlyph extends StatelessWidget {
  final bool isX;
  final Color color;
  final double size;

  const TicTacToeGlyph({
    super.key,
    required this.isX,
    required this.color,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: MarkPainter(isX: isX, color: color, progress: 1, thickness: 1.1),
        ),
      );
}
