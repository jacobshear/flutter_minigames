/// Optional sound hooks for [CrazyEightsTable]. Package stays
/// audio-plugin-free — hosts map these onto their own SFX bank.
class CrazyEightsSounds {
  /// Deal fan-out finished.
  final void Function()? onDeal;

  /// Card landed on the discard pile.
  final void Function()? onPlay;

  /// Card slid off the stock into a hand.
  final void Function()? onDraw;

  /// Forced pass (stock empty, no playable card).
  final void Function()? onPass;

  /// Illegal tap (unplayable card / empty stock).
  final void Function()? onInvalid;

  final void Function()? onWin;

  /// Pip-count tie ended the game with no winner.
  final void Function()? onGameDraw;

  const CrazyEightsSounds({
    this.onDeal,
    this.onPlay,
    this.onDraw,
    this.onPass,
    this.onInvalid,
    this.onWin,
    this.onGameDraw,
  });

  static const silent = CrazyEightsSounds();
}
