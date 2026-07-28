import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'card_glyphs.dart';
import 'card_suits.dart';
import 'playing_card.dart';

/// Colours and proportions of a card face. Immutable and cheap to compare —
/// the picture cache is keyed partly on this, so give a game its own palette
/// by passing one const instance around, not by rebuilding it per frame.
@immutable
class PlayingCardStyle {
  /// The card stock.
  final Color face;

  /// Hearts and diamonds.
  final Color red;

  /// Clubs and spades.
  final Color black;

  /// Hairline around the card edge.
  final Color edge;

  /// Field colour of the card back.
  final Color back;

  /// Line work on the card back.
  final Color backInk;

  /// Corner radius as a fraction of card width.
  final double cornerRadiusFactor;

  const PlayingCardStyle({
    this.face = const Color(0xFFFCFBF7),
    this.red = const Color(0xFFC8102E),
    this.black = const Color(0xFF17181C),
    this.edge = const Color(0x33000000),
    this.back = const Color(0xFF17408B),
    this.backInk = const Color(0xFFF3F1EA),
    this.cornerRadiusFactor = 0.085,
  });

  /// The ink a card of [suit] is printed in.
  Color inkFor(Suit suit) => suit.isRed ? red : black;

  /// Corner radius for a card [width] wide.
  double cornerRadius(double width) => width * cornerRadiusFactor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayingCardStyle &&
          other.face == face &&
          other.red == red &&
          other.black == black &&
          other.edge == edge &&
          other.back == back &&
          other.backInk == backInk &&
          other.cornerRadiusFactor == cornerRadiusFactor);

  @override
  int get hashCode => Object.hash(
        face,
        red,
        black,
        edge,
        back,
        backInk,
        cornerRadiusFactor,
      );
}

/// The default palette — a classic white-stock, red/black poker deck.
const PlayingCardStyle kDefaultCardStyle = PlayingCardStyle();

/// Standard playing-card aspect ratio (width : height = 1 : 1.4).
const double kCardAspectRatio = 1.4;

// ---------------------------------------------------------------------------
// Public painting entry points
// ---------------------------------------------------------------------------

/// Paints [card] filling [rect] in the classic poker idiom: white stock,
/// rounded corners, red/black suit ink, a corner index (rank over pip) at the
/// top-left and again rotated 180° at the bottom-right, the standard pip
/// layouts for 2–10, a single large pip for the ace, and a framed mirrored
/// panel for J/Q/K.
///
/// With `faceUp: false` this paints the shared card back and ignores [card] —
/// which is what lets a caller keep one code path for both sides of a card.
///
/// Everything is vector: no fonts, no assets. The result is recorded into a
/// [ui.Picture] keyed by (quantised size, card, style), so repainting a fanned
/// hand every frame costs one `drawPicture` per card.
void paintPlayingCard(
  Canvas canvas,
  Rect rect,
  PlayingCard card, {
  bool faceUp = true,
  PlayingCardStyle style = kDefaultCardStyle,
}) {
  if (!faceUp) {
    paintCardBack(canvas, rect, style: style);
    return;
  }
  _drawCached(
    canvas,
    rect,
    _cacheKey(rect.size, card.index, style),
    (c, s) => _recordFace(c, s, card, style),
  );
}

/// Paints the shared card back filling [rect].
void paintCardBack(
  Canvas canvas,
  Rect rect, {
  PlayingCardStyle style = kDefaultCardStyle,
}) {
  _drawCached(
    canvas,
    rect,
    _cacheKey(rect.size, 52, style),
    (c, s) => _recordBack(c, s, style),
  );
}

/// Empties the face cache. Only useful between tests.
@visibleForTesting
void clearPlayingCardCache() {
  for (final p in _cache.values) {
    p.dispose();
  }
  _cache.clear();
}

/// How many recorded faces are held right now. Test-only.
@visibleForTesting
int get playingCardCacheSize => _cache.length;

