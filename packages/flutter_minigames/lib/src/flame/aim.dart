import 'package:forge2d/forge2d.dart' show Vector2;

/// Turns a drag/flick vector into a launch impulse with a hard power cap.
///
/// The gesture model is a slingshot: the player drags *back* from the piece and
/// releases, and the piece launches in the *opposite* direction to the drag
/// (set [invert] false for a push-forward model instead). Drag distance maps to
/// power linearly up to [maxDrag]; beyond that the power saturates so a wild
/// flick can never exceed [maxImpulse]. A [deadZone] swallows tiny accidental
/// drags so a fumbled tap doesn't fire a shot.
///
/// [power01] exposes the same 0..1 magnitude the impulse uses, for driving a
/// power meter in the UI without recomputing the mapping.
class AimToImpulse {
  /// Drag length (in the same units as the drag vector) that maps to full
  /// power. Longer drags clamp to full power.
  final double maxDrag;

  /// Impulse magnitude at full power. Also the ceiling — never exceeded.
  final double maxImpulse;

  /// Impulse magnitude at the bottom of the live power range (just past the
  /// dead zone), so even a light flick produces a usable slide.
  final double minImpulse;

  /// Drags shorter than this produce no shot ([impulse] returns zero).
  final double deadZone;

  /// When true (default) the impulse points opposite the drag (slingshot).
  final bool invert;

  const AimToImpulse({
    this.maxDrag = 240,
    this.maxImpulse = 26,
    this.minImpulse = 4,
    this.deadZone = 6,
    this.invert = true,
  })  : assert(maxDrag > 0),
        assert(maxImpulse >= minImpulse);

  /// Normalized 0..1 power for [drag], after dead-zone and cap. Feed a UI meter.
  double power01(Vector2 drag) {
    final len = drag.length;
    if (len <= deadZone) return 0;
    return ((len - deadZone) / (maxDrag - deadZone)).clamp(0.0, 1.0);
  }

  /// The 0..1 power an already-computed [impulse] represents — the inverse of
  /// the magnitude mapping in [impulse]. Lets a banked wind-up redraw its own
  /// power meter without keeping the original drag around.
  double power01Of(Vector2 impulse) {
    final len = impulse.length;
    if (len <= minImpulse) return 0;
    return ((len - minImpulse) / (maxImpulse - minImpulse)).clamp(0.0, 1.0);
  }

  /// The launch impulse for [drag]. Zero (below [deadZone]) means "no shot".
  Vector2 impulse(Vector2 drag) {
    final len = drag.length;
    if (len <= deadZone) return Vector2.zero();
    final p = power01(drag);
    final magnitude = minImpulse + (maxImpulse - minImpulse) * p;
    // Normalize direction off the raw drag, then scale + orient.
    final dir = (drag / len) * (invert ? -1.0 : 1.0);
    return dir * magnitude;
  }
}
