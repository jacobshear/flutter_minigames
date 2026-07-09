import 'package:flutter/material.dart';

import '../screens/tictactoe_play_screen.dart';
import '../theme/demo_theme.dart';

/// One entry on the main menu. Add a package → add a row here. That's the loop.
class GameCatalogEntry {
  final String id;
  final String title;
  final String tagline;
  final String players;
  final Color accent;
  final IconData icon;

  /// When false, the card shows "Coming soon" and does not navigate.
  final bool available;

  /// Builds the play screen. Only required when [available] is true.
  final WidgetBuilder? builder;

  const GameCatalogEntry({
    required this.id,
    required this.title,
    required this.tagline,
    required this.players,
    required this.accent,
    required this.icon,
    this.available = true,
    this.builder,
  });
}

/// All games the demo knows about. Local-only today; multiplayer hooks live
/// under `lib/multiplayer/` so entries stay mode-agnostic.
List<GameCatalogEntry> get gameCatalog => [
      GameCatalogEntry(
        id: 'tictactoe',
        title: 'Tic-tac-toe',
        tagline: 'Ink marks, win-line glow, confetti.',
        players: '2 players · hot seat',
        accent: DemoColors.coral,
        icon: Icons.grid_3x3_rounded,
        builder: (_) => const TicTacToePlayScreen(),
      ),
      // Placeholders — next games land here as packages ship.
      const GameCatalogEntry(
        id: 'connect_four',
        title: 'Connect four',
        tagline: 'Gravity drops, cascade wins.',
        players: '2 players',
        accent: DemoColors.teal,
        icon: Icons.view_column_rounded,
        available: false,
      ),
      const GameCatalogEntry(
        id: 'dots_and_boxes',
        title: 'Dots and boxes',
        tagline: 'Claim edges, steal boxes.',
        players: '2 players',
        accent: Color(0xFFF4B740),
        icon: Icons.apps_rounded,
        available: false,
      ),
    ];
