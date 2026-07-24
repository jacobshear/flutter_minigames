import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'crazy_eights_game.dart';

/// Pure-vector playing-card rendering (no image assets, no Text glyphs) so
/// cards rasterize crisply at any size — including in golden/PNG renders.
///
/// Rank indices use a small stroked vector font; suits are filled paths.
/// Number cards get classic pip arrangements, face cards a GP-simple framed
/// letter portrait.
abstract final class CrazyEightsCardArt {
  static const Color red = Color(0xFFD8342C);
  static const Color ink = Color(0xFF26262B);
  static const Color cardWhite = Color(0xFFFDFDFB);
  static const Color backBlue = Color(0xFF3672DC);

  static Color suitColor(int suit) =>
      (suit == CrazyEightsCards.hearts || suit == CrazyEightsCards.diamonds)
          ? red
          : ink;

  /// Corner radius used for a card of [size].
  static double cornerRadius(Size size) => size.width * 0.13;

  // -------------------------------------------------------------------------
  // Card faces
  // -------------------------------------------------------------------------

  /// Paints the face of [card] (0..51) filling [rect].
  static void paintFace(Canvas canvas, Rect rect, int card) {
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(cornerRadius(rect.size)),
    );
    _paintCardBase(canvas, rect, rrect);

    final rank = CrazyEightsCards.rankOf(card);
    final suit = CrazyEightsCards.suitOf(card);
    final color = suitColor(suit);
    final w = rect.width;

    // Corner indices (top-left + rotated bottom-right).
    void corner() {
      final glyphH = w * 0.20;
      final label = CrazyEightsCards.rankLabels[rank];
      final glyphW = _paintGlyphRun(
        canvas,
        label,
        origin: rect.topLeft + Offset(w * 0.075, w * 0.075),
        height: glyphH,
        color: color,
      );
      paintSuit(
        canvas,
        Rect.fromCenter(
          center: rect.topLeft +
              Offset(w * 0.075 + glyphW / 2, w * 0.075 + glyphH + w * 0.10),
          width: w * 0.125,
          height: w * 0.125,
        ),
        suit,
      );
    }

    corner();
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(math.pi);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    corner();
    canvas.restore();

