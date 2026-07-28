import 'package:flutter/material.dart';

/// Vector staunton-style piece silhouettes, drawn straight to canvas so any
/// consumer (board, launcher tiles) can render pieces at any size without
/// image assets.
class ChessPieceArt {
  ChessPieceArt._();

  /// Paints [piece] (a FEN char: `PNBRQK` white, `pnbrqk` black) centered on
  /// [center], standing [height] tall.
  static void paint(
    Canvas canvas, {
    required Offset center,
    required double height,
    required String piece,
    Color whiteFill = const Color(0xFFF4F1E8),
    Color blackFill = const Color(0xFF33323A),
    double opacity = 1,
  }) {
    final isWhite = piece == piece.toUpperCase();
    final fill = isWhite ? whiteFill : blackFill;
    final outline = isWhite
        ? Color.lerp(fill, Colors.black, 0.62)!
        : Color.lerp(fill, Colors.white, 0.4)!;

    final h = height;
    final origin = center - Offset(h / 2, h / 2);
    Offset p(double x, double y) => origin + Offset(x * h, y * h);
    Rect box(double l, double t, double r, double b) =>
        Rect.fromPoints(p(l, t), p(r, b));

    final type = piece.toLowerCase();
    final body = Path();

    // Shared plinth. Piece bodies sit on top of it.
    body.addRRect(RRect.fromRectAndRadius(
      box(0.22, 0.82, 0.78, 0.94),
      Radius.circular(0.05 * h),
    ));

    switch (type) {
      case 'p':
        body.addOval(Rect.fromCircle(center: p(0.5, 0.32), radius: 0.13 * h));
        body.moveTo(p(0.42, 0.42).dx, p(0.42, 0.42).dy);
        body.quadraticBezierTo(
            p(0.36, 0.62).dx, p(0.36, 0.62).dy, p(0.30, 0.84).dx, p(0.30, 0.84).dy);
        body.lineTo(p(0.70, 0.84).dx, p(0.70, 0.84).dy);
        body.quadraticBezierTo(
            p(0.64, 0.62).dx, p(0.64, 0.62).dy, p(0.58, 0.42).dx, p(0.58, 0.42).dy);
        body.close();
        body.addRRect(RRect.fromRectAndRadius(
            box(0.34, 0.44, 0.66, 0.50), Radius.circular(0.02 * h)));
      case 'r':
        // Crenellated top.
        final t = Path()
          ..moveTo(p(0.28, 0.30).dx, p(0.28, 0.30).dy)
          ..lineTo(p(0.28, 0.12).dx, p(0.28, 0.12).dy)
          ..lineTo(p(0.40, 0.12).dx, p(0.40, 0.12).dy)
          ..lineTo(p(0.40, 0.19).dx, p(0.40, 0.19).dy)
          ..lineTo(p(0.46, 0.19).dx, p(0.46, 0.19).dy)
          ..lineTo(p(0.46, 0.12).dx, p(0.46, 0.12).dy)
          ..lineTo(p(0.54, 0.12).dx, p(0.54, 0.12).dy)
          ..lineTo(p(0.54, 0.19).dx, p(0.54, 0.19).dy)
          ..lineTo(p(0.60, 0.19).dx, p(0.60, 0.19).dy)
          ..lineTo(p(0.60, 0.12).dx, p(0.60, 0.12).dy)
          ..lineTo(p(0.72, 0.12).dx, p(0.72, 0.12).dy)
          ..lineTo(p(0.72, 0.30).dx, p(0.72, 0.30).dy)
          ..close();
        body.addPath(t, Offset.zero);
        body.moveTo(p(0.34, 0.30).dx, p(0.34, 0.30).dy);
        body.lineTo(p(0.66, 0.30).dx, p(0.66, 0.30).dy);
        body.lineTo(p(0.62, 0.72).dx, p(0.62, 0.72).dy);
        body.lineTo(p(0.70, 0.84).dx, p(0.70, 0.84).dy);
        body.lineTo(p(0.30, 0.84).dx, p(0.30, 0.84).dy);
        body.lineTo(p(0.38, 0.72).dx, p(0.38, 0.72).dy);
        body.close();
      case 'n':
        // Horse silhouette facing left.
        final n = Path()
          ..moveTo(p(0.30, 0.84).dx, p(0.30, 0.84).dy)
          ..lineTo(p(0.70, 0.84).dx, p(0.70, 0.84).dy)
          ..quadraticBezierTo(p(0.72, 0.56).dx, p(0.72, 0.56).dy,
              p(0.62, 0.36).dx, p(0.62, 0.36).dy)
          ..quadraticBezierTo(p(0.58, 0.24).dx, p(0.58, 0.24).dy,
              p(0.55, 0.13).dx, p(0.55, 0.13).dy)
          ..lineTo(p(0.48, 0.08).dx, p(0.48, 0.08).dy)
          ..lineTo(p(0.46, 0.16).dx, p(0.46, 0.16).dy)
          ..lineTo(p(0.38, 0.12).dx, p(0.38, 0.12).dy)
          ..lineTo(p(0.38, 0.22).dx, p(0.38, 0.22).dy)
          ..quadraticBezierTo(p(0.24, 0.32).dx, p(0.24, 0.32).dy,
              p(0.22, 0.44).dx, p(0.22, 0.44).dy)
          ..lineTo(p(0.30, 0.50).dx, p(0.30, 0.50).dy)
          ..quadraticBezierTo(p(0.36, 0.50).dx, p(0.36, 0.50).dy,
              p(0.40, 0.44).dx, p(0.40, 0.44).dy)
          ..quadraticBezierTo(p(0.42, 0.58).dx, p(0.42, 0.58).dy,
              p(0.34, 0.70).dx, p(0.34, 0.70).dy)
          ..close();
        body.addPath(n, Offset.zero);
      case 'b':
        // Mitre with a ball on top; the slash is cut by the outline pass.
        body.addOval(Rect.fromCircle(center: p(0.5, 0.10), radius: 0.045 * h));
        body.moveTo(p(0.5, 0.15).dx, p(0.5, 0.15).dy);
        body.quadraticBezierTo(p(0.68, 0.32).dx, p(0.68, 0.32).dy,
            p(0.60, 0.50).dx, p(0.60, 0.50).dy);
        body.lineTo(p(0.40, 0.50).dx, p(0.40, 0.50).dy);
        body.quadraticBezierTo(p(0.32, 0.32).dx, p(0.32, 0.32).dy,
            p(0.5, 0.15).dx, p(0.5, 0.15).dy);
        body.close();
        body.moveTo(p(0.40, 0.54).dx, p(0.40, 0.54).dy);
        body.lineTo(p(0.60, 0.54).dx, p(0.60, 0.54).dy);
        body.lineTo(p(0.68, 0.84).dx, p(0.68, 0.84).dy);
        body.lineTo(p(0.32, 0.84).dx, p(0.32, 0.84).dy);
        body.close();
      case 'q':
        // Three-point coronet with balls, waisted body, flared skirt.
        body.addOval(Rect.fromCircle(center: p(0.31, 0.10), radius: 0.038 * h));
        body.addOval(Rect.fromCircle(center: p(0.5, 0.06), radius: 0.038 * h));
        body.addOval(Rect.fromCircle(center: p(0.69, 0.10), radius: 0.038 * h));
        body.moveTo(p(0.30, 0.36).dx, p(0.30, 0.36).dy);
        body.lineTo(p(0.31, 0.14).dx, p(0.31, 0.14).dy);
        body.lineTo(p(0.42, 0.30).dx, p(0.42, 0.30).dy);
        body.lineTo(p(0.5, 0.11).dx, p(0.5, 0.11).dy);
        body.lineTo(p(0.58, 0.30).dx, p(0.58, 0.30).dy);
        body.lineTo(p(0.69, 0.14).dx, p(0.69, 0.14).dy);
        body.lineTo(p(0.70, 0.36).dx, p(0.70, 0.36).dy);
        body.close();
        body.addRRect(RRect.fromRectAndRadius(
            box(0.33, 0.37, 0.67, 0.43), Radius.circular(0.02 * h)));
        body.moveTo(p(0.40, 0.44).dx, p(0.40, 0.44).dy);
        body.quadraticBezierTo(p(0.44, 0.60).dx, p(0.44, 0.60).dy,
            p(0.30, 0.84).dx, p(0.30, 0.84).dy);
        body.lineTo(p(0.70, 0.84).dx, p(0.70, 0.84).dy);
        body.quadraticBezierTo(p(0.56, 0.60).dx, p(0.56, 0.60).dy,
            p(0.60, 0.44).dx, p(0.60, 0.44).dy);
        body.close();
      case 'k':
        // Cross above an arched crown, waisted body, flared skirt.
        body.addRRect(RRect.fromRectAndRadius(
            box(0.475, 0.02, 0.525, 0.17), Radius.circular(0.012 * h)));
        body.addRRect(RRect.fromRectAndRadius(
            box(0.42, 0.065, 0.58, 0.115), Radius.circular(0.012 * h)));
        body.moveTo(p(0.34, 0.36).dx, p(0.34, 0.36).dy);
        body.quadraticBezierTo(p(0.34, 0.20).dx, p(0.34, 0.20).dy,
            p(0.5, 0.18).dx, p(0.5, 0.18).dy);
        body.quadraticBezierTo(p(0.66, 0.20).dx, p(0.66, 0.20).dy,
            p(0.66, 0.36).dx, p(0.66, 0.36).dy);
        body.close();
        body.addRRect(RRect.fromRectAndRadius(
            box(0.33, 0.37, 0.67, 0.43), Radius.circular(0.02 * h)));
        body.moveTo(p(0.41, 0.44).dx, p(0.41, 0.44).dy);
        body.quadraticBezierTo(p(0.45, 0.60).dx, p(0.45, 0.60).dy,
            p(0.31, 0.84).dx, p(0.31, 0.84).dy);
        body.lineTo(p(0.69, 0.84).dx, p(0.69, 0.84).dy);
        body.quadraticBezierTo(p(0.55, 0.60).dx, p(0.55, 0.60).dy,
            p(0.59, 0.44).dx, p(0.59, 0.44).dy);
        body.close();
    }

    // Contact shadow, in two parts under a key light from the upper left: a
    // wide ambient blur pushed down-right, and a tight dark core right at the
    // foot so the piece reads as standing on the square, not floating over it.
    canvas.drawOval(
      box(0.20, 0.86, 0.86, 0.99),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20 * opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.045 * h),
    );
    canvas.drawOval(
      box(0.24, 0.905, 0.79, 0.965),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28 * opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.014 * h),
    );

    final bounds = box(0, 0, 1, 1);

    // Turned on a lathe: the body is a solid of revolution, so the dominant
    // shading is *lateral* — a lit band left of the axis, a core shadow to the
    // right of it, and a thin bounce off the board at the far edge.
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color.lerp(fill, Colors.black, isWhite ? 0.18 : 0.34)!
              .withValues(alpha: opacity),
          Color.lerp(fill, Colors.white, isWhite ? 0.46 : 0.30)!
              .withValues(alpha: opacity),
          fill.withValues(alpha: opacity),
          Color.lerp(fill, Colors.black, isWhite ? 0.30 : 0.48)!
              .withValues(alpha: opacity),
          Color.lerp(fill, Colors.white, isWhite ? 0.14 : 0.12)!
              .withValues(alpha: opacity),
        ],
        stops: const [0.0, 0.22, 0.48, 0.86, 1.0],
      ).createShader(bounds);
    canvas.drawPath(body, fillPaint);

    // Vertical pass: top-lit crown, ambient occlusion pooling at the base.
    canvas.save();
    canvas.clipPath(body);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.16 * opacity),
            Colors.white.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.10 * opacity),
            Colors.black.withValues(alpha: 0.26 * opacity),
          ],
          stops: const [0.0, 0.34, 0.74, 1.0],
        ).createShader(bounds),
    );
    // Felt pad on the base: the underside of every real piece.
    canvas.drawRect(
      box(0.0, 0.925, 1.0, 1.0),
      Paint()
        ..color = const Color(0xFF2A1A18).withValues(alpha: 0.55 * opacity),
    );
    canvas.restore();

    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.035 * h
        ..strokeJoin = StrokeJoin.round
        ..color = outline.withValues(alpha: opacity),
    );

    // Specular: a soft vertical sliver of light on the key side of the axis.
    canvas.save();
    canvas.clipPath(body);
    canvas.drawRect(
      box(0.30, 0.04, 0.44, 0.86),
      Paint()
        ..color = Colors.white.withValues(alpha: (isWhite ? 0.26 : 0.13) * opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.05 * h),
    );
    canvas.restore();

    // Bishop's mitre slash, cut in the outline color.
    if (type == 'b') {
      canvas.drawLine(
        p(0.44, 0.36),
        p(0.56, 0.24),
        Paint()
          ..strokeWidth = 0.035 * h
          ..strokeCap = StrokeCap.round
          ..color = outline.withValues(alpha: opacity),
      );
    }
  }
}
