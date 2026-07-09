import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/demo_theme.dart';

/// Which miniature to paint on a launcher tile.
enum GameTileKind { ticTacToe, connectFour, dotsAndBoxes }

/// Colorful toy diorama for a launcher tile — GamePigeon-style: the art
/// *is* the identity, not a monochrome SF Symbol.
class GameTileArt extends StatelessWidget {
  final GameTileKind kind;

  const GameTileArt({super.key, required this.kind});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: switch (kind) {
        GameTileKind.ticTacToe => _TicTacToeTilePainter(),
        GameTileKind.connectFour => _ConnectFourTilePainter(),
        GameTileKind.dotsAndBoxes => _DotsBoxesTilePainter(),
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _TicTacToeTilePainter extends CustomPainter {
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

    void xAt(int col, int row) {
      final c = Offset(
        board.left + (col + 0.5) * cell,
        board.top + (row + 0.5) * cell,
      );
      final s = cell * 0.22;
      final p = Paint()
        ..color = DemoColors.coral
        ..strokeWidth = size.width * 0.04
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c + Offset(-s, -s), c + Offset(s, s), p);
      canvas.drawLine(c + Offset(s, -s), c + Offset(-s, s), p);
    }

    void oAt(int col, int row) {
      final c = Offset(
        board.left + (col + 0.5) * cell,
        board.top + (row + 0.5) * cell,
      );
      canvas.drawCircle(
        c,
        cell * 0.24,
        Paint()
          ..color = DemoColors.teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.04,
      );
    }

    xAt(0, 0);
    oAt(1, 0);
    xAt(2, 2);
    oAt(0, 2);
    xAt(1, 1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ConnectFourTilePainter extends CustomPainter {
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

    // Simple pattern of discs.
    final pattern = <(int c, int r, Color color)>[
      (1, 3, DemoColors.coral),
      (1, 2, DemoColors.gold),
      (2, 3, DemoColors.gold),
      (2, 2, DemoColors.coral),
      (2, 1, DemoColors.coral),
      (3, 3, DemoColors.coral),
      (3, 2, DemoColors.gold),
    ];

    for (var col = 0; col < cols; col++) {
      for (var row = 0; row < rows; row++) {
        final c = Offset(
          frame.left + (col + 0.5) * cellW,
          frame.top + (row + 0.5) * cellH,
        );
        canvas.drawCircle(c, holeR, Paint()..color = const Color(0xFFE8F0FF));
      }
    }
    for (final (col, row, color) in pattern) {
      final c = Offset(
        frame.left + (col + 0.5) * cellW,
        frame.top + (row + 0.5) * cellH,
      );
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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DotsBoxesTilePainter extends CustomPainter {
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
    const n = 3; // 3x3 dots
    final step = area.width / (n - 1);

    final claimed = Paint()
      ..strokeWidth = size.width * 0.045
      ..strokeCap = StrokeCap.round;

    // A few claimed edges + one filled box.
    claimed.color = DemoColors.coral;
    canvas.drawLine(
      Offset(area.left, area.top),
      Offset(area.left + step, area.top),
      claimed,
    );
    canvas.drawLine(
      Offset(area.left, area.top),
      Offset(area.left, area.top + step),
      claimed,
    );
    claimed.color = DemoColors.teal;
    canvas.drawLine(
      Offset(area.left + step, area.top),
      Offset(area.left + step, area.top + step),
      claimed,
    );
    canvas.drawLine(
      Offset(area.left, area.top + step),
      Offset(area.left + step, area.top + step),
      claimed,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(area.left + 2, area.top + 2, step - 4, step - 4),
        Radius.circular(size.width * 0.04),
      ),
      Paint()..color = DemoColors.coral.withValues(alpha: 0.25),
    );

    // Guide free edges.
    final free = Paint()
      ..color = DemoColors.ink.withValues(alpha: 0.12)
      ..strokeWidth = size.width * 0.03
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(area.left + step, area.top),
      Offset(area.left + 2 * step, area.top),
      free,
    );
    canvas.drawLine(
      Offset(area.left + 2 * step, area.top),
      Offset(area.left + 2 * step, area.top + step),
      free,
    );

    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final o = Offset(area.left + x * step, area.top + y * step);
        canvas.drawCircle(o, size.width * 0.04, Paint()..color = DemoColors.ink);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
