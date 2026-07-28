/// Optional sound hooks for [ChessBoard]. Package stays audio-plugin-free.
class ChessSounds {
  final void Function()? onMove;
  final void Function()? onCapture;
  final void Function()? onCheck;
  final void Function()? onInvalid;
  final void Function()? onWin;
  final void Function()? onDraw;

  const ChessSounds({
    this.onMove,
    this.onCapture,
    this.onCheck,
    this.onInvalid,
    this.onWin,
    this.onDraw,
  });

  static const silent = ChessSounds();
}
