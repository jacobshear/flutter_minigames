import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_minigames/src/cards/cards.dart';

/// Launcher-tile miniature for Gin Rummy: a felt tray with the stock and
/// discard up top and a small hand below, where a run of three sits in its
/// tray and a fourth card slides in to complete it — the loop shows what the
/// game is about in one gesture.
class GinRummyTileArt extends StatefulWidget {
  final double phase;

  const GinRummyTileArt({super.key, this.phase = 0});

  @override
  State<GinRummyTileArt> createState() => _GinRummyTileArtState();
}

class _GinRummyTileArtState extends State<GinRummyTileArt>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6400),
    )..repeat();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => CustomPaint(
        painter: _GinRummyTilePainter(t: (c.value + widget.phase) % 1.0),
      ),
    );
  }
}

class _GinRummyTilePainter extends CustomPainter {
  final double t;

  _GinRummyTilePainter({required this.t});

  static final List<PlayingCard> _run = PlayingCard.parseAll('5H 6H 7H');
  static final PlayingCard _joiner = PlayingCard.parse('8H');
  static final PlayingCard _discardTop = PlayingCard.parse('QS');

  @override
  void paint(Canvas canvas, Size size) {
    _paintFelt(canvas, size);

    final w = size.shortestSide;
    final cardW = w * 0.185;
    final cardH = cardW * kCardAspectRatio;
    final cx = size.width / 2;

    // Timeline: idle, then the 8 flies in and joins the run, then a hold.
    final fly = Curves.easeInOutCubic.transform(
      ((t - 0.45) / 0.22).clamp(0.0, 1.0),
    );
    final breathe = math.sin(t * 2 * math.pi) * w * 0.006;

    // Stock + discard.
    final stockC = Offset(cx - cardW * 0.85, size.height * 0.30);
    final discardC = Offset(cx + cardW * 0.85, size.height * 0.30);
    for (var i = 2; i >= 0; i--) {
      _card(
        canvas,
        center: stockC - Offset(i * 1.6, i * 1.6),
        w: cardW,
        angle: -0.05,
        card: null,
      );
    }
    _card(canvas, center: discardC, w: cardW, angle: 0.07, card: _discardTop);

    // The meld tray and its run, low and centred.
    final step = cardW * 0.56;
    final runW = cardW + step * (_run.length + fly - 1);
    final left = cx - runW / 2;
    final rowY = size.height * 0.70 + breathe;

    final trayRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        left - w * 0.03,
        rowY - cardH / 2 - w * 0.03,
        runW + w * 0.06,
        cardH + w * 0.06,
      ),
      Radius.circular(w * 0.05),
    );
    canvas.drawRRect(
      trayRect,
      Paint()..color = const Color(0xFF57C7FF).withValues(alpha: 0.22),
    );
    canvas.drawRRect(
      trayRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.011
        ..color = const Color(0xFF57C7FF).withValues(alpha: 0.7),
    );

    for (var i = 0; i < _run.length; i++) {
      _card(
        canvas,
        center: Offset(left + cardW / 2 + i * step, rowY),
        w: cardW,
        angle: 0,
        card: _run[i],
      );
    }

    // The joining card: out of the discard pile and into the run.
    final from = discardC;
    final to = Offset(left + cardW / 2 + _run.length * step, rowY);
    final at = Offset.lerp(from, to, fly)!;
    _card(
      canvas,
      center: at,
      w: cardW * (1 + 0.10 * math.sin(fly * math.pi)),
      angle: 0.07 * (1 - fly),
      card: _joiner,
      glow: fly > 0.98,
    );
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
          colors: [Color(0xFF35946A), Color(0xFF23694A), Color(0xFF174F36)],
          stops: [0.0, 0.5, 1.0],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.4),
          radius: 1.05,
          colors: [
            Colors.white.withValues(alpha: 0.13),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.14),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  void _card(
    Canvas canvas, {
    required Offset center,
    required double w,
    required double angle,
    required PlayingCard? card,
    bool glow = false,
  }) {
    final h = w * kCardAspectRatio;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.shift(Offset(0, w * 0.05)),
        Radius.circular(w * 0.09),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.24)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.07),
    );
    if (card == null) {
      paintCardBack(canvas, rect);
    } else {
      paintPlayingCard(canvas, rect, card);
    }
    if (glow) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.deflate(0.5),
          Radius.circular(w * 0.09),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.045
          ..color = const Color(0xFFF4B740).withValues(alpha: 0.9),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GinRummyTilePainter old) => old.t != t;
}
