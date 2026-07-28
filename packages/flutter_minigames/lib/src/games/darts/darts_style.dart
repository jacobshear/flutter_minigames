import 'package:flutter/material.dart';

import 'darts_sounds.dart';

/// Visual + juice config for the darts scene.
///
/// Defaults aim at a real board under a bright oche light: sisal cream against
/// matte black, saturated red/green ring beds, a steel wire spider and a black
/// number ring. The room around it is a quiet dim so the board carries the eye.
class DartsStyle {
  /// The pale sisal beds.
  final Color? creamColor;

  /// The dark beds.
  final Color? blackColor;

  /// Double/treble ring red and green.
  final Color? redColor;
  final Color? greenColor;

  /// The wire spider and the number-ring wire.
  final Color? wireColor;

  /// The black surround the numbers sit on.
  final Color? surroundColor;

  /// Room walls and floor.
  final Color? wallColor;
  final Color? floorColor;

  /// Player names shown on the chips.
  final String player1Label;
  final String player2Label;

  /// Player accents.
  final Color? player1Color;
  final Color? player2Color;

  final bool haptics;
  final bool confetti;
  final DartsSounds sounds;

  const DartsStyle({
    this.creamColor,
    this.blackColor,
    this.redColor,
    this.greenColor,
    this.wireColor,
    this.surroundColor,
    this.wallColor,
    this.floorColor,
    this.player1Label = 'Player 1',
    this.player2Label = 'Player 2',
    this.player1Color,
    this.player2Color,
    this.haptics = true,
    this.confetti = true,
    this.sounds = DartsSounds.silent,
  });

  Color get cream => creamColor ?? const Color(0xFFEBD9A8);
  Color get black => blackColor ?? const Color(0xFF17171A);
  Color get red => redColor ?? const Color(0xFFC8392F);
  Color get green => greenColor ?? const Color(0xFF2E8B4F);
  Color get wire => wireColor ?? const Color(0xFFB9BEC6);
  Color get surround => surroundColor ?? const Color(0xFF101014);
  Color get wall => wallColor ?? const Color(0xFF2A2F3A);
  Color get floor => floorColor ?? const Color(0xFF6B4A2E);

  Color get player1 => player1Color ?? const Color(0xFFD8443C);
  Color get player2 => player2Color ?? const Color(0xFF2E6FB0);

  Color colorFor(String playerId, List<String> playerIds) =>
      playerId == playerIds.first ? player1 : player2;

  String labelFor(String playerId, List<String> playerIds) =>
      playerId == playerIds.first ? player1Label : player2Label;
}
