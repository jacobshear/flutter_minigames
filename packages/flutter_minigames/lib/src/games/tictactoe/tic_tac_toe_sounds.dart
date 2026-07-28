/// Optional sound hooks for [TicTacToeBoard].
///
/// The package intentionally does **not** depend on any audio plugin — hosts
/// inject callbacks (SystemSound, `audioplayers`, a custom mixer, silence).
/// Motion and haptics stay package-owned; audio is the host's brand decision.
class TicTacToeSounds {
  /// Fired when a mark is placed (after a successful move lands in state).
  final void Function()? onPlace;

  /// Fired when a player wins (once, at the transition into the win outcome).
  final void Function()? onWin;

  /// Fired when the game ends in a draw.
  final void Function()? onDraw;

  const TicTacToeSounds({
    this.onPlace,
    this.onWin,
    this.onDraw,
  });

  /// No-op sounds — the default.
  static const silent = TicTacToeSounds();
}
