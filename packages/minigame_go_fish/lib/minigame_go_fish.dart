/// Go Fish: a pure two-player [GoFishGame] reducer plus its card-table UI.
///
/// The quick one in the card set — luck-heavy by design, and built to be fast
/// and legible rather than deep. The rank groups in your hand *are* the rank
/// picker, so the only decision the game has takes one tap.
///
/// See `go_fish_game.dart` for the exact rule variant implemented (7-card
/// two-handed deal, ask-only-what-you-hold, and Pagat's "fish up the rank you
/// asked for and go again").
library;

export 'src/go_fish_game.dart';
export 'src/go_fish_sounds.dart';
export 'src/go_fish_style.dart';
export 'src/go_fish_table.dart';
export 'src/go_fish_tile_art.dart';
