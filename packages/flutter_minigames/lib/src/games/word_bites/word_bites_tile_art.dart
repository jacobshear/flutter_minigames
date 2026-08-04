import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Launcher-tile miniature for Word Bites: a couple of biscuit dominoes and
/// singles on a kitchen-tile backdrop, spelling "BITE", with a stray domino
/// and single gently bobbing. Self-contained (no example-app imports),
/// matching the toy-diorama style of the launcher's tile art.
class WordBitesTileArt extends StatefulWidget {
  final double phase;

  const WordBitesTileArt({super.key, this.phase = 0});

  @override
  State<WordBitesTileArt> createState() => _WordBitesTileArtState();
}

class _WordBitesTileArtState extends State<WordBitesTileArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4600),
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
        return CustomPaint(painter: _WordBitesTilePainter(t: t));
      },
    );
  }
}

class _WordBitesTilePainter extends CustomPainter {
  final double t;

  _WordBitesTilePainter({required this.t});

  static const _board = Color(0xFFBFD5E2);
  static const _grout = Color(0xFF9FBACB);
  static const _biscuit = Color(0xFFF6E7C6);
  static const _cocoa = Color(0xFF6B4A26);
  static const _green = Color(0xFF34C759);

  @override
  void paint(Canvas canvas, Size size) {
    // Kitchen-tile backdrop, full bleed (launcher tile clips its corners).
    // Grout cells stay square — sized off the short side — and tile outward
    // to cover wide canvases; on a square canvas this is the authored 5x5.
    canvas.drawRect(Offset.zero & size, Paint()..color = _grout);
    const grid = 5;
    final cellS = size.shortestSide / grid;
    final cols = (size.width / cellS).ceil();
    final rows = (size.height / cellS).ceil();
    final inset = cellS * 0.04;
    final tileR = Radius.circular(cellS * 0.14);
    final tilePaint = Paint();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        tilePaint.color = Color.lerp(
          _board,
          Colors.white,
          (r + c).isEven ? 0.09 : 0.03,
        )!;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              c * cellS + inset,
              r * cellS + inset,
              cellS - inset * 2,
              cellS - inset * 2,
            ),
            tileR,
          ),
          tilePaint,
        );
      }
    }

    final u = size.shortestSide / 5.4; // letter-cell unit
    final bob = math.sin(2 * math.pi * t);
    final bob2 = math.sin(2 * math.pi * t + 2.1);

    // Word row: horizontal domino [B I] + singles [T] [E] centered.
    final rowY = size.height * 0.42;
    final rowX = (size.width - u * 4.3) / 2;
    // Soft green glow beneath the formed word, breathing slowly.
    final glow = 0.16 + 0.10 * (0.5 + 0.5 * math.sin(2 * math.pi * t));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rowX - u * 0.12, rowY - u * 0.12, u * 4.5, u * 1.24),
        Radius.circular(u * 0.3),
      ),
      Paint()
        ..color = _green.withValues(alpha: glow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.18),
    );
    _piece(canvas, Offset(rowX, rowY), u, 'BI', horizontal: true);
    _piece(canvas, Offset(rowX + u * 2.15, rowY), u, 'T');
    _piece(canvas, Offset(rowX + u * 3.3, rowY), u, 'E');

    // Stray vertical domino and single, bobbing gently. Anchored as
    // offsets-from-center off the short side (0.71 and 0.16 of the authored
    // square side), so they hug the word row instead of drifting to the
    // edges of a wide canvas.
    final s = size.shortestSide;
    _piece(
      canvas,
      Offset(
        size.width / 2 + s * 0.21,
        size.height * 0.03 + bob * u * 0.07,
      ),
      u * 0.88,
      'ON',
      vertical: true,
    );
    _piece(
      canvas,
      Offset(
        size.width / 2 - s * 0.34,
        size.height * 0.74 + bob2 * u * 0.07,
      ),
      u * 0.88,
      'S',
    );
  }

  void _piece(
    Canvas canvas,
    Offset topLeft,
    double u,
    String letters, {
    bool horizontal = false,
    bool vertical = false,
  }) {
    final w = horizontal ? u * 2 : u;
    final h = vertical ? u * 2 : u;
    final rect = Rect.fromLTWH(topLeft.dx, topLeft.dy, w, h);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(u * 0.22));

    canvas.drawRRect(
      rr.shift(Offset(0, u * 0.07)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.09),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(_biscuit, Colors.white, 0.35)!,
            _biscuit,
            Color.lerp(_biscuit, const Color(0xFF8A6B3F), 0.22)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, u * 0.035)
        ..color = Color.lerp(_biscuit, _cocoa, 0.45)!,
    );

    // Domino seam.
    if (letters.length == 2) {
      final seam = Paint()
        ..color = _cocoa.withValues(alpha: 0.25)
        ..strokeWidth = 1.1;
      if (horizontal) {
        canvas.drawLine(
          Offset(rect.center.dx, rect.top + u * 0.16),
          Offset(rect.center.dx, rect.bottom - u * 0.16),
          seam,
        );
      } else {
        canvas.drawLine(
          Offset(rect.left + u * 0.16, rect.center.dy),
          Offset(rect.right - u * 0.16, rect.center.dy),
          seam,
        );
      }
    }

    for (var i = 0; i < letters.length; i++) {
      final center = letters.length == 1
          ? rect.center
          : horizontal
              ? Offset(rect.left + u * (0.5 + i), rect.center.dy)
              : Offset(rect.center.dx, rect.top + u * (0.5 + i));
      final tp = TextPainter(
        text: TextSpan(
          text: letters[i],
          style: TextStyle(
            color: _cocoa,
            fontWeight: FontWeight.w900,
            fontSize: u * 0.54,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_WordBitesTilePainter old) => old.t != t;
}
