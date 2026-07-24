/// Optional sound hooks for [FillerBoard]. Package stays audio-plugin-free.
class FillerSounds {
  /// A color swatch was tapped (a legal pick).
  final void Function()? onPick;

  /// One capture wavefront ring landed (fires per ring, animation-driven).
  final void Function()? onCapture;

  final void Function()? onInvalid;
  final void Function()? onWin;
  final void Function()? onDraw;

  const FillerSounds({
    this.onPick,
    this.onCapture,
    this.onInvalid,
    this.onWin,
    this.onDraw,
  });

  static const silent = FillerSounds();
}
