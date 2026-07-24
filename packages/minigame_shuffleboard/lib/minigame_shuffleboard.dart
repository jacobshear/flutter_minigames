/// Shuffleboard for flutter_minigames — the first physics game.
///
/// Pure [ShuffleboardGame] rules (no physics) plus a Flame/Forge2D board that
/// simulates the slide locally and serializes the settled positions as the
/// move. See [ShuffleboardGame] for the trust boundary.
library;

export 'src/shuffleboard_board.dart';
export 'src/shuffleboard_game.dart';
export 'src/shuffleboard_sounds.dart';
export 'src/shuffleboard_style.dart';
export 'src/shuffleboard_tile_art.dart';
