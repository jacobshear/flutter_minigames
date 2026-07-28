/// Optional sound hooks for the mini-golf board. The package stays
/// audio-plugin-free — the host app wires these to its own SFX bank.
///
/// All hooks fire from real simulation events — every one is a [PuttEvent] the
/// putt simulator recorded at a specific step, replayed on the sample it
/// happened on. Never from a timer, so audio tracks the physics exactly.
class MiniGolfSounds {
  /// A putt is struck.
  final void Function()? onPutt;

  /// The ball banked off a rail, struck a solid, or lipped out of the cup.
  final void Function()? onWallHit;

  /// The ball dropped in the cup.
  final void Function()? onSink;

  /// The putt settled without holing out (ordinary rest or out-of-bounds).
  final void Function()? onRest;

  /// The match was won.
  final void Function()? onWin;

  /// The match ended in a draw.
  final void Function()? onDraw;

  const MiniGolfSounds({
    this.onPutt,
    this.onWallHit,
    this.onSink,
    this.onRest,
    this.onWin,
    this.onDraw,
  });

  static const silent = MiniGolfSounds();
}
