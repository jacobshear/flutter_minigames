import 'package:flutter/material.dart';

import '../screens/connect_four_play_screen.dart';
import '../screens/dots_and_boxes_play_screen.dart';
import '../screens/reversi_play_screen.dart';
import '../screens/tictactoe_play_screen.dart';
import '../widgets/game_tile_art.dart';

/// One launcher tile. Add a package → add a row. Designed so a host can also
/// render this catalog inside a chat sheet (same entries, constrained height).
class GameCatalogEntry {
  final String id;
  final String title;
  final GameTileKind art;
  final bool available;
  final WidgetBuilder? builder;

  const GameCatalogEntry({
    required this.id,
    required this.title,
    required this.art,
    this.available = true,
    this.builder,
  });
}

/// Games shown on the launcher. Local hot-seat builders today; multiplayer
/// hosts swap [PlaySession] inside each play screen later.
List<GameCatalogEntry> get gameCatalog => [
      GameCatalogEntry(
        id: 'tictactoe',
        title: 'Tic-Tac-Toe',
        art: GameTileKind.ticTacToe,
        builder: (_) => const TicTacToePlayScreen(),
      ),
      GameCatalogEntry(
        id: 'connect_four',
        title: '4 in a Row',
        art: GameTileKind.connectFour,
        builder: (_) => const ConnectFourPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'dots_and_boxes',
        title: 'Dots & Boxes',
        art: GameTileKind.dotsAndBoxes,
        builder: (_) => const DotsAndBoxesPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'reversi',
        title: 'Reversi',
        art: GameTileKind.reversi,
        builder: (_) => const ReversiPlayScreen(),
      ),
    ];
