/// Optional sound hooks for [WordHuntBoard]. Package stays audio-plugin-free —
/// the host app wires these to its own SFX bank.
class WordHuntSounds {
  /// A tile joins the current trace (finger picked it up).
  final void Function()? onTilePick;

  /// A valid new word was released.
  final void Function()? onWordFound;

  /// Invalid or already-found word released.
  final void Function()? onInvalid;

  /// A timed round just ended (submission handoff).
  final void Function()? onRoundEnd;

  /// Match over with a winner.
  final void Function()? onWin;

  /// Match over in a tie.
  final void Function()? onDraw;

  const WordHuntSounds({
    this.onTilePick,
    this.onWordFound,
    this.onInvalid,
    this.onRoundEnd,
    this.onWin,
    this.onDraw,
  });

  static const silent = WordHuntSounds();
}
