import 'match.dart';

/// The network seam. This is the single most important interface in the
/// library: games talk only to a [GameTransport], never to a concrete backend.
///
/// The library ships [LocalTransport] (in-memory, for hot-seat and tests).
/// An app supplies its own implementation — `flutter_minigames_firebase`, for
/// instance, backs one with Realtime Database. The core never imports any
/// networking package, which is what keeps every game reusable.
abstract class GameTransport {
  /// Persist a brand-new match and make it visible to [watchMatch].
  Future<void> createMatch(Match match);

  /// Persist [updatedMatch] (a new turn) and broadcast it to watchers.
  ///
  /// Implementations backed by a shared store should apply this as an
  /// optimistic-concurrency write (reject if `currentPlayerId`/`turnCount`
  /// moved underneath us) to guard against double-submits.
  Future<void> submitTurn(Match updatedMatch);

  /// A stream that fires whenever the match changes — i.e. when the opponent
  /// takes their turn.
  Stream<Match> watchMatch(String matchId);

  /// Fetch the current match snapshot, or `null` if it doesn't exist. Used to
  /// resume a half-finished game.
  Future<Match?> loadMatch(String matchId);
}
