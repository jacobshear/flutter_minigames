/// Optional sound hooks for [ConnectFourBoard].
///
/// Package stays free of audio plugins — hosts inject callbacks.
class ConnectFourSounds {
  /// Disc lands in a cell after a drop.
  final void Function()? onDrop;

  /// A player wins.
  final void Function()? onWin;

  /// Board is full with no winner.
  final void Function()? onDraw;

  /// Player tried a full column (or otherwise invalid column).
  final void Function()? onInvalid;

  const ConnectFourSounds({
    this.onDrop,
    this.onWin,
    this.onDraw,
    this.onInvalid,
  });

  static const silent = ConnectFourSounds();
}
