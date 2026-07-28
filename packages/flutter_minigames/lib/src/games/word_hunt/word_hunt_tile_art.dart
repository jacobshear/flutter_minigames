import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Launcher-tile miniature for Word Hunt: a parchment 4×4 letter grid with a
/// word ("HUNT") being traced on a smooth loop — the capsule trail draws
/// tile-by-tile, flashes green on completion, then clears. Matches the
/// toy-diorama style of the example app's tile art while staying
/// self-contained in this package.
class WordHuntTileArt extends StatefulWidget {
  final double phase;

  const WordHuntTileArt({super.key, this.phase = 0});

  @override
  State<WordHuntTileArt> createState() => _WordHuntTileArtState();
}

class _WordHuntTileArtState extends State<WordHuntTileArt>
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
      builder: (context, _) {
        final t = (_c.value + widget.phase) % 1.0;
        return CustomPaint(painter: _WordHuntTilePainter(t: t));
      },
    );
  }
}

class _WordHuntTilePainter extends CustomPainter {
  final double t;

  _WordHuntTilePainter({required this.t});

  /// Fixed miniature board (row-major). "HUNT" runs down the diagonal-ish
  /// path below; the rest is quiet filler.
  static const List<String> _letters = [
    'H', 'E', 'R', 'O',
    'A', 'U', 'S', 'E',
    'P', 'I', 'N', 'D',
    'W', 'O', 'T', 'L',
  ];

  /// Trace path for HUNT: H(0,0) → U(1,1) → N(2,2) → T(3,2).
  static const List<int> _path = [0, 5, 10, 14];

  // Loop: 0–0.15 idle · 0.15–0.55 trace draws · 0.55–0.80 green hold ·
  // 0.80–1.0 fade out.
  double get _traceT =>
      Curves.easeInOut.transform(((t - 0.15) / 0.40).clamp(0.0, 1.0));
  double get _validT => ((t - 0.55) / 0.06).clamp(0.0, 1.0);
  double get _fadeT => ((t - 0.80) / 0.20).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    // Felt backdrop, full bleed (tile clips its own corners).
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B7A5C), Color(0xFF2E6B4F), Color(0xFF215240)],
          stops: [0.0, 0.5, 1.0],
        ).createShader(Offset.zero & size),
    );

    // Parchment slab.
    final side = size.shortestSide * 0.84;
    final slabRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: side,
      height: side,
    );
    final slab = RRect.fromRectAndRadius(
      slabRect,
      Radius.circular(side * 0.10),
    );
    canvas.drawRRect(
      slab.shift(Offset(0, side * 0.02)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, side * 0.03),
    );
    canvas.drawRRect(
      slab,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(const Color(0xFFE8D9B0), Colors.white, 0.10)!,
            const Color(0xFFE8D9B0),
            Color.lerp(const Color(0xFFE8D9B0), Colors.black, 0.08)!,
          ],
        ).createShader(slabRect),
    );

    // Tiles.
    const n = 4;
    final pad = side * 0.06;
    final gap = side * 0.03;
    final cell = (side - pad * 2 - gap * (n - 1)) / n;
    Rect tileRect(int i) {
      final r = i ~/ n;
      final c = i % n;
      return Rect.fromLTWH(
        slabRect.left + pad + c * (cell + gap),
        slabRect.top + pad + r * (cell + gap),
        cell,
        cell,
      );
    }

    // How much of the trace is lit right now.
    final lit = _traceT * _path.length;
    final valid = _validT;
    final fade = 1 - _fadeT;
    final neutral = const Color(0xFFF4B740);
    final green = const Color(0xFF3FA862);
    final traceColor = Color.lerp(neutral, green, valid)!;

    for (var i = 0; i < _letters.length; i++) {
      final rect = tileRect(i);
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.22));
      final pathIndex = _path.indexOf(i);
      final selected =
          pathIndex >= 0 && lit > pathIndex && fade > 0.01 && t >= 0.15;

      canvas.drawRRect(
        rr.shift(Offset(0, cell * 0.05)),
        Paint()..color = Colors.black.withValues(alpha: 0.10),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..color = selected
              ? Color.lerp(const Color(0xFFFDF6E0), traceColor,
                  fade.clamp(0.0, 1.0))!
              : const Color(0xFFFDF6E0),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, cell * 0.04)
          ..color = selected
              ? Color.lerp(traceColor, Colors.black, 0.18)!
                  .withValues(alpha: fade.clamp(0.0, 1.0))
              : const Color(0xFFD8C58F),
      );

      final tp = TextPainter(
        text: TextSpan(
          text: _letters[i],
          style: TextStyle(
            color: selected
                ? Color.lerp(const Color(0xFF54401F), Colors.white, fade)!
                : const Color(0xFF54401F),
            fontWeight: FontWeight.w800,
            fontSize: cell * 0.52,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        rect.center - Offset(tp.width / 2, tp.height / 2),
      );
    }

    // Capsule trail over the lit tiles.
    if (lit > 0 && fade > 0.01) {
      final centers = [for (final i in _path) tileRect(i).center];
      final whole = lit.floor().clamp(0, centers.length - 1);
      final frac = (lit - whole).clamp(0.0, 1.0);
      final trail = Path()..moveTo(centers[0].dx, centers[0].dy);
      for (var i = 1; i <= whole; i++) {
        trail.lineTo(centers[i].dx, centers[i].dy);
      }
      if (whole < centers.length - 1 && frac > 0) {
        final a = centers[whole];
        final b = centers[whole + 1];
        final mid = Offset.lerp(a, b, frac)!;
        trail.lineTo(mid.dx, mid.dy);
      }
      canvas.drawPath(
        trail,
        Paint()
          ..color = traceColor.withValues(alpha: 0.45 * fade)
          ..strokeWidth = cell * 0.34
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_WordHuntTilePainter old) => old.t != t;
}
