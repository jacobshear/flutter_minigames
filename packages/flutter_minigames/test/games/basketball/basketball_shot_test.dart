import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/basketball/basketball.dart';
import 'package:flutter_minigames/src/engine3d/engine3d.dart';

void main() {
  group('BasketballShot encode/decode', () {
    test('round-trips through encode/decode', () {
      const shot = BasketballShot(
        round: 1,
        tMs: 12345,
        spawnX: -0.271234,
        aim: 0.4567,
        made: true,
        points: 1,
        ballIndex: 7,
      );
      final decoded = BasketballShot.decode(shot.encode())!;
      expect(decoded.round, 1);
      expect(decoded.tMs, 12345);
      expect(decoded.spawnX, closeTo(-0.271, 0.001));
      expect(decoded.aim, closeTo(0.457, 0.001));
      expect(decoded.made, isTrue);
      expect(decoded.points, 1);
      expect(decoded.ballIndex, 7);
    });

    test('a whole shot list round-trips', () {
      final shots = [
        const BasketballShot(
          round: 0,
          tMs: 0,
          spawnX: 0.1,
          aim: -0.2,
          made: false,
          points: 0,
          ballIndex: 0,
        ),
        const BasketballShot(
          round: 0,
          tMs: 250,
          spawnX: -0.1,
          aim: 0.3,
          made: true,
          points: 1,
          ballIndex: 1,
        ),
      ];
      final decoded = decodeShotList(encodeShotList(shots));
      expect(decoded.length, 2);
      expect(decoded[0].made, isFalse);
      expect(decoded[1].made, isTrue);
      expect(decoded[1].ballIndex, 1);
    });

    test('a corrupt or foreign entry is dropped, not thrown', () {
      expect(BasketballShot.decode('nonsense'), isNull);
      expect(BasketballShot.decode([1, 2]), isNull);
      expect(decodeShotList('nonsense'), isEmpty);
      final mixed = decodeShotList([
        1,
        'x',
        [0, 0, 0, 0, true, 1, 0],
      ]);
      expect(mixed, hasLength(1));
    });

    test('a missing shots payload decodes to an empty list', () {
      expect(decodeShotList(null), isEmpty);
    });

    test('the encoding stays lean — a busy round is well under a few KB', () {
      final shots = [
        for (var i = 0; i < 60; i++)
          BasketballShot(
            round: i < 30 ? 0 : 1,
            tMs: (i % 30) * 1500,
            spawnX: (i.isEven ? 1 : -1) * 0.2137,
            aim: (i.isEven ? 1 : -1) * 0.4321,
            made: i % 3 == 0,
            points: i % 3 == 0 ? 1 : 0,
            ballIndex: i,
          ),
      ];
      final encoded = encodeShotList(shots).toString();
      expect(encoded.length, lessThan(3000),
          reason: '60 shots encoded to ${encoded.length} chars');
    });
  });

  group('the game reducer wires the shot log through', () {
    const game = BasketballGame();
    const players = ['p1', 'p2'];
    BasketballState fresh() => game.initialState(seed: 1, playerIds: players);

    test('applyMove stores the shot log against the shooter', () {
      final shots = [
        const BasketballShot(
          round: 0,
          tMs: 100,
          spawnX: 0,
          aim: 0,
          made: true,
          points: 1,
          ballIndex: 0,
        ),
      ];
      var s = fresh();
      s = game.applyMove(
        s,
        BasketballMove(owner: 'p1', roundScores: const [1, 0], shots: shots),
      );
      expect(s.shotsOf('p1'), hasLength(1));
      expect(s.shotsOf('p1').single.made, isTrue);
      expect(s.shotsOf('p2'), isEmpty, reason: 'p2 has not submitted yet');
    });

    test('a move built with no shots (the pre-replay shape) still applies', () {
      var s = fresh();
      s = game.applyMove(
        s,
        const BasketballMove(owner: 'p1', roundScores: [4, 2]),
      );
      expect(s.roundsOf('p1'), [4, 2]);
      expect(s.shotsOf('p1'), isEmpty);
    });

    test('state and move round-trip the shot log through JSON', () {
      final shots = [
        const BasketballShot(
          round: 0,
          tMs: 10,
          spawnX: 0.05,
          aim: -0.4,
          made: false,
          points: 0,
          ballIndex: 0,
        ),
        const BasketballShot(
          round: 1,
          tMs: 900,
          spawnX: -0.2,
          aim: 0.9,
          made: true,
          points: 1,
          ballIndex: 1,
        ),
      ];
      final move =
          BasketballMove(owner: 'p1', roundScores: const [1, 1], shots: shots);
      final decodedMove = game.decodeMove(game.encodeMove(move));
      expect(decodedMove.shots, hasLength(2));
      expect(decodedMove.shots[1].round, 1);
      expect(decodedMove.shots[1].made, isTrue);

      var s = fresh();
      s = game.applyMove(s, move);
      final decodedState =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(decodedState.shotsOf('p1'), hasLength(2));
      expect(decodedState.shotsOf('p1')[1].made, isTrue);
      expect(decodedState.roundsOf('p1'), [1, 1]);
    });

    test('a LEGACY state with no shots key at all decodes fine', () {
      final legacyJson = {
        'playerIds': players,
        'submissions': {
          'p1': [5, 4],
        },
        // No 'shots' key — this is exactly what a pre-replay match looks
        // like on disk.
      };
      final s = game.decodeState(legacyJson, game.stateSchemaVersion);
      expect(s.roundsOf('p1'), [5, 4]);
      expect(s.shotsOf('p1'), isEmpty);
      expect(s.isFinished, isFalse);
    });

    test('decoding a move with no shots key defaults to an empty log', () {
      final m = game.decodeMove({
        'owner': 'p1',
        'roundScores': [3, 2],
      });
      expect(m.shots, isEmpty);
    });
  });

  group('determinism: a logged shot replays to the same outcome', () {
    // This is the load-bearing guarantee behind BasketballRoundReplay: given
    // the same (mode, spawnX, aim, round time), BasketballRoundSim always
    // produces the same flight, because nothing about a shot in flight
    // consults the sim's rng — only the auto-respawned *next* ready ball
    // does, and a replayed shot always overrides `ready` itself before
    // shooting (exactly like the `simulateShot` helper below).

    test('a dead-centre make replays as a make through a fresh sim', () {
      // aim=0 at spawnX=0 in normal mode is the tuned dead-centre shot (see
      // basketball_physics_test.dart: "a dead-centre shot is a basket").
      final logged = _throwAndLog(
        mode: BasketballHoopMode.normal,
        spawnX: 0,
        aim: 0,
        atTime: 3.0,
      );
      expect(logged.made, isTrue,
          reason: 'the shot recorded for the log must itself be a make');

      final replayed = _replayShot(logged, BasketballHoopMode.normal);
      expect(replayed.made, isTrue);
    });

    test('a hard-miss aim replays as a miss too', () {
      final logged = _throwAndLog(
        mode: BasketballHoopMode.normal,
        spawnX: 0,
        aim: 1.0, // wide right — see basketball_physics_test.dart's "-1" case
        atTime: 1.0,
      );
      expect(logged.made, isFalse);

      final replayed = _replayShot(logged, BasketballHoopMode.normal);
      expect(replayed.made, isFalse);
    });

    test('a moving-hoop make replays as a make against the same mode', () {
      // The rig's lateral offset at round time t depends on mode, so the
      // replay must be given BasketballHoopMode.moving too, or it re-aims at
      // a stationary hoop that was not where the shot was actually thrown.
      const mode = BasketballHoopMode.moving;
      const atTime = 4.4;
      final leadAim = BasketballAim.leadAim(mode, 0, atTime);
      final logged = _throwAndLog(
        mode: mode,
        spawnX: 0,
        aim: leadAim,
        atTime: atTime,
      );
      final replayed = _replayShot(logged, mode);
      expect(replayed.made, logged.made);
    });
  });
}

