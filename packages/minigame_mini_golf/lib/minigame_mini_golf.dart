/// Mini Golf for flutter_minigames.
///
/// A perspective-3-D putting game on the [minigames_3d] seam: the shooter
/// simulates a putt locally ([MiniGolfPutt]) and serializes the settled outcome;
/// [MiniGolfGame] is a pure [TurnGame] reducer over that outcome. Both players
/// play the same seeded course ([MiniGolfCourse.forHole]), whose holes are dealt
/// from a permutation of eight distinct [MiniGolfArchetype]s so no two
/// neighbours share a shape. Fewest total strokes wins.
library;

export 'src/mini_golf_board.dart' show MiniGolfBoard, MiniGolfScenePainter;
export 'src/mini_golf_camera.dart' show MiniGolfCamera, MiniGolfCameraPhase;
export 'src/mini_golf_course.dart'
    show
        MiniGolfArchetype,
        MiniGolfArchetypeLabel,
        MiniGolfCourse,
        MiniGolfObstacle;
export 'src/mini_golf_game.dart' show MiniGolfGame, MiniGolfState, MiniGolfMove;
export 'src/mini_golf_render.dart' show paintMiniGolfScene;
export 'src/mini_golf_sim.dart'
    show MiniGolfPutt, PuttEvent, PuttEventKind, PuttResult, PuttSample;
export 'src/mini_golf_sounds.dart' show MiniGolfSounds;
export 'src/mini_golf_style.dart' show MiniGolfStyle;
export 'src/mini_golf_tile_art.dart' show MiniGolfTileArt;
export 'src/mini_golf_view.dart'
    show MiniGolfAimView, MiniGolfBallView, MiniGolfImpactView, MiniGolfView;
export 'src/mini_golf_world.dart' show BallRoll, MiniGolfWorld;
