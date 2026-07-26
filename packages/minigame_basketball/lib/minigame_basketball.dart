/// Basketball for flutter_minigames — a first-person 3-D shootaround.
///
/// You stand at the line and shoot **into** the screen: the ball arcs away from
/// you, shrinking as it goes, and drops through the rim. Built on
/// `minigames_3d` (3-axis ballistics, a pinhole camera, swept analytic
/// collision, depth-sorted painting) and drawn with a plain `CustomPaint`, so
/// the whole scene is a pure function of a [BasketballView] and every frame is
/// snapshot-testable.
///
/// The rules live in [BasketballGame], a pure round-submission [TurnGame] that
/// imports nothing but `minigames_core`: two 45-second rounds per player at a
/// fixed range, one point per basket, higher total wins. The board runs the
/// simulation locally and submits the per-round scores; the reducer records
/// them defensively.
library;

// The public view/sim API speaks in world vectors, so consumers need the type
// without having to depend on minigames_3d themselves.
export 'package:minigames_3d/minigames_3d.dart' show Vec3;
export 'src/basketball_court.dart'
    show BasketballAim, BasketballCourt, BasketballHoopMode;
export 'src/basketball_game.dart';
export 'src/basketball_results.dart';
export 'src/basketball_round_board.dart';
export 'src/basketball_scoreboard.dart';
export 'src/basketball_sim.dart';
export 'src/basketball_sounds.dart';
export 'src/basketball_style.dart';
export 'src/basketball_tile_art.dart';
export 'src/basketball_view.dart';
