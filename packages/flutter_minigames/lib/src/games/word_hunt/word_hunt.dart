/// Word Hunt for flutter_minigames — boggle-style trace-the-grid word search:
/// a pure TurnGame (round-submission model, dictionary-validated) plus a
/// Flutter board with swipe tracing, timed rounds, and a results screen.
library;

// Re-exported so hosts that only depend on this package can load the shared
// dictionary the game needs.
export 'package:flutter_minigames/src/words/words.dart' show WordDictionary;

export 'word_hunt_board.dart';
export 'word_hunt_game.dart';
export 'word_hunt_sounds.dart';
export 'word_hunt_style.dart';
export 'word_hunt_tile_art.dart';
