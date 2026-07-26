/// Optional sound hooks for the knockout board. The package stays
/// audio-plugin-free — the host app wires these to its own SFX bank.
///
/// All hooks fire from real simulation/settle events (a launch, a Forge2D
/// contact, the settle callback), never from a timer, so audio tracks the
/// physics exactly.
class KnockoutSounds {
  /// A puck is flicked.
  final void Function()? onLaunch;

  /// Two pucks collided mid-flick.
  final void Function()? onCollision;

  /// The settled flick knocked at least one opponent puck off the platform.
  final void Function()? onKnockOff;

  /// The settled flick sent one of the mover's own pucks off (an own goal).
  final void Function()? onOwnLoss;

  /// The match was won.
  final void Function()? onWin;

  /// The match ended in a draw (both sides cleared on the same flick).
  final void Function()? onDraw;

  const KnockoutSounds({
    this.onLaunch,
    this.onCollision,
    this.onKnockOff,
    this.onOwnLoss,
    this.onWin,
    this.onDraw,
  });

  static const silent = KnockoutSounds();
}