// ---------------------------------------------------------------------------
// Bounded LRU picture cache
// ---------------------------------------------------------------------------

/// A fanned hand plus piles at two sizes is well under this; the cap only
/// exists so an animation that sweeps through sizes cannot grow without bound.
const int _cacheLimit = 128;

final LinkedHashMap<int, ui.Picture> _cache = LinkedHashMap<int, ui.Picture>();

/// Quantise to half-pixels so a card that breathes by a fraction of a pixel
/// reuses its picture instead of re-recording every frame.
int _cacheKey(Size size, int face, PlayingCardStyle style) => Object.hash(
      (size.width * 2).round(),
      (size.height * 2).round(),
      face,
      style,
    );

void _drawCached(
  Canvas canvas,
  Rect rect,
  int key,
  void Function(Canvas, Size) record,
) {
  if (rect.width <= 0 || rect.height <= 0) return;
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

// ---------------------------------------------------------------------------
// Face layout
//
// All constants are fractions of the card's own width (w) or height (h), so
// the face is resolution-independent and holds together from 24 px to 400 px.
// ---------------------------------------------------------------------------

/// Centre of the corner index column.
const double _indexCx = 0.140;

/// Rank glyph height in the corner index.
const double _indexGlyphH = 0.105;

/// Top of the corner index.
const double _indexTop = 0.042;

/// Suit pip size in the corner index.
const double _indexPip = 0.105;

/// Pip-field column centres and the rows they span.
const List<double> _pipCols = [0.345, 0.5, 0.655];
const double _pipTop = 0.190;
const double _pipBottom = 0.810;
const double _pipSize = 0.175;

/// Pip positions as (column index, row fraction 0..1). Rows past the halfway
/// mark print upside down, exactly as they do on a real deck.
const Map<int, List<(int, double)>> _pipLayouts = {
  2: [(1, 0.0), (1, 1.0)],
  3: [(1, 0.0), (1, 0.5), (1, 1.0)],
  4: [(0, 0.0), (2, 0.0), (0, 1.0), (2, 1.0)],
  5: [(0, 0.0), (2, 0.0), (1, 0.5), (0, 1.0), (2, 1.0)],
  6: [(0, 0.0), (2, 0.0), (0, 0.5), (2, 0.5), (0, 1.0), (2, 1.0)],
  7: [
    (0, 0.0),
    (2, 0.0),
    (1, 0.25),
    (0, 0.5),
    (2, 0.5),
    (0, 1.0),
    (2, 1.0),
  ],
  8: [
    (0, 0.0),
    (2, 0.0),
    (1, 0.25),
    (0, 0.5),
    (2, 0.5),
    (1, 0.75),
    (0, 1.0),
    (2, 1.0),
  ],
  9: [
    (0, 0.0),
    (2, 0.0),
    (0, 1 / 3),
    (2, 1 / 3),
    (1, 0.5),
    (0, 2 / 3),
    (2, 2 / 3),
    (0, 1.0),
    (2, 1.0),
  ],
  10: [
    (0, 0.0),
    (2, 0.0),
    (1, 1 / 6),
    (0, 1 / 3),
    (2, 1 / 3),
    (0, 2 / 3),
    (2, 2 / 3),
    (1, 5 / 6),
    (0, 1.0),
    (2, 1.0),
  ],
};

void _recordFace(
  Canvas canvas,
  Size size,
  PlayingCard card,
  PlayingCardStyle style,
) {
  final rect = Offset.zero & size;
  _paintStock(canvas, rect, style);

  final ink = style.inkFor(card.suit);
  if (card.rank == Rank.ace) {
    _paintAce(canvas, rect, card.suit, ink);
  } else if (card.rank.isFace) {
    _paintCourt(canvas, rect, card, ink, style);
  } else {
    _paintPips(canvas, rect, card, ink);
  }
  _paintCornerIndices(canvas, rect, card, ink);
}

/// White stock: a soft top-to-bottom gradient (paper is never flat), a hairline
/// edge, and a barely-there inner keyline so overlapping cards in a fan still
/// separate.
void _paintStock(Canvas canvas, Rect rect, PlayingCardStyle style) {
  final rrect = RRect.fromRectAndRadius(
    rect,
    Radius.circular(style.cornerRadius(rect.width)),
  );
  canvas.drawRRect(
    rrect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _white,
          style.face,
          Color.lerp(style.face, const Color(0xFF8A8578), 0.10)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect),
  );
  canvas.drawRRect(
    rrect.deflate(0.5),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = style.edge,
  );
}

