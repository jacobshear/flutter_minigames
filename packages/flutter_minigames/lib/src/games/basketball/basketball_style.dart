import 'package:flutter/material.dart';

import 'basketball_sounds.dart';

/// Visual + juice config for the first-person court.
///
/// Defaults aim for GamePigeon Basketball fidelity seen from the shooter's
/// eyes: warm hardwood receding to a vanishing point, a glass backboard with an
/// orange rim floating above it, and a big orange ball at the bottom of frame.
class BasketballStyle {
  /// Hardwood floor.
  final Color? courtColor;

  /// Gym behind the hoop (also the haze colour distant things fade toward).
  final Color? backdropColor;

  /// The basketball.
  final Color? ballColor;

  /// Rim + backboard accents.
  final Color? rimColor;

  /// Painted court lines.
  final Color? lineColor;

  /// Player 1 accent (chips / confetti).
  final Color? player1Color;

  /// Player 2 accent.
  final Color? player2Color;

  /// Player names shown on the chips.
  final String player1Label;
  final String player2Label;

  final bool haptics;
  final bool confetti;
  final BasketballSounds sounds;

  const BasketballStyle({
    this.courtColor,
    this.backdropColor,
    this.ballColor,
    this.rimColor,
    this.lineColor,
    this.player1Color,
    this.player2Color,
    this.player1Label = 'Player 1',
    this.player2Label = 'Player 2',
    this.haptics = true,
    this.confetti = true,
    this.sounds = BasketballSounds.silent,
  });

  /// Warm hardwood.
  Color resolveCourt(ColorScheme s) => courtColor ?? const Color(0xFFC08A45);

  /// Dim gym interior behind the hoop; doubles as the distance haze.
  Color resolveBackdrop(ColorScheme s) =>
      backdropColor ?? const Color(0xFF20293A);

  /// Classic basketball orange.
  Color resolveBall(ColorScheme s) => ballColor ?? const Color(0xFFE8802B);

  /// Orange rim (a touch hotter than the ball).
  Color resolveRim(ColorScheme s) => rimColor ?? const Color(0xFFF0531C);

  /// Painted lines.
  Color resolveLine(ColorScheme s) => lineColor ?? const Color(0xFFFDF6EA);

  /// Gold used for bonus balls and the heat streak.
  Color get gold => const Color(0xFFF7C948);

  Color resolvePlayer1(ColorScheme s) =>
      player1Color ?? const Color(0xFFE8802B);

  Color resolvePlayer2(ColorScheme s) =>
      player2Color ?? const Color(0xFF2E6FB0);

  Color colorFor(ColorScheme s, String playerId, List<String> playerIds) =>
      playerId == playerIds.first ? resolvePlayer1(s) : resolvePlayer2(s);
}
