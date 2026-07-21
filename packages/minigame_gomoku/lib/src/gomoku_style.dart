import 'package:flutter/material.dart';

import 'gomoku_sounds.dart';

/// Visual + juice config for [GomokuBoard].
class GomokuStyle {
  final Color? boardColor;
  final Color? lineColor;
  final Color? blackStoneColor;
  final Color? whiteStoneColor;

  /// Felt table the board sits on (fills the widget behind the slab).
  final Color? tableColor;

  /// Player names shown on the chips (black owns the bottom chip).
  final String blackLabel;
  final String whiteLabel;

  final bool haptics;
  final bool confetti;
  final GomokuSounds sounds;

  const GomokuStyle({
    this.boardColor,
    this.lineColor,
    this.blackStoneColor,
    this.whiteStoneColor,
    this.tableColor,
    this.blackLabel = 'Player 1',
    this.whiteLabel = 'Player 2',
    this.haptics = true,
    this.confetti = true,
    this.sounds = GomokuSounds.silent,
  });

  // Pale sun-bleached birch slab with quiet ink lines (GP read).
  Color resolveBoard(ColorScheme s) => boardColor ?? const Color(0xFFE5D6B4);
  Color resolveLine(ColorScheme s) =>
      lineColor ?? const Color(0xFF6B5233).withValues(alpha: 0.55);
  Color resolveBlack(ColorScheme s) =>
      blackStoneColor ?? const Color(0xFF26262B);
  Color resolveWhite(ColorScheme s) =>
      whiteStoneColor ?? const Color(0xFFF2F1EC);
  // Deep maroon felt (GP chat-table read).
  Color resolveTable(ColorScheme s) => tableColor ?? const Color(0xFF6E3B3B);
}