/// Named so the gradient above reads without importing material.
const Color _white = Color(0xFFFFFFFF);

/// Rank glyph over a suit pip, top-left, then the same rotated 180°.
void _paintCornerIndices(
  Canvas canvas,
  Rect rect,
  PlayingCard card,
  Color ink,
) {
  final w = rect.width;
  final h = rect.height;
  final glyphH = h * _indexGlyphH;
  final label = card.rank.label;
  final runW = CardGlyphs.runWidth(label, glyphH);
  final cx = w * _indexCx;
  final pipSize = w * _indexPip;

  void index() {
    CardGlyphs.paintRun(
      canvas,
      label,
      origin: Offset(cx - runW / 2, h * _indexTop),
      height: glyphH,
      color: ink,
      weight: 0.20,
    );
    CardSuits.paint(
      canvas,
      Rect.fromCenter(
        center: Offset(
          cx,
          h * (_indexTop + _indexGlyphH + 0.022) + pipSize / 2,
        ),
        width: pipSize,
        height: pipSize,
      ),
      card.suit,
      ink,
    );
  }

  index();
  canvas.save();
  canvas.translate(rect.center.dx, rect.center.dy);
  canvas.rotate(math.pi);
  canvas.translate(-rect.center.dx, -rect.center.dy);
  index();
  canvas.restore();
}

/// One oversized centre pip.
void _paintAce(Canvas canvas, Rect rect, Suit suit, Color ink) {
  final d = rect.width * 0.36;
  CardSuits.paint(
    canvas,
    Rect.fromCenter(center: rect.center, width: d, height: d),
    suit,
    ink,
  );
}

/// The standard 2–10 pip grids.
void _paintPips(Canvas canvas, Rect rect, PlayingCard card, Color ink) {
  final layout = _pipLayouts[card.rank.ordinal];
  if (layout == null) return;
  final w = rect.width;
  final h = rect.height;
  final d = w * _pipSize;
  for (final (col, row) in layout) {
    final centre = Offset(
      w * _pipCols[col],
      h * (_pipTop + (_pipBottom - _pipTop) * row),
    );
    final box = Rect.fromCenter(center: centre, width: d, height: d);
    if (row > 0.5) {
      CardSuits.paintInverted(canvas, box, card.suit, ink);
    } else {
      CardSuits.paint(canvas, box, card.suit, ink);
    }
  }
}

