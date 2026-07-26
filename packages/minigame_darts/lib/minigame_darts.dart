/// Darts (501) for flutter_minigames — a first-person 3-D throw at a
/// regulation board, built on the `minigames_3d` harness.
///
/// Three layers, strictly separated:
///
/// * **Rules** — [DartsGame] is a pure `TurnGame` over [DartsState] and
///   [DartsMove]. It imports `minigames_core` only: no physics, no rendering.
///   [DartsBoardGeometry] turns a point on the board face into a sector and a
///   multiplier, and is the single scoring authority for both the simulation
///   and the art.
/// * **Simulation** — [DartsFlight] runs one throw headlessly on the harness
///   integrator; [DartsAim] maps a flick onto a solved speed band so the game
///   is actually playable (see its doc).
/// * **Rendering** — [paintDartsScene] is a pure function of a [DartsView], so
///   the whole scene is snapshot-testable. [DartsBoardWidget] is the only
///   stateful piece.
library;

export 'src/darts_board.dart';
export 'src/darts_board_geometry.dart';
export 'src/darts_game.dart';
export 'src/darts_scene.dart';
export 'src/darts_sounds.dart';
export 'src/darts_style.dart';
export 'src/darts_throw.dart';
export 'src/darts_tile_art.dart';
