/// Gin Rummy: a pure [GinRummyGame] reducer plus its card table.
///
/// The rules — and the handful of deliberate simplifications — are documented
/// at the top of `src/gin_rummy_game.dart`. The meld solver, which is the part
/// worth reusing, lives in [GinRummyMelds] and finds the true minimum-deadwood
/// partition rather than a greedy one.
///
/// Deliberately does **not** re-export `minigames_cards`: import that directly
/// where you need [PlayingCard] or [CardView], so no consumer ends up with two
/// unrelated packages fighting over the same names.
library;

export 'src/gin_rummy_game.dart';
export 'src/gin_rummy_meld.dart';
export 'src/gin_rummy_sounds.dart';
export 'src/gin_rummy_style.dart';
export 'src/gin_rummy_table.dart';
export 'src/gin_rummy_tile_art.dart';
