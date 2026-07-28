import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:minigames_cards/minigames_cards.dart';

/// Launcher-tile miniature for Go Fish: a pond of backs up top and three
/// sevens in a tray below, with the fourth seven sailing across from the
/// opponent's side to close the book — the one beat the whole game is built
/// around, in a four-second loop.
class GoFishTileArt extends StatefulWidget {
  final double phase;

  const GoFishTileArt({super.key, this.phase = 0});

  @override
  State<GoFishTileArt> createState() => _GoFishTileArtState();
}

class _GoFishTileArtState extends State<GoFishTileArt>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
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
        painter: _GoFishTilePainter(t: (c.value + widget.phase) % 1.0),
      ),
    );
  }
}

class _GoFishTilePainter extends CustomPainter {
  final double t;

  _GoFishTilePainter({required this.t});

  static final List<PlayingCard> _held = PlayingCard.parseAll('7C 7D 7H');
  static final PlayingCard _joiner = PlayingCard.parse('7S');

  static const Color _felt = Color(0xFF1C5E63);
  static const Color _book = Color(0xFF57C7FF);
  static const Color _catch = Color(0xFF7BE0A8);

  @override
  void paint(Canvas canvas, Size size) {
    _paintFelt(canvas, size);

    final w = size.shortestSide;
    final cardW = w * 0.175;
    final cardH = cardW * kCardAspectRatio;
    final cx = size.width / 2;

    // Timeline: the ask lands, the seventh sails over, the book lays down.
    final fly = Curves.easeInOutCubic.transform(
      ((t - 0.34) / 0.24).clamp(0.0, 1.0),
    );
    final booked = Curves.easeOutBack.transform(
      ((t - 0.66) / 0.16).clamp(0.0, 1.0),
    );
    final swell = math.sin(t * 2 * math.pi) * w * 0.005;

    // The pond, centre-top, with the opponent's backs fanned above it.
    final pondC = Offset(cx, size.height * 0.36);
    for (var i = 2; i >= 0; i--) {
      _card(
        canvas,
        center: pondC - Offset(i * 1.8, i * 1.8),
        w: cardW,
        angle: 0,
        card: null,
      );
    }
    for (var i = 0; i < 3; i++) {
      _card(
        canvas,
        center: Offset(cx + (i - 1) * cardW * 0.52, size.height * 0.135),
        w: cardW * 0.78,
        angle: (i - 1) * 0.10,
        card: null,
      );
    }

    // The hand: three sevens in their tray, low and centred.
    final step = cardW * 0.50;
    final groupW = cardW + step * (_held.length - 1);
    final left = cx - groupW / 2;
    final rowY = size.height * 0.755 + swell;

    // Once the book closes the group lifts away and a book chip takes its
    // place — the same swap the table makes.
    final layDown = booked.clamp(0.0, 1.0);
    final trayAlpha = (1 - layDown).clamp(0.0, 1.0);

    if (trayAlpha > 0.02) {
      final trayRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left - w * 0.03,
          rowY - cardH / 2 - w * 0.055,
          groupW + w * 0.06,
          cardH + w * 0.085,
        ),
        Radius.circular(w * 0.05),
      );
      final tint = Color.lerp(Colors.white, _catch, fly)!;
      canvas.drawRRect(
        trayRect,
        Paint()..color = tint.withValues(alpha: 0.14 * trayAlpha),
      );
      canvas.drawRRect(
        trayRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.010
          ..color = tint.withValues(alpha: (0.35 + 0.5 * fly) * trayAlpha),
      );
      CardGlyphs.paintRun(
        canvas,
        '7',
        origin: Offset(left - w * 0.005, rowY - cardH / 2 - w * 0.048),
        height: w * 0.075,
        color: tint.withValues(alpha: 0.92 * trayAlpha),
        weight: 0.22,
      );

      for (var i = 0; i < _held.length; i++) {
        _card(
          canvas,
          center: Offset(left + cardW / 2 + i * step, rowY + layDown * w * 0.2),
          w: cardW,
          angle: 0,
          card: _held[i],
          alpha: trayAlpha,
        );
      }

      // The fourth seven, out of the opponent's fan and into the group.
      final from = Offset(cx + cardW * 0.52, size.height * 0.135);
      final to = Offset(left + cardW / 2 + _held.length * step * 0.62, rowY);
      final at = Offset.lerp(from, to, fly)!;
      if (fly > 0.001) {
        _card(
          canvas,
          center: at,
          w: cardW * (1 + 0.12 * math.sin(fly * math.pi)),
          angle: 0.22 * (1 - fly),
          card: _joiner,
          glow: fly > 0.97,
          alpha: trayAlpha,
        );
      }
    }

    if (layDown > 0.02) {
      _bookChip(
        canvas,
        center: Offset(cx, rowY - (1 - layDown) * w * 0.1),
        width: w * 0.34 * layDown.clamp(0.6, 1.0),
        height: w * 0.30 * layDown.clamp(0.6, 1.0),
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
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(_felt, Colors.white, 0.16)!,
            _felt,
            Color.lerp(_felt, Colors.black, 0.36)!,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Offset.zero & size),
    );
    canvas.save();
    canvas.clipRRect(outer);
    for (var i = 1; i <= 3; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * 0.5, size.height * 0.36),
          width: size.width * 0.30 * i,
          height: size.height * 0.12 * i,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.008
          ..color = Colors.white.withValues(alpha: 0.07),
      );
    }
    canvas.restore();
  }

  void _bookChip(
    Canvas canvas, {
    required Offset center,
    required double width,
    required double height,
  }) {
    final rect = Rect.fromCenter(
      center: center,
      width: width,
      height: height,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(height * 0.26));
    canvas.drawRRect(rrect, Paint()..color = _book.withValues(alpha: 0.26));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = height * 0.055
        ..color = _book,
    );
    CardGlyphs.paintCentered(
      canvas,
      '7',
      center: Offset(rect.center.dx, rect.top + height * 0.38),
      height: height * 0.44,
      color: Colors.white,
      weight: 0.21,
    );
    final pipS = height * 0.18;
    for (var i = 0; i < Suit.values.length; i++) {
      CardSuits.paint(
        canvas,
        Rect.fromCenter(
          center: Offset(
            rect.center.dx - pipS * 2.4 + i * pipS * 1.6,
            rect.bottom - height * 0.20,
          ),
          width: pipS,
          height: pipS,
        ),
        Suit.values[i],
        Colors.white.withValues(alpha: 0.85),
      );
    }
  }

  void _card(
    Canvas canvas, {
    required Offset center,
    required double w,
    required double angle,
    required PlayingCard? card,
    bool glow = false,
    double alpha = 1.0,
  }) {
    if (alpha <= 0.01) return;
    final h = w * kCardAspectRatio;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    if (alpha < 0.99) {
      canvas.saveLayer(
        Rect.fromCenter(center: Offset.zero, width: w * 2, height: h * 2),
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }
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
        RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(w * 0.09)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.045
          ..color = _catch.withValues(alpha: 0.9),
      );
    }
    if (alpha < 0.99) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoFishTilePainter old) => old.t != t;
}
