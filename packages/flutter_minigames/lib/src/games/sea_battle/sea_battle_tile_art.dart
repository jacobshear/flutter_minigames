import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Launcher-tile miniature for Sea Battle: a soft blue sea grid with a couple
/// of gray hulls, hit pegs, miss dots, and a gently looping shot splash.
/// Matches the rounded-slab look of the other launcher tiles.
class SeaBattleTileArt extends StatefulWidget {
  /// Set false for a fully static rendering (e.g. screenshots).
  final bool animate;

  const SeaBattleTileArt({super.key, this.animate = true});

  @override
  State<SeaBattleTileArt> createState() => _SeaBattleTileArtState();
}

class _SeaBattleTileArtState extends State<SeaBattleTileArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
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
        painter: _SeaBattleTilePainter(t: _c.value),
      ),
    );
  }
}

class _SeaBattleTilePainter extends CustomPainter {
  final double t;

  _SeaBattleTilePainter({required this.t});

  static const int n = 8;

  @override
  void paint(Canvas canvas, Size size) {
    // Sea slab tile.
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
          colors: [Color(0xFFBFE2F4), Color(0xFF8FC6E4)],
        ).createShader(Offset.zero & size),
    );

    final side = size.shortestSide * 0.82;
    final board = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: side,
      height: side,
    );
    final cell = board.width / n;

    Offset center(int r, int c) => Offset(
          board.left + (c + 0.5) * cell,
          board.top + (r + 0.5) * cell,
        );

    // Grid.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = math.max(0.7, cell * 0.05);
    for (var i = 0; i <= n; i++) {
      canvas.drawLine(
        Offset(board.left, board.top + i * cell),
        Offset(board.right, board.top + i * cell),
        line,
      );
      canvas.drawLine(
        Offset(board.left + i * cell, board.top),
        Offset(board.left + i * cell, board.bottom),
        line,
      );
    }

    // Ships: one 3-long horizontal (partly hit), one 2-long vertical.
    void ship(int r, int c, int len, bool horizontal) {
      final first = Rect.fromLTWH(
          board.left + c * cell, board.top + r * cell, cell, cell);
      final last = Rect.fromLTWH(
        board.left + (horizontal ? c + len - 1 : c) * cell,
        board.top + (horizontal ? r : r + len - 1) * cell,
        cell,
        cell,
      );
      final hull = first.expandToInclude(last).deflate(cell * 0.16);
      final rr =
          RRect.fromRectAndRadius(hull, Radius.circular(hull.shortestSide / 2));
      const base = Color(0xFF95A0AC);
      canvas.drawRRect(
        rr.shift(Offset(0, cell * 0.06)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.16)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.1),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(base, Colors.white, 0.3)!,
              base,
              Color.lerp(base, Colors.black, 0.2)!,
            ],
          ).createShader(hull),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, cell * 0.05)
          ..color = const Color(0xFF5A636D).withValues(alpha: 0.6),
      );
    }

    ship(2, 1, 3, true);
    ship(5, 5, 2, false);

    // Hit pegs on the horizontal ship.
    const hit = Color(0xFFE8452E);
    for (final (r, c) in const [(2, 1), (2, 2)]) {
      final o = center(r, c);
      final rad = cell * 0.2;
      canvas.drawCircle(
        o,
        rad * 1.5,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.22)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, rad * 0.5),
      );
      canvas.drawCircle(
        o,
        rad,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.4),
            colors: [
              Color.lerp(hit, Colors.white, 0.45)!,
              hit,
              Color.lerp(hit, Colors.black, 0.3)!,
            ],
          ).createShader(Rect.fromCircle(center: o, radius: rad)),
      );
    }

    // Miss dots scattered on open water.
    final miss = Paint()..color = const Color(0xFFF4F7FA);
    for (final (r, c) in const [(0, 5), (4, 2), (6, 1), (1, 0)]) {
      canvas.drawCircle(center(r, c), cell * 0.11, miss);
    }

    // Looping splash: ripple rings expanding on one cell, twice per cycle.
    final splashAt = center(5, 3);
    for (final phase in const [0.0, 0.5]) {
      final v = ((t - phase) % 1.0) / 0.5;
      if (v < 0 || v > 1) continue;
      final eased = Curves.easeOut.transform(v.clamp(0.0, 1.0));
      canvas.drawCircle(
        splashAt,
        cell * (0.15 + 0.55 * eased),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, cell * 0.08 * (1 - eased))
          ..color = Colors.white.withValues(alpha: 0.8 * (1 - eased)),
      );
    }
  }

  @override
  bool shouldRepaint(_SeaBattleTilePainter old) => old.t != t;
}
