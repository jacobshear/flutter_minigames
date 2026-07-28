/// Anagrams for flutter_minigames: GamePigeon-style timed word-finding over
/// shared letters — a pure round-submission [TurnGame] plus the round board,
/// results view, and launcher tile art.
library;

// Re-exported so hosts that only depend on this package (e.g. the example
// app's play screen) can load/share the dictionary without adding a direct
// minigames_words dependency.
export 'package:flutter_minigames/src/words/words.dart' show WordDictionary;

export 'anagrams_board.dart';
export 'anagrams_game.dart';
export 'anagrams_results.dart';
export 'anagrams_sounds.dart';
export 'anagrams_style.dart';
export 'anagrams_tile_art.dart';
