import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'eight_ball_style.dart';

/// Launcher-tile miniature for 8-Ball: a green felt slab with a wood rail, a
/// racked cluster of numbered balls at the top and the cue rolling up to break
/// on a loop. Matches the rounded-slab look of the other tiles.
class EightBallTileArt extends StatefulWidget {
  /// Loop phase offset (the launcher staggers tiles by phase).
  final double phase;

  const EightBallTileArt({super.key, this.phase = 0});

  @override
  State<EightBallTileArt> createState() => _EightBallTileArtState();
}

class _EightBallTileArtState extends State<EightBallTileArt>
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
        painter: _EightBallTilePainter(t: (_c.value + widget.phase) % 1.0),
      ),
    );
  }
}

class _EightBallTilePainter extends CustomPainter {
  final double t;

  _EightBallTilePainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.22),
    );

    // Wood rail.
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6E4A2C), Color(0xFF4A2E19)],
        ).createShader(Offset.zero & size),
    );

    // Felt inset.
    final margin = size.width * 0.12;
    final felt = Rect.fromLTRB(
      margin,
      margin,
      size.width - margin,
      size.height - margin,
    );
    final feltRR =
        RRect.fromRectAndRadius(felt, Radius.circular(size.width * 0.06));
    canvas.save();
    canvas.clipRRect(feltRR);
    canvas.drawRRect(
      feltRR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.1),
          radius: 1.1,
          colors: [
            const Color(0xFF278C57),
            const Color(0xFF1F7A4D),
            Color.lerp(const Color(0xFF1F7A4D), Colors.black, 0.3)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(felt),
    );

    double xOf(double nx) => felt.left + nx * felt.width;
    double yOf(double ny) => felt.top + ny * felt.height;

    // Pockets at the felt corners + side midpoints.
    final pocketR = size.width * 0.052;
    final pockets = [
      felt.topLeft,
      felt.topRight,
      felt.bottomLeft,
      felt.bottomRight,
      Offset(felt.left, felt.center.dy),
      Offset(felt.right, felt.center.dy),
    ];
    for (final p in pockets) {
      canvas.drawCircle(p, pocketR, Paint()..color = Colors.black);
      canvas.drawCircle(
        p,
        pocketR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, size.width * 0.006)
          ..color = const Color(0xFFB98A3E).withValues(alpha: 0.55),
      );
    }

    final r = size.width * 0.055;

    // A small racked cluster near the top: 8 centre, a couple of mates.
    _ball(canvas, Offset(xOf(0.5), yOf(0.24)), r, 8);
    _ball(canvas, Offset(xOf(0.5 - 0.09), yOf(0.19)), r, 1);
    _ball(canvas, Offset(xOf(0.5 + 0.09), yOf(0.19)), r, 11);
    _ball(canvas, Offset(xOf(0.5 - 0.045), yOf(0.30)), r, 3);
    _ball(canvas, Offset(xOf(0.5 + 0.045), yOf(0.30)), r, 13);

    // Cue rolling up the felt on the loop.
    final roll = Curves.easeInOut.transform((t % 1.0).clamp(0.0, 1.0));
    final ny = 0.82 - 0.32 * roll;
    _ball(canvas, Offset(xOf(0.5), yOf(ny)), r, 0);

    canvas.restore();
  }

  void _ball(Canvas canvas, Offset c, double r, int number) {
    final base = EightBallStyle.ballColor(number);
    final isStripe = number >= 9 && number <= 15;
    canvas.drawCircle(
      c.translate(0, r * 0.2),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.35),
    );
    if (isStripe) {
      _sphere(canvas, c, r, const Color(0xFFF6F1E7));
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
      canvas.drawRect(
        Rect.fromCenter(center: c, width: r * 2, height: r * 1.1),
        Paint()..color = base,
      );
      canvas.restore();
    } else {
      _sphere(canvas, c, r, base);
    }
    if (number != 0) {
      canvas.drawCircle(c, r * 0.5, Paint()..color = const Color(0xFFF8F4EC));
    }
    canvas.drawCircle(
      c.translate(-r * 0.3, -r * 0.34),
      r * 0.2,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  void _sphere(Canvas canvas, Offset c, double r, Color base) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [
            Color.lerp(base, Colors.white, 0.55)!,
            base,
            Color.lerp(base, Colors.black, 0.4)!,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_EightBallTilePainter old) => old.t != t;
}
