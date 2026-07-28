import 'package:flutter/material.dart';

import 'connect_four_sounds.dart';

/// Visual + juice configuration for [ConnectFourBoard].
///
/// Motion (gravity drop, bounce, win pulse) is package-owned; brand colours
/// and whether confetti/haptics/sounds fire are injected by the host.
class ConnectFourStyle {
  /// First player's disc colour. Defaults to `colorScheme.primary`.
  final Color? player0Color;

  /// Second player's disc colour. Defaults to `colorScheme.tertiary`.
  final Color? player1Color;

  /// Plastic frame around the holes. Defaults to a deep blue-ink.
  final Color? boardColor;

  /// Hole / empty-slot colour. Defaults to a warm paper tone.
  final Color? holeColor;

  final bool haptics;
  final bool confetti;
  final ConnectFourSounds sounds;

  const ConnectFourStyle({
    this.player0Color,
    this.player1Color,
    this.boardColor,
    this.holeColor,
    this.haptics = true,
    this.confetti = true,
    this.sounds = ConnectFourSounds.silent,
  });

  Color resolveP0(ColorScheme scheme) => player0Color ?? scheme.primary;
  Color resolveP1(ColorScheme scheme) => player1Color ?? scheme.tertiary;
  Color resolveBoard(ColorScheme scheme) =>
      boardColor ?? const Color(0xFF2F5DA8);
  Color resolveHole(ColorScheme scheme) => holeColor ?? const Color(0xFFF7F0E4);

  Color resolvePlayer(ColorScheme scheme, bool isPlayer0) =>
      isPlayer0 ? resolveP0(scheme) : resolveP1(scheme);
}
