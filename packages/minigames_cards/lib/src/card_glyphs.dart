import 'package:flutter/rendering.dart';

/// A hand-stroked vector mini-font for card faces and counters.
///
/// Card art never uses `TextPainter`: a widget test's default font renders
/// every glyph as a filled box, which makes PNG renders unjudgeable, and text
/// layout is the slowest thing in a card painter. These glyphs are centreline
/// strokes in a unit box (x 0..advance, y 0..1, y down), scaled and stroked —
/// crisp at any size, identical in tests and on device.
///
/// Covers `0`–`9`, `A`, `J`, `Q`, `K` — enough for card ranks and for the
/// numeric counters card games need (deadwood counts, scores, book totals).
abstract final class CardGlyphs {
  /// Gap between glyphs, relative to glyph height.
  static const double tracking = 0.10;

  /// Advance width of [ch] relative to glyph height.
  static double advance(String ch) => switch (ch) {
        '1' => 0.42,
        '.' => 0.26,
        '-' => 0.50,
        _ => 0.72,
      };

  /// Width of [label] rendered at [height].
  static double runWidth(String label, double height) {
    var w = 0.0;
    for (var i = 0; i < label.length; i++) {
      if (i > 0) w += tracking;
      w += advance(label[i]);
    }
    return w * height;
  }

  /// Strokes [label] with its top-left corner at [origin], [height] tall.
  ///
  /// When [outline] is set the run is stroked twice — a wider outline pass,
  /// then the fill — which is what lets a glyph sit on a busy field without
  /// losing its edge. Returns the painted width.
  static double paintRun(
    Canvas canvas,
    String label, {
    required Offset origin,
    required double height,
    required Color color,
    double weight = 0.19,
    Color? outline,
    double outlineWeight = 0.34,
    double outlineAlpha = 1.0,
  }) {
    Paint pen(Color c, double stroke) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = height * stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = c;

    final passes = <Paint>[
      if (outline != null)
        pen(outline.withValues(alpha: outlineAlpha), outlineWeight),
      pen(color, weight),
    ];

    var x = origin.dx;
    for (var i = 0; i < label.length; i++) {
      if (i > 0) x += tracking * height;
      final ch = label[i];
      final adv = advance(ch);
      final m = Matrix4.translationValues(x, origin.dy, 0)
        ..scaleByDouble(adv * height, height, 1, 1);
      for (final path in strokes(ch)) {
        final scaled = path.transform(m.storage);
        for (final paint in passes) {
          canvas.drawPath(scaled, paint);
        }
      }
      x += adv * height;
    }
    return x - origin.dx;
  }

  /// Strokes [label] centred on [center].
  static void paintCentered(
    Canvas canvas,
    String label, {
    required Offset center,
    required double height,
    required Color color,
    double weight = 0.19,
    Color? outline,
    double outlineWeight = 0.34,
    double outlineAlpha = 1.0,
  }) {
    final w = runWidth(label, height);
    paintRun(
      canvas,
      label,
      origin: center - Offset(w / 2, height / 2),
      height: height,
      color: color,
      weight: weight,
      outline: outline,
      outlineWeight: outlineWeight,
      outlineAlpha: outlineAlpha,
    );
  }

