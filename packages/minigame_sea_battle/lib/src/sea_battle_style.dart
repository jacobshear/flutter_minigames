import 'package:flutter/material.dart';

import 'sea_battle_sounds.dart';

/// Visual + juice config for [SeaBattleBoard].
class SeaBattleStyle {
  /// Sea surface of the grids.
  final Color? waterColor;

  /// Grid lines over the water.
  final Color? gridLineColor;

  /// Ship hull base color.
  final Color? shipColor;

  /// Hit peg color.
  final Color? hitColor;

  /// Miss dot color.
  final Color? missColor;

  /// Felt table the grids sit on (fills the widget behind the boards).
  final Color? tableColor;

  /// Player names shown on the chips (player 1 owns the bottom chip).
  final String player1Label;
  final String player2Label;

  final bool haptics;
  final bool confetti;
  final SeaBattleSounds sounds;

  const SeaBattleStyle({
    this.waterColor,
    this.gridLineColor,
    this.shipColor,
    this.hitColor,
    this.missColor,
    this.tableColor,
    this.player1Label = 'Player 1',
    this.player2Label = 'Player 2',
    this.haptics = true,
    this.confetti = true,
    this.sounds = SeaBattleSounds.silent,
  });

  // Soft GP sea: pale sky-blue water, whisper-white grid.
  Color resolveWater(ColorScheme s) => waterColor ?? const Color(0xFFA8D4EC);
  Color resolveGridLine(ColorScheme s) =>
      gridLineColor ?? Colors.white.withValues(alpha: 0.55);
  Color resolveShip(ColorScheme s) => shipColor ?? const Color(0xFF95A0AC);
  Color resolveHit(ColorScheme s) => hitColor ?? const Color(0xFFE8452E);
  Color resolveMiss(ColorScheme s) => missColor ?? const Color(0xFFF4F7FA);
  // Deep maroon felt (GP chat-table read).
  Color resolveTable(ColorScheme s) => tableColor ?? const Color(0xFF6E3B3B);
}
