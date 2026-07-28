import 'package:flutter/material.dart';
import 'package:minigames_cards/minigames_cards.dart';

import 'gin_rummy_sounds.dart';

/// Look + juice config for `GinRummyTable`.
@immutable
class GinRummyStyle {
  /// Card-table felt. Defaults to the same green the other card games use.
  final Color? tableColor;

  /// Names on the seat chips. Seat 0 is "Player 1" and always acts first.
  final String p1Label;
  final String p2Label;

  /// Card palette handed to `minigames_cards`.
  final PlayingCardStyle cards;

  /// Tint behind a run group in the hand.
  final Color runTint;

  /// Tint behind a set group in the hand.
  final Color setTint;

  /// Ring on the selected card.
  final Color selection;

  final bool haptics;

  /// Opaque "Pass to Player N" cover between hot-seat turns, so a hidden hand
  /// is never leaked across the handoff. Ignored when the controller is not
  /// hot-seat.
  final bool handoffCover;

  final GinRummySounds sounds;

  const GinRummyStyle({
    this.tableColor,
    this.p1Label = 'Player 1',
    this.p2Label = 'Player 2',
    this.cards = kDefaultCardStyle,
    this.runTint = const Color(0xFF57C7FF),
    this.setTint = const Color(0xFFFFC24B),
    this.selection = const Color(0xFFF4B740),
    this.haptics = true,
    this.handoffCover = true,
    this.sounds = GinRummySounds.silent,
  });

  String seatLabel(int seat) => seat == 0 ? p1Label : p2Label;

  Color resolveTable(ColorScheme scheme) =>
      tableColor ?? const Color(0xFF23694A);
}