  /// The centreline strokes of [ch] in its unit box. Unknown characters
  /// return an empty list rather than throwing — a missing glyph should never
  /// take a frame down.
  static List<Path> strokes(String ch) {
    switch (ch) {
      case 'A':
        return [
          Path()
            ..moveTo(0.06, 1.0)
            ..lineTo(0.5, 0.02)
            ..lineTo(0.94, 1.0),
          Path()
            ..moveTo(0.25, 0.68)
            ..lineTo(0.75, 0.68),
        ];
      case 'J':
        return [
          Path()
            ..moveTo(0.30, 0.02)
            ..lineTo(0.96, 0.02),
          Path()
            ..moveTo(0.66, 0.02)
            ..lineTo(0.66, 0.70)
            ..cubicTo(0.66, 1.05, 0.10, 1.05, 0.07, 0.70),
        ];
      case 'Q':
        return [
          Path()
            ..addOval(
              Rect.fromCenter(
                center: const Offset(0.47, 0.48),
                width: 0.80,
                height: 0.92,
              ),
            ),
          Path()
            ..moveTo(0.56, 0.70)
            ..lineTo(0.95, 1.04),
        ];
      case 'K':
        return [
          Path()
            ..moveTo(0.12, 0.02)
            ..lineTo(0.12, 1.0),
          Path()
            ..moveTo(0.88, 0.02)
            ..lineTo(0.17, 0.58),
          Path()
            ..moveTo(0.42, 0.42)
            ..lineTo(0.92, 1.0),
        ];
      case '0':
        return [
          Path()
            ..addOval(
              Rect.fromCenter(
                center: const Offset(0.5, 0.51),
                width: 0.76,
                height: 0.98,
              ),
            ),
        ];
      case '1':
        return [
          Path()
            ..moveTo(0.05, 0.26)
            ..lineTo(0.60, 0.02)
            ..lineTo(0.60, 1.0),
        ];
      case '2':
        return [
          Path()
            ..moveTo(0.10, 0.27)
            ..cubicTo(0.11, -0.03, 0.86, -0.04, 0.86, 0.28)
            ..cubicTo(0.86, 0.53, 0.46, 0.66, 0.08, 1.0)
            ..lineTo(0.90, 1.0),
        ];
      case '3':
        return [
          Path()
            ..moveTo(0.10, 0.20)
            ..cubicTo(0.20, -0.05, 0.86, -0.04, 0.85, 0.25)
            ..cubicTo(0.84, 0.46, 0.58, 0.50, 0.44, 0.50)
            ..cubicTo(0.60, 0.50, 0.89, 0.55, 0.88, 0.76)
            ..cubicTo(0.86, 1.06, 0.15, 1.05, 0.08, 0.78),
        ];
      case '4':
        return [
          Path()
            ..moveTo(0.70, 1.0)
            ..lineTo(0.70, 0.02)
            ..lineTo(0.05, 0.69)
            ..lineTo(0.95, 0.69),
        ];
      case '5':
        return [
          Path()
            ..moveTo(0.83, 0.03)
            ..lineTo(0.22, 0.03)
            ..lineTo(0.15, 0.45)
            ..cubicTo(0.34, 0.32, 0.90, 0.37, 0.88, 0.70)
            ..cubicTo(0.86, 1.05, 0.16, 1.06, 0.08, 0.79),
        ];
      case '6':
        return [
          Path()
            ..moveTo(0.80, 0.05)
            ..cubicTo(0.44, -0.08, 0.12, 0.22, 0.11, 0.60)
            ..cubicTo(0.10, 0.90, 0.29, 1.03, 0.50, 1.03)
            ..cubicTo(0.72, 1.03, 0.88, 0.89, 0.87, 0.72)
            ..cubicTo(0.85, 0.47, 0.48, 0.41, 0.29, 0.53),
        ];
      case '7':
        return [
          Path()
            ..moveTo(0.07, 0.03)
            ..lineTo(0.91, 0.03)
            ..lineTo(0.38, 1.0),
        ];
      case '8':
        return [
          Path()
            ..addOval(
              Rect.fromCenter(
                center: const Offset(0.5, 0.26),
                width: 0.56,
                height: 0.44,
              ),
            ),
          Path()
            ..addOval(
              Rect.fromCenter(
                center: const Offset(0.5, 0.74),
                width: 0.70,
                height: 0.52,
              ),
            ),
        ];
      case '9':
        return [
          Path()
            ..addOval(
              Rect.fromCenter(
                center: const Offset(0.50, 0.29),
                width: 0.62,
                height: 0.50,
              ),
            ),
          Path()
            ..moveTo(0.81, 0.34)
            ..cubicTo(0.79, 0.70, 0.64, 0.91, 0.38, 1.02),
        ];
      case '-':
        return [
          Path()
            ..moveTo(0.10, 0.52)
            ..lineTo(0.90, 0.52),
        ];
      case '.':
        return [
          Path()
            ..moveTo(0.50, 0.97)
            ..lineTo(0.52, 0.97),
        ];
      default:
        return const [];
    }
  }
}
