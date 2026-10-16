import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/shuffleboard/shuffleboard.dart';

/// The pull a player has to make, on a lane the size a phone actually draws.
///
/// Full power used to be a fixed 200pt pull back from a puck that rests at
/// 93% of the lane: on a 6.1" phone that barely fit below the puck, on an SE
/// it did not, and overshooting the far end (≳190pt) was out of reach.
void main() {
  /// Pull straight back [pull] points on a [lane]-sized scene and let the
  /// slide settle. Returns the launched puck's status.
  PuckStatus shoot(Vector2 lane, double pull) {
    final scene = ShuffleboardScene(
      style: const ShuffleboardStyle(),
      scheme: const ColorScheme.light(),
    )..onGameResize(lane);
    scene.applyState(
      const ShuffleboardGame().initialState(
        seed: 0,
        playerIds: const ['p1', 'p2'],
      ),
      'p1',
    );
    PuckStatus? status;
    scene.onSettled = (_, s, __) => status = s;
    scene.beginAim(const Offset(90, 100));
    scene.updateAim(Offset(90, 100 + pull));
    scene.endAim();
    for (var t = 0.0; status == null && t < 20; t += 1 / 60) {
      scene.update(1 / 60);
    }
    return status!;
  }

  // The lane rects a 6.1" iPhone and an SE draw (measured from the board).
  final phone = Vector2(186, 402);
  final se = Vector2(159, 344);

  test('a full pull overshoots the far end', () {
    expect(
      shoot(phone, ShuffleboardScene.fullPullFor(phone.y)),
      PuckStatus.offEnd,
    );
  });

  test('a firm pull short of full stays on the board', () {
    expect(
      shoot(phone, 0.85 * ShuffleboardScene.fullPullFor(phone.y)),
      isNot(PuckStatus.offEnd),
    );
  });

  test('full power fits in the room below the puck on an SE', () {
    // 167pt of board under the shooter at 343×542 (lane 159×344): full
    // power must arrive well before the finger runs out of screen.
    final fullPull = ShuffleboardScene.fullPullFor(se.y);
    expect(fullPull, lessThan(167 * 0.8));
    expect(shoot(se, fullPull), PuckStatus.offEnd);
  });
}
