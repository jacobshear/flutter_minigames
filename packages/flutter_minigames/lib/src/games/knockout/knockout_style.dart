import 'package:flutter/material.dart';

import 'knockout_sounds.dart';

/// Visual + juice config for the knockout board.
///
/// Defaults aim for GamePigeon Knockout fidelity: a raised light-stone platform
/// floating over a dark void (so the edge a puck falls off is legible), and two
/// saturated puck colours that read on the stone.
class KnockoutStyle {
  /// Raised platform surface.
  final Color? platformColor;

  /// The dark void the platform floats over.
  final Color? voidColor;

  /// Player 1 puck color (near/bottom chip).
  final Color? player1Color;

  /// Player 2 puck color (far/top chip).
  final Color? player2Color;

  /// Player names shown on the chips (player 1 owns the near/bottom half).
  final String player1Label;
  final String player2Label;

  final bool haptics;
  final bool confetti;
  final KnockoutSounds sounds;

  const KnockoutStyle({
    this.platformColor,
    this.voidColor,
    this.player1Color,
    this.player2Color,
    this.player1Label = 'Player 1',
    this.player2Label = 'Player 2',
    this.haptics = true,
    this.confetti = true,
    this.sounds = KnockoutSounds.silent,
  });

  // Cool light stone the pucks pop against.
  Color resolvePlatform(ColorScheme s) =>
      platformColor ?? const Color(0xFFC9CDD6);
  // Near-black void beyond the lip.
  Color resolveVoid(ColorScheme s) => voidColor ?? const Color(0xFF0E1116);
  // Warm red vs cool blue weights (GP read).
  Color resolvePlayer1(ColorScheme s) =>
      player1Color ?? const Color(0xFFE5484D);
  Color resolvePlayer2(ColorScheme s) =>
      player2Color ?? const Color(0xFF3E7BFA);

  Color colorFor(ColorScheme s, String playerId, List<String> playerIds) =>
      playerId == playerIds.first ? resolvePlayer1(s) : resolvePlayer2(s);
}
