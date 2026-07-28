/// Optional sound hooks for [GomokuBoard]. Package stays audio-plugin-free.
class GomokuSounds {
  final void Function()? onPlace;
  final void Function()? onInvalid;
  final void Function()? onWin;
  final void Function()? onDraw;

  const GomokuSounds({
    this.onPlace,
    this.onInvalid,
    this.onWin,
    this.onDraw,
  });

  static const silent = GomokuSounds();
}
