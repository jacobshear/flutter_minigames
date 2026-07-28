/// Optional sound hooks for the shuffleboard board. The package stays
/// audio-plugin-free — the host app wires these to its own SFX bank.
///
/// All hooks fire from real simulation/settle events (a launch, a Forge2D
/// contact, the settle callback), never from a timer, so audio tracks the
/// physics exactly.
class ShuffleboardSounds {
  /// A slide is launched.
  final void Function()? onLaunch;

  /// Two pucks collided mid-slide.
  final void Function()? onCollision;

  /// The settled slide left at least one puck in a scoring band.
  final void Function()? onScore;

  /// The slide fouled (short of the line) or ran off the end.
  final void Function()? onFoul;

  /// The match was won.
  final void Function()? onWin;

  /// The match ended in a draw.
  final void Function()? onDraw;

  const ShuffleboardSounds({
    this.onLaunch,
    this.onCollision,
    this.onScore,
    this.onFoul,
    this.onWin,
    this.onDraw,
  });

  static const silent = ShuffleboardSounds();
}
