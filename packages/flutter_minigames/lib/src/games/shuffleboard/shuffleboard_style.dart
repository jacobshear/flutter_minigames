import 'package:flutter/material.dart';

import 'shuffleboard_sounds.dart';

/// Visual + juice config for the shuffleboard board.
///
/// Defaults aim for GamePigeon Shuffleboard fidelity: a warm maple lane with a
/// darker frame, cool scoring bands at the far end, and two saturated puck
/// colors that read on the wood.
class ShuffleboardStyle {
  /// Maple lane surface.
  final Color? laneColor;

  /// Darker frame/felt around the lane.
  final Color? frameColor;

  /// Wash over the scoring triangle at the far end.
  final Color? zoneColor;

  /// The foul line color.
  final Color? foulLineColor;

  /// Player 1 puck color (near chip).
  final Color? player1Color;

  /// Player 2 puck color (far chip).
  final Color? player2Color;

  /// Player names shown on the chips (player 1 owns the near/bottom chip).
  final String player1Label;
  final String player2Label;

  final bool haptics;
  final bool confetti;
  final ShuffleboardSounds sounds;

  const ShuffleboardStyle({
    this.laneColor,
    this.frameColor,
    this.zoneColor,
    this.foulLineColor,
    this.player1Color,
    this.player2Color,
    this.player1Label = 'Player 1',
    this.player2Label = 'Player 2',
    this.haptics = true,
    this.confetti = true,
    this.sounds = ShuffleboardSounds.silent,
  });

  // Warm maple lane.
  Color resolveLane(ColorScheme s) => laneColor ?? const Color(0xFFE3B778);
  // Deep walnut frame the lane floats in.
  Color resolveFrame(ColorScheme s) => frameColor ?? const Color(0xFF5A3A22);
  // Cool chalk wash for the scoring triangle.
  Color resolveZone(ColorScheme s) => zoneColor ?? const Color(0xFF3E6E8E);
  Color resolveFoulLine(ColorScheme s) =>
      foulLineColor ?? const Color(0xFF7A2E2E);
  // Red vs blue weights (GP read).
  Color resolvePlayer1(ColorScheme s) =>
      player1Color ?? const Color(0xFFD8443C);
  Color resolvePlayer2(ColorScheme s) =>
      player2Color ?? const Color(0xFF2E6FB0);

  Color colorFor(ColorScheme s, String playerId, List<String> playerIds) =>
      playerId == playerIds.first ? resolvePlayer1(s) : resolvePlayer2(s);
}
