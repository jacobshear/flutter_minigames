/// Optional sound hooks for the Anagrams round UI. Package stays
/// audio-plugin-free — the host app wires real players (see DemoSfx).
class AnagramsSounds {
  /// Letter tile tapped (staged or returned).
  final void Function()? onTap;

  /// Valid word accepted.
  final void Function()? onValid;

  /// Invalid or duplicate word rejected.
  final void Function()? onInvalid;

  /// Round timer hit zero.
  final void Function()? onRoundEnd;

  final void Function()? onWin;
  final void Function()? onDraw;

  const AnagramsSounds({
    this.onTap,
    this.onValid,
    this.onInvalid,
    this.onRoundEnd,
    this.onWin,
    this.onDraw,
  });

  static const silent = AnagramsSounds();
}
