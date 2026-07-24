/// Optional sound hooks for [SeaBattleBoard]. Package stays audio-plugin-free.
class SeaBattleSounds {
  /// Shot lands in open water.
  final void Function()? onMiss;

  /// Shot strikes a ship.
  final void Function()? onHit;

  /// The struck ship went down (fires instead of [onHit]).
  final void Function()? onSunk;

  /// Illegal tap (already-resolved cell, bad ship drop).
  final void Function()? onInvalid;

  /// Fleet shuffled or a ship moved/rotated during placement.
  final void Function()? onPlace;

  final void Function()? onWin;

  const SeaBattleSounds({
    this.onMiss,
    this.onHit,
    this.onSunk,
    this.onInvalid,
    this.onPlace,
    this.onWin,
  });

  static const silent = SeaBattleSounds();
}
