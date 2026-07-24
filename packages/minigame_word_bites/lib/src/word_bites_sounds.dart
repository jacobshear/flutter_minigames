/// Optional sound hooks for [WordBitesBoard]. Package stays audio-plugin-free.
///
/// Cues fire off gesture events and animation controllers (never
/// `Future.delayed`): pickup on pan start, settle when the snap animation
/// lands, word-scored when the flash starts, invalid when a drop bounces.
class WordBitesSounds {
  final void Function()? onPickup;
  final void Function()? onSettle;
  final void Function()? onWordScored;
  final void Function()? onInvalid;

  const WordBitesSounds({
    this.onPickup,
    this.onSettle,
    this.onWordScored,
    this.onInvalid,
  });

  static const silent = WordBitesSounds();
}
