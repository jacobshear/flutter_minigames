import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/classic_game_tile_art.dart' show tileSilhouette;

/// Launcher-tile miniature for Shuffleboard: a warm maple mini-lane with cool
/// scoring bands at the far end and a couple of red/blue weights, one gently
/// sliding up-lane on a loop. Matches the rounded-slab look of the other tiles.
class ShuffleboardTileArt extends StatefulWidget {
  /// Loop phase offset (the launcher staggers tiles by phase).
  final double phase;

  const ShuffleboardTileArt({super.key, this.phase = 0});

  @override
  State<ShuffleboardTileArt> createState() => _ShuffleboardTileArtState();
}

class _ShuffleboardTileArtState extends State<ShuffleboardTileArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6200),
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
        painter: _ShuffleboardTilePainter(t: (_c.value + widget.phase) % 1.0),
      ),
    );
  }
}

class _ShuffleboardTilePainter extends CustomPainter {
  final double t;

  _ShuffleboardTilePainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    // Lane and weight metrics scale by the short side so a wide card window
    // keeps the authored lane centered in the walnut frame rather than
    // stretching it. Identical on square tiles (s == width).
    final s = size.shortestSide;
    final outer = tileSilhouette(size);

    // Walnut frame.
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6E4A2C), Color(0xFF4A2E19)],
        ).createShader(Offset.zero & size),
    );

    // Maple lane inset, centered horizontally. Authored square margin was
    // 0.16 * side each side, i.e. a half-width of 0.34 * side from center.
    final halfLane = s * 0.34;
    final lane = Rect.fromLTRB(
      size.width / 2 - halfLane,
      size.height * 0.1,
      size.width / 2 + halfLane,
      size.height * 0.9,
    );
    final laneRR = RRect.fromRectAndRadius(lane, Radius.circular(s * 0.05));
    canvas.save();
    canvas.clipRRect(laneRR);
    canvas.drawRRect(
      laneRR,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF0C689), Color(0xFFDCA867), Color(0xFFB07E45)],
          stops: [0.0, 0.5, 1.0],
        ).createShader(lane),
    );

    double yOf(double ny) => lane.top + ny * lane.height;
    double xOf(double nx) => lane.left + nx * lane.width;

    // Scoring bands at the far (top) end: 3 / 2 / 1.
    const zone = Color(0xFF3E6E8E);
    final bands = [
      (0.0, 0.14, 3, 0.32),
      (0.14, 0.28, 2, 0.24),
      (0.28, 0.44, 1, 0.16),
    ];
    for (final (a, b, label, alpha) in bands) {
      final r = Rect.fromLTRB(lane.left, yOf(a), lane.right, yOf(b));
      canvas.drawRect(r, Paint()..color = zone.withValues(alpha: alpha));
      canvas.drawLine(
        Offset(lane.left, yOf(b)),
        Offset(lane.right, yOf(b)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = math.max(0.8, s * 0.01),
      );
      _label(canvas, Offset(xOf(0.5), yOf((a + b) / 2)), '$label', s * 0.12);
    }

    // Foul line.
    canvas.drawLine(
      Offset(lane.left, yOf(0.62)),
      Offset(lane.right, yOf(0.62)),
      Paint()
        ..color = const Color(0xFF7A2E2E)
        ..strokeWidth = math.max(1, s * 0.014),
    );

    final r = s * 0.075;

    // A resting blue weight parked in zone 2.
    _weight(canvas, Offset(xOf(0.4), yOf(0.2)), r, const Color(0xFF2E6FB0),
        scoring: true);
    // A resting red weight in the neutral zone.
    _weight(canvas, Offset(xOf(0.62), yOf(0.5)), r, const Color(0xFFD8443C));

    // A red weight sliding up-lane on the loop (from base to zone 1).
    final slide = Curves.easeOut.transform((t % 1.0).clamp(0.0, 1.0));
    final ny = 0.9 - 0.6 * slide;
    _weight(canvas, Offset(xOf(0.5), yOf(ny)), r, const Color(0xFFD8443C),
        scoring: ny < 0.44);

    canvas.restore();
  }

  void _label(Canvas canvas, Offset center, String text, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _weight(Canvas canvas, Offset c, double r, Color base,
      {bool scoring = false}) {
    canvas.drawCircle(
      c.translate(0, r * 0.24),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.4),
    );
    if (scoring) {
      canvas.drawCircle(
        c,
        r * 1.3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.16
          ..color = const Color(0xFFF4B740).withValues(alpha: 0.85),
      );
    }
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

  @override
  bool shouldRepaint(_ShuffleboardTilePainter old) => old.t != t;
}
