import 'package:flutter/material.dart';

import 'reversi_sounds.dart';

/// Visual + juice config for [ReversiBoard].
class ReversiStyle {
  final Color? darkColor;
  final Color? lightColor;
  final Color? boardColor;
  final Color? gridColor;
  final Color? legalHintColor;

  final bool haptics;
  final bool confetti;
  final bool showLegalMoves;
  final ReversiSounds sounds;

  const ReversiStyle({
    this.darkColor,
    this.lightColor,
    this.boardColor,
    this.gridColor,
    this.legalHintColor,
    this.haptics = true,
    this.confetti = true,
    this.showLegalMoves = true,
    this.sounds = ReversiSounds.silent,
  });

  Color resolveDark(ColorScheme s) => darkColor ?? const Color(0xFF1C1C1E);
  Color resolveLight(ColorScheme s) => lightColor ?? const Color(0xFFF5F5F7);
  Color resolveBoard(ColorScheme s) =>
      boardColor ?? const Color(0xFF2D8A4E);
  Color resolveGrid(ColorScheme s) =>
      gridColor ?? Colors.black.withValues(alpha: 0.18);
  Color resolveHint(ColorScheme s) =>
      legalHintColor ?? Colors.white.withValues(alpha: 0.35);
}
