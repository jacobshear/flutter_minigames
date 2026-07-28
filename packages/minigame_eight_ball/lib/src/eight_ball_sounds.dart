/// Optional sound hooks for the 8-ball board. The package stays audio-plugin-
/// free — the host app wires these to its own SFX bank.
///
/// All hooks fire from real simulation/settle events (a break, a Forge2D
/// contact, a pocket capture, the settle callback), never from a timer, so
/// audio tracks the physics exactly.
class EightBallSounds {
  /// The cue was struck (break / shot launched).
  final void Function()? onBreak;

  /// Two balls collided mid-shot (cue↔ball or ball↔ball).
  final void Function()? onCollision;

  /// A ball banked off a cushion.
  ///
  /// Falls back to [onCollision] when not supplied, so an existing host keeps
  /// hearing rails without rewiring. The hooks are deliberately argument-free
  /// (the package ships no audio dependency and cannot set a per-shot volume),
  /// so the *weight* of a bounce is carried by the board instead: a nudge is
  /// silent, and the haptic and the cloth compression both scale with the
  /// impact speed.
  final void Function()? onRail;

  /// A ball dropped into a pocket.
  final void Function()? onPocket;

  /// The stroke fouled (scratch or wrong first contact).
  final void Function()? onFoul;

  /// The match was won.
  final void Function()? onWin;

  /// The match was lost (early 8 / scratch on the 8) — a somber cue.
  final void Function()? onLoss;

  const EightBallSounds({
    this.onBreak,
    this.onCollision,
    this.onRail,
    this.onPocket,
    this.onFoul,
    this.onWin,
    this.onLoss,
  });

  static const silent = EightBallSounds();
}
