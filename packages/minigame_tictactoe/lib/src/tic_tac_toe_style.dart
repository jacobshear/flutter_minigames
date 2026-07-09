import 'package:flutter/material.dart';

/// Visual configuration for [TicTacToeBoard]. Every colour is optional and
/// falls back to the ambient [ColorScheme], so the board looks intentional out
/// of the box and *distinctive* when a host app injects its own palette — the
/// motion is baked in, the brand is yours.
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

  const TicTacToeStyle({
    this.xColor,
    this.oColor,
    this.gridColor,
    this.winLineColor,
    this.haptics = true,
    this.confetti = true,
  });

  Color resolveX(ColorScheme scheme) => xColor ?? scheme.primary;
  Color resolveO(ColorScheme scheme) => oColor ?? scheme.tertiary;
  Color resolveGrid(ColorScheme scheme) =>
      gridColor ?? scheme.onSurface.withValues(alpha: 0.78);
  Color resolveMark(ColorScheme scheme, bool isX) =>
      isX ? resolveX(scheme) : resolveO(scheme);
}
