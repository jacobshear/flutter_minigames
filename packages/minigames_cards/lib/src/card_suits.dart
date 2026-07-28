import 'package:flutter/rendering.dart';

import 'playing_card.dart';

/// Vector suit pips, drawn as filled paths in a unit box (0..1 × 0..1).
///
/// Same reasoning as [CardGlyphs]: no font, no asset, so a pip is crisp at
/// 12 px in a corner index and at 200 px on a splash, and renders identically
/// inside a widget test.
abstract final class CardSuits {
  /// The filled outline of [suit] scaled into [rect].
  static Path path(Suit suit, Rect rect) {
    final unit = switch (suit) {
      Suit.spades => _spade(),
      Suit.hearts => _heart(),
      Suit.diamonds => _diamond(),
      Suit.clubs => _club(),
    };
    final m = Matrix4.translationValues(rect.left, rect.top, 0)
      ..scaleByDouble(rect.width, rect.height, 1, 1);
    return unit.transform(m.storage);
  }

  /// Fills [suit] into [rect] with [color].
  static void paint(Canvas canvas, Rect rect, Suit suit, Color color) {
    canvas.drawPath(path(suit, rect), Paint()..color = color);
  }

  /// Fills [suit] into [rect] rotated 180° about the rect's centre — the way
  /// the lower half of a pip layout is printed.
  static void paintInverted(
    Canvas canvas,
    Rect rect,
    Suit suit,
    Color color,
  ) {
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(3.141592653589793);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    paint(canvas, rect, suit, color);
    canvas.restore();
  }

  static Path _heart() => Path()
    ..moveTo(0.5, 0.98)
    ..cubicTo(0.22, 0.74, 0.04, 0.55, 0.04, 0.32)
    ..cubicTo(0.04, 0.12, 0.20, 0.02, 0.32, 0.02)
    ..cubicTo(0.42, 0.02, 0.48, 0.08, 0.5, 0.16)
    ..cubicTo(0.52, 0.08, 0.58, 0.02, 0.68, 0.02)
    ..cubicTo(0.80, 0.02, 0.96, 0.12, 0.96, 0.32)
    ..cubicTo(0.96, 0.55, 0.78, 0.74, 0.5, 0.98)
    ..close();

  static Path _diamond() => Path()
    ..moveTo(0.5, 0.0)
    ..cubicTo(0.60, 0.18, 0.74, 0.36, 0.88, 0.5)
    ..cubicTo(0.74, 0.64, 0.60, 0.82, 0.5, 1.0)
    ..cubicTo(0.40, 0.82, 0.26, 0.64, 0.12, 0.5)
    ..cubicTo(0.26, 0.36, 0.40, 0.18, 0.5, 0.0)
    ..close();

  static Path _spade() => Path()
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

  static Path _club() => Path()
    ..addOval(Rect.fromCircle(center: const Offset(0.5, 0.25), radius: 0.21))
    ..addOval(Rect.fromCircle(center: const Offset(0.25, 0.56), radius: 0.21))
    ..addOval(Rect.fromCircle(center: const Offset(0.75, 0.56), radius: 0.21))
    ..moveTo(0.53, 0.64)
    ..cubicTo(0.55, 0.88, 0.61, 0.96, 0.68, 1.0)
    ..lineTo(0.32, 1.0)
    ..cubicTo(0.39, 0.96, 0.45, 0.88, 0.47, 0.64)
    ..close();
}
