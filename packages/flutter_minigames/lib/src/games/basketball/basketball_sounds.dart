/// Optional sound hooks for the basketball round. The package stays
/// audio-plugin-free — the host app wires these to its own SFX bank.
///
/// The set mirrors the shipped game: a ball bouncing, a rattle off the iron,
/// the net swish of a make, the end-of-round buzzer and the whistle that starts
/// a round. Every hook fires from a real simulation contact or the round
/// clock — never from `Future.delayed` — so audio tracks the physics instead of
/// drifting away from it.
///
/// [onBounce] and [onRim] receive the impact speed so the host can vary
/// pitch/gain with it; the board also rate-limits them, because a floor full of
/// loose balls will otherwise machine-gun the same sample.
class BasketballSounds {
  /// A ball hit the floor. Argument is impact speed, world units/s.
  final void Function(double speed)? onBounce;

  /// A ball rattled the iron or slapped the backboard. Argument is speed.
  final void Function(double speed)? onRim;

  /// A ball dropped through the net.
  final void Function()? onSwish;

  /// A round started.
  final void Function()? onWhistle;

  /// A round's clock ran out.
  final void Function()? onBuzzer;

  /// The match was won.
  final void Function()? onWin;

  /// The match ended in a draw.
  final void Function()? onDraw;

  const BasketballSounds({
    this.onBounce,
    this.onRim,
    this.onSwish,
    this.onWhistle,
    this.onBuzzer,
    this.onWin,
    this.onDraw,
  });

  static const silent = BasketballSounds();
}
