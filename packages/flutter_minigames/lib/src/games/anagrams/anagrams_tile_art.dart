import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/classic_game_tile_art.dart' show tileSilhouette;

/// Launcher-tile miniature for Anagrams: wooden letter tiles pop in one by
/// one to spell a short word, a green "valid!" underline flashes, then the
/// board clears and the next word begins. Matches the toy-diorama loop style
/// of the example app's tile art while staying self-contained here.
class AnagramsTileArt extends StatefulWidget {
  final double phase;

  const AnagramsTileArt({super.key, this.phase = 0});

  @override
  State<AnagramsTileArt> createState() => _AnagramsTileArtState();
}

class _AnagramsTileArtState extends State<AnagramsTileArt>
    with SingleTickerProviderStateMixin {
  static const _words = ['WORD', 'PLAY', 'GAME', 'EPIC'];

  final _rng = math.Random();

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5400),
  )..repeat();

  late int _wordIndex = _rng.nextInt(_words.length);
  double _lastT = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _maybeAdvance(double t) {
    if (t + 0.25 < _lastT) {
      _wordIndex =
          (_wordIndex + 1 + _rng.nextInt(_words.length - 1)) % _words.length;
    }
    _lastT = t;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = (_c.value + widget.phase) % 1.0;
        _maybeAdvance(t);
        return CustomPaint(
          painter: _AnagramsTilePainter(t: t, word: _words[_wordIndex]),
        );
      },
    );
  }
}

class _AnagramsTilePainter extends CustomPainter {
  final double t;
  final String word;

  _AnagramsTilePainter({required this.t, required this.word});

  // Loop timeline (matches the shared tile-art rhythm):
  //   0.00–0.62  letters pop in one per beat
  //   0.62–0.82  green valid underline + tiny bounce
  //   0.82–1.00  clear (tiles scale away)
  static const double _actionEnd = 0.62;
  static const double _celebrateEnd = 0.82;

  double get _presence {
    if (t < _celebrateEnd) return 1;
    return 1 -
        Curves.easeInOutCubic.transform(
          (t - _celebrateEnd) / (1 - _celebrateEnd),
        );
  }

  double _letterPop(int i, int count) {
    if (t >= _actionEnd) return 1;
    final u = (t / _actionEnd) * count;
    final step = u.floor();
    if (i > step) return 0;
    if (i < step) return 1;
    return Curves.easeOutBack.transform((u - step).clamp(0.0, 1.0));
  }

  double get _celebrate {
    if (t < _actionEnd) return 0;
    final u = ((t - _actionEnd) / (_celebrateEnd - _actionEnd)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(u) * _presence;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Maroon felt slab (mini version of the in-game table).
    final r = tileSilhouette(size);
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7E4747), Color(0xFF6E3B3B), Color(0xFF522A2A)],
        ).createShader(Offset.zero & size),
    );
    // Soft top light + bottom vignette for depth (matches the other tiles).
    canvas.drawRRect(
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.15, -0.35),
          radius: 1.05,
          colors: [
            Colors.white.withValues(alpha: 0.13),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.12),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Offset.zero & size),
    );
    // Thin lip edge so the tile reads as a tray, not a flat stamp.
    canvas.drawRRect(
      r.deflate(size.shortestSide * 0.012),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.014
        ..color = Colors.black.withValues(alpha: 0.12),
    );

    final n = word.length;
    final tileSide = size.shortestSide * 0.205;
    final gap = size.shortestSide * 0.032;
    final totalW = n * tileSide + (n - 1) * gap;
    final left = (size.width - totalW) / 2;
    final cy = size.height * 0.40;

    final celebrate = _celebrate;
    final presence = _presence;

    for (var i = 0; i < n; i++) {
      final pop = _letterPop(i, n) * presence;
      if (pop <= 0.02) continue;
      // Tiny synchronized bounce during the celebrate beat.
      final bounce = math.sin(celebrate * math.pi) *
          tileSide *
          0.10 *
          (i.isEven ? 1 : 0.7);
      final cx = left + i * (tileSide + gap) + tileSide / 2;
      _drawTile(
        canvas,
        Offset(cx, cy - bounce),
        tileSide * pop.clamp(0.0, 1.1),
        word[i],
        pop.clamp(0.0, 1.0),
      );
    }

    // Recessed rack sockets below — the tiles "rose" out of these.
    const socketCount = 6;
    final sSide = size.shortestSide * 0.105;
    final sGap = size.shortestSide * 0.028;
    final sTotal = socketCount * sSide + (socketCount - 1) * sGap;
    final sLeft = (size.width - sTotal) / 2;
    final sy = size.height * 0.72;
    for (var i = 0; i < socketCount; i++) {
      final rect = Rect.fromLTWH(sLeft + i * (sSide + sGap), sy, sSide, sSide);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(sSide * 0.24)),
        Paint()..color = Colors.black.withValues(alpha: 0.20),
      );
    }

    // Green valid underline.
    if (celebrate > 0.01) {
      final y = cy + tileSide * 0.72;
      final half = totalW / 2 * Curves.easeOutCubic.transform(celebrate);
      canvas.drawLine(
        Offset(size.width / 2 - half, y),
        Offset(size.width / 2 + half, y),
        Paint()
          ..color = const Color(0xFF34C759).withValues(alpha: 0.9 * presence)
          ..strokeWidth = size.shortestSide * 0.028
          ..strokeCap = StrokeCap.round,
      );
      // Score spark above the word.
      final sparkY = cy - tileSide * 1.05 - celebrate * tileSide * 0.25;
      final tp = TextPainter(
        text: TextSpan(
          text: '+2000',
          style: TextStyle(
            color: const Color(0xFF34C759)
                .withValues(alpha: (1 - celebrate * 0.4) * presence),
            fontSize: size.shortestSide * 0.095,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(size.width / 2 - tp.width / 2, sparkY),
      );
    }
  }

  void _drawTile(
    Canvas canvas,
    Offset center,
    double side,
    String letter,
    double alpha,
  ) {
    if (side < 1) return;
    final rect = Rect.fromCenter(center: center, width: side, height: side);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(side * 0.22));

    // Contact shadow.
    canvas.drawRRect(
      rr.shift(Offset(0, side * 0.08)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22 * alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, side * 0.10),
    );
    // Wooden face.
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF6E9C8), Color(0xFFDDC08D)],
        ).createShader(rect),
    );
    // Edge ink.
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = side * 0.04
        ..color = const Color(0xFF3E2E14).withValues(alpha: 0.35 * alpha),
    );
    // Glyph.
    final tp = TextPainter(
      text: TextSpan(
        text: letter,
        style: TextStyle(
          color: const Color(0xFF3E2E14).withValues(alpha: alpha),
          fontSize: side * 0.62,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(_AnagramsTilePainter old) =>
      old.t != t || old.word != word;
}
