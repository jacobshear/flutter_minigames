import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/classic_game_tile_art.dart' show tileSilhouette;

/// Launcher-tile miniature for Knockout: a raised light platform over a dark
/// void with a couple of resting pucks and one flying off the lip on a loop.
/// Matches the rounded-slab look of the other tiles.
class KnockoutTileArt extends StatefulWidget {
  /// Loop phase offset (the launcher staggers tiles by phase).
  final double phase;

  const KnockoutTileArt({super.key, this.phase = 0});

  @override
  State<KnockoutTileArt> createState() => _KnockoutTileArtState();
}

class _KnockoutTileArtState extends State<KnockoutTileArt>
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
        painter: _KnockoutTilePainter(t: (_c.value + widget.phase) % 1.0),
      ),
    );
  }
}

class _KnockoutTilePainter extends CustomPainter {
  final double t;

  _KnockoutTilePainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    // Puck/platform metrics scale by the short side so a wide card window
    // reads as the square scene on a wider platform, not a stretched one.
    // Identical on square tiles (s == width).
    final s = size.shortestSide;
    final outer = tileSilhouette(size);

    // Void backdrop.
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.1),
          radius: 0.9,
          colors: [Color(0xFF1B2029), Color(0xFF0C0F14)],
        ).createShader(Offset.zero & size),
    );

    // Raised platform slab. The void margin comes from the short side; the
    // slab itself spans whatever the canvas gives it, so a wide card shows a
    // wide platform.
    final margin = s * 0.16;
    final plat = Rect.fromLTRB(
      margin,
      margin,
      size.width - margin,
      size.height - margin,
    );
    final platRR = RRect.fromRectAndRadius(plat, Radius.circular(s * 0.1));
    // Slab shadow.
    canvas.drawRRect(
      platRR.shift(Offset(0, s * 0.03)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03),
    );
    canvas.save();
    canvas.clipRRect(platRR);
    canvas.drawRRect(
      platRR,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFDDE0E7), Color(0xFFC9CDD6), Color(0xFFAAAFBB)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(plat),
    );

    double yOf(double ny) => plat.top + ny * plat.height;
    double xOf(double nx) => plat.left + nx * plat.width;

    // Half-court line + emblem.
    canvas.drawLine(
      Offset(plat.left, yOf(0.5)),
      Offset(plat.right, yOf(0.5)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.1)
        ..strokeWidth = math.max(0.8, size.width * 0.008),
    );

    final r = size.width * 0.075;

    // A resting blue puck (far half) and a resting red puck (near half).
    _puck(canvas, Offset(xOf(0.34), yOf(0.28)), r, const Color(0xFF3E7BFA));
    _puck(canvas, Offset(xOf(0.6), yOf(0.72)), r, const Color(0xFFE5484D));

    canvas.restore();

    // A red puck flying off the right lip on the loop (tips over + fades),
    // drawn OUTSIDE the platform clip so it clears the edge into the void.
    final p = Curves.easeIn.transform((t % 1.0).clamp(0.0, 1.0));
    final flyNx = 0.72 + 0.42 * p; // travels off the right lip
    final alpha = p < 0.6 ? 1.0 : (1 - (p - 0.6) / 0.4);
    final squashX = 1 - 0.7 * p;
    _fallingPuck(
      canvas,
      Offset(xOf(flyNx), yOf(0.34)),
      r * (1 - 0.25 * p),
      Color.lerp(const Color(0xFFE5484D), Colors.black, 0.5 * p)!,
      alpha.clamp(0.0, 1.0),
      squashX,
    );
  }

  void _puck(Canvas canvas, Offset c, double r, Color base) {
    canvas.drawCircle(
      c.translate(0, r * 0.24),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.4),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [
            Color.lerp(base, Colors.white, 0.5)!,
            base,
            Color.lerp(base, Colors.black, 0.35)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r * 0.5,
      Paint()
        ..color = Color.lerp(base, Colors.white, 0.2)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.1,
    );
  }

  void _fallingPuck(
    Canvas canvas,
    Offset c,
    double r,
    Color base,
    double alpha,
    double squashX,
  ) {
    if (alpha <= 0.01) return;
    canvas.saveLayer(
      Rect.fromCircle(center: c, radius: r * 2),
      Paint()..color = Colors.white.withValues(alpha: alpha),
    );
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(squashX, 1);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [
            Color.lerp(base, Colors.white, 0.5)!,
            base,
            Color.lerp(base, Colors.black, 0.35)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_KnockoutTilePainter old) => old.t != t;
}
