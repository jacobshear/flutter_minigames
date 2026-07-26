/// Optional sound hooks for the darts board. The package stays audio-plugin
/// free — the host app wires these to its own SFX bank.
///
/// Every hook fires from a real simulation or rules event (the release of a
/// flick, a swept board-plane crossing, a bust computed by the pure reducer),
/// never from a timer, so audio tracks the physics exactly.
///
/// 501 has no draw, so there is no draw hook.
class DartsSounds {
  /// A dart left the hand.
  final void Function()? onThrow;

  /// A dart stuck in the board (any score, including a single).
  final void Function()? onStick;

  /// A treble, a double or a bull — the hits worth a louder thud.
  final void Function()? onBigScore;

  /// The dart missed the scoring area entirely (surround or floor).
  final void Function()? onMiss;

  /// The visit busted and the score reverted.
  final void Function()? onBust;

  /// Someone checked out.
  final void Function()? onWin;

  const DartsSounds({
    this.onThrow,
    this.onStick,
    this.onBigScore,
    this.onMiss,
    this.onBust,
    this.onWin,
  });

  static const silent = DartsSounds();
}
