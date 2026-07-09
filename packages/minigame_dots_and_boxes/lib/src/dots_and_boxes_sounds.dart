/// Optional sound hooks for [DotsAndBoxesBoard].
/// Package stays free of audio plugins — hosts inject callbacks.
class DotsAndBoxesSounds {
  /// An edge was claimed.
  final void Function()? onClaim;

  /// One or more boxes completed ([count] boxes in this move).
  final void Function(int count)? onBox;

  /// Mover kept their turn after scoring.
  final void Function()? onExtraTurn;

  final void Function()? onWin;
  final void Function()? onDraw;

  const DotsAndBoxesSounds({
    this.onClaim,
    this.onBox,
    this.onExtraTurn,
    this.onWin,
    this.onDraw,
  });

  static const silent = DotsAndBoxesSounds();
}