/// Throws one shot exactly as the live board does (fresh ready ball at
/// [spawnX], sim time set to [atTime]) and runs it to rest, returning a
/// [BasketballShot] log entry for it — the same shape
/// `BasketballRoundBoard`'s `_recordShot`/`_resolveShot` produce.
BasketballShot _throwAndLog({
  required BasketballHoopMode mode,
  required double spawnX,
  required double aim,
  required double atTime,
}) {
  final ball =
      simulateShot(mode: mode, aim: aim, spawnX: spawnX, atTime: atTime);
  return BasketballShot(
    round: 0,
    tMs: (atTime * 1000).round(),
    spawnX: spawnX,
    aim: aim,
    made: ball.made,
    points: ball.made ? 1 : 0,
    ballIndex: 0,
  );
}

/// Replays a logged shot the way `BasketballRoundReplay` does internally:
/// fresh sim, ready ball forced to the logged spawnX, shoot with the logged
/// aim, run to rest.
LiveBall _replayShot(BasketballShot shot, BasketballHoopMode mode) {
  final sim = BasketballRoundSim(mode: mode, rng: math.Random(0));
  sim.time = shot.tMs / 1000;
  sim.ready = LiveBall(
    id: -1,
    spawnX: shot.spawnX,
    body: Projectile(
      position: Vec3(
        shot.spawnX,
        BasketballCourt.spawnPoint.y,
        BasketballCourt.spawnPoint.z,
      ),
      velocity: Vec3.zero,
      config: BasketballCourt.throwConfig,
    ),
  );
  final ball = sim.shoot(shot.aim)!;
  var guard = 0;
  while (!ball.atRest && guard++ < 2400) {
    sim.advance(BasketballCourt.throwConfig.fixedDt);
  }
  return ball;
}
