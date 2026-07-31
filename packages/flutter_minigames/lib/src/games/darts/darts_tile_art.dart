import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'darts_board_geometry.dart';

/// Launcher-tile miniature for Darts: a board seen face-on with a dart looping
/// in from the corner and sticking in the treble 20.
///
/// Face-on and flat on purpose — the tile is a 2-D emblem, not a scene, so it
/// draws the board directly rather than going through the camera. Every ring
/// ratio still comes from [DartsBoardGeometry], so the emblem and the game
/// cannot drift apart.
class DartsTileArt extends StatefulWidget {
  /// Loop phase offset (the launcher staggers tiles by phase).
  final double phase;

  /// The darts actually in the board this visit, when this tile shows a live
  /// match. A [DartHit] is a sector plus a multiplier, which is the whole of
  /// what the game models — sector gives the bed's angle, multiplier gives its
  /// radial band (1 single, 2 the double ring, 3 the treble). So the real darts
  /// can be stood in their real beds; nothing is being approximated.
  ///
  /// Non-null also stops the scripted dart looping in: a still shows darts
  /// already in the board, not one in flight.
  final List<DartHit>? liveVisit;

  /// The viewer's remaining score, shown on the board like a scoreboard peg.
  /// Null hides it.
  final int? liveScore;

  /// Freeze the loop. Cards and rasterized map bubbles are stills.
  final bool animate;

  const DartsTileArt({
    super.key,
    this.phase = 0,
    this.liveVisit,
    this.liveScore,
    this.animate = true,
  });

  @override
  State<DartsTileArt> createState() => _DartsTileArtState();
}

class _DartsTileArtState extends State<DartsTileArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return CustomPaint(
        painter: _DartsTilePainter(
          t: 1.0,
          liveVisit: widget.liveVisit,
          liveScore: widget.liveScore,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        painter: _DartsTilePainter(
          t: (_c.value + widget.phase) % 1.0,
          liveVisit: widget.liveVisit,
          liveScore: widget.liveScore,
        ),
      ),
    );
  }
}

class _DartsTilePainter extends CustomPainter {
  final double t;
  final List<DartHit>? liveVisit;
  final int? liveScore;

  _DartsTilePainter({required this.t, this.liveVisit, this.liveScore});

  static const _cream = Color(0xFFEBD9A8);
  static const _black = Color(0xFF17171A);
  static const _red = Color(0xFFC8392F);
  static const _green = Color(0xFF2E8B4F);
  static const _wire = Color(0xFFB9BEC6);

