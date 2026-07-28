import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/archery/archery.dart';
import 'package:flutter_minigames/src/core/core.dart';

const game = ArcheryGame();
const players = ['p1', 'p2'];

ArcheryState fresh({int seed = 7}) =>
    game.initialState(seed: seed, playerIds: players);

/// Applies one arrow worth [ring] points for the current shooter, using an
/// offset that really does score that ring.
ArcheryState shoot(ArcheryState state, int ring) {
  final index = ArcheryGame.ringValues.indexOf(ring);
  final offset = index < 0
      ? ArcheryGame.faceRadius * 2 // deliberate miss
      : ArcheryGame.ringWidth * (index + 0.5);
  final move = ArcheryMove.fromImpact(
    shooter: state.currentPlayerId,
    targetIndex: state.targetIndex,
    arrowIndex: state.arrowIndex,
    offsetX: offset,
    offsetY: 0,
  );
  expect(game.validateMove(state, move, state.currentPlayerId), isTrue);
  expect(move.ring, ring);
  return game.applyMove(state, move);
}

ArcheryState shootAll(ArcheryState state, List<int> rings) {
  var s = state;
  for (final r in rings) {
    s = shoot(s, r);
  }
  return s;
}

void main() {
  group('ring scoring', () {
    test('dead centre is a 10', () {
      expect(ArcheryGame.ringValue(0, 0), 10);
      expect(ArcheryGame.ringValueForRadius(0), 10);
    });

    test('every ring boundary belongs to the inner ring', () {
      const w = ArcheryGame.ringWidth;
      expect(ArcheryGame.ringValueForRadius(w), 10);
      expect(ArcheryGame.ringValueForRadius(w * 1.0001), 8);
      expect(ArcheryGame.ringValueForRadius(w * 2), 8);
      expect(ArcheryGame.ringValueForRadius(w * 2.0001), 6);
      expect(ArcheryGame.ringValueForRadius(w * 3), 6);
      expect(ArcheryGame.ringValueForRadius(w * 3.0001), 4);
      expect(ArcheryGame.ringValueForRadius(w * 4), 4);
      expect(ArcheryGame.ringValueForRadius(w * 4.0001), 2);
      expect(ArcheryGame.ringValueForRadius(ArcheryGame.faceRadius), 2);
    });

    test('off the face scores nothing', () {
      expect(ArcheryGame.ringValueForRadius(ArcheryGame.faceRadius * 1.001), 0);
      expect(ArcheryGame.ringValue(0.5, 0.5), 0);
      expect(ArcheryGame.onFace(0.5, 0.5), isFalse);
      expect(ArcheryGame.onFace(0.1, 0.1), isTrue);
    });

    test('scores by radius, not by axis', () {
      // A 45° hit at the gold's radius is still a 10; the same distance out
      // along one axis must agree.
      const r = ArcheryGame.ringWidth;
      final diagonal = r / 1.4142135623730951;
      expect(ArcheryGame.ringValue(diagonal, diagonal), 10);
      expect(ArcheryGame.ringValue(r, 0), 10);
      expect(ArcheryGame.ringValue(0, r), 10);
    });

    test('a perfect end is 30 and a perfect match is 120', () {
      var s = fresh();
      s = shootAll(s, List.filled(ArcheryGame.arrowsPerTarget, 10));
      expect(s.targetTotalsOf('p1').first, 30);

      s = shootAll(s, List.filled(9, 10)); // rest of p1's targets
      expect(s.totalOf('p1'), ArcheryGame.maxScore);
      expect(ArcheryGame.maxScore, 120);
    });
  });

  group('four targets, three arrows', () {
    test('arrow → target → handoff → finished', () {
      var s = fresh();
      expect(s.phase, ArcheryPhase.p1Shooting);
      expect(s.currentPlayerId, 'p1');
      expect(s.targetIndex, 0);
      expect(s.arrowIndex, 0);
      expect(s.arrowsLeftAtTarget, 3);

      s = shoot(s, 10);
      expect(s.arrowIndex, 1);
      expect(s.targetIndex, 0);
      s = shoot(s, 8);
      s = shoot(s, 6);
      // Three arrows spent: same shooter, next target.
      expect(s.currentPlayerId, 'p1');
      expect(s.targetIndex, 1);
      expect(s.arrowIndex, 0);

      s = shootAll(s, List.filled(9, 4));
      // Player 1 is out of arrows: hand over.
      expect(s.phase, ArcheryPhase.handoff);
      expect(s.currentPlayerId, 'p2');
      expect(s.targetIndex, 0);
      expect(game.outcome(s), isNull);

      s = shoot(s, 2);
      expect(s.phase, ArcheryPhase.p2Shooting);

      s = shootAll(s, List.filled(11, 2));
      expect(s.phase, ArcheryPhase.finished);
      expect(s.arrowsShotBy('p1'), ArcheryGame.arrowsPerPlayer);
      expect(s.arrowsShotBy('p2'), ArcheryGame.arrowsPerPlayer);
    });

    test('higher total wins', () {
      var s = fresh();
      s = shootAll(s, List.filled(12, 10)); // p1: 120
      s = shootAll(s, List.filled(12, 8)); // p2: 96
      expect(s.totalOf('p1'), 120);
      expect(s.totalOf('p2'), 96);
      expect(game.outcome(s), const GameOutcome.win('p1'));
    });

    test('equal totals are a draw', () {
      var s = fresh();
      s = shootAll(s, List.filled(12, 6));
      s = shootAll(s, List.filled(12, 6));
      expect(game.outcome(s), const GameOutcome.draw());
    });

    test('a miss banks nothing but still uses the arrow', () {
      var s = fresh();
      s = shoot(s, 0);
      expect(s.totalOf('p1'), 0);
      expect(s.arrowsShotBy('p1'), 1);
      expect(s.shotsOf('p1').single.onFace, isFalse);
    });

    test('per-target breakdown chunks the arrows by end', () {
      var s = fresh();
      s = shootAll(s, [10, 10, 10, 8, 8, 8, 6, 6, 6, 4, 4, 4]);
      expect(s.targetTotalsOf('p1'), [30, 24, 18, 12]);
      expect(s.totalOf('p1'), 84);
    });

    test('arrows stuck in the current face are readable per end', () {
      var s = fresh();
      s = shootAll(s, [10, 8]);
      final arrows = s.arrowsAt('p1', 0);
      expect(arrows.length, 2);
      expect(arrows.map((a) => a.ring), [10, 8]);
      expect(s.arrowsAt('p1', 1), isEmpty);
    });
  });

  group('move validation', () {
    test('rejects the wrong player, target, or arrow', () {
      final s = fresh();
      final good = ArcheryMove.fromImpact(
        shooter: 'p1',
        targetIndex: 0,
        arrowIndex: 0,
        offsetX: 0,
        offsetY: 0,
      );
      expect(game.validateMove(s, good, 'p1'), isTrue);
      expect(game.validateMove(s, good, 'p2'), isFalse);

      final wrongTarget = ArcheryMove.fromImpact(
        shooter: 'p1',
        targetIndex: 2,
        arrowIndex: 0,
        offsetX: 0,
        offsetY: 0,
      );
      expect(game.validateMove(s, wrongTarget, 'p1'), isFalse);

      final wrongArrow = ArcheryMove.fromImpact(
        shooter: 'p1',
        targetIndex: 0,
        arrowIndex: 2,
        offsetX: 0,
        offsetY: 0,
      );
      expect(game.validateMove(s, wrongArrow, 'p1'), isFalse);
    });

    test('rejects a score the impact point does not support', () {
      final s = fresh();
      const lying = ArcheryMove(
        shooter: 'p1',
        targetIndex: 0,
        arrowIndex: 0,
        ring: 10,
        offsetX: 0.5, // that is a 2, not a 10
        offsetY: 0,
        onFace: true,
      );
      expect(game.validateMove(s, lying, 'p1'), isFalse);

      const offFaceButScoring = ArcheryMove(
        shooter: 'p1',
        targetIndex: 0,
        arrowIndex: 0,
        ring: 6,
        offsetX: 3,
        offsetY: 0,
        onFace: false,
      );
      expect(game.validateMove(s, offFaceButScoring, 'p1'), isFalse);
    });

    test('rejects everything once the match is over', () {
      var s = fresh();
      s = shootAll(s, List.filled(24, 6));
      final move = ArcheryMove.fromImpact(
        shooter: 'p2',
        targetIndex: 3,
        arrowIndex: 2,
        offsetX: 0,
        offsetY: 0,
      );
      expect(game.validateMove(s, move, 'p2'), isFalse);
    });
  });

  group('seeded conditions', () {
    test('are identical for both players', () {
      // The generator takes no player argument at all, so this is structural:
      // whatever player 1 faced at target i, player 2 faces at target i.
      var s = fresh(seed: 91);
      final p1Conditions = [
        for (var i = 0; i < ArcheryGame.targetCount; i++)
          ArcheryGame.conditionsAt(s.seed, i),
      ];
      s = shootAll(s, List.filled(12, 6));
      expect(s.currentPlayerId, 'p2');
      for (var i = 0; i < ArcheryGame.targetCount; i++) {
        final c = ArcheryGame.conditionsAt(s.seed, i);
        expect(c.distance, p1Conditions[i].distance);
        expect(c.windSpeed, p1Conditions[i].windSpeed);
        expect(c.windAngle, p1Conditions[i].windAngle);
      }
      // And the state exposes the right one as the shooter advances.
      expect(s.conditions.distance, p1Conditions[0].distance);
    });

    test('are reproducible per seed and differ between seeds', () {
      final a = ArcheryGame.conditionsForSeed(2024);
      final b = ArcheryGame.conditionsForSeed(2024);
      final c = ArcheryGame.conditionsForSeed(2025);
      for (var i = 0; i < ArcheryGame.targetCount; i++) {
        expect(a[i].distance, b[i].distance);
        expect(a[i].windSpeed, b[i].windSpeed);
        expect(a[i].windAngle, b[i].windAngle);
      }
      expect(
        [for (final t in a) t.distance],
        isNot([for (final t in c) t.distance]),
      );
    });

    test('distance and wind both ramp across every seed', () {
      for (var seed = 0; seed < 200; seed++) {
        final targets = ArcheryGame.conditionsForSeed(seed);
        expect(targets.length, 4);
        for (var i = 1; i < targets.length; i++) {
          expect(
            targets[i].distance,
            greaterThan(targets[i - 1].distance),
            reason: 'seed $seed target $i is not further away',
          );
          expect(
            targets[i].windSpeed,
            greaterThan(targets[i - 1].windSpeed),
            reason: 'seed $seed target $i is not windier',
          );
        }
        expect(targets.first.distance, inInclusiveRange(13, 17));
        expect(targets.last.distance, inInclusiveRange(36, 40));
        expect(targets.last.windSpeed, inInclusiveRange(6.5, 9));
      }
    });

    test('wind is mostly crosswind, in both directions across seeds', () {
      var right = 0;
      var left = 0;
      for (var seed = 0; seed < 120; seed++) {
        final t = ArcheryGame.conditionsForSeed(seed).last;
        // |cross| dominates |along| for every generated wind.
        expect(t.crossComponent.abs(), greaterThan(t.alongComponent.abs()));
        if (t.crossComponent > 0) {
          right++;
        } else {
          left++;
        }
      }
      expect(right, greaterThan(20));
      expect(left, greaterThan(20));
    });

    test('summary reads as a HUD line', () {
      const c =
          TargetConditions(index: 2, distance: 30, windSpeed: 6, windAngle: 0);
      expect(c.summary(), 'Target 3 · 30 m · wind 6.0 →');
    });
  });

  group('serialization', () {
    test('state round-trips through JSON', () {
      var s = fresh(seed: 33);
      s = shootAll(s, [10, 0, 6, 8, 8]);
      final decoded = game.decodeState(
        game.encodeState(s),
        game.stateSchemaVersion,
      );
      expect(decoded.seed, s.seed);
      expect(decoded.playerIds, s.playerIds);
      expect(decoded.totalOf('p1'), s.totalOf('p1'));
      expect(decoded.arrowsShotBy('p1'), s.arrowsShotBy('p1'));
      expect(decoded.targetIndex, s.targetIndex);
      expect(decoded.arrowIndex, s.arrowIndex);
      expect(decoded.phase, s.phase);
      expect(
          decoded.shotsOf('p1').first.offsetX, s.shotsOf('p1').first.offsetX);
      expect(decoded.shotsOf('p1')[1].onFace, isFalse);
    });

    test('a finished state round-trips with its outcome intact', () {
      var s = fresh();
      s = shootAll(s, List.filled(12, 10));
      s = shootAll(s, List.filled(12, 4));
      final decoded = game.decodeState(
        game.encodeState(s),
        game.stateSchemaVersion,
      );
      expect(decoded.phase, ArcheryPhase.finished);
      expect(game.outcome(decoded), const GameOutcome.win('p1'));
      expect(decoded.targetTotalsOf('p2'), [12, 12, 12, 12]);
    });

    test('move round-trips through JSON', () {
      final move = ArcheryMove.fromImpact(
        shooter: 'p2',
        targetIndex: 3,
        arrowIndex: 1,
        offsetX: -0.19,
        offsetY: 0.07,
      );
      final decoded = game.decodeMove(game.encodeMove(move));
      expect(decoded.shooter, 'p2');
      expect(decoded.targetIndex, 3);
      expect(decoded.arrowIndex, 1);
      expect(decoded.ring, move.ring);
      expect(decoded.offsetX, move.offsetX);
      expect(decoded.offsetY, move.offsetY);
      expect(decoded.onFace, isTrue);
    });

    test('conditions round-trip through JSON', () {
      final c = ArcheryGame.conditionsAt(5, 2);
      final decoded = TargetConditions.fromJson(c.toJson());
      expect(decoded.index, c.index);
      expect(decoded.distance, c.distance);
      expect(decoded.windSpeed, c.windSpeed);
      expect(decoded.windAngle, c.windAngle);
    });

    test('an encoded state survives a full match replay', () {
      // Encode/decode after every single arrow: the reducer must never depend
      // on anything that does not survive the wire.
      var s = fresh(seed: 12);
      for (var i = 0; i < ArcheryGame.arrowsPerPlayer * 2; i++) {
        s = shoot(s, ArcheryGame.ringValues[i % 5]);
        s = game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      }
      expect(s.phase, ArcheryPhase.finished);
      expect(game.outcome(s), isNotNull);
    });
  });
}
