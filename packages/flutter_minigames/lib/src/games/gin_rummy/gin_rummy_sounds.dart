/// Sound hooks for the Gin Rummy table.
///
/// The game package owns no audio: it calls these nullable callbacks from real
/// events (a state change, an animation completing) and the host app maps them
/// onto whatever mixer it has. Never fire a cue from a `Future.delayed` — if
/// there is no event to hang it on, there is no cue.
class GinRummySounds {
  /// The hand has finished dealing in.
  final void Function()? onDeal;

  /// A card was drawn from the stock.
  final void Function()? onDrawStock;

  /// A card was taken off the discard pile (including the opening upcard).
  final void Function()? onTakeDiscard;

  /// The opening upcard was refused.
  final void Function()? onPassUpcard;

  /// A card landed on the discard pile.
  final void Function()? onDiscard;

  /// Someone knocked.
  final void Function()? onKnock;

  /// Someone went gin.
  final void Function()? onGin;

  /// A card was laid off onto the knocker's meld.
  final void Function()? onLayOff;

  /// An illegal tap (unknockable hand, wrong pile, blocked discard).
  final void Function()? onInvalid;

  /// The match was won.
  final void Function()? onWin;

  /// The hand was cancelled (stock exhausted) or the match tied.
  final void Function()? onDraw;

  const GinRummySounds({
    this.onDeal,
    this.onDrawStock,
    this.onTakeDiscard,
    this.onPassUpcard,
    this.onDiscard,
    this.onKnock,
    this.onGin,
    this.onLayOff,
    this.onInvalid,
    this.onWin,
    this.onDraw,
  });

  /// No audio at all — the default, and what tests use.
  static const GinRummySounds silent = GinRummySounds();
}
