/// Optional sound hooks for the Cup Pong board. The package stays
/// audio-plugin-free — the host app wires these to its own SFX bank.
///
/// Every hook fires from a real simulation event (the launch, a swept surface
/// contact, the make test, the reducer's balls-back / re-rack result), never
/// from a `Future.delayed` — so audio tracks the physics exactly instead of
/// drifting away from it on a slow frame.
class CupPongSounds {
  /// The ball left the hand.
  final void Function()? onThrow;

  /// The ball bounced off the table, a rim, or the outside of a cup.
  final void Function()? onBounce;

  /// The ball dropped into a cup.
  final void Function()? onHit;

  /// The throw resolved without scoring.
  final void Function()? onMiss;

  /// Both balls went in — the thrower keeps them.
  final void Function()? onBallsBack;

  /// The defender's rack reformed (at 6 cups, then at 3).
  final void Function()? onRerack;

  /// The match was won.
  final void Function()? onWin;

  /// The match ended in a draw.
  final void Function()? onDraw;

  const CupPongSounds({
    this.onThrow,
    this.onBounce,
    this.onHit,
    this.onMiss,
    this.onBallsBack,
    this.onRerack,
    this.onWin,
    this.onDraw,
  });

  static const silent = CupPongSounds();
}
