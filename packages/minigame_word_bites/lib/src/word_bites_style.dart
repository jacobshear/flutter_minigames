import 'package:flutter/material.dart';

import 'word_bites_sounds.dart';

/// Visual + juice config for [WordBitesBoard].
///
/// GP Word Bites read: a bright kitchen-tile board (pale porcelain-blue tiles
/// with light grout) sitting on the repo's felt table, with chunky rounded
/// biscuit-colored letter pieces.
class WordBitesStyle {
  /// Felt table behind the board (fills the widget, Mancala convention).
  final Color? tableColor;

  /// Kitchen-tile face color.
  final Color? boardColor;

  /// Grout lines between tiles.
  final Color? groutColor;

  /// Letter-piece body (biscuit).
  final Color? pieceColor;

  /// Letter glyph color on pieces.
  final Color? letterColor;

  /// Scored-word flash.
  final Color? flashColor;

  /// Accent for the player chip (dot + active tint).
  final Color? accentColor;

  final bool haptics;
  final WordBitesSounds sounds;

  const WordBitesStyle({
    this.tableColor,
    this.boardColor,
    this.groutColor,
    this.pieceColor,
    this.letterColor,
    this.flashColor,
    this.accentColor,
    this.haptics = true,
    this.sounds = WordBitesSounds.silent,
  });

  // Deep maroon felt (GP chat-table read, matches Gomoku/Mancala).
  Color get table => tableColor ?? const Color(0xFF6E3B3B);
  // Pale porcelain blue tile.
  Color get board => boardColor ?? const Color(0xFFBFD5E2);
  Color get grout => groutColor ?? const Color(0xFF9FBACB);
  // Warm biscuit piece with dark cocoa letters ("bites").
  Color get piece => pieceColor ?? const Color(0xFFF6E7C6);
  Color get letter => letterColor ?? const Color(0xFF6B4A26);
  Color get flash => flashColor ?? const Color(0xFF34C759);
  Color get accent => accentColor ?? const Color(0xFF007AFF);
}
