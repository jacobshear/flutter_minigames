import 'package:flutter/widgets.dart';

/// What the embedding app already shows around a board, so the board can
/// leave it out.
///
/// A host that draws its own match chrome — whose turn it is, the result,
/// its own rematch control — wraps the board in
/// `GameHostChrome(hostOwnsStatus: true, child: board)`. Boards then drop the
/// status they would otherwise paint themselves, so the screen never says
/// "Sam's turn" in two places or tells the player to "Tap New game" when the
/// host's button is called something else.
///
/// Without a [GameHostChrome] ancestor every board behaves exactly as before:
/// the example app and any host that shows no chrome keep the on-board status.
class GameHostChrome extends InheritedWidget {
  /// The host shows the turn and the result. Boards drop:
  /// * standing turn pills and "{name}'s turn / slide / to ask" lines;
  /// * result pills and banners ("{name} WINS", "DRAW", "Match over");
  /// * "Waiting for…" lines;
  /// * the end-of-match "Tap New game to play again" hints.
  ///
  /// Events anchored to the board stay (HIT / MISS / SUNK, CHECK, "Choose a
  /// suit", aiming and rule hints, score counters): the host can't draw those
  /// in the right place.
  final bool hostOwnsStatus;

  const GameHostChrome({
    super.key,
    this.hostOwnsStatus = false,
    required super.child,
  });

  /// Whether the nearest [GameHostChrome] owns turn and result status.
  /// False when there is none.
  static bool hostOwnsStatusOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GameHostChrome>()
          ?.hostOwnsStatus ??
      false;

  @override
  bool updateShouldNotify(GameHostChrome oldWidget) =>
      oldWidget.hostOwnsStatus != hostOwnsStatus;
}
