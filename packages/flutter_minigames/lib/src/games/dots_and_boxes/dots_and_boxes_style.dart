import 'package:flutter/material.dart';

import 'dots_and_boxes_sounds.dart';

/// Visual + juice config for [DotsAndBoxesBoard].
class DotsAndBoxesStyle {
  final Color? player0Color;
  final Color? player1Color;
  final Color? boardColor;
  final Color? freeEdgeColor;
  final Color? dotColor;

  final bool haptics;
  final bool confetti;
  final DotsAndBoxesSounds sounds;

  const DotsAndBoxesStyle({
    this.player0Color,
    this.player1Color,
    this.boardColor,
    this.freeEdgeColor,
    this.dotColor,
    this.haptics = true,
    this.confetti = true,
    this.sounds = DotsAndBoxesSounds.silent,
  });

  Color resolveP0(ColorScheme s) => player0Color ?? s.primary;
  Color resolveP1(ColorScheme s) => player1Color ?? s.tertiary;
  Color resolveBoard(ColorScheme s) => boardColor ?? const Color(0xFFFFFDF8);
  Color resolveFreeEdge(ColorScheme s) =>
      freeEdgeColor ?? s.onSurface.withValues(alpha: 0.14);
  Color resolveDot(ColorScheme s) =>
      dotColor ?? s.onSurface.withValues(alpha: 0.72);
  Color resolvePlayer(ColorScheme s, bool isP0) =>
      isP0 ? resolveP0(s) : resolveP1(s);
}
