/// Optional sound hooks for [ReversiBoard]. Package stays audio-plugin-free.
class ReversiSounds {
  final void Function()? onPlace;
  final void Function(int flipCount)? onFlip;
  final void Function()? onPass;
  final void Function()? onWin;
  final void Function()? onDraw;

  const ReversiSounds({
    this.onPlace,
    this.onFlip,
    this.onPass,
    this.onWin,
    this.onDraw,
  });

  static const silent = ReversiSounds();
}
