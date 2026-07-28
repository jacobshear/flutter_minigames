import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'crazy_eights_card_art.dart';

/// Launcher-tile miniature for Crazy 8s: a green felt tray with a small fan
/// of cards, a stock pile, and an 8 that loops a play onto the discard pile.
/// Matches the toy-diorama style of the other launcher tiles.
class CrazyEightsTileArt extends StatefulWidget {
  final double phase;

  const CrazyEightsTileArt({super.key, this.phase = 0});

  @override
  State<CrazyEightsTileArt> createState() => _CrazyEightsTileArtState();
}

class _CrazyEightsTileArtState extends State<CrazyEightsTileArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6800),
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
        return CustomPaint(painter: _CrazyEightsTilePainter(t: t));
      },
    );
  }
}

class _CrazyEightsTilePainter extends CustomPainter {
  final double t;

  _CrazyEightsTilePainter({required this.t});

  // Card ids (suit * 13 + rank): 8♥ = 1*13+7, A♠ = 0, K♦ = 2*13+12, 5♣ = 3*13+4.
  static const int _eightHearts = 20;
  static const int _aceSpades = 0;
  static const int _kingDiamonds = 38;
  static const int _fiveClubs = 43;

  @override
  void paint(Canvas canvas, Size size) {
    _paintFelt(canvas, size);

    final w = size.shortestSide;
    final cardW = w * 0.24;
    final cx = size.width / 2;

    // Timeline: 0–0.55 idle breathing, 0.55–0.75 the 8 flies to the pile,
    // 0.75–0.9 hold, 0.9–1 the pile card resets underneath.
    final flyT = Curves.easeInOutCubic.transform(
      ((t - 0.55) / 0.20).clamp(0.0, 1.0),
    );
    final settle = ((t - 0.75) / 0.15).clamp(0.0, 1.0);

    // Stock pile top-left.
    final stockC = Offset(cx - cardW * 1.1, size.height * 0.30);
    for (var i = 2; i >= 0; i--) {
      _card(
        canvas,
        center: stockC - Offset(i * 1.5, i * 1.5),
        w: cardW,
        angle: -0.06,
        faceUp: false,
      );
    }

    // Discard pile top-right: K♦ underneath, 8♥ lands on top.
    final discardC = Offset(cx + cardW * 1.1, size.height * 0.32);
    _card(canvas, center: discardC, w: cardW, angle: 0.08,
        faceUp: true, card: _kingDiamonds);
    if (settle > 0 || flyT >= 1) {
      _card(canvas, center: discardC, w: cardW, angle: -0.05,
          faceUp: true, card: _eightHearts);
    }

    // Bottom fan: A♠, 8♥ (flies), 5♣.
    final baseY = size.height * 0.78;
    final breathe = math.sin(t * 2 * math.pi * 2) * w * 0.006;

    _card(
      canvas,
      center: Offset(cx - cardW * 0.72, baseY + w * 0.02),
      w: cardW * 1.06,
      angle: -0.22,
      faceUp: true,
      card: _aceSpades,
    );
    _card(
      canvas,
      center: Offset(cx + cardW * 0.72, baseY + w * 0.02),
      w: cardW * 1.06,
      angle: 0.22,
      faceUp: true,
      card: _fiveClubs,
    );
    // The 8 sits proud of the fan (playable) and flies to the discard.
    if (flyT < 1) {
      final from = Offset(cx, baseY - w * 0.035 + breathe);
      final at = Offset.lerp(from, discardC, flyT)!;
      final angle = -0.05 * flyT;
      final scale = 1.0 + 0.15 * math.sin(flyT * math.pi);
      _card(
        canvas,
        center: at,
        w: cardW * 1.06 * scale,
        angle: angle,
        faceUp: true,
        card: _eightHearts,
        glow: flyT == 0,
      );
    }
  }

  void _paintFelt(Canvas canvas, Size size) {
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
          colors: [Color(0xFF3FA862), Color(0xFF2D8A4E), Color(0xFF1F6B3A)],
          stops: [0.0, 0.48, 1.0],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.15, -0.35),
          radius: 1.05,
          colors: [
            Colors.white.withValues(alpha: 0.14),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.12),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      outer.deflate(size.width * 0.012),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.014
        ..color = Colors.black.withValues(alpha: 0.12),
    );
  }

  void _card(
    Canvas canvas, {
    required Offset center,
    required double w,
    required double angle,
    required bool faceUp,
    int? card,
    bool glow = false,
  }) {
    final h = w * 1.4;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.shift(Offset(0, w * 0.06)),
        Radius.circular(w * 0.13),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.07),
    );
    if (faceUp) {
      CrazyEightsCardArt.paintFace(canvas, rect, card!);
    } else {
      CrazyEightsCardArt.paintBack(canvas, rect);
    }
    if (glow) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.deflate(0.5),
          Radius.circular(w * 0.13),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.05
          ..color = const Color(0xFFF4B740).withValues(alpha: 0.9),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CrazyEightsTilePainter old) => old.t != t;
}
