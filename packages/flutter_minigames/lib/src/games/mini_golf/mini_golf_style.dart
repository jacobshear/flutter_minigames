import 'package:flutter/material.dart';

import 'mini_golf_sounds.dart';

/// Visual + juice config for the mini-golf scene.
///
/// Defaults aim for a bright, sunlit municipal mini-golf course seen in 3/4
/// perspective: striped bent-grass felt, pale timber rails, dark rough beyond
/// them, a red flag in the cup, and a white ball ringed in the acting player's
/// colour.
class MiniGolfStyle {
  /// Putting-green felt.
  final Color? greenColor;

  /// Rough / out-of-bounds beyond the rails, and the distance fog colour.
  final Color? roughColor;

  /// The raised rail/wall colour.
  final Color? wallColor;

  /// Interior blocks and posts.
  final Color? obstacleColor;

  /// Sky above the horizon.
  final Color? skyColor;

  /// The flag colour at the cup.
  final Color? flagColor;

  /// Player 1 ball accent (chip + ball ring).
  final Color? player1Color;

  /// Player 2 ball accent.
  final Color? player2Color;

  /// Player names shown on the chips.
  final String player1Label;
  final String player2Label;

  final bool haptics;
  final bool confetti;

  /// Whether a new hole opens with a short camera reveal that sweeps from the
  /// cup back to the tee. Interrupted by the first touch.
  final bool previewPan;
  final MiniGolfSounds sounds;

  const MiniGolfStyle({
    this.greenColor,
    this.roughColor,
    this.wallColor,
    this.obstacleColor,
    this.skyColor,
    this.flagColor,
    this.player1Color,
    this.player2Color,
    this.player1Label = 'Player 1',
    this.player2Label = 'Player 2',
    this.haptics = true,
    this.confetti = true,
    this.previewPan = true,
    this.sounds = MiniGolfSounds.silent,
  });

  /// Bright bent-grass green.
  Color resolveGreen(ColorScheme s) => greenColor ?? const Color(0xFF3FA45A);

  /// Deep rough the green floats in — also the haze colour, so distance fades
  /// everything toward it.
  Color resolveRough(ColorScheme s) => roughColor ?? const Color(0xFF20492C);

  /// Pale timber rail.
  Color resolveWall(ColorScheme s) => wallColor ?? const Color(0xFFE3D8BE);

  /// Interior solids — a warmer, darker timber so they never read as rails.
  Color resolveObstacle(ColorScheme s) =>
      obstacleColor ?? const Color(0xFFB4643C);

  /// Sky above the horizon.
  Color resolveSky(ColorScheme s) => skyColor ?? const Color(0xFF9CC9E8);

  /// Classic red flag.
  Color resolveFlag(ColorScheme s) => flagColor ?? const Color(0xFFE23B32);

  /// Player ball accents (a warm and a cool marker).
  Color resolvePlayer1(ColorScheme s) =>
      player1Color ?? const Color(0xFFF5A623);

  Color resolvePlayer2(ColorScheme s) =>
      player2Color ?? const Color(0xFF2E9BE6);

  Color colorFor(ColorScheme s, String playerId, List<String> playerIds) =>
      playerId == playerIds.first ? resolvePlayer1(s) : resolvePlayer2(s);
}
