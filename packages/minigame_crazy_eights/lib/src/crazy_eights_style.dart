import 'package:flutter/material.dart';

import 'crazy_eights_sounds.dart';

/// Visual + juice config for [CrazyEightsTable].
class CrazyEightsStyle {
  /// Card-table felt (fills the widget).
  final Color? tableColor;

  /// Player names shown on the side chips (player 1 owns the bottom seat at
  /// match start).
  final String p1Label;
  final String p2Label;

  final bool haptics;
  final bool confetti;

  /// Show the opaque "Pass to Player N" cover between hot-seat turns so
  /// hands are not leaked across the handoff. Ignored (never shown) for
  /// non-hot-seat controllers.
  final bool handoffCover;

  final CrazyEightsSounds sounds;

  const CrazyEightsStyle({
    this.tableColor,
    this.p1Label = 'Player 1',
    this.p2Label = 'Player 2',
    this.haptics = true,
    this.confetti = true,
    this.handoffCover = true,
    this.sounds = CrazyEightsSounds.silent,
  });

  String seatLabel(int seat) => seat == 0 ? p1Label : p2Label;

  // Card-table green felt (GP read).
  Color resolveTable(ColorScheme s) => tableColor ?? const Color(0xFF2D8A4E);
}
