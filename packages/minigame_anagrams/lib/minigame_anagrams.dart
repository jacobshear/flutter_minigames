/// Anagrams for flutter_minigames: GamePigeon-style timed word-finding over
/// shared letters — a pure round-submission [TurnGame] plus the round board,
/// results view, and launcher tile art.
library;

// Re-exported so hosts that only depend on this package (e.g. the example
// app's play screen) can load/share the dictionary without adding a direct
// minigames_words dependency.
export 'package:minigames_words/minigames_words.dart' show WordDictionary;

export 'src/anagrams_board.dart';
export 'src/anagrams_game.dart';
export 'src/anagrams_results.dart';
export 'src/anagrams_sounds.dart';
export 'src/anagrams_style.dart';
export 'src/anagrams_tile_art.dart';
