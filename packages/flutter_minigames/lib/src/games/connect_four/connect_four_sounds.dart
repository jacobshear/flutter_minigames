/// Optional sound hooks for [ConnectFourBoard].
///
/// Package stays free of audio plugins — hosts inject callbacks.
///
/// [onDrop] receives the drop height in rows (1 = adjacent slot, 6 = full
/// column) so hosts can pick a short vs long impact sound.
class ConnectFourSounds {
  /// Disc lands. [dropRows] is how far it fell (1..6).
  final void Function(int dropRows)? onDrop;

  /// A player wins (after the landing disc has settled).
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