/// J / Q / K: a framed panel split on the diagonal into two mirrored halves,
/// each carrying the rank letter and the suit pip. It is the court card's
/// composition without pretending to draw a courtier at 60 px.
void _paintCourt(
  Canvas canvas,
  Rect rect,
  PlayingCard card,
  Color ink,
  PlayingCardStyle style,
) {
  final w = rect.width;
  final h = rect.height;
  final panel = Rect.fromLTRB(
    rect.left + w * 0.200,
    rect.top + h * 0.135,
    rect.right - w * 0.200,
    rect.bottom - h * 0.135,
  );
  final r = Radius.circular(w * 0.045);
  final rr = RRect.fromRectAndRadius(panel, r);

  canvas.drawRRect(
    rr,
    Paint()..color = Color.lerp(style.face, ink, 0.10)!,
  );
  canvas.drawRRect(
    rr,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, w * 0.016)
      ..color = ink,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
        panel.deflate(w * 0.036), Radius.circular(w * 0.03)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, w * 0.008)
      ..color = ink.withValues(alpha: 0.55),
  );

  // The mirror line: a court card is the same figure twice, head to head.
  canvas.save();
  canvas.clipRRect(rr);
  canvas.drawLine(
    panel.bottomLeft,
    panel.topRight,
    Paint()
      ..strokeWidth = math.max(0.6, w * 0.010)
      ..color = ink.withValues(alpha: 0.35),
  );
  canvas.restore();

  final glyphH = panel.height * 0.26;
  final pip = w * 0.145;
  final halfCentre = Offset(
    panel.left + panel.width * 0.33,
    panel.top + panel.height * 0.27,
  );

  void half() {
    CardGlyphs.paintCentered(
      canvas,
      card.rank.label,
      center: halfCentre,
      height: glyphH,
      color: ink,
      weight: 0.20,
    );
    CardSuits.paint(
      canvas,
      Rect.fromCenter(
        center:
            halfCentre + Offset(panel.width * 0.30, glyphH * 0.20 + pip * 0.5),
        width: pip,
        height: pip,
      ),
      card.suit,
      ink,
    );
  }

  half();
  canvas.save();
  canvas.translate(panel.center.dx, panel.center.dy);
  canvas.rotate(math.pi);
  canvas.translate(-panel.center.dx, -panel.center.dy);
  half();
  canvas.restore();
}

// ---------------------------------------------------------------------------
// Back
// ---------------------------------------------------------------------------

void _recordBack(Canvas canvas, Size size, PlayingCardStyle style) {
  final rect = Offset.zero & size;
  final w = size.width;
  _paintStock(canvas, rect, style);

  final field = rect.deflate(w * 0.062);
  final fieldR = RRect.fromRectAndRadius(
    field,
    Radius.circular(w * 0.055),
  );
  canvas.drawRRect(fieldR, Paint()..color = style.back);

  // Diagonal lattice — the classic guilloche read, at a density that survives
  // being 40 px wide in a stock pile.
  canvas.save();
  canvas.clipRRect(fieldR);
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.7, w * 0.014)
    ..color = style.backInk.withValues(alpha: 0.24);
  final step = w * 0.16;
  for (var x = -field.height; x < field.width + field.height; x += step) {
    canvas.drawLine(
      Offset(field.left + x, field.top),
      Offset(field.left + x + field.height, field.bottom),
      line,
    );
    canvas.drawLine(
      Offset(field.left + x + field.height, field.top),
      Offset(field.left + x, field.bottom),
      line,
    );
  }
  canvas.restore();

  canvas.drawRRect(
    fieldR.deflate(w * 0.030),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, w * 0.020)
      ..color = style.backInk.withValues(alpha: 0.85),
  );

  // Centre rosette so the back has a focal point and never reads as a face.
  final c = rect.center;
  final ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.8, w * 0.018);
  canvas.drawCircle(
    c,
    w * 0.235,
    ring..color = style.backInk.withValues(alpha: 0.88),
  );
  canvas.drawCircle(
    c,
    w * 0.180,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, w * 0.010)
      ..color = style.backInk.withValues(alpha: 0.55),
  );
  canvas.drawCircle(
    c,
    w * 0.070,
    Paint()..color = style.backInk.withValues(alpha: 0.90),
  );

  // The four suits ringed around the rosette — the back still says "deck".
  for (var i = 0; i < 4; i++) {
    final a = math.pi / 4 + i * math.pi / 2;
    final d = w * 0.145;
    CardSuits.paint(
      canvas,
      Rect.fromCenter(
        center: c + Offset(math.cos(a), math.sin(a)) * w * 0.315,
        width: d,
        height: d,
      ),
      Suit.values[i],
      style.backInk.withValues(alpha: 0.78),
    );
  }
}
