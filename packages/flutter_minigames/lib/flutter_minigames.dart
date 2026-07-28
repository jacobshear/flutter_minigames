/// Async turn-based mini-games for Flutter.
///
/// Two reusable machines, and 26 games built on them:
///
///  * **A turn engine** — [TurnGame] is a pure, serializable contract
///    (`applyMove(state, move) -> newState`). No rendering, no timers, no
///    randomness beyond the match seed.
///  * **A transport seam** — [GameTransport] is four methods. The same game
///    runs hot-seat here and networked in your app with no code changes; the
///    engine never imports a backend. (See `flutter_minigames_firebase` for a
///    Realtime Database adapter.)
///
/// Importing this barrel makes every game reachable, which defeats
/// tree-shaking. An app that wants three games should import just those:
///
/// ```dart
/// import 'package:flutter_minigames/games/darts.dart';
/// ```
library;

export 'src/core/core.dart';
export 'src/ui/ui.dart';
export 'src/cards/cards.dart';
export 'src/engine3d/engine3d.dart';
export 'src/flame/flame.dart';
export 'src/words/words.dart';

export 'src/games/anagrams/anagrams.dart';
export 'src/games/archery/archery.dart';
export 'src/games/basketball/basketball.dart';
export 'src/games/checkers/checkers.dart';
export 'src/games/chess/chess.dart';
export 'src/games/connect_four/connect_four.dart';
export 'src/games/crazy_eights/crazy_eights.dart';
export 'src/games/cup_pong/cup_pong.dart';
export 'src/games/darts/darts.dart';
export 'src/games/dots_and_boxes/dots_and_boxes.dart';
export 'src/games/eight_ball/eight_ball.dart';
export 'src/games/filler/filler.dart';
export 'src/games/gin_rummy/gin_rummy.dart';
export 'src/games/go_fish/go_fish.dart';
export 'src/games/gomoku/gomoku.dart';
export 'src/games/knockout/knockout.dart';
export 'src/games/mancala/mancala.dart';
export 'src/games/mini_golf/mini_golf.dart';
export 'src/games/reversi/reversi.dart';
export 'src/games/sea_battle/sea_battle.dart';
export 'src/games/shuffleboard/shuffleboard.dart';
export 'src/games/tictactoe/tictactoe.dart';
export 'src/games/word_bites/word_bites.dart';
export 'src/games/word_hunt/word_hunt.dart';
