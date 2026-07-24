/// Shared word dictionary for flutter_minigames word games.
///
/// Bundles the public-domain ENABLE word list (~173k words) and exposes a
/// [WordDictionary] with O(log n) `contains` / `hasPrefix` lookups plus
/// seeded word picking for round generation. Load it once per app:
///
/// ```dart
/// final dict = await WordDictionary.load();
/// dict.contains('quixotic'); // true
/// ```
library;

export 'src/word_dictionary.dart';
