import 'package:flutter/material.dart';

import 'eight_ball_sounds.dart';

/// Visual + juice config for the 8-ball board.
///
/// Defaults aim for GamePigeon 8-Ball fidelity: a green felt bed, a warm wood
/// rail, brass-lipped pockets, and the standard pool-ball colour set.
class EightBallStyle {
  /// Green playing felt.
  final Color? feltColor;

  /// Wood rail/cushion frame around the felt.
  final Color? railColor;

  /// Player 1 label (breaks first).
  final String player1Label;
  final String player2Label;

  final bool haptics;
  final bool confetti;
  final EightBallSounds sounds;

  const EightBallStyle({
    this.feltColor,
    this.railColor,
    this.player1Label = 'Player 1',
    this.player2Label = 'Player 2',
    this.haptics = true,
    this.confetti = true,
    this.sounds = EightBallSounds.silent,
  });

  Color resolveFelt(ColorScheme s) => feltColor ?? const Color(0xFF14663D);
  Color resolveRail(ColorScheme s) => railColor ?? const Color(0xFF5A3A22);

  /// The canonical colour of a numbered pool ball (cue → white, 8 → black).
  static Color ballColor(int number) {
    switch (number) {
      case 0:
        return const Color(0xFFF6F1E7); // cue (ivory white)
      case 1:
      case 9:
        return const Color(0xFFF2C31E); // yellow
      case 2:
      case 10:
        return const Color(0xFF1E52B0); // blue
      case 3:
      case 11:
        return const Color(0xFFD8352A); // red
      case 4:
      case 12:
        return const Color(0xFF5D2E8C); // purple
      case 5:
      case 13:
        return const Color(0xFFE87A20); // orange
      case 6:
      case 14:
        return const Color(0xFF1F7A3D); // green
      case 7:
      case 15:
        return const Color(0xFF7A2222); // maroon
      case 8:
        return const Color(0xFF161616); // black
      default:
        return const Color(0xFF888888);
    }
  }
}
