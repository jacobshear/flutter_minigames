import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'crazy_eights_game.dart';

/// Pure-vector card rendering (no image assets, no Text glyphs) so cards
/// rasterize crisply at any size — including in golden/PNG renders.
///
/// The deck is a real 52-card deck because the rules need suit + rank, but the
/// cards are drawn in the Uno idiom rather than the poker one:
///
///  * each suit owns a bold colour (spades blue, hearts red, diamonds amber,
///    clubs green) so a hand is scannable by colour, not by pip silhouette;
///  * a thick white die-cut border around a saturated colour field;
///  * the signature white ellipse tilted across the middle, carrying the rank
///    as a big outlined vector glyph (numeral for 2–10, letter for A/J/Q/K);
///  * small rank + suit pip in two opposite corners, 180° apart.
///
/// The wild 8 gets a dark field and a four-colour quartered ellipse; once a
/// suit is declared the ellipse and an inner ring switch to that colour.
///
/// Faces are recorded into a [ui.Picture] keyed by size + identity, so the
/// glyph and pip paths are only walked when a card first appears at a size.
abstract final class CrazyEightsCardArt {
  // -- Uno palette: one committed colour per suit ---------------------------

  /// ♠ spades.
  static const Color spadeBlue = Color(0xFF1466CE);

  /// ♥ hearts.
  static const Color heartRed = Color(0xFFDE1F2B);

  /// ♦ diamonds.
  static const Color diamondAmber = Color(0xFFED9A00);

  /// ♣ clubs.
  static const Color clubGreen = Color(0xFF149B4A);

  /// Kept for callers that want "the red" (confetti, accents).
  static const Color red = heartRed;

  /// Kept for callers that want "the blue" (confetti, accents).
  static const Color backBlue = spadeBlue;

  static const Color ink = Color(0xFF1A1B21);
  static const Color cardWhite = Color(0xFFFCFCFA);

  /// Field colour of a wild 8 and of the card back.
  static const Color wildDark = Color(0xFF23252E);

  /// The back's oval. Deliberately a fifth colour no suit owns, so a
  /// face-down card can never be mistaken for a declared wild 8.
  static const Color backViolet = Color(0xFF6E45E2);

  /// The four suit colours in suit order (spades, hearts, diamonds, clubs).
  static const List<Color> suitColors = [
    spadeBlue,
    heartRed,
    diamondAmber,
    clubGreen,
  ];

  static Color suitColor(int suit) => suitColors[suit & 3];

  /// Corner radius used for a card of [size].
  static double cornerRadius(Size size) => size.width * 0.125;

  // -------------------------------------------------------------------------
  // Public entry points
  // -------------------------------------------------------------------------

  /// Paints the face of [card] (0..51) filling [rect].
  ///
  /// [declaredSuit] only affects 8s: a wild 8 with a live declared suit paints
  /// that suit's colour instead of the four-colour wild treatment.
  static void paintFace(
    Canvas canvas,
    Rect rect,
    int card, {
    int? declaredSuit,
  }) {
    final declared =
        CrazyEightsCards.isEight(card) ? declaredSuit : null;
    _draw(canvas, rect, _key(rect.size, card, declared),
        (c, s) => _recordFace(c, s, card, declared));
  }

  /// Paints the shared card back filling [rect].
  static void paintBack(Canvas canvas, Rect rect) {
    _draw(canvas, rect, _key(rect.size, 52, null), _recordBack);
  }

