import 'package:flutter/material.dart';

import 'mancala_sounds.dart';

/// Visual + juice config for [MancalaBoard].
class MancalaStyle {
  final Color? boardColor;
  final Color? pitColor;
  final Color? seedColor;
  final Color? southAccent;
  final Color? northAccent;

  /// Felt table the board sits on (fills the widget behind the tray).
  final Color? tableColor;

  /// Player names shown beside the board (south owns the right column).
  final String southLabel;
  final String northLabel;

  final bool haptics;
  final bool confetti;
  final MancalaSounds sounds;

  /// Seeds per pit at start (classic Kalah is 4).
  final int seedsPerPit;

  const MancalaStyle({
    this.boardColor,
    this.pitColor,
    this.seedColor,
    this.southAccent,
    this.northAccent,
    this.tableColor,
    this.southLabel = 'Player 1',
    this.northLabel = 'Player 2',
    this.haptics = true,
    this.confetti = true,
    this.sounds = MancalaSounds.silent,
    this.seedsPerPit = 4,
  });

  // Warm hardwood slab + scoops routed from the same stock (GP read).
  Color resolveBoard(ColorScheme s) =>
      boardColor ?? const Color(0xFFCFAE74);
  Color resolvePit(ColorScheme s) =>
      pitColor ?? const Color(0xFFBE9A5E);
  Color resolveSeed(ColorScheme s) =>
      seedColor ?? const Color(0xFFFFE082);
  Color resolveSouth(ColorScheme s) =>
      southAccent ?? const Color(0xFF1C1C1E);
  Color resolveNorth(ColorScheme s) =>
      northAccent ?? const Color(0xFFE53935);
  // Deep maroon felt (GP chat-table read).
  Color resolveTable(ColorScheme s) =>
      tableColor ?? const Color(0xFF6E3B3B);
}
