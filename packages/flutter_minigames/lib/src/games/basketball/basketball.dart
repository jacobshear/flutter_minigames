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
export 'package:flutter_minigames/src/engine3d/engine3d.dart' show Vec3;
export 'basketball_court.dart'
    show BasketballAim, BasketballCourt, BasketballHoopMode;
export 'basketball_game.dart';
export 'basketball_results.dart';
export 'basketball_round_board.dart';
export 'basketball_scoreboard.dart';
export 'basketball_sim.dart';
export 'basketball_sounds.dart';
export 'basketball_style.dart';
export 'basketball_tile_art.dart';
export 'basketball_view.dart';
