import 'package:flutter/material.dart';

import 'filler_sounds.dart';

/// GP-adjacent Filler palette: red, orange, green, teal, purple, charcoal.
const List<Color> kFillerCellColors = [
  Color(0xFFE0453A), // red
  Color(0xFFF1A23B), // orange
  Color(0xFF63B94D), // green
  Color(0xFF3FB6C4), // teal
  Color(0xFF8B5FBF), // purple
  Color(0xFF3B3B45), // charcoal
];

/// Visual + juice config for [FillerBoard].
class FillerStyle {
  /// The 6 cell colors, indexed by the logic's color index.
  final List<Color> cellColors;

  /// Felt table the board sits on (fills the widget behind the slab).
  final Color? tableColor;

  /// Dark slab behind the grid cells.
  final Color? slabColor;

  /// Player names shown on the chips (player 1 owns the bottom-left corner).
  final String p1Label;
  final String p2Label;

  final bool haptics;
  final bool confetti;
  final FillerSounds sounds;

  const FillerStyle({
    this.cellColors = kFillerCellColors,
    this.tableColor,
    this.slabColor,
    this.p1Label = 'Player 1',
    this.p2Label = 'Player 2',
    this.haptics = true,
    this.confetti = true,
    this.sounds = FillerSounds.silent,
  });

  // Deep maroon felt (GP chat-table read).
  Color resolveTable(ColorScheme s) => tableColor ?? const Color(0xFF6E3B3B);
  Color resolveSlab(ColorScheme s) => slabColor ?? const Color(0xFF232329);
}
