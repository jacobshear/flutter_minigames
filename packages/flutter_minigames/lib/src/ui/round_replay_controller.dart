import 'package:flutter/foundation.dart';

/// Drives one playback of an opponent's round (anagrams, word hunt, word
/// bites, basketball).
///
/// Round games are simultaneous-solo: each player plays the same board on
/// their own clock, so there is no turn to rewind — a replay is a compressed
/// reconstruction of what the other player did, built from their submission.
/// The replay widgets own the timeline; this object is the host's handle on
/// it:
///  * speed — NOT held here. Fast-forward uses `ReplayTimeDilation`, the
///    same global scale turn-game replays use, so a replay widget animates
///    with ordinary controllers and needs no speed plumbing of its own.
///  * [skip] — jump to the end: the widget shows the final state at once
///    and reports [finished].
///  * [finished] — true once the timeline has played out or been skipped;
///    the host swaps to the results view then.
class RoundReplayController extends ChangeNotifier {
  bool _finished = false;
  bool _skipRequested = false;

  /// True once playback has ended (played out or skipped).
  bool get finished => _finished;

  /// True after [skip]; replay widgets read it on every notify and jump to
  /// their final frame.
  bool get skipRequested => _skipRequested;

  /// Jump to the end of the replay.
  void skip() {
    if (_finished || _skipRequested) return;
    _skipRequested = true;
    notifyListeners();
  }

  /// Called by the replay widget when its timeline completes (or it has
  /// applied a [skip]). Idempotent.
  void markFinished() {
    if (_finished) return;
    _finished = true;
    notifyListeners();
  }
}
