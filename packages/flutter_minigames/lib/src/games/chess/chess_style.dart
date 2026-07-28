import 'package:flutter/material.dart';

import 'chess_sounds.dart';

/// Visual + juice config for [ChessBoard].
class ChessStyle {
  final Color? lightSquareColor;
  final Color? darkSquareColor;
  final Color? whitePieceColor;
  final Color? blackPieceColor;

  /// Tint for the last move's from/to squares and the selected square.
  final Color? highlightColor;

  /// Felt table the board sits on (fills the widget behind the slab).
  final Color? tableColor;

  /// Player names shown on the chips (white owns the bottom chip).
  final String whiteLabel;
  final String blackLabel;

  final bool haptics;
  final bool confetti;
  final ChessSounds sounds;

  const ChessStyle({
    this.lightSquareColor,
    this.darkSquareColor,
    this.whitePieceColor,
    this.blackPieceColor,
    this.highlightColor,
    this.tableColor,
    this.whiteLabel = 'Player 1',
    this.blackLabel = 'Player 2',
    this.haptics = true,
    this.confetti = true,
    this.sounds = ChessSounds.silent,
  });

  // Pale birch + sun-warmed walnut two-tone (GP read).
  Color resolveLight(ColorScheme s) =>
      lightSquareColor ?? const Color(0xFFEBDDBE);
  Color resolveDark(ColorScheme s) =>
      darkSquareColor ?? const Color(0xFFB08A5F);
  Color resolveWhitePiece(ColorScheme s) =>
      whitePieceColor ?? const Color(0xFFF4F1E8);
  Color resolveBlackPiece(ColorScheme s) =>
      blackPieceColor ?? const Color(0xFF33323A);
  Color resolveHighlight(ColorScheme s) =>
      highlightColor ?? const Color(0xFFF4B740);
  // Deep maroon felt (GP chat-table read).
  Color resolveTable(ColorScheme s) => tableColor ?? const Color(0xFF6E3B3B);
}
