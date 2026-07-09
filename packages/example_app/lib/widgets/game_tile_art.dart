import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/demo_theme.dart';

/// Which miniature to paint on a launcher tile.
enum GameTileKind { ticTacToe, connectFour, dotsAndBoxes }

/// Colorful toy diorama that plays a complete short match on a smooth loop.
class GameTileArt extends StatefulWidget {
  final GameTileKind kind;
  final double phase;

  const GameTileArt({
    super.key,
    required this.kind,
    this.phase = 0,
  });

  @override
  State<GameTileArt> createState() => _GameTileArtState();
}

class _GameTileArtState extends State<GameTileArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    // Long enough that each move reads; loop fade handles the seam.
    duration: switch (widget.kind) {
      GameTileKind.ticTacToe => const Duration(milliseconds: 5600),
      GameTileKind.connectFour => const Duration(milliseconds: 7000),
      GameTileKind.dotsAndBoxes => const Duration(milliseconds: 7800),
    },
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = (_c.value + widget.phase) % 1.0;
        return CustomPaint(
          painter: switch (widget.kind) {
            GameTileKind.ticTacToe => _TicTacToeTilePainter(t: t),
            GameTileKind.connectFour => _ConnectFourTilePainter(t: t),
            GameTileKind.dotsAndBoxes => _DotsBoxesTilePainter(t: t),
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared timeline — even beats, long settle, soft loop fade.
// ---------------------------------------------------------------------------

/// Progress of [step] given global loop time [t].
///
/// Layout of the loop:
///   0 ──────── actionEnd ── celebrateEnd ── 1
///   |  moves…            |  hold win     | fade |
double _beat(
  double t,
  int step,
  int moveCount, {
  double actionEnd = 0.76,
  double drawShare = 0.62,
}) {
  // During celebrate + fade, every move is fully painted.
  if (t >= actionEnd) return 1;
  final u = (t / actionEnd).clamp(0.0, 1.0);
  final pos = u * moveCount;
  final i = pos.floor().clamp(0, moveCount);
  if (step > i) return 0;
  if (step < i) return 1;
  final local = pos - i;
  if (local >= drawShare) return 1;
  return Curves.easeOutCubic.transform(local / drawShare);
}

/// 0→1 over the celebrate window (after last move).
double _celebrate(
  double t, {
  double actionEnd = 0.76,
  double celebrateEnd = 0.90,
}) {
  if (t < actionEnd) return 0;
  if (t >= celebrateEnd) return 1;
  return Curves.easeOutCubic.transform(
    (t - actionEnd) / (celebrateEnd - actionEnd),
  );
}

/// Softly fades everything out before the loop wraps (prevents hard reset pop).
double _loopOpacity(double t, {double fadeStart = 0.90}) {
  if (t < fadeStart) return 1;
  return 1 - Curves.easeInCubic.transform((t - fadeStart) / (1 - fadeStart));
}

// ---------------------------------------------------------------------------
// Tic-tac-toe — complete short game, X wins top row.
// ---------------------------------------------------------------------------

class _TicTacToeTilePainter extends CustomPainter {
  final double t;
  _TicTacToeTilePainter({required this.t});

  static const _moves = <(int col, int row, bool isX)>[
    (0, 0, true),
    (1, 1, false),
    (2, 0, true),
    (0, 2, false),
    (1, 0, true), // X wins top
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = _loopOpacity(t);
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );

    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.22),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF8F0), Color(0xFFFFE8D6)],
        ).createShader(Offset.zero & size),
    );

    final pad = size.width * 0.18;
    final board = Rect.fromLTWH(
      pad,
      pad,
      size.width - pad * 2,
      size.height - pad * 2,
    );
    final cell = board.width / 3;
    final grid = Paint()
      ..color = DemoColors.ink.withValues(alpha: 0.55)
      ..strokeWidth = size.width * 0.028
      ..strokeCap = StrokeCap.round;

    for (var i = 1; i <= 2; i++) {
      canvas.drawLine(
        Offset(board.left + cell * i, board.top + cell * 0.12),
        Offset(board.left + cell * i, board.bottom - cell * 0.12),
        grid,
      );
      canvas.drawLine(
        Offset(board.left + cell * 0.12, board.top + cell * i),
        Offset(board.right - cell * 0.12, board.top + cell * i),
        grid,
      );
    }

    for (var i = 0; i < _moves.length; i++) {
      final p = _beat(t, i, _moves.length);
      if (p <= 0) continue;
      final (col, row, isX) = _moves[i];
      final c = Offset(
        board.left + (col + 0.5) * cell,
        board.top + (row + 0.5) * cell,
      );
      if (isX) {
        _drawX(canvas, c, cell * 0.22, size.width * 0.04, DemoColors.coral, p);
      } else {
        _drawO(canvas, c, cell * 0.24, size.width * 0.04, DemoColors.teal, p);
      }
    }

    final winP = _celebrate(t);
    if (winP > 0) {
      final y = board.top + 0.5 * cell;
      final a = Offset(board.left + 0.18 * cell, y);
      final b = Offset(board.right - 0.18 * cell, y);
      canvas.drawLine(
        a,
        Offset.lerp(a, b, winP)!,
        Paint()
          ..color = DemoColors.coral.withValues(alpha: 0.9)
          ..strokeWidth = size.width * 0.05
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.restore();
  }

  void _drawX(
    Canvas canvas,
    Offset c,
    double s,
    double stroke,
    Color color,
    double p,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final p1 = (p * 2).clamp(0.0, 1.0);
    final p2 = ((p - 0.5) * 2).clamp(0.0, 1.0);
    final a0 = c + Offset(-s, -s);
    final a1 = c + Offset(s, s);
    canvas.drawLine(a0, Offset.lerp(a0, a1, p1)!, paint);
    if (p2 > 0) {
      final b0 = c + Offset(s, -s);
      final b1 = c + Offset(-s, s);
      canvas.drawLine(b0, Offset.lerp(b0, b1, p2)!, paint);
    }
  }

  void _drawO(
    Canvas canvas,
    Offset c,
    double radius,
    double stroke,
    Color color,
    double p,
  ) {
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius),
      -math.pi / 2,
      2 * math.pi * p,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TicTacToeTilePainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// Connect four — full short game, coral vertical win in center column.
// ---------------------------------------------------------------------------

class _ConnectFourTilePainter extends CustomPainter {
  final double t;
  _ConnectFourTilePainter({required this.t});

  // landRow: 0 = top visual, 3 = bottom. Coral stacks col 2 for the win.
  static const _drops = <(int col, int landRow, Color color)>[
    (2, 3, DemoColors.coral), // C bottom
    (1, 3, DemoColors.gold),
    (2, 2, DemoColors.coral),
    (0, 3, DemoColors.gold),
    (2, 1, DemoColors.coral),
    (3, 3, DemoColors.gold),
    (2, 0, DemoColors.coral), // C vertical four — win
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = _loopOpacity(t);
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );

    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.22),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5B9DFF), Color(0xFF2B6BCB)],
        ).createShader(Offset.zero & size),
    );

    final pad = size.width * 0.14;
    final frame = Rect.fromLTWH(
      pad,
      pad * 1.15,
      size.width - pad * 2,
      size.height - pad * 2.1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, Radius.circular(size.width * 0.08)),
      Paint()..color = const Color(0xFF1E5AAD),
    );

    const cols = 5;
    const rows = 4;
    final cellW = frame.width / cols;
    final cellH = frame.height / rows;
    final holeR = math.min(cellW, cellH) * 0.32;

    for (var col = 0; col < cols; col++) {
      for (var row = 0; row < rows; row++) {
        final c = Offset(
          frame.left + (col + 0.5) * cellW,
          frame.top + (row + 0.5) * cellH,
        );
        canvas.drawCircle(c, holeR, Paint()..color = const Color(0xFFE8F0FF));
      }
    }

    for (var i = 0; i < _drops.length; i++) {
      final p = _beat(t, i, _drops.length, drawShare: 0.70);
      if (p <= 0) continue;
      final (col, landRow, color) = _drops[i];
      final restY = frame.top + (landRow + 0.5) * cellH;
      final startY = frame.top - cellH * 0.75;
      // Gravity ease-in; soft bounce only in the last 18% of the beat.
      final fallT = Curves.easeInCubic.transform(p.clamp(0.0, 1.0));
      var y = lerpDouble(startY, restY, fallT)!;
      if (p > 0.82) {
        final b = (p - 0.82) / 0.18;
        y -= math.sin(b * math.pi) * cellH * 0.07;
      }
      final c = Offset(frame.left + (col + 0.5) * cellW, y);
      canvas.drawCircle(
        c,
        holeR * 0.92,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.35),
            colors: [
              Color.lerp(color, Colors.white, 0.35)!,
              color,
            ],
          ).createShader(Rect.fromCircle(center: c, radius: holeR)),
      );
    }

    // Win line down center column during celebrate.
    final winP = _celebrate(t);
    if (winP > 0) {
      final x = frame.left + (2 + 0.5) * cellW;
      final a = Offset(x, frame.top + 0.35 * cellH);
      final b = Offset(x, frame.bottom - 0.35 * cellH);
      canvas.drawLine(
        a,
        Offset.lerp(a, b, winP)!,
        Paint()
          ..color = DemoColors.coral.withValues(alpha: 0.9)
          ..strokeWidth = size.width * 0.055
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.02),
      );
      canvas.drawLine(
        a,
        Offset.lerp(a, b, winP)!,
        Paint()
          ..color = DemoColors.coral
          ..strokeWidth = size.width * 0.035
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ConnectFourTilePainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// Dots & boxes — full 2×2 board, all boxes claimed, coral wins 3–1.
// ---------------------------------------------------------------------------

class _DotsBoxesTilePainter extends CustomPainter {
  final double t;
  _DotsBoxesTilePainter({required this.t});

  /// Full 2×2 board (12 edges). Teal takes box (0,0); coral takes the other
  /// three (3–1). ('h'|'v', row, col, color).
  static const _play = <(String kind, int r, int c, Color color)>[
    ('h', 0, 0, DemoColors.coral),
    ('v', 0, 0, DemoColors.teal),
    ('v', 0, 1, DemoColors.coral),
    ('h', 1, 0, DemoColors.teal), // closes box00 → teal
    ('h', 0, 1, DemoColors.coral),
    ('v', 0, 2, DemoColors.teal),
    ('v', 1, 0, DemoColors.coral),
    ('v', 1, 2, DemoColors.teal),
    ('h', 1, 1, DemoColors.coral), // closes box01 → coral
    ('h', 2, 0, DemoColors.coral),
    ('h', 2, 1, DemoColors.coral),
    ('v', 1, 1, DemoColors.coral), // closes box10 + box11 → coral
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = _loopOpacity(t);
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );

    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.22),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBF0), Color(0xFFFFF0C8)],
        ).createShader(Offset.zero & size),
    );

    final pad = size.width * 0.2;
    final area = Rect.fromLTWH(
      pad,
      pad,
      size.width - pad * 2,
      size.height - pad * 2,
    );
    const n = 3;
    final step = area.width / (n - 1);

    Offset d(int x, int y) => Offset(area.left + x * step, area.top + y * step);

    final free = Paint()
      ..color = DemoColors.ink.withValues(alpha: 0.12)
      ..strokeWidth = size.width * 0.028
      ..strokeCap = StrokeCap.round;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n - 1; x++) {
        canvas.drawLine(d(x, y), d(x + 1, y), free);
      }
    }
    for (var y = 0; y < n - 1; y++) {
      for (var x = 0; x < n; x++) {
        canvas.drawLine(d(x, y), d(x, y + 1), free);
      }
    }

    for (var i = 0; i < _play.length; i++) {
      final p = _beat(t, i, _play.length, drawShare: 0.58);
      if (p <= 0) continue;
      final (kind, er, ec, color) = _play[i];
      final Offset a;
      final Offset b;
      if (kind == 'h') {
        a = d(ec, er);
        b = d(ec + 1, er);
      } else {
        a = d(ec, er);
        b = d(ec, er + 1);
      }
      canvas.drawLine(
        a,
        Offset.lerp(a, b, p)!,
        Paint()
          ..color = color
          ..strokeWidth = size.width * 0.045
          ..strokeCap = StrokeCap.round,
      );
    }

    void maybeFill(int br, int bc, int closeStep, Color owner) {
      final p = _beat(t, closeStep, _play.length, drawShare: 0.58);
      if (p < 0.9) return;
      final local = Curves.easeOutBack.transform(
        ((p - 0.9) / 0.1).clamp(0.0, 1.0),
      );
      final cFill = math.max(local, _celebrate(t) * (p >= 1 ? 1.0 : local));
      final cx = area.left + (bc + 0.5) * step;
      final cy = area.top + (br + 0.5) * step;
      final side = (step - 6) * (0.2 + 0.8 * cFill.clamp(0.0, 1.0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy), width: side, height: side),
          Radius.circular(size.width * 0.035),
        ),
        Paint()..color = owner.withValues(alpha: 0.32 * cFill.clamp(0.0, 1.0)),
      );
    }

    maybeFill(0, 0, 3, DemoColors.teal);
    maybeFill(0, 1, 8, DemoColors.coral);
    maybeFill(1, 0, 11, DemoColors.coral);
    maybeFill(1, 1, 11, DemoColors.coral);

    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        canvas.drawCircle(
          d(x, y),
          size.width * 0.038,
          Paint()..color = DemoColors.ink,
        );
      }
    }

    final winP = _celebrate(t);
    if (winP > 0) {
      canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.12),
        size.width * 0.09 * winP,
        Paint()
          ..color = DemoColors.coral.withValues(alpha: 0.4 * winP)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.045),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_DotsBoxesTilePainter old) => old.t != t;
}
