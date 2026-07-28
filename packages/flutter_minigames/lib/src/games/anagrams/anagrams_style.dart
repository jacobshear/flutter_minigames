import 'package:flutter/material.dart';

import 'anagrams_sounds.dart';

/// Visual + juice config for the Anagrams round board and results view.
///
/// Defaults follow the repo's GP conventions: maroon felt table, warm wooden
/// letter tiles with dark glyphs, black translucent pills for transient
/// messages.
class AnagramsStyle {
  /// Felt table behind the play area.
  final Color? tableColor;

  /// Wooden tile face (top of the subtle vertical gradient).
  final Color? tileTopColor;

  /// Wooden tile face (bottom of the gradient).
  final Color? tileBottomColor;

  /// Letter glyph + tile edge ink.
  final Color? glyphColor;

  /// Accent for valid-word flashes and score popups.
  final Color validColor;

  /// Accent for invalid/duplicate feedback.
  final Color invalidColor;

  final String player1Label;
  final String player2Label;

  final bool haptics;
  final AnagramsSounds sounds;

  const AnagramsStyle({
    this.tableColor,
    this.tileTopColor,
    this.tileBottomColor,
    this.glyphColor,
    this.validColor = const Color(0xFF34C759),
    this.invalidColor = const Color(0xFFFF3B30),
    this.player1Label = 'Player 1',
    this.player2Label = 'Player 2',
    this.haptics = true,
    this.sounds = AnagramsSounds.silent,
  });

  // Deep maroon felt (GP chat-table read, matches Gomoku/Mancala).
  Color resolveTable(ColorScheme s) => tableColor ?? const Color(0xFF6E3B3B);

  // Warm birch tile with a sun-bleached top edge.
  Color resolveTileTop(ColorScheme s) => tileTopColor ?? const Color(0xFFF6E9C8);
  Color resolveTileBottom(ColorScheme s) =>
      tileBottomColor ?? const Color(0xFFDDC08D);
  Color resolveGlyph(ColorScheme s) => glyphColor ?? const Color(0xFF3E2E14);

  String labelOf(int playerIndex) =>
      playerIndex == 0 ? player1Label : player2Label;
}
