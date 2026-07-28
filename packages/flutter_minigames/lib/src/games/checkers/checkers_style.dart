import 'package:flutter/material.dart';

import 'checkers_sounds.dart';

/// Visual + juice config for [CheckersBoard].
class CheckersStyle {
  final Color? darkPieceColor;
  final Color? lightPieceColor;
  final Color? darkSquareColor;
  final Color? lightSquareColor;
  final Color? selectColor;
  final Color? hintColor;

  final bool haptics;
  final bool confetti;
  final CheckersSounds sounds;

  const CheckersStyle({
    this.darkPieceColor,
    this.lightPieceColor,
    this.darkSquareColor,
    this.lightSquareColor,
    this.selectColor,
    this.hintColor,
    this.haptics = true,
    this.confetti = true,
    this.sounds = CheckersSounds.silent,
  });

  Color resolveDarkPiece(ColorScheme s) =>
      darkPieceColor ?? const Color(0xFF1C1C1E);
  Color resolveLightPiece(ColorScheme s) =>
      lightPieceColor ?? const Color(0xFFE53935);
  Color resolveDarkSquare(ColorScheme s) =>
      darkSquareColor ?? const Color(0xFF5D4037);
  Color resolveLightSquare(ColorScheme s) =>
      lightSquareColor ?? const Color(0xFFD7CCC8);
  Color resolveSelect(ColorScheme s) =>
      selectColor ?? const Color(0xFFFFCC00);
  Color resolveHint(ColorScheme s) =>
      hintColor ?? Colors.white.withValues(alpha: 0.45);
}
