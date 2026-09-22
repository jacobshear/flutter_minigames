import 'package:flutter/scheduler.dart';

/// Fast-forwards every animation on screen while a replay runs.
///
/// Boards animate a replayed turn with their own `AnimationController`s and
/// tickers, which know nothing about `MatchController.replaySpeed`. Scaling
/// the scheduler's [timeDilation] reaches all of them at once — piece
/// slides, flights, confetti — with no per-board plumbing. Physics boards
/// that step a simulation by a FIXED dt per tick (rather than by elapsed
/// time) must read [stepsPerTick] and step that many times, or their shot
/// will not speed up.
///
/// Global by nature, so every replay host must call [reset] when the replay
/// ends and when it is disposed; [apply] with 1 is equivalent.
abstract final class ReplayTimeDilation {
  /// The factor currently applied (1 = real time).
  static double get speed => 1 / timeDilation;

  /// How many fixed simulation steps a physics board should run per tick to
  /// keep pace with the current speed. Always at least 1.
  static int get stepsPerTick {
    final s = speed;
    return s <= 1 ? 1 : s.round();
  }

  /// Run animations [speed] times faster (clamped to 1–8).
  static void apply(double speed) {
    final clamped = speed.clamp(1.0, 8.0).toDouble();
    final dilation = 1 / clamped;
    if (timeDilation != dilation) timeDilation = dilation;
  }

  /// Back to real time.
  static void reset() {
    if (timeDilation != 1.0) timeDilation = 1.0;
  }
}
