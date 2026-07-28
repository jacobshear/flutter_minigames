/// Shared table chrome for flutter_minigames.
///
/// Every game had grown its own private `_Pill` — twelve near-identical black
/// boxes, and twelve copies of the same `AnimatedSwitcher` duplicate-key crash.
/// This package owns that surface once.
library;

export 'game_notice.dart';
export 'game_pill.dart';
