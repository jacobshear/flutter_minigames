/// Knockout for flutter_minigames — a top-down flick game.
///
/// Pure [KnockoutGame] rules (no physics) plus a Flame/Forge2D board that
/// simulates the flick locally and serializes the settled positions (with
/// `fell` flags) as the move. Every platform edge is open: knock the opponent's
/// pucks off without knocking your own off. See [KnockoutGame] for the trust
/// boundary and the elimination win condition.
library;

export 'src/knockout_board.dart';
export 'src/knockout_game.dart';
export 'src/knockout_sounds.dart';
export 'src/knockout_style.dart';
export 'src/knockout_tile_art.dart';