  /// Paints suit [suit] filling [rect] (in its own suit colour unless
  /// [color] is given).
  static void paintSuit(Canvas canvas, Rect rect, int suit, {Color? color}) {
    canvas.drawPath(
      suitPath(suit, rect),
      Paint()..color = color ?? suitColor(suit),
    );
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

  /// Paints [suit]'s pip inside [rect] in white over a thin dark keyline, the
  /// way pips sit on a colour field. Used by the cards and by the table's
  /// declared-suit badge so the two always match.
  static void paintSuitOnColor(
    Canvas canvas,
    Rect rect,
    int suit, {
    Color fill = Colors.white,
    Color keyline = ink,
    double keylineAlpha = 0.35,
  }) {
    final path = suitPath(suit, rect);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, rect.width * 0.13)
        ..strokeJoin = StrokeJoin.round
        ..color = keyline.withValues(alpha: keylineAlpha),
    );
    canvas.drawPath(path, Paint()..color = fill);
  }

  // -------------------------------------------------------------------------
  // Picture cache — a face is static per (size, card, declared suit)
  // -------------------------------------------------------------------------

  static const int _cacheLimit = 96;
  static final LinkedHashMap<int, ui.Picture> _cache =
      LinkedHashMap<int, ui.Picture>();

  static int _key(Size size, int face, int? declared) {
    final w = (size.width * 2).round();
    final h = (size.height * 2).round();
    return (((w * 8192 + h) * 64) + face) * 8 + (declared == null ? 0 : declared + 1);
  }

  static void _draw(
    Canvas canvas,
    Rect rect,
    int key,
    void Function(Canvas, Size) record,
  ) {
    var picture = _cache.remove(key);
    if (picture == null) {
      final recorder = ui.PictureRecorder();
      final size = rect.size;
      record(Canvas(recorder, Offset.zero & size), size);
      picture = recorder.endRecording();
      while (_cache.length >= _cacheLimit) {
        _cache.remove(_cache.keys.first)!.dispose();
      }
    }
    _cache[key] = picture; // re-insert = most recently used
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  /// Drops every cached face. Only useful in tests.
  @visibleForTesting
  static void clearCache() {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
  }

  // -------------------------------------------------------------------------
  // Face
  // -------------------------------------------------------------------------

  static void _recordFace(Canvas canvas, Size size, int card, int? declared) {
    final rect = Offset.zero & size;
    final w = size.width;
    final rank = CrazyEightsCards.rankOf(card);
    final suit = CrazyEightsCards.suitOf(card);
    final wild = CrazyEightsCards.isEight(card);
    final field = wild ? wildDark : suitColor(suit);

    final inner = _paintStock(canvas, rect, field);

    // A wild 8 with a live declared suit wears a thick ring of that colour
    // just inside the white border — visible even when the card is overlapped.
    if (wild && declared != null) {
      final ringR = RRect.fromRectAndRadius(
        inner.deflate(w * 0.035),
        Radius.circular(w * 0.05),
      );
      canvas.drawRRect(
        ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.055
          ..color = suitColor(declared),
      );
    }

    _paintEllipse(canvas, rect, card, declared);
    _paintCorners(canvas, rect, rank, suit, wild);
  }

  /// White die-cut border + saturated colour field. Returns the field rect.
  static Rect _paintStock(Canvas canvas, Rect rect, Color field) {
    final w = rect.width;
    final r = cornerRadius(rect.size);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(r));

    // The cut edge of the stock, peeking out opposite the key light.
    canvas.drawRRect(
      rrect.shift(Offset(w * 0.008, w * 0.010)),
      Paint()..color = const Color(0xFFCFCBBE),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            cardWhite,
            Color.lerp(cardWhite, const Color(0xFF6E6A5E), 0.13)!,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect),
    );
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ink.withValues(alpha: 0.16),
    );

    final inner = rect.deflate(w * 0.078);
    final innerR = RRect.fromRectAndRadius(inner, Radius.circular(w * 0.068));
    canvas.drawRRect(
      innerR,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(field, Colors.white, 0.16)!,
            field,
            Color.lerp(field, Colors.black, 0.20)!,
          ],
          stops: const [0.0, 0.46, 1.0],
        ).createShader(inner),
    );
    return inner;
  }

  /// Tilt of the signature ellipse (negative = right side lifted), which also
  /// keeps the widest part of the oval away from the two corner marks.
  static const double _ellipseTilt = -0.42;

  static void _paintEllipse(Canvas canvas, Rect rect, int card, int? declared) {
    final w = rect.width;
    final center = rect.center;
    final rank = CrazyEightsCards.rankOf(card);
    final wild = CrazyEightsCards.isEight(card);
    final oval = Rect.fromCenter(
      center: Offset.zero,
      width: w * 0.82,
      height: w * 0.64,
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(_ellipseTilt);

    // Soft drop under the oval so it sits on the field rather than in it.
    canvas.drawOval(
      oval.shift(Offset(w * 0.012, w * 0.018)),
      Paint()..color = Colors.black.withValues(alpha: 0.16),
    );

    final Color glyphFill;
    final Color glyphOutline;
    if (!wild) {
      canvas.drawOval(oval, Paint()..color = Colors.white);
      glyphFill = suitColor(CrazyEightsCards.suitOf(card));
      glyphOutline = ink;
    } else if (declared != null) {
      canvas.drawOval(oval, Paint()..color = suitColor(declared));
      canvas.drawOval(
        oval.deflate(w * 0.016),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.022
          ..color = Colors.white.withValues(alpha: 0.9),
      );
      // The declared suit's pip flanks the 8 along the oval's long axis.
      for (final dx in [-w * 0.295, w * 0.295]) {
        paintSuitOnColor(
          canvas,
          Rect.fromCenter(
            center: Offset(dx, 0),
            width: w * 0.115,
            height: w * 0.115,
          ),
          declared,
        );
      }
      glyphFill = Colors.white;
      glyphOutline = ink;
    } else {
      _paintWildQuarters(canvas, oval, w);
      glyphFill = Colors.white;
      glyphOutline = ink;
    }
    canvas.restore();

    // The rank rides upright on top of the tilted oval — a tilted numeral
    // costs more legibility than the flourish is worth at hand size.
    final label = CrazyEightsCards.rankLabels[rank];
    final factor = _glyphRunWidth(label, 1);
    // Sized so the glyph's box stays inside the tilted oval — a rank that
    // spills onto the colour field loses its white backing and its contrast.
    final height = math.min(w * 0.44, w * 0.53 / factor);
    final runW = factor * height;
    _paintGlyphRun(
      canvas,
      label,
      origin: center - Offset(runW / 2, height / 2),
      height: height,
      color: glyphFill,
      outline: glyphOutline,
      weight: wild ? 0.24 : 0.23,
      outlineWeight: wild ? 0.40 : 0.36,
    );
  }

  /// The four-colour quartered oval that marks an undeclared wild 8.
  static void _paintWildQuarters(Canvas canvas, Rect oval, double w) {
    canvas.save();
    canvas.clipPath(Path()..addOval(oval));
    final reach = oval.width;
    for (var i = 0; i < 4; i++) {
      final start = -math.pi * 0.75 + i * math.pi / 2;
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..arcTo(
            Rect.fromCircle(center: Offset.zero, radius: reach),
            start,
            math.pi / 2,
            false,
          )
          ..close(),
        Paint()..color = suitColors[i],
      );
    }
    canvas.restore();
    // Thin white splits, then a white rim, so the quarters read as one badge.
    final split = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.018
      ..color = Colors.white.withValues(alpha: 0.85);
    canvas.save();
    canvas.clipPath(Path()..addOval(oval));
    for (var i = 0; i < 2; i++) {
      final a = -math.pi * 0.25 + i * math.pi / 2;
      final d = Offset(math.cos(a), math.sin(a)) * oval.width;
      canvas.drawLine(-d, d, split);
    }
    canvas.restore();
    canvas.drawOval(
      oval.deflate(w * 0.011),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.022
        ..color = Colors.white,
    );
  }

  /// Small rank + suit pip in the top-left and (rotated 180°) bottom-right.
  static void _paintCorners(
    Canvas canvas,
    Rect rect,
    int rank,
    int suit,
    bool wild,
  ) {
    final w = rect.width;
    final glyphH = w * 0.17;
    final label = CrazyEightsCards.rankLabels[rank];
    final origin = rect.topLeft + Offset(w * 0.115, w * 0.115);

    void corner() {
      final runW = _paintGlyphRun(
        canvas,
        label,
        origin: origin,
        height: glyphH,
        color: Colors.white,
        outline: ink,
        weight: 0.22,
        outlineWeight: 0.40,
        outlineAlpha: 0.45,
      );
      paintSuitOnColor(
        canvas,
        Rect.fromCenter(
          center: origin + Offset(runW / 2, glyphH + w * 0.075),
          width: w * 0.115,
          height: w * 0.115,
        ),
        suit,
        keylineAlpha: wild ? 0.0 : 0.30,
      );
    }

    corner();
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(math.pi);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    corner();
    canvas.restore();
  }

  // -------------------------------------------------------------------------
  // Back
  // -------------------------------------------------------------------------

  static void _recordBack(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final w = size.width;
    final inner = _paintStock(canvas, rect, wildDark);

    // A diagonal lattice over the field — no face has one, so a back is never
    // mistaken for a card even at a glance.
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(inner, Radius.circular(w * 0.068)),
    );
    final lattice = Paint()
      ..color = Colors.white.withValues(alpha: 0.09)
      ..strokeWidth = math.max(0.8, w * 0.018);
    final step = w * 0.15;
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

    // Corner pips in the four suit colours — the same mapping the faces use.
    const corners = [
      Offset(0.20, 0.13),
      Offset(0.80, 0.13),
      Offset(0.20, 0.87),
      Offset(0.80, 0.87),
    ];
    for (var i = 0; i < 4; i++) {
      final u = corners[i];
      paintSuit(
        canvas,
        Rect.fromCenter(
          center: Offset(
            inner.left + u.dx * inner.width,
            inner.top + u.dy * inner.height,
          ),
          width: w * 0.13,
          height: w * 0.13,
        ),
        i,
        color: suitColors[i].withValues(alpha: 0.92),
      );
    }

    final oval = Rect.fromCenter(
      center: Offset.zero,
      width: w * 0.82,
      height: w * 0.64,
    );
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(_ellipseTilt);
    canvas.drawOval(
      oval.shift(Offset(w * 0.012, w * 0.018)),
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );
    canvas.drawOval(oval, Paint()..color = backViolet);
    canvas.drawOval(
      oval.deflate(w * 0.016),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.022
        ..color = Colors.white.withValues(alpha: 0.92),
    );
    canvas.restore();

    final height = w * 0.44;
    final runW = _glyphRunWidth('8', height);
    _paintGlyphRun(
      canvas,
      '8',
      origin: rect.center - Offset(runW / 2, height / 2),
      height: height,
      color: Colors.white,
      outline: ink,
      weight: 0.26,
      outlineWeight: 0.42,
    );
  }

  // -------------------------------------------------------------------------
  // Suits
  // -------------------------------------------------------------------------

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
  /// (top-left), [height] tall. When [outline] is given the run is stroked
  /// twice — a wider outline pass, then the fill — which is what gives the
  /// rank its Uno weight. Returns the run width.
  static double _paintGlyphRun(
    Canvas canvas,
    String label, {
    required Offset origin,
    required double height,
    required Color color,
    Color? outline,
    double weight = 0.17,
    double outlineWeight = 0.30,
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
      if (i > 0) x += 0.10 * height;
      final ch = label[i];
      final adv = _glyphAdvance(ch);
      final m = Matrix4.translationValues(x, origin.dy, 0)
        ..scaleByDouble(adv * height, height, 1, 1);
      final strokes = [
        for (final s in _glyphStrokes(ch)) s.transform(m.storage),
      ];
      for (final paint in passes) {
        for (final stroke in strokes) {
          canvas.drawPath(stroke, paint);
        }
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

/// A single card as a widget: face-up art for [card], or the shared back when
/// [faceUp] is false. Aspect ratio is fixed at 1 : 1.4.
class PlayingCardView extends StatelessWidget {
  /// Card 0..51; may be null when [faceUp] is false.
  final int? card;
  final bool faceUp;
  final double width;

  /// Live declared suit — only meaningful when [card] is an 8.
  final int? declaredSuit;

  /// Gold ring + slight glow marking a playable card.
  final bool highlighted;

  /// Drop shadow under the card.
  final bool shadow;

  const PlayingCardView({
    super.key,
    required this.card,
    required this.width,
    this.faceUp = true,
    this.declaredSuit,
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
          declaredSuit: declaredSuit,
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
  final int? declaredSuit;
  final bool highlighted;
  final bool shadow;

  _CardPainter({
    required this.card,
    required this.faceUp,
    required this.declaredSuit,
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
      // Two-part contact shadow under a key from the upper left: a wide
      // ambient blur, then a tight core so the card sits on the cloth.
      canvas.drawRRect(
        rrect.shift(Offset(size.width * 0.055, size.width * 0.075)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.24)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.09),
      );
      canvas.drawRRect(
        rrect.shift(Offset(size.width * 0.016, size.width * 0.022)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.26)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.022),
      );
    }
    if (faceUp) {
      CrazyEightsCardArt.paintFace(
        canvas,
        rect,
        card!,
        declaredSuit: declaredSuit,
      );
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
      old.declaredSuit != declaredSuit ||
      old.highlighted != highlighted ||
      old.shadow != shadow;
}
