import 'package:flutter/material.dart';
import 'package:flutter_minigames/src/cards/cards.dart';

import 'go_fish_sounds.dart';

/// Look + juice config for `GoFishTable`.
@immutable
class GoFishStyle {
  /// Card-table felt. Defaults to the blue-green the other card games use for
  /// the "water" games; null resolves to [defaultTable].
  final Color? tableColor;

  /// Names on the seat chips. Seat 0 is "Player 1" and always asks first.
  final String p1Label;
  final String p2Label;

  /// Card palette handed to `minigames_cards`.
  final PlayingCardStyle cards;

  /// Tint on the rank group you have selected to ask for.
  final Color selection;

  /// Tint on a completed book.
  final Color bookTint;

  /// Tint on the transfer beat — the cards flying across the table.
  final Color catchTint;

  final bool haptics;

  /// Opaque "Pass to Player N" cover between hot-seat turns. Hands are hidden
  /// information and a shared phone must not leak them. Ignored when the
  /// controller is not hot-seat.
  final bool handoffCover;

  final GoFishSounds sounds;

  const GoFishStyle({
    this.tableColor,
    this.p1Label = 'Player 1',
    this.p2Label = 'Player 2',
    this.cards = kDefaultCardStyle,
    this.selection = const Color(0xFFF4B740),
    this.bookTint = const Color(0xFF57C7FF),
    this.catchTint = const Color(0xFF7BE0A8),
    this.haptics = true,
    this.handoffCover = true,
    this.sounds = GoFishSounds.silent,
  });

  /// The default felt: a deep sea-green, so the pond reads as water without
  /// the table stopping being a card table.
  static const Color defaultTable = Color(0xFF1C5E63);

  String seatLabel(int seat) => seat == 0 ? p1Label : p2Label;

  Color resolveTable(ColorScheme scheme) => tableColor ?? defaultTable;
}