  @override
  void paint(Canvas canvas, Size size) {
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
          colors: [Color(0xFF31384A), Color(0xFF1A1E28)],
        ).createShader(Offset.zero & size),
    );
    canvas.save();
    canvas.clipRRect(outer);

    final centre = Offset(size.width * 0.5, size.height * 0.47);
    final r = size.width * 0.36;

    // Surround.
    canvas.drawCircle(
      centre.translate(0, r * 0.08),
      r * DartsBoardGeometry.numberRingRatio,
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      centre,
      r * DartsBoardGeometry.numberRingRatio,
      Paint()..color = const Color(0xFF101014),
    );

    const span = DartsBoardGeometry.sectorSpan;
    // Canvas arcs measure from +x counter-clockwise-in-screen-space; the board
    // measures clockwise from 12 o'clock, so a sector centred at `a` starts at
    // screen angle `a - 90° - half`.
    for (var i = 0; i < 20; i++) {
      final start = i * span - math.pi / 2 - span / 2;
      final dark = i.isEven;
      final bed = dark ? _black : _cream;
      final ring = dark ? _red : _green;
      void band(double r0, double r1, Color color) {
        final path = Path()
          ..addArc(Rect.fromCircle(center: centre, radius: r1), start, span)
          ..arcTo(
            Rect.fromCircle(center: centre, radius: r0),
            start + span,
            -span,
            false,
          )
          ..close();
        canvas.drawPath(path, Paint()..color = color);
      }

      band(DartsBoardGeometry.outerBullRatio * r,
          DartsBoardGeometry.innerTrebleRatio * r, bed);
      band(DartsBoardGeometry.innerTrebleRatio * r,
          DartsBoardGeometry.outerTrebleRatio * r, ring);
      band(DartsBoardGeometry.outerTrebleRatio * r,
          DartsBoardGeometry.innerDoubleRatio * r, bed);
      band(DartsBoardGeometry.innerDoubleRatio * r, r, ring);
    }

    canvas.drawCircle(
      centre,
      DartsBoardGeometry.outerBullRatio * r,
      Paint()..color = _green,
    );
    canvas.drawCircle(
      centre,
      DartsBoardGeometry.innerBullRatio * r,
      Paint()..color = _red,
    );

    // Wire spider.
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, size.width * 0.006)
      ..color = _wire.withValues(alpha: 0.85);
    for (final ratio in const [
      DartsBoardGeometry.outerBullRatio,
      DartsBoardGeometry.innerTrebleRatio,
      DartsBoardGeometry.outerTrebleRatio,
      DartsBoardGeometry.innerDoubleRatio,
      1.0,
    ]) {
      canvas.drawCircle(centre, ratio * r, wire);
    }
    for (var i = 0; i < 20; i++) {
      final a = i * span - math.pi / 2 - span / 2;
      canvas.drawLine(
        centre +
            Offset(math.cos(a), math.sin(a)) *
                (DartsBoardGeometry.outerBullRatio * r),
        centre + Offset(math.cos(a), math.sin(a)) * r,
        wire,
      );
    }

    // --- darts in the board ---------------------------------------------
    //
    // A live visit stands each real dart in its real bed. A [DartHit] carries
    // a sector and a multiplier, and that IS the board's coordinate system:
    // the sector picks the wedge (via DartsBoardGeometry.sectorOrder, which is
    // the true 20-1-18-4 running order, not a guess), and the multiplier picks
    // the radial band — 3 the treble ring, 2 the double ring, 1 the single bed
    // between them, 25 the bull. Nothing is approximated; a still shows
    // exactly where the darts went.
    void drawDart(Offset tip, double angle, {double scale = 1.0}) {
      // Come in from the lower right, foreshortened — a dart standing in the
      // board, not a pin lying on it.
      final unit = Offset(math.cos(angle), math.sin(angle));
      final len = size.width * 0.22 * scale;
      final tail = tip - unit * len;
      final perp = Offset(-unit.dy, unit.dx);
      canvas.drawLine(
        tail + unit * (len * 0.3),
        tip,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1.2, size.width * 0.022 * scale)
          ..color = const Color(0xFFD3D8DF),
      );
      final finW = size.width * 0.045 * scale;
      canvas.drawPath(
        Path()
          ..moveTo(tail.dx + perp.dx * finW, tail.dy + perp.dy * finW)
          ..lineTo(tail.dx + unit.dx * len * 0.34, tail.dy + unit.dy * len * 0.34)
          ..lineTo(tail.dx - perp.dx * finW, tail.dy - perp.dy * finW)
          ..lineTo(tail.dx, tail.dy)
          ..close(),
        Paint()..color = const Color(0xFFF4B740),
      );
    }

    final visit = liveVisit;
    if (visit != null) {
      for (var i = 0; i < visit.length; i++) {
        final h = visit[i];
        if (h.multiplier == 0) continue; // a miss is off the board entirely

        final Offset tip;
        if (h.sector == 25) {
          // Bull: inner (x2) sits dead centre, outer (x1) in the ring around it.
          final ratio = h.multiplier == 2
              ? 0.0
              : (DartsBoardGeometry.innerBullRatio +
                      DartsBoardGeometry.outerBullRatio) /
                  2;
          // Fan the three darts so they do not stack into one mark.
          final spread = i * 0.7 - 0.7;
          tip = centre +
              Offset(math.cos(spread), math.sin(spread)) * (r * ratio) +
              Offset(r * 0.02 * i, 0);
        } else {
          final index = DartsBoardGeometry.sectorOrder.indexOf(h.sector);
          if (index < 0) continue;
          // Centre of the wedge, nudged within it so three darts in the same
          // bed read as three darts.
          final a = DartsBoardGeometry.sectorCentreAngle(index) -
              math.pi / 2 +
              (i - 1) * DartsBoardGeometry.sectorSpan * 0.22;
          final ratio = switch (h.multiplier) {
            3 => (DartsBoardGeometry.innerTrebleRatio +
                    DartsBoardGeometry.outerTrebleRatio) /
                2,
            2 => (DartsBoardGeometry.innerDoubleRatio + 1.0) / 2,
            _ => (DartsBoardGeometry.outerTrebleRatio +
                    DartsBoardGeometry.innerDoubleRatio) /
                2,
          };
          tip = centre + Offset(math.cos(a), math.sin(a)) * (r * ratio);
        }
        drawDart(tip, math.atan2(-0.55, -0.83));
      }

      final score = liveScore;
      if (score != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: '$score',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: size.width * 0.13,
              height: 1.0,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final pad = size.width * 0.045;
        final box = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * 0.5 - tp.width / 2 - pad,
            size.height * 0.90 - tp.height / 2 - pad * 0.6,
            tp.width + pad * 2,
            tp.height + pad * 1.2,
          ),
          Radius.circular(size.width * 0.05),
        );
        canvas.drawRRect(box, Paint()..color = const Color(0xCC101014));
        tp.paint(
          canvas,
          Offset(size.width * 0.5 - tp.width / 2,
              size.height * 0.90 - tp.height / 2),
        );
      }
    } else {
      // A dart looping in to the treble 20 (top sector, red bed).
      final target = centre +
          Offset(
            -r * 0.06,
            -r *
                (DartsBoardGeometry.innerTrebleRatio +
                    DartsBoardGeometry.outerTrebleRatio) /
                2,
          );
      final travel = Curves.easeOutCubic.transform(
        ((t - 0.05) / 0.45).clamp(0.0, 1.0),
      );
      final rest = t > 0.5 ? 1.0 : travel;
      final from = Offset(size.width * 1.12, size.height * 1.05);
      final tip = Offset.lerp(from, target, rest)!;
      final dir = (target - from);
      final unit = dir / dir.distance;
      final len = size.width * (0.30 - 0.10 * rest);
      final tail = tip - unit * len;
      final perp = Offset(-unit.dy, unit.dx);

      canvas.drawLine(
        tail + unit * (len * 0.3),
        tip,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1.4, size.width * 0.026)
          ..color = const Color(0xFFD3D8DF),
      );
      final finW = size.width * 0.055;
      final fin = Path()
        ..moveTo(tail.dx + perp.dx * finW, tail.dy + perp.dy * finW)
        ..lineTo(tail.dx + unit.dx * len * 0.34, tail.dy + unit.dy * len * 0.34)
        ..lineTo(tail.dx - perp.dx * finW, tail.dy - perp.dy * finW)
        ..lineTo(tail.dx, tail.dy)
        ..close();
      canvas.drawPath(fin, Paint()..color = const Color(0xFFF4B740));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_DartsTilePainter old) =>
      old.t != t ||
      old.liveVisit != liveVisit ||
      old.liveScore != liveScore;
}
