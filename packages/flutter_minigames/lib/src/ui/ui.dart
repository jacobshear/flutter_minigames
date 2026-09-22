/// Shared table chrome for flutter_minigames.
///
/// Every game had grown its own private `_Pill` — twelve near-identical black
/// boxes, and twelve copies of the same `AnimatedSwitcher` duplicate-key crash.
/// This package owns that surface once.
library;

export 'game_notice.dart';
export 'game_pill.dart';
export 'classic_game_tile_art.dart';
export 'replay_time_dilation.dart';
export 'round_replay_controller.dart';
export 'tile_art_clock.dart';
