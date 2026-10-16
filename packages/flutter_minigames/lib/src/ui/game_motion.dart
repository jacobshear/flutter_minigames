import 'package:flutter/widgets.dart';

/// The library's one Reduce Motion check.
///
/// Reads `MediaQuery.disableAnimations`. Flutter's iOS embedder never sets
/// that flag from the iOS Reduce Motion switch (it only fills
/// `accessibilityFeatures.reduceMotion`), so an iOS host has to bridge one
/// into the other above the boards — see the README. Every looping or
/// decorative animation (confetti, notice overshoot and shake, idle pulses)
/// checks this; motion that carries game state (a piece sliding to its
/// square, a card flying to the pile) keeps playing, because the move is the
/// information.
abstract final class GameMotion {
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
