/// The terminal result of a game: a win for one player, or a draw.
///
/// A `null` [GameOutcome] anywhere in the API means "the game is still going".
class GameOutcome {
  /// The winning player id. Non-null iff [isDraw] is false.
  final String? winnerId;

  /// Whether the game ended in a draw (no winner).
  final bool isDraw;

  /// A win for [winnerId].
  const GameOutcome.win(String this.winnerId) : isDraw = false;

  /// A draw — nobody won.
  const GameOutcome.draw()
      : winnerId = null,
        isDraw = true;

  /// True when a single player won.
  bool get isWin => !isDraw;

  @override
  bool operator ==(Object other) =>
      other is GameOutcome &&
      other.winnerId == winnerId &&
      other.isDraw == isDraw;

  @override
  int get hashCode => Object.hash(winnerId, isDraw);

  @override
  String toString() =>
      isDraw ? 'GameOutcome.draw()' : 'GameOutcome.win($winnerId)';
}
