/// Transport-agnostic turn engine for async turn-based mini-games.
///
/// The whole framework is three ideas:
///  * [TurnGame] — a pure, serializable game contract every game implements.
///  * [GameTransport] — the network seam. The library ships [LocalTransport]
///    (hot-seat / in-memory); apps supply their own (e.g. a Firebase adapter).
///  * [MatchController] — glues a game to a transport for the UI to drive.
library;

export 'src/game_outcome.dart';
export 'src/local_transport.dart';
export 'src/match.dart';
export 'src/match_controller.dart';
export 'src/transport.dart';
export 'src/turn_game.dart';
