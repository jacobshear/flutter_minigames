import 'package:flutter/material.dart';

import 'tic_tac_toe_sounds.dart';

/// Visual + juice configuration for [TicTacToeBoard].
///
/// Colours fall back to the ambient [ColorScheme]. Motion is baked into the
/// board; brand (palette, whether confetti/haptics/sounds fire) is injected
/// here so every host gets the same feel in their own skin.
class TicTacToeStyle {
  /// Colour of the X mark. Defaults to `colorScheme.primary`.
  final Color? xColor;

  /// Colour of the O mark. Defaults to `colorScheme.tertiary`.
  final Color? oColor;

  /// Colour of the drawn grid lines. Defaults to a muted `onSurface`.
  final Color? gridColor;

  /// Colour of the winning-line stroke. Defaults to the winner's mark colour.
  final Color? winLineColor;

  /// Whether to fire haptic feedback on placement / win.
  final bool haptics;

  /// Whether to burst confetti on a win.
  final bool confetti;

  /// Optional sound hooks. Defaults to [TicTacToeSounds.silent].
  final TicTacToeSounds sounds;

  const TicTacToeStyle({
    this.xColor,
    this.oColor,
    this.gridColor,
    this.winLineColor,
    this.haptics = true,
    this.confetti = true,
    this.sounds = TicTacToeSounds.silent,
  });

  Color resolveX(ColorScheme scheme) => xColor ?? scheme.primary;
  Color resolveO(ColorScheme scheme) => oColor ?? scheme.tertiary;
  Color resolveGrid(ColorScheme scheme) =>
      gridColor ?? scheme.onSurface.withValues(alpha: 0.78);
  Color resolveMark(ColorScheme scheme, bool isX) =>
      isX ? resolveX(scheme) : resolveO(scheme);
}
