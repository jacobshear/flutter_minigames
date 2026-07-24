import 'package:flutter/material.dart';

import 'word_hunt_sounds.dart';

/// Visual + juice config for [WordHuntBoard].
class WordHuntStyle {
  /// Felt table the parchment board sits on (fills the widget behind it).
  final Color? tableColor;

  /// Parchment slab behind the tiles.
  final Color? boardColor;

  /// Letter tile face.
  final Color? tileColor;

  /// Letter glyph color.
  final Color? letterColor;

  /// Trace while it could still become a word (neutral).
  final Color? traceNeutralColor;

  /// Trace when the current path spells a valid new word.
  final Color? traceValidColor;

  /// Trace when the current path spells a word already found this round.
  final Color? traceDuplicateColor;

  /// Flash on an invalid release.
  final Color? traceInvalidColor;

  /// Player names shown on the chips (player 1 plays the first round).
  final String player1Label;
  final String player2Label;

  /// Round length in seconds (GamePigeon uses 80).
  final int roundSeconds;

  final bool haptics;
  final WordHuntSounds sounds;

  const WordHuntStyle({
    this.tableColor,
    this.boardColor,
    this.tileColor,
    this.letterColor,
    this.traceNeutralColor,
    this.traceValidColor,
    this.traceDuplicateColor,
    this.traceInvalidColor,
    this.player1Label = 'Player 1',
    this.player2Label = 'Player 2',
    this.roundSeconds = 80,
    this.haptics = true,
    this.sounds = WordHuntSounds.silent,
  });

  // Deep pine felt (GP word-hunt table read).
  Color resolveTable(ColorScheme s) => tableColor ?? const Color(0xFF2E6B4F);
  // Warm parchment slab.
  Color resolveBoard(ColorScheme s) => boardColor ?? const Color(0xFFE8D9B0);
  // Chunky cream tile.
  Color resolveTile(ColorScheme s) => tileColor ?? const Color(0xFFFDF6E0);
  Color resolveLetter(ColorScheme s) => letterColor ?? const Color(0xFF54401F);
  Color resolveNeutral(ColorScheme s) =>
      traceNeutralColor ?? const Color(0xFFF4B740);
  Color resolveValid(ColorScheme s) =>
      traceValidColor ?? const Color(0xFF3FA862);
  Color resolveDuplicate(ColorScheme s) =>
      traceDuplicateColor ?? const Color(0xFF9A9A94);
  Color resolveInvalid(ColorScheme s) =>
      traceInvalidColor ?? const Color(0xFFE0533D);

  String labelFor(int playerIndex) =>
      playerIndex == 0 ? player1Label : player2Label;
}
