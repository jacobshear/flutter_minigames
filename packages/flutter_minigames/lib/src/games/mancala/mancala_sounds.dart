/// Optional sound hooks for [MancalaBoard]. Package stays audio-plugin-free.
class MancalaSounds {
  /// Hand picked up (sow started).
  final void Function()? onSow;

  /// One stone landed in a cup (fires per deposit during the sow).
  final void Function()? onDrop;

  final void Function()? onCapture;
  final void Function()? onExtraTurn;

  /// Tapped an empty own pit or an opponent pit on your turn.
  final void Function()? onInvalid;

  final void Function()? onWin;
  final void Function()? onDraw;

  const MancalaSounds({
    this.onSow,
    this.onDrop,
    this.onCapture,
    this.onExtraTurn,
    this.onInvalid,
    this.onWin,
    this.onDraw,
  });

  static const silent = MancalaSounds();
}
