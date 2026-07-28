import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/basketball/basketball.dart';
import 'package:flutter_minigames/src/core/core.dart';

void main() {
  const game = BasketballGame();
  const players = ['p1', 'p2'];

  BasketballState fresh() => game.initialState(seed: 7, playerIds: players);

  BasketballMove move(String owner, List<int> rounds) =>
      BasketballMove(owner: owner, roundScores: rounds);

  group('rules', () {
    test('two rounds of 45 seconds, at one fixed range', () {
      expect(BasketballGame.roundCount, 2);
      expect(game.roundSeconds, 45);
      // There is exactly one hoop depth — the range never changes by round.
      expect(BasketballCourt.hoopZ,
          BasketballCourt.spawnZ + BasketballCourt.hoopDistance);
    });

    test('a fresh match is player 1 to shoot, with nothing scored', () {
      final s = fresh();
      expect(s.nextToPlay, 'p1');
      expect(game.currentPlayer(s), 'p1');
      expect(s.isFinished, isFalse);
      expect(game.outcome(s), isNull);
      expect(s.scoreOf('p1'), 0);
      expect(s.roundsOf('p2'), [0, 0]);
    });

    test('p1 shoots, then p2, then the match is finished', () {
      var s = fresh();
      s = game.applyMove(s, move('p1', [7, 9]));
      expect(s.nextToPlay, 'p2');
      expect(s.isFinished, isFalse);
      expect(game.outcome(s), isNull);
      expect(s.hasSubmitted('p1'), isTrue);
      expect(s.hasSubmitted('p2'), isFalse);

      s = game.applyMove(s, move('p2', [4, 5]));
      expect(s.nextToPlay, isNull);
      expect(s.isFinished, isTrue);
      expect(game.outcome(s), const GameOutcome.win('p1'));
    });

    test('a score is the sum of the two rounds — it accumulates', () {
      var s = fresh();
      s = game.applyMove(s, move('p1', [6, 11]));
      expect(s.scoreOf('p1'), 17);
      expect(s.roundsOf('p1'), [6, 11]);
    });

    test('equal totals are a draw, however they were split', () {
      var s = fresh();
      s = game.applyMove(s, move('p1', [3, 9]));
      s = game.applyMove(s, move('p2', [8, 4]));
      expect(s.scoreOf('p1'), 12);
      expect(s.scoreOf('p2'), 12);
      expect(game.outcome(s), const GameOutcome.draw());
    });

    test('p2 wins when they put up more', () {
      var s = fresh();
      s = game.applyMove(s, move('p1', [2, 2]));
      s = game.applyMove(s, move('p2', [5, 1]));
      expect(game.outcome(s), const GameOutcome.win('p2'));
    });
  });

  group('validation', () {
    test('only the player who is up may submit, and only for themselves', () {
      final s = fresh();
      expect(game.validateMove(s, move('p1', [1, 1]), 'p1'), isTrue);
      expect(game.validateMove(s, move('p2', [1, 1]), 'p2'), isFalse,
          reason: 'p2 is not up yet');
      expect(game.validateMove(s, move('p2', [1, 1]), 'p1'), isFalse,
          reason: 'p1 cannot submit p2 a round');
    });

    test('a wrong number of rounds is rejected outright', () {
      final s = fresh();
      expect(game.validateMove(s, move('p1', [1]), 'p1'), isFalse);
      expect(game.validateMove(s, move('p1', [1, 2, 3]), 'p1'), isFalse);
      expect(game.validateMove(s, move('p1', const []), 'p1'), isFalse);
    });

    test('nobody may submit twice, or after the match ends', () {
      var s = fresh();
      s = game.applyMove(s, move('p1', [1, 1]));
      expect(game.validateMove(s, move('p1', [9, 9]), 'p1'), isFalse);
      s = game.applyMove(s, move('p2', [1, 1]));
      expect(game.validateMove(s, move('p2', [9, 9]), 'p2'), isFalse);
      expect(game.validateMove(s, move('p1', [9, 9]), 'p1'), isFalse);
    });
  });

  group('the reducer is defensive about what it records', () {
    test('negative scores collapse to zero', () {
      var s = fresh();
      s = game.applyMove(s, move('p1', [-5, 3]));
      expect(s.roundsOf('p1'), [0, 3]);
      expect(s.scoreOf('p1'), 3);
    });

    test('absurd scores are clamped, not trusted', () {
      var s = fresh();
      s = game.applyMove(s, move('p1', [1 << 30, 4]));
      expect(s.roundsOf('p1'), [BasketballGame.maxRoundScore, 4]);
    });

    test('short and long round lists are normalised to exactly two', () {
      expect(BasketballGame.normaliseRounds([5]), [5, 0]);
      expect(BasketballGame.normaliseRounds([]), [0, 0]);
      expect(BasketballGame.normaliseRounds([1, 2, 3, 4]), [1, 2]);
    });

    test('applyMove is pure — the state handed in is untouched', () {
      final before = fresh();
      final after = game.applyMove(before, move('p1', [3, 3]));
      expect(before.submissions, isEmpty);
      expect(after.submissions.keys, ['p1']);
      expect(identical(before, after), isFalse);
    });
  });

  group('serialization', () {
    test('state round-trips, mid-match and finished', () {
      var s = fresh();
      s = game.applyMove(s, move('p1', [6, 2]));
      final mid = game.decodeState(
        game.encodeState(s),
        game.stateSchemaVersion,
      );
      expect(mid.playerIds, players);
      expect(mid.roundsOf('p1'), [6, 2]);
      expect(mid.nextToPlay, 'p2');

      s = game.applyMove(s, move('p2', [1, 1]));
      final done = game.decodeState(
        game.encodeState(s),
        game.stateSchemaVersion,
      );
      expect(done.isFinished, isTrue);
      expect(game.outcome(done), const GameOutcome.win('p1'));
    });

    test('a move round-trips', () {
      final m = move('p2', [12, 8]);
      final back = game.decodeMove(game.encodeMove(m));
      expect(back.owner, 'p2');
      expect(back.roundScores, [12, 8]);
    });

    test('a corrupt payload decodes to something sane rather than throwing', () {
      final back = game.decodeMove({'owner': 'p1', 'roundScores': 'nonsense'});
      expect(back.roundScores, isEmpty);
      expect(BasketballGame.normaliseRounds(back.roundScores), [0, 0]);

      final state = game.decodeState({
        'playerIds': players,
        'submissions': {
          'p1': [3, -2, 99],
        },
      }, game.stateSchemaVersion);
      expect(state.roundsOf('p1'), [3, 0], reason: 'clamped and truncated');
    });
  });

  group('through the transport, as the app runs it', () {
    test('two controllers on one transport agree on the finished match',
        () async {
      final transport = LocalTransport();
      final a = await MatchController.create<BasketballState, BasketballMove>(
        game: game,
        transport: transport,
        matchId: 'm1',
        playerIds: players,
        localPlayerId: 'p1',
        hotSeat: true,
        seed: 3,
      );
      await a.submitMove(move('p1', [8, 6]));
      await a.submitMove(move('p2', [9, 4]));
      expect(a.state!.isFinished, isTrue);
      expect(a.state!.scoreOf('p1'), 14);
      expect(a.state!.scoreOf('p2'), 13);
      expect(a.outcome, const GameOutcome.win('p1'));
      await a.dispose();
    });
  });
}
