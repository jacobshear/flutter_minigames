/// Sound hooks for the Go Fish table.
///
/// The game package owns no audio: it calls these nullable callbacks from real
/// events (a state change, an animation completing) and the host app maps them
/// onto whatever mixer it has. Never fire a cue from a `Future.delayed` — if
/// there is no event to hang it on, there is no cue.
class GoFishSounds {
  /// The opening deal has finished landing.
  final void Function()? onDeal;

  /// An ask was sent.
  final void Function()? onAsk;

  /// The ask hit — cards are coming across the table. The payoff beat; fired
  /// when the transfer animation lands, not when the state arrives.
  final void Function()? onCatch;

  /// "Go fish" — the ask missed and a card came off the pond.
  final void Function()? onGoFish;

  /// The pond was dry, so the go fish drew nothing.
  final void Function()? onDryPond;

  /// A book of four was laid down.
  final void Function()? onBook;

  /// An illegal tap (a rank you do not hold, a tap during the handoff).
  final void Function()? onInvalid;

  /// The match was won.
  final void Function()? onWin;

  /// The match ended level on books.
  final void Function()? onDraw;

  const GoFishSounds({
    this.onDeal,
    this.onAsk,
    this.onCatch,
    this.onGoFish,
    this.onDryPond,
    this.onBook,
    this.onInvalid,
    this.onWin,
    this.onDraw,
  });

  /// No audio at all — the default, and what tests use.
  static const GoFishSounds silent = GoFishSounds();
}
