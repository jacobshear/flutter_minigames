/// Cup Pong for flutter_minigames — **first-person** perspective 3-D.
///
/// You look down the table at the opponent's rack and throw the ball *into the
/// screen*: it arcs away from you, shrinking, with its shadow tracking it across
/// the table, and drops into a cup. Built on `minigames_3d` (3-axis ballistics,
/// a pinhole camera, swept analytic surfaces, painter's-algorithm depth
/// sorting), not on a 2-D engine — a side view has no depth axis and
/// structurally cannot be this game.
///
/// * [CupPongGame] — the rules, pure and physics-free: 10 cups, two balls a
///   turn, balls back on a two-for-two, re-racks at 6 and 3.
/// * [CupPongThrowSim] / [CupPongAim] — the ballistics, and the solver that
///   makes a flick land where the player meant it to.
/// * [paintCupPongTable] — the whole scene as a pure function of a
///   [CupPongView], so it renders and can be inspected headlessly.
/// * [CupPongBoard] — the `CustomPaint` board that owns the sim and submits the
///   throw outcome as a move.
library;

export 'cup_pong_board.dart';
export 'cup_pong_game.dart';
export 'cup_pong_painter.dart';
export 'cup_pong_sim.dart';
export 'cup_pong_sounds.dart';
export 'cup_pong_style.dart';
export 'cup_pong_tile_art.dart';
export 'cup_pong_world.dart';
