/// Optional sound hooks for [CheckersBoard]. Package stays audio-plugin-free.
class CheckersSounds {
  final void Function()? onSelect;
  final void Function()? onMove;
  final void Function()? onCapture;
  final void Function()? onKing;
  final void Function()? onWin;
  final void Function()? onDraw;

  const CheckersSounds({
    this.onSelect,
    this.onMove,
    this.onCapture,
    this.onKing,
    this.onWin,
    this.onDraw,
  });

  static const silent = CheckersSounds();
}
