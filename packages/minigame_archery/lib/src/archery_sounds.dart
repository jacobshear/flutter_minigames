/// Optional sound hooks for the archery range. The package stays
/// audio-plugin-free — the host app wires these to its own SFX bank.
///
/// Every hook fires from a real event: the draw controller starting, the focus
/// timer crossing its warning threshold, the release, and the simulated impact
/// landing. None of them is scheduled off a `Future.delayed`, so audio always
/// tracks what the arrow actually did.
class ArcherySounds {
  /// The bow started being drawn (a creak of limb tension).
  final void Function()? onBowDraw;

  /// Focus is about to break — the cue to release now.
  final void Function()? onFocusWarn;

  /// The string was loosed.
  final void Function()? onLoose;

  /// The arrow struck the face (any scoring ring).
  final void Function()? onHit;

  /// The arrow struck the gold.
  final void Function()? onBullseye;

  /// The arrow missed the face entirely.
  final void Function()? onMiss;

  /// The shooter moved on to the next target.
  final void Function()? onNextTarget;

  /// The match was won.
  final void Function()? onWin;

  /// The match ended level.
  final void Function()? onTie;

  const ArcherySounds({
    this.onBowDraw,
    this.onFocusWarn,
    this.onLoose,
    this.onHit,
    this.onBullseye,
    this.onMiss,
    this.onNextTarget,
    this.onWin,
    this.onTie,
  });

  static const silent = ArcherySounds();
}
