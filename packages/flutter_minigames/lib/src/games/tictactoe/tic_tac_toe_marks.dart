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

  /// The stroke geometry for the current [progress], as a single path so the
  /// body, its cast shadow and its bevel are all the same shape.
  Path _shape(double s, double inset) {
    final path = Path();
    if (isX) {
      final a1 = Offset(inset, inset);
      final a2 = Offset(s - inset, s - inset);
      final b1 = Offset(s - inset, inset);
      final b2 = Offset(inset, s - inset);
      // First diagonal draws over [0, 0.55], second over [0.45, 1].
      final t1 = (progress / 0.55).clamp(0.0, 1.0);
      final t2 = ((progress - 0.45) / 0.55).clamp(0.0, 1.0);
      if (t1 > 0) {
        path.moveTo(a1.dx, a1.dy);
        final e = Offset.lerp(a1, a2, Curves.easeOut.transform(t1))!;
        path.lineTo(e.dx, e.dy);
      }
      if (t2 > 0) {
        path.moveTo(b1.dx, b1.dy);
        final e = Offset.lerp(b1, b2, Curves.easeOut.transform(t2))!;
        path.lineTo(e.dx, e.dy);
      }
    } else {
      final rect = Rect.fromLTRB(inset, inset, s - inset, s - inset);
      final sweep = 2 * math.pi * Curves.easeOut.transform(progress);
      path.addArc(rect, -math.pi / 2, sweep);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final s = size.shortestSide;
    final inset = s * 0.25;
    final width = s * 0.115 * thickness;
    final path = _shape(s, inset);

    Paint stroke(double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 1. Contact shadow. The mark is a piece of enamel sitting in the board's
    //    recess, so the shadow is short, offset down-right (light upper-left)
    //    and tight — not a soft halo floating under a sticker.
    canvas.drawPath(
      path.shift(Offset(width * 0.16, width * 0.24)),
      stroke(width)
        ..color = const Color(0x59000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.26),
    );

    // 2..4 composite inside one layer so the bevel and specular can be masked
    // to the body with srcATop — the bead has to die exactly at the mark's edge
    // or it reads as a blurry outline instead of a rolled edge.
    final box = Rect.fromLTWH(0, 0, s, s);
    canvas.saveLayer(box.inflate(width), Paint());

    // 2. Body. One light direction across the whole mark rather than a
    //    per-stroke gradient, so both diagonals of an X agree.
    canvas.drawPath(
      path,
      stroke(width)
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.30)!,
            color,
            Color.lerp(color, Colors.black, 0.30)!,
          ],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(box),
    );

    // 3. Rolled edge: a bright bead along the lit side, a dark one opposite.
    canvas.drawPath(
      path.shift(Offset(-width * 0.20, -width * 0.22)),
      stroke(width * 0.34)
        ..color = Colors.white.withValues(alpha: 0.42)
        ..blendMode = BlendMode.srcATop
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.12),
    );
    canvas.drawPath(
      path.shift(Offset(width * 0.19, width * 0.21)),
      stroke(width * 0.30)
        ..color = Color.lerp(color, Colors.black, 0.55)!.withValues(alpha: 0.45)
        ..blendMode = BlendMode.srcATop
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.12),
    );

    // 4. Specular pinstripe — the wet-lacquer read. Deliberately faint: on an X
    //    the two diagonals cross, and a strong highlight piles up into a bright
    //    blob at the centre that reads as grease rather than gloss.
    canvas.drawPath(
      path.shift(Offset(-width * 0.28, -width * 0.30)),
      stroke(width * 0.10)
        ..color = Colors.white.withValues(alpha: 0.32)
        ..blendMode = BlendMode.srcATop
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.05),
    );
    canvas.restore();
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
          painter:
              MarkPainter(isX: isX, color: color, progress: 1, thickness: 1.1),
        ),
      );
}
