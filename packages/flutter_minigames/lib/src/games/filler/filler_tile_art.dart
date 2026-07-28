import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'filler_game.dart';
import 'filler_style.dart';

/// Launcher-tile miniature for Filler: a real seeded mid-game board (two
/// territories flooding from opposite corners) with a subtle breathing
/// shimmer on each blob. Matches the toy-diorama style of the example app's
/// tile art while staying self-contained in this package.
class FillerTileArt extends StatefulWidget {
  final double phase;

  const FillerTileArt({super.key, this.phase = 0});

  @override
  State<FillerTileArt> createState() => _FillerTileArtState();
}

class _FillerTileArtState extends State<FillerTileArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  )..repeat();

  late final FillerState _mid = _buildMidGame();

  /// Deterministic mid-game board: greedy-capture a few turns so two lively
  /// blobs read instantly as "Filler".
  static FillerState _buildMidGame() {
    const game = FillerGame();
    var s = game.initialState(seed: 12, playerIds: const ['a', 'b']);
    for (var turn = 0; turn < 6; turn++) {
      FillerMove? best;
      var bestGain = -1;
      for (var c = 0; c < FillerState.colorCount; c++) {
        final m = FillerMove(c);
        if (!game.validateMove(s, m, s.currentPlayerId)) continue;
        final gain = game.applyMove(s, m).scoreOfIndex(s.turnIndex);
        if (gain > bestGain) {
          bestGain = gain;
          best = m;
        }
      }
      if (best == null) break;
      s = game.applyMove(s, best);
    }
    return s;
  }

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
          painter: _FillerTilePainter(state: _mid, t: t),
        );
      },
    );
  }
}

class _FillerTilePainter extends CustomPainter {
  final FillerState state;
  final double t;

  _FillerTilePainter({required this.state, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    // Dark slab backdrop, full bleed (tile clips its own corners).
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF232329),
    );

    // Center the grid with a slim margin.
    final margin = size.shortestSide * 0.09;
    final gridW = size.width - margin * 2;
    final gridH = size.height - margin * 2;
    final cellW = gridW / FillerState.cols;
    final cellH = gridH / FillerState.rows;
    final gap = math.min(cellW, cellH) * 0.10;
    final radius = Radius.circular(math.min(cellW, cellH) * 0.24);
    final paint = Paint();

    for (var i = 0; i < FillerState.cellCount; i++) {
      final r = FillerState.rowOf(i);
      final c = FillerState.colOf(i);
      var color = kFillerCellColors[state.cells[i]];

      // Subtle alternating breath on the two territories.
      final owner = state.owners[i];
      if (owner != -1) {
        final wave = math.sin(2 * math.pi * t + (owner == 0 ? 0 : math.pi));
        color = Color.lerp(
          color,
          Colors.white,
          0.05 + 0.05 * wave.clamp(0.0, 1.0),
        )!;
      }

      paint.color = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            margin + c * cellW + gap / 2,
            margin + r * cellH + gap / 2,
            cellW - gap,
            cellH - gap,
          ),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FillerTilePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.state != state;
}
