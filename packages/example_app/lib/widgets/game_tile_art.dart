import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/demo_theme.dart';

/// Which miniature to paint on a launcher tile.
enum GameTileKind { ticTacToe, connectFour, dotsAndBoxes }

/// Colorful toy diorama that **plays itself** in a short loop — a silent
/// miniature match, GamePigeon-style identity with a bit of life.
class GameTileArt extends StatefulWidget {
  final GameTileKind kind;

  /// Phase offset so neighboring tiles don't animate in lockstep.
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
    duration: switch (widget.kind) {
      GameTileKind.ticTacToe => const Duration(milliseconds: 4800),
      GameTileKind.connectFour => const Duration(milliseconds: 5200),
      GameTileKind.dotsAndBoxes => const Duration(milliseconds: 5000),
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
        // Phase shifts the loop without Timers (tests + dispose-safe).
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
// Helpers
// ---------------------------------------------------------------------------

double _stepProgress(double t, int step, int totalSteps, {double hold = 0.12}) {
  // Divide the loop into [totalSteps] beats; each mark draws over most of
  // its beat, then holds. Remainder of the loop is a brief idle before reset.
  final active = 1.0 - hold;
  final segment = active / totalSteps;
  final start = step * segment;
  final end = start + segment * 0.72;
  if (t < start) return 0;
  if (t >= end) return 1;
  return Curves.easeOutCubic.transform((t - start) / (end - start));
}

// ---------------------------------------------------------------------------
// Tic-tac-toe: X/O appear in turn, then a win line, then clear.
// ---------------------------------------------------------------------------

class _TicTacToeTilePainter extends CustomPainter {
  final double t;
  _TicTacToeTilePainter({required this.t});

  // Sequence: X(0,0), O(1,1), X(2,0), O(0,2), X(1,0) wins top row.
  static const _moves = <(int col, int row, bool isX)>[
    (0, 0, true),
    (1, 1, false),
    (2, 0, true),
    (0, 2, false),
    (1, 0, true),
  ];

  @override
  void paint(Canvas canvas, Size size) {
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
      final p = _stepProgress(t, i, _moves.length + 1);
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

    // Win line across top row after last X lands.
    final winP = _stepProgress(t, _moves.length, _moves.length + 1, hold: 0.18);
    if (winP > 0) {
      final y = board.top + 0.5 * cell;
      final a = Offset(board.left + 0.2 * cell, y);
      final b = Offset(board.right - 0.2 * cell, y);
      final end = Offset.lerp(a, b, winP)!;
      canvas.drawLine(
        a,
        end,
        Paint()
          ..color = DemoColors.coral.withValues(alpha: 0.85)
          ..strokeWidth = size.width * 0.05
          ..strokeCap = StrokeCap.round,
      );
    }
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
    // First diagonal, then second.
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
// Connect four: discs drop into columns in sequence.
// ---------------------------------------------------------------------------

class _ConnectFourTilePainter extends CustomPainter {
  final double t;
  _ConnectFourTilePainter({required this.t});

  // (col, landRow from top visual 0..3, color) in drop order.
  static const _drops = <(int col, int landRow, Color color)>[
    (1, 3, DemoColors.coral),
    (2, 3, DemoColors.gold),
    (1, 2, DemoColors.coral),
    (3, 3, DemoColors.gold),
    (2, 2, DemoColors.coral),
    (2, 1, DemoColors.gold),
    (1, 1, DemoColors.coral),
  ];

  @override
  void paint(Canvas canvas, Size size) {
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

    // Holes first.
    for (var col = 0; col < cols; col++) {
      for (var row = 0; row < rows; row++) {
        final c = Offset(
          frame.left + (col + 0.5) * cellW,
          frame.top + (row + 0.5) * cellH,
        );
        canvas.drawCircle(c, holeR, Paint()..color = const Color(0xFFE8F0FF));
      }
    }

    // Discs with drop animation per step.
    for (var i = 0; i < _drops.length; i++) {
      final p = _stepProgress(t, i, _drops.length, hold: 0.1);
      if (p <= 0) continue;
      final (col, landRow, color) = _drops[i];
      final restY = frame.top + (landRow + 0.5) * cellH;
      final startY = frame.top - cellH * 0.6;
      // Ease-in fall with tiny bounce at end.
      final fall = Curves.easeInCubic.transform(p.clamp(0.0, 1.0));
      final bounce = p > 0.85
          ? math.sin((p - 0.85) / 0.15 * math.pi) * cellH * 0.06
          : 0.0;
      final y = startY + (restY - startY) * fall - bounce;
      final c = Offset(frame.left + (col + 0.5) * cellW, y);
      final appear = p.clamp(0.0, 1.0);
      canvas.drawCircle(
        c,
        holeR * 0.92 * (0.85 + 0.15 * appear),
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

    // Re-draw blue faceplate strips between holes so falling discs feel
    // "behind" plastic (simple: draw horizontal bars between rows).
    final face = Paint()..color = const Color(0xFF1E5AAD);
    for (var row = 0; row <= rows; row++) {
      final y = frame.top + row * cellH;
      canvas.drawRect(
        Rect.fromLTWH(frame.left, y - holeR * 0.15, frame.width, holeR * 0.3),
        face,
      );
    }
    // Side rails.
    canvas.drawRect(
      Rect.fromLTWH(frame.left, frame.top, holeR * 0.25, frame.height),
      face,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        frame.right - holeR * 0.25,
        frame.top,
        holeR * 0.25,
        frame.height,
      ),
      face,
    );
  }

  @override
  bool shouldRepaint(_ConnectFourTilePainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// Dots & boxes: edges claim one by one, box fills when closed.
// ---------------------------------------------------------------------------

class _DotsBoxesTilePainter extends CustomPainter {
  final double t;
  _DotsBoxesTilePainter({required this.t});

  // Edges of the top-left box + one more edge, then a second box starts.
  // 0 top, 1 left, 2 right, 3 bottom of box (0,0); 4 top of box to the right.
  static const _edgeColors = [
    DemoColors.coral,
    DemoColors.teal,
    DemoColors.coral,
    DemoColors.teal, // closes first box → coral win tint
    DemoColors.coral,
  ];

  @override
  void paint(Canvas canvas, Size size) {
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

    Offset dot(int x, int y) =>
        Offset(area.left + x * step, area.top + y * step);

    // Free edge guides.
    final free = Paint()
      ..color = DemoColors.ink.withValues(alpha: 0.12)
      ..strokeWidth = size.width * 0.03
      ..strokeCap = StrokeCap.round;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n - 1; x++) {
        canvas.drawLine(dot(x, y), dot(x + 1, y), free);
      }
    }
    for (var y = 0; y < n - 1; y++) {
      for (var x = 0; x < n; x++) {
        canvas.drawLine(dot(x, y), dot(x, y + 1), free);
      }
    }

    final edges = <(Offset a, Offset b)>[
      (dot(0, 0), dot(1, 0)), // top
      (dot(0, 0), dot(0, 1)), // left
      (dot(1, 0), dot(1, 1)), // right
      (dot(0, 1), dot(1, 1)), // bottom — closes box
      (dot(1, 0), dot(2, 0)), // next edge
    ];

    for (var i = 0; i < edges.length; i++) {
      final p = _stepProgress(t, i, edges.length + 1, hold: 0.14);
      if (p <= 0) continue;
      final (a, b) = edges[i];
      final end = Offset.lerp(a, b, p)!;
      canvas.drawLine(
        a,
        end,
        Paint()
          ..color = _edgeColors[i]
          ..strokeWidth = size.width * 0.045
          ..strokeCap = StrokeCap.round,
      );
    }

    // Box fill after bottom edge (index 3) completes.
    final boxP = _stepProgress(t, 3, edges.length + 1, hold: 0.14);
    if (boxP > 0.85) {
      final fill = Curves.easeOutBack.transform(
        ((boxP - 0.85) / 0.15).clamp(0.0, 1.0),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(area.left + step / 2, area.top + step / 2),
            width: (step - 6) * fill,
            height: (step - 6) * fill,
          ),
          Radius.circular(size.width * 0.04),
        ),
        Paint()..color = DemoColors.teal.withValues(alpha: 0.28 * fill),
      );
    }

    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        canvas.drawCircle(
          dot(x, y),
          size.width * 0.04,
          Paint()..color = DemoColors.ink,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DotsBoxesTilePainter old) => old.t != t;
}
