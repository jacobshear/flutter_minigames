/// Archery for flutter_minigames — a first-person 3-D bow game.
///
/// Wii Sports Resort's format: four targets, three arrows at each, with the
/// distance growing and the wind strengthening every time. Pure [ArcheryGame]
/// rules (no physics) plus an [ArcheryRange] that simulates the arrow on the
/// `minigames_3d` harness and serializes the *outcome* of each shot as the move.
library;

export 'src/archery_game.dart';
export 'src/archery_range.dart';
export 'src/archery_shot.dart';
export 'src/archery_sounds.dart';
export 'src/archery_style.dart';
export 'src/archery_tile_art.dart';
export 'src/archery_view.dart';