    // Center art.
    if (rank == 0) {
      // Ace — one big pip.
      paintSuit(
        canvas,
        Rect.fromCenter(center: rect.center, width: w * 0.44, height: w * 0.44),
        suit,
      );
    } else if (rank <= 9) {
      _paintPips(canvas, rect, rank, suit);
    } else {
      _paintFaceCard(canvas, rect, rank, suit);
    }
  }

  /// Paints the shared card back filling [rect].
  static void paintBack(Canvas canvas, Rect rect) {
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(cornerRadius(rect.size)),
    );
    _paintCardBase(canvas, rect, rrect);

    final inner = rect.deflate(rect.width * 0.075);
    final innerR = RRect.fromRectAndRadius(
      inner,
      Radius.circular(cornerRadius(rect.size) * 0.62),
    );
    canvas.drawRRect(
      innerR,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A85EE), backBlue, Color(0xFF2A5BC0)],
        ).createShader(inner),
    );

    // Diagonal lattice.
    canvas.save();
    canvas.clipRRect(innerR);
    final lattice = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = math.max(1, rect.width * 0.022);
    final step = rect.width * 0.13;
    for (var x = -inner.height; x < inner.width; x += step) {
      canvas.drawLine(
        Offset(inner.left + x, inner.top),
        Offset(inner.left + x + inner.height, inner.bottom),
        lattice,
      );
      canvas.drawLine(
        Offset(inner.left + x + inner.height, inner.top),
        Offset(inner.left + x, inner.bottom),
        lattice,
      );
    }
    canvas.restore();

    canvas.drawRRect(
      innerR.deflate(rect.width * 0.02),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, rect.width * 0.018)
        ..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  static void _paintCardBase(Canvas canvas, Rect rect, RRect rrect) {
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            cardWhite,
            Color.lerp(cardWhite, Colors.black, 0.045)!,
          ],
        ).createShader(rect),
    );
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ink.withValues(alpha: 0.16),
    );
  }

  // -------------------------------------------------------------------------
  // Pips
  // -------------------------------------------------------------------------

  /// Classic pip positions per rank index 1..9 (2..10), in unit coords of the
  /// pip area.
  static const Map<int, List<Offset>> _pipLayouts = {
    1: [Offset(0.5, 0.16), Offset(0.5, 0.84)],
    2: [Offset(0.5, 0.14), Offset(0.5, 0.5), Offset(0.5, 0.86)],
    3: [
      Offset(0.26, 0.16), Offset(0.74, 0.16),
      Offset(0.26, 0.84), Offset(0.74, 0.84),
    ],
    4: [
      Offset(0.26, 0.16), Offset(0.74, 0.16), Offset(0.5, 0.5),
      Offset(0.26, 0.84), Offset(0.74, 0.84),
    ],
    5: [
      Offset(0.26, 0.16), Offset(0.74, 0.16),
      Offset(0.26, 0.5), Offset(0.74, 0.5),
      Offset(0.26, 0.84), Offset(0.74, 0.84),
    ],
    6: [
      Offset(0.26, 0.16), Offset(0.74, 0.16), Offset(0.5, 0.33),
      Offset(0.26, 0.5), Offset(0.74, 0.5),
      Offset(0.26, 0.84), Offset(0.74, 0.84),
    ],
    7: [
      Offset(0.26, 0.16), Offset(0.74, 0.16), Offset(0.5, 0.33),
      Offset(0.26, 0.5), Offset(0.74, 0.5), Offset(0.5, 0.67),
      Offset(0.26, 0.84), Offset(0.74, 0.84),
    ],
    8: [
      Offset(0.26, 0.14), Offset(0.74, 0.14),
      Offset(0.26, 0.38), Offset(0.74, 0.38), Offset(0.5, 0.5),
      Offset(0.26, 0.62), Offset(0.74, 0.62),
      Offset(0.26, 0.86), Offset(0.74, 0.86),
    ],
    9: [
      Offset(0.26, 0.14), Offset(0.74, 0.14), Offset(0.5, 0.26),
      Offset(0.26, 0.38), Offset(0.74, 0.38),
      Offset(0.26, 0.62), Offset(0.74, 0.62), Offset(0.5, 0.74),
      Offset(0.26, 0.86), Offset(0.74, 0.86),
    ],
  };

  static void _paintPips(Canvas canvas, Rect rect, int rank, int suit) {
    // Inset past the corner indices so pip rows never merge with them.
    final area = Rect.fromLTRB(
      rect.left + rect.width * 0.27,
      rect.top + rect.height * 0.235,
      rect.right - rect.width * 0.27,
      rect.bottom - rect.height * 0.235,
    );
    final pip = rect.width * (rank >= 8 ? 0.165 : 0.19);
    for (final u in _pipLayouts[rank]!) {
      final c = Offset(
        area.left + u.dx * area.width,
        area.top + u.dy * area.height,
      );
      final flipped = u.dy > 0.5;
      if (flipped) {
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(math.pi);
        canvas.translate(-c.dx, -c.dy);
      }
      paintSuit(
        canvas,
        Rect.fromCenter(center: c, width: pip, height: pip),
        suit,
      );
      if (flipped) canvas.restore();
    }
  }

  static void _paintFaceCard(Canvas canvas, Rect rect, int rank, int suit) {
    final color = suitColor(suit);
    final w = rect.width;
    final frame = Rect.fromLTRB(
      rect.left + w * 0.20,
      rect.top + rect.height * 0.18,
      rect.right - w * 0.20,
      rect.bottom - rect.height * 0.18,
    );
    final frameR = RRect.fromRectAndRadius(frame, Radius.circular(w * 0.06));

    // Quiet patterned panel behind the letter.
    canvas.save();
    canvas.clipRRect(frameR);
    canvas.drawRect(frame, Paint()..color = color.withValues(alpha: 0.06));
    final hatch = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..strokeWidth = math.max(1, w * 0.016);
    final step = w * 0.10;
    for (var x = -frame.height; x < frame.width; x += step) {
      canvas.drawLine(
        Offset(frame.left + x, frame.top),
        Offset(frame.left + x + frame.height, frame.bottom),
        hatch,
      );
    }
    canvas.restore();
    canvas.drawRRect(
      frameR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, w * 0.022)
        ..color = color.withValues(alpha: 0.75),
    );

    // Big letter portrait.
    final glyphH = rect.height * 0.26;
    final label = CrazyEightsCards.rankLabels[rank];
    final glyphW = _glyphRunWidth(label, glyphH);
    _paintGlyphRun(
      canvas,
      label,
      origin: rect.center - Offset(glyphW / 2, glyphH / 2),
      height: glyphH,
      color: color,
      weight: 0.20,
    );

    // Small pips top and bottom of the frame (bottom one rotated).
    final pip = w * 0.13;
    paintSuit(
      canvas,
      Rect.fromCenter(
        center: Offset(rect.center.dx, frame.top + rect.height * 0.075),
        width: pip,
        height: pip,
      ),
      suit,
    );
    final bottom = Offset(rect.center.dx, frame.bottom - rect.height * 0.075);
    canvas.save();
    canvas.translate(bottom.dx, bottom.dy);
    canvas.rotate(math.pi);
    canvas.translate(-bottom.dx, -bottom.dy);
    paintSuit(
      canvas,
      Rect.fromCenter(center: bottom, width: pip, height: pip),
      suit,
    );
    canvas.restore();
  }

  // -------------------------------------------------------------------------
  // Suits
  // -------------------------------------------------------------------------

  /// Paints suit [suit] filling [rect] (in its own suit color unless
  /// [color] is given).
  static void paintSuit(Canvas canvas, Rect rect, int suit, {Color? color}) {
    final path = suitPath(suit, rect);
    canvas.drawPath(path, Paint()..color = color ?? suitColor(suit));
  }

  /// The filled outline of [suit] scaled into [rect].
  static Path suitPath(int suit, Rect rect) {
    final unit = switch (suit) {
      CrazyEightsCards.spades => _spadeUnit(),
      CrazyEightsCards.hearts => _heartUnit(),
      CrazyEightsCards.diamonds => _diamondUnit(),
      _ => _clubUnit(),
    };
    final m = Matrix4.translationValues(rect.left, rect.top, 0)
      ..scaleByDouble(rect.width, rect.height, 1, 1);
    return unit.transform(m.storage);
  }

  static Path _heartUnit() => Path()
    ..moveTo(0.5, 0.98)
    ..cubicTo(0.22, 0.74, 0.04, 0.55, 0.04, 0.32)
    ..cubicTo(0.04, 0.12, 0.20, 0.02, 0.32, 0.02)
    ..cubicTo(0.42, 0.02, 0.48, 0.08, 0.5, 0.16)
    ..cubicTo(0.52, 0.08, 0.58, 0.02, 0.68, 0.02)
    ..cubicTo(0.80, 0.02, 0.96, 0.12, 0.96, 0.32)
    ..cubicTo(0.96, 0.55, 0.78, 0.74, 0.5, 0.98)
    ..close();

  static Path _diamondUnit() => Path()
    ..moveTo(0.5, 0.0)
    ..cubicTo(0.60, 0.18, 0.74, 0.36, 0.90, 0.5)
    ..cubicTo(0.74, 0.64, 0.60, 0.82, 0.5, 1.0)
    ..cubicTo(0.40, 0.82, 0.26, 0.64, 0.10, 0.5)
    ..cubicTo(0.26, 0.36, 0.40, 0.18, 0.5, 0.0)
    ..close();

  static Path _spadeUnit() => Path()
    ..moveTo(0.5, 0.02)
    ..cubicTo(0.62, 0.22, 0.94, 0.42, 0.94, 0.62)
    ..cubicTo(0.94, 0.78, 0.80, 0.86, 0.68, 0.86)
    ..cubicTo(0.60, 0.86, 0.55, 0.82, 0.52, 0.76)
    ..cubicTo(0.54, 0.90, 0.60, 0.97, 0.66, 1.0)
    ..lineTo(0.34, 1.0)
    ..cubicTo(0.40, 0.97, 0.46, 0.90, 0.48, 0.76)
    ..cubicTo(0.45, 0.82, 0.40, 0.86, 0.32, 0.86)
    ..cubicTo(0.20, 0.86, 0.06, 0.78, 0.06, 0.62)
    ..cubicTo(0.06, 0.42, 0.38, 0.22, 0.5, 0.02)
    ..close();

  static Path _clubUnit() => Path()
    ..addOval(Rect.fromCircle(center: const Offset(0.5, 0.26), radius: 0.21))
    ..addOval(Rect.fromCircle(center: const Offset(0.26, 0.56), radius: 0.21))
    ..addOval(Rect.fromCircle(center: const Offset(0.74, 0.56), radius: 0.21))
    ..moveTo(0.52, 0.66)
    ..cubicTo(0.54, 0.88, 0.60, 0.96, 0.66, 1.0)
    ..lineTo(0.34, 1.0)
    ..cubicTo(0.40, 0.96, 0.46, 0.88, 0.48, 0.66)
    ..close();

  // -------------------------------------------------------------------------
  // Vector rank glyphs (stroked mini-font, unit box 0..1 × 0..1, y down)
  // -------------------------------------------------------------------------

  /// Advance width (relative to height 1) per glyph.
  static double _glyphAdvance(String ch) => ch == '1' ? 0.42 : 0.78;

  static double _glyphRunWidth(String label, double height) {
    var w = 0.0;
    for (var i = 0; i < label.length; i++) {
      if (i > 0) w += 0.10;
      w += _glyphAdvance(label[i]);
    }
    return w * height;
  }

  /// Paints [label] ('A', '2'…'10', 'J', 'Q', 'K') starting at [origin]
  /// (top-left), [height] tall. Returns the run width.
  static double _paintGlyphRun(
    Canvas canvas,
    String label, {
    required Offset origin,
    required double height,
    required Color color,
    double weight = 0.17,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = height * weight
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    var x = origin.dx;
    for (var i = 0; i < label.length; i++) {
      if (i > 0) x += 0.10 * height;
      final ch = label[i];
      final adv = _glyphAdvance(ch);
      final m = Matrix4.translationValues(x, origin.dy, 0)
        ..scaleByDouble(adv * height, height, 1, 1);
      for (final stroke in _glyphStrokes(ch)) {
        canvas.drawPath(stroke.transform(m.storage), paint);
      }
      x += adv * height;
    }
    return x - origin.dx;
  }

  static List<Path> _glyphStrokes(String ch) {
    switch (ch) {
      case 'A':
        return [
          Path()
            ..moveTo(0.08, 1)
            ..lineTo(0.5, 0.02)
            ..lineTo(0.92, 1),
          Path()
            ..moveTo(0.27, 0.66)
            ..lineTo(0.73, 0.66),
        ];
      case '2':
        return [
          Path()
            ..moveTo(0.14, 0.28)
            ..cubicTo(0.14, -0.02, 0.86, -0.02, 0.86, 0.28)
            ..cubicTo(0.86, 0.52, 0.50, 0.64, 0.12, 1.0)
            ..lineTo(0.90, 1.0),
        ];
      case '3':
        return [
          Path()
            ..moveTo(0.13, 0.20)
            ..cubicTo(0.22, -0.05, 0.87, -0.03, 0.86, 0.25)
            ..cubicTo(0.85, 0.46, 0.60, 0.50, 0.47, 0.50)
            ..cubicTo(0.62, 0.50, 0.90, 0.55, 0.89, 0.76)
            ..cubicTo(0.87, 1.05, 0.18, 1.05, 0.11, 0.79),
        ];
      case '4':
        return [
          Path()
            ..moveTo(0.72, 1)
            ..lineTo(0.72, 0.02)
            ..lineTo(0.08, 0.68)
            ..lineTo(0.95, 0.68),
        ];
      case '5':
        return [
          Path()
            ..moveTo(0.82, 0.02)
            ..lineTo(0.22, 0.02)
            ..lineTo(0.16, 0.46)
            ..cubicTo(0.35, 0.34, 0.90, 0.38, 0.88, 0.70)
            ..cubicTo(0.86, 1.04, 0.20, 1.05, 0.12, 0.80),
        ];
      case '6':
        return [
          Path()
            ..moveTo(0.80, 0.06)
            ..cubicTo(0.45, -0.08, 0.15, 0.22, 0.14, 0.60)
            ..cubicTo(0.13, 0.90, 0.30, 1.02, 0.51, 1.02)
            ..cubicTo(0.73, 1.02, 0.88, 0.88, 0.87, 0.72)
            ..cubicTo(0.85, 0.48, 0.50, 0.42, 0.32, 0.52),
        ];
      case '7':
        return [
          Path()
            ..moveTo(0.10, 0.02)
            ..lineTo(0.90, 0.02)
            ..lineTo(0.40, 1.0),
        ];
      case '8':
        return [
          Path()
            ..addOval(
              Rect.fromCenter(
                center: const Offset(0.5, 0.27),
                width: 0.58,
                height: 0.46,
              ),
            ),
          Path()
            ..addOval(
              Rect.fromCenter(
                center: const Offset(0.5, 0.74),
                width: 0.68,
                height: 0.52,
              ),
            ),
        ];
      case '9':
        return [
          Path()
            ..addOval(
              Rect.fromCenter(
                center: const Offset(0.5, 0.30),
                width: 0.62,
                height: 0.52,
              ),
            ),
          Path()
            ..moveTo(0.81, 0.36)
            ..cubicTo(0.78, 0.70, 0.66, 0.90, 0.42, 1.0),
        ];
      case '1':
        return [
          Path()
            ..moveTo(0.08, 0.24)
            ..lineTo(0.62, 0.02)
            ..lineTo(0.62, 1.0),
        ];
      case '0':
        return [
          Path()
            ..addOval(
              Rect.fromCenter(
                center: const Offset(0.5, 0.51),
                width: 0.80,
                height: 0.98,
              ),
            ),
        ];
      case 'J':
        return [
          Path()
            ..moveTo(0.34, 0.02)
            ..lineTo(0.94, 0.02),
          Path()
            ..moveTo(0.66, 0.02)
            ..lineTo(0.66, 0.70)
            ..cubicTo(0.66, 1.04, 0.12, 1.04, 0.10, 0.72),
        ];
      case 'Q':
        return [
          Path()
            ..addOval(
              Rect.fromCenter(
                center: const Offset(0.48, 0.48),
                width: 0.80,
                height: 0.92,
              ),
            ),
          Path()
            ..moveTo(0.58, 0.70)
            ..lineTo(0.94, 1.02),
        ];
      case 'K':
        return [
          Path()
            ..moveTo(0.16, 0.02)
            ..lineTo(0.16, 1.0),
          Path()
            ..moveTo(0.85, 0.02)
            ..lineTo(0.20, 0.60),
          Path()
            ..moveTo(0.46, 0.44)
            ..lineTo(0.90, 1.0),
        ];
      default:
        return const [];
    }
  }
}

