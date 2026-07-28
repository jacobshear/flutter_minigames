import 'package:flutter/material.dart';

import 'archery_sounds.dart';

/// Visual + juice config for the archery range.
///
/// Defaults aim for a bright Wii-Sports-Resort morning: cool sky, mown grass
/// converging to a hazy treeline, and a FITA-coloured face that reads instantly
/// as archery (gold centre, then red, blue, black, white outward).
class ArcheryStyle {
  final Color? skyTopColor;
  final Color? skyHorizonColor;
  final Color? grassNearColor;
  final Color? grassFarColor;

  /// Colour everything fades toward with distance.
  final Color? hazeColor;

  /// Straw butt the face is pinned to.
  final Color? buttColor;

  /// Player accents (chips, confetti, the wind flag).
  final Color? player1Color;
  final Color? player2Color;

  final String player1Label;
  final String player2Label;

  final bool haptics;
  final bool confetti;

  /// Slow-motion beat as a gold-bound arrow arrives.
  final bool slowMotionOnBullseye;

  final ArcherySounds sounds;

  const ArcheryStyle({
    this.skyTopColor,
    this.skyHorizonColor,
    this.grassNearColor,
    this.grassFarColor,
    this.hazeColor,
    this.buttColor,
    this.player1Color,
    this.player2Color,
    this.player1Label = 'Player 1',
    this.player2Label = 'Player 2',
    this.haptics = true,
    this.confetti = true,
    this.slowMotionOnBullseye = true,
    this.sounds = ArcherySounds.silent,
  });

  Color resolveSkyTop(ColorScheme s) => skyTopColor ?? const Color(0xFF2E76C4);
  Color resolveSkyHorizon(ColorScheme s) =>
      skyHorizonColor ?? const Color(0xFFC8E4F4);
  Color resolveGrassNear(ColorScheme s) =>
      grassNearColor ?? const Color(0xFF4E8B3A);
  Color resolveGrassFar(ColorScheme s) =>
      grassFarColor ?? const Color(0xFF87B76A);
  Color resolveHaze(ColorScheme s) => hazeColor ?? const Color(0xFFD3E6EF);
  Color resolveButt(ColorScheme s) => buttColor ?? const Color(0xFFD9B871);
  Color resolvePlayer1(ColorScheme s) =>
      player1Color ?? const Color(0xFFD8443C);
  Color resolvePlayer2(ColorScheme s) =>
      player2Color ?? const Color(0xFF2E6FB0);

  Color colorFor(ColorScheme s, String playerId, List<String> playerIds) =>
      playerId == playerIds.first ? resolvePlayer1(s) : resolvePlayer2(s);

  String labelFor(int playerIndex) =>
      playerIndex == 0 ? player1Label : player2Label;

  /// Ring fills from the gold outward — FITA order, so the colour *is* the
  /// score: gold 10, red 8, blue 6, black 4, white 2.
  static const List<Color> ringColors = [
    Color(0xFFF6C445), // 10 — gold
    Color(0xFFE2483C), // 8  — red
    Color(0xFF3F8FD1), // 6  — blue
    Color(0xFF2B2B30), // 4  — black
    Color(0xFFF2F1EC), // 2  — white
  ];

  /// Ink used for ring separators and the numbers on the face.
  static const Color ringLine = Color(0x552B2B30);
}
