/// Fires once when a simulation has come to rest.
///
/// Reusable across any stepped simulation: feed it one boolean per step —
/// whether every dynamic body is below the velocity thresholds ("calm") — and
/// it reports the single frame on which the sim is considered settled. Settle
/// requires [framesRequired] *consecutive* calm steps so a body that is merely
/// passing through zero velocity (e.g. at the top of a bounce) doesn't trip it.
/// A hard [maxSteps] budget guarantees termination even if the sim never fully
/// stops (grazing contacts, residual jitter).
class SettleDetector {
  /// Consecutive calm steps required before declaring the sim settled.
  final int framesRequired;

  /// Hard cap on total steps; hitting it settles the run as [timedOut].
  final int maxSteps;

  int _calmFrames = 0;
  int _steps = 0;
  bool _done = false;
  bool _timedOut = false;

  SettleDetector({this.framesRequired = 12, this.maxSteps = 1200})
      : assert(framesRequired > 0),
        assert(maxSteps > 0);

  /// Whether the sim has settled (calmly or via timeout).
  bool get isSettled => _done;

  /// Whether the settle was forced by the step budget rather than true rest.
  bool get timedOut => _timedOut;

  /// Steps consumed so far.
  int get steps => _steps;

  /// Advance one step. [calm] is true when every dynamic body is below the
  /// caller's velocity thresholds this step. Returns true on the single step
  /// that transitions the run to settled (fires exactly once per run).
  bool step({required bool calm}) {
    if (_done) return false;
    _steps++;
    _calmFrames = calm ? _calmFrames + 1 : 0;
    if (_calmFrames >= framesRequired) {
      _done = true;
      return true;
    }
    if (_steps >= maxSteps) {
      _done = true;
      _timedOut = true;
      return true;
    }
    return false;
  }

  /// Reset for a fresh run (call before each launch).
  void reset() {
    _calmFrames = 0;
    _steps = 0;
    _done = false;
    _timedOut = false;
  }
}