/// A single playing card as a widget: face-up art for [card], or the shared
/// back when [faceUp] is false. Aspect ratio is fixed at 1 : 1.4.
class PlayingCardView extends StatelessWidget {
  /// Card 0..51; may be null when [faceUp] is false.
  final int? card;
  final bool faceUp;
  final double width;

  /// Gold ring + slight glow marking a playable card.
  final bool highlighted;

  /// Drop shadow under the card.
  final bool shadow;

  const PlayingCardView({
    super.key,
    required this.card,
    required this.width,
    this.faceUp = true,
    this.highlighted = false,
    this.shadow = true,
  }) : assert(card != null || !faceUp, 'face-up cards need a card value');

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 1.4,
      child: CustomPaint(
        painter: _CardPainter(
          card: card,
          faceUp: faceUp,
          highlighted: highlighted,
          shadow: shadow,
        ),
      ),
    );
  }
}

class _CardPainter extends CustomPainter {
  final int? card;
  final bool faceUp;
  final bool highlighted;
  final bool shadow;

  _CardPainter({
    required this.card,
    required this.faceUp,
    required this.highlighted,
    required this.shadow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(CrazyEightsCardArt.cornerRadius(size)),
    );
    if (shadow) {
      canvas.drawRRect(
        rrect.shift(Offset(0, size.width * 0.05)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.28)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.06),
      );
    }
    if (faceUp) {
      CrazyEightsCardArt.paintFace(canvas, rect, card!);
    } else {
      CrazyEightsCardArt.paintBack(canvas, rect);
    }
    if (highlighted) {
      canvas.drawRRect(
        rrect.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, size.width * 0.045)
          ..color = const Color(0xFFF4B740),
      );
    }
  }

  @override
  bool shouldRepaint(_CardPainter old) =>
      old.card != card ||
      old.faceUp != faceUp ||
      old.highlighted != highlighted ||
      old.shadow != shadow;
}
