import 'package:flutter/material.dart';

import 'cup_pong_sounds.dart';

/// Visual + juice config for the Cup Pong board.
///
/// Defaults aim for GamePigeon Cup Pong fidelity: a dim room, a warm wooden
/// table receding to the vanishing point, a rack of red Solo cups down-range,
/// a bright white ping-pong ball, and two saturated player accents.
class CupPongStyle {
  /// Table surface.
  final Color? tableColor;

  /// The room the table sits in. Doubles as the fog colour distance hazes
  /// toward, so it has to match the backdrop or the haze reads as grime.
  final Color? backgroundColor;

  /// Cup colour for the rack.
  final Color? cupColor;

  /// The thrown ball colour.
  final Color? ballColor;

  /// Player accents for the chips.
  final Color? player1Color;
  final Color? player2Color;

  /// Player names shown on the chips.
  final String player1Label;
  final String player2Label;

  final bool haptics;
  final bool confetti;
  final CupPongSounds sounds;

  const CupPongStyle({
    this.tableColor,
    this.backgroundColor,
    this.cupColor,
    this.ballColor,
    this.player1Color,
    this.player2Color,
    this.player1Label = 'Player 1',
    this.player2Label = 'Player 2',
    this.haptics = true,
    this.confetti = true,
    this.sounds = CupPongSounds.silent,
  });

  /// Warm wood.
  Color resolveTable() => tableColor ?? const Color(0xFF8C5E33);

  /// Dim room behind the table; also the haze/fog colour.
  Color get roomColor => backgroundColor ?? const Color(0xFF211410);

  /// Classic red party cup.
  Color resolveCup(ColorScheme s) => cupColor ?? const Color(0xFFD8352A);

  /// Bright ping-pong white.
  Color resolveBall(ColorScheme s) => ballColor ?? const Color(0xFFF6F3EA);

  Color resolvePlayer1(ColorScheme s) =>
      player1Color ?? const Color(0xFFF39A2E);

  Color resolvePlayer2(ColorScheme s) =>
      player2Color ?? const Color(0xFF2E6FB0);

  Color colorFor(ColorScheme s, String playerId, List<String> playerIds) =>
      playerId == playerIds.first ? resolvePlayer1(s) : resolvePlayer2(s);
}
