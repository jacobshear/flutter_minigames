import 'package:flutter/material.dart';
import 'package:flutter_minigames/games/anagrams.dart' show AnagramsTileArt;
import 'package:flutter_minigames/games/archery.dart' show ArcheryTileArt;
import 'package:flutter_minigames/games/basketball.dart' show BasketballTileArt;
import 'package:flutter_minigames/games/crazy_eights.dart';
import 'package:flutter_minigames/games/darts.dart' show DartsTileArt;
import 'package:flutter_minigames/games/cup_pong.dart' show CupPongTileArt;
import 'package:flutter_minigames/games/eight_ball.dart' show EightBallTileArt;
import 'package:flutter_minigames/games/filler.dart';
import 'package:flutter_minigames/games/gin_rummy.dart' show GinRummyTileArt;
import 'package:flutter_minigames/games/go_fish.dart' show GoFishTileArt;
import 'package:flutter_minigames/games/knockout.dart' show KnockoutTileArt;
import 'package:flutter_minigames/games/mini_golf.dart' show MiniGolfTileArt;
import 'package:flutter_minigames/games/sea_battle.dart' show SeaBattleTileArt;
import 'package:flutter_minigames/games/shuffleboard.dart' show ShuffleboardTileArt;
import 'package:flutter_minigames/games/word_bites.dart' show WordBitesTileArt;
import 'package:flutter_minigames/games/word_hunt.dart' show WordHuntTileArt;

import '../screens/anagrams_play_screen.dart';
import '../screens/archery_play_screen.dart';
import '../screens/basketball_play_screen.dart';
import '../screens/checkers_play_screen.dart';
import '../screens/crazy_eights_play_screen.dart';
import '../screens/filler_play_screen.dart';
import '../screens/chess_play_screen.dart';
import '../screens/connect_four_play_screen.dart';
import '../screens/cup_pong_play_screen.dart';
import '../screens/darts_play_screen.dart';
import '../screens/dots_and_boxes_play_screen.dart';
import '../screens/eight_ball_play_screen.dart';
import '../screens/gin_rummy_play_screen.dart';
import '../screens/go_fish_play_screen.dart';
import '../screens/gomoku_play_screen.dart';
import '../screens/knockout_play_screen.dart';
import '../screens/mancala_play_screen.dart';
import '../screens/mini_golf_play_screen.dart';
import '../screens/reversi_play_screen.dart';
import '../screens/sea_battle_play_screen.dart';
import '../screens/shuffleboard_play_screen.dart';
import '../screens/tictactoe_play_screen.dart';
import '../screens/word_bites_play_screen.dart';
import '../screens/word_hunt_play_screen.dart';
import '../widgets/game_tile_art.dart';

/// One launcher tile. Add a package → add a row. Designed so a host can also
/// render this catalog inside a chat sheet (same entries, constrained height).
class GameCatalogEntry {
  final String id;
  final String title;

  /// Built-in tile art from example_app's [GameTileArt] set. Newer games ship
  /// their own tile widget from their package via [artBuilder] instead.
  final GameTileKind? art;

  /// Package-owned tile art; receives the launcher's shared animation phase.
  /// Wins over [art] when both are set.
  final Widget Function(BuildContext context, double phase)? artBuilder;

  final bool available;
  final WidgetBuilder? builder;

  const GameCatalogEntry({
    required this.id,
    required this.title,
    this.art,
    this.artBuilder,
    this.available = true,
    this.builder,
  }) : assert(art != null || artBuilder != null, 'provide art or artBuilder');
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
      GameCatalogEntry(
        id: 'checkers',
        title: 'Checkers',
        art: GameTileKind.checkers,
        builder: (_) => const CheckersPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'mancala',
        title: 'Mancala',
        art: GameTileKind.mancala,
        builder: (_) => const MancalaPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'gomoku',
        title: 'Gomoku',
        art: GameTileKind.gomoku,
        builder: (_) => const GomokuPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'chess',
        title: 'Chess',
        art: GameTileKind.chess,
        builder: (_) => const ChessPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'sea_battle',
        title: 'Sea Battle',
        artBuilder: (_, __) => const SeaBattleTileArt(),
        builder: (_) => const SeaBattlePlayScreen(),
      ),
      GameCatalogEntry(
        id: 'filler',
        title: 'Filler',
        artBuilder: (_, phase) => FillerTileArt(phase: phase),
        builder: (_) => const FillerPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'crazy_eights',
        title: 'Crazy 8s',
        artBuilder: (_, phase) => CrazyEightsTileArt(phase: phase),
        builder: (_) => const CrazyEightsPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'anagrams',
        title: 'Anagrams',
        artBuilder: (_, phase) => AnagramsTileArt(phase: phase),
        builder: (_) => const AnagramsPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'word_bites',
        title: 'Word Bites',
        artBuilder: (_, phase) => WordBitesTileArt(phase: phase),
        builder: (_) => const WordBitesPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'word_hunt',
        title: 'Word Hunt',
        artBuilder: (_, phase) => WordHuntTileArt(phase: phase),
        builder: (_) => const WordHuntPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'shuffleboard',
        title: 'Shuffleboard',
        artBuilder: (_, phase) => ShuffleboardTileArt(phase: phase),
        builder: (_) => const ShuffleboardPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'knockout',
        title: 'Knockout',
        artBuilder: (_, phase) => KnockoutTileArt(phase: phase),
        builder: (_) => const KnockoutPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'eight_ball',
        title: '8-Ball',
        artBuilder: (_, phase) => EightBallTileArt(phase: phase),
        builder: (_) => const EightBallPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'mini_golf',
        title: 'Mini Golf',
        artBuilder: (_, phase) => MiniGolfTileArt(phase: phase),
        builder: (_) => const MiniGolfPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'basketball',
        title: 'Basketball',
        artBuilder: (_, phase) => BasketballTileArt(phase: phase),
        builder: (_) => const BasketballPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'cup_pong',
        title: 'Cup Pong',
        artBuilder: (_, phase) => CupPongTileArt(phase: phase),
        builder: (_) => const CupPongPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'archery',
        title: 'Archery',
        artBuilder: (_, phase) => ArcheryTileArt(phase: phase),
        builder: (_) => const ArcheryPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'darts',
        title: 'Darts',
        artBuilder: (_, phase) => DartsTileArt(phase: phase),
        builder: (_) => const DartsPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'gin_rummy',
        title: 'Gin Rummy',
        artBuilder: (_, phase) => GinRummyTileArt(phase: phase),
        builder: (_) => const GinRummyPlayScreen(),
      ),
      GameCatalogEntry(
        id: 'go_fish',
        title: 'Go Fish',
        artBuilder: (_, phase) => GoFishTileArt(phase: phase),
        builder: (_) => const GoFishPlayScreen(),
      ),
    ];
