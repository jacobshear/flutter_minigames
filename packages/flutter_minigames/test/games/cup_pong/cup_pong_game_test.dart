import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/cup_pong/cup_pong.dart';
import 'package:flutter_minigames/src/core/core.dart';

void main() {
  const game = CupPongGame();
  const players = ['p1', 'p2'];

  CupPongState fresh() => game.initialState(seed: 1, playerIds: players);

  CupPongThrow shot(CupPongState s, {int? cup}) {
    final owner = s.currentPlayerId;
    return CupPongThrow(
      owner: owner,
      target: s.opponentOf(owner),
      hitCupId: cup,
    );
  }

  /// Applies a throw for whoever is up, hitting [cup] (or missing).
  CupPongState play(CupPongState s, {int? cup}) =>
      game.applyMove(s, shot(s, cup: cup));

  group('rack geometry', () {
    test('10 cups form a 1-2-3-4 triangle with the apex nearest', () {
      expect(CupPongGame.rowsFor(10), [1, 2, 3, 4]);
      final cups = CupPongGame.rackFor([for (var i = 0; i < 10; i++) i]);
      expect(cups.length, 10);
      // Apex: one cup, dead centre, at depth 0 — the end pointing at you.
      expect(cups.first.x, 0);
      expect(cups.first.z, 0);
      final back = cups.where((c) => c.z == 3).toList();
      expect(back.length, 4);
      expect(back.map((c) => c.x).toList(), [-1.5, -0.5, 0.5, 1.5]);
      for (var z = 0; z < 4; z++) {
        expect(cups.where((c) => c.z == z).length, z + 1);
      }
    });

    test('re-rack tightens the triangle and preserves ids', () {
      final six = CupPongGame.rerack(
        CupPongGame.rackFor([for (var i = 0; i < 10; i++) i]).take(6).toList(),
      );
      expect(six.length, 6);
      expect(six.map((c) => c.id).toList(), [0, 1, 2, 3, 4, 5]);
      expect(CupPongGame.rowsFor(6), [1, 2, 3]);
      // Shallower than a 10-rack: three rows instead of four.
      expect(six.map((c) => c.z).reduce((a, b) => a > b ? a : b), 2);
    });

    test('rack for 3 is a 1-2 triangle', () {
      expect(CupPongGame.rowsFor(3), [1, 2]);
      expect(CupPongGame.rackFor([7, 8, 9]).map((c) => c.id), [7, 8, 9]);
    });
  });

  group('setup', () {
    test('both players start with a full rack and p1 leads', () {
      final s = fresh();
      expect(s.remainingOf('p1'), 10);
      expect(s.remainingOf('p2'), 10);
      expect(game.currentPlayer(s), 'p1');
      expect(s.ballsThrown, 0);
      expect(s.ballNumber, 1);
      expect(game.outcome(s), isNull);
    });
  });

  group('validateMove', () {
    test('rejects the wrong player, wrong target, and dead cups', () {
      final s = fresh();
      expect(game.validateMove(s, shot(s, cup: 0), 'p1'), isTrue);
      expect(game.validateMove(s, shot(s, cup: 0), 'p2'), isFalse);
      expect(
        game.validateMove(
          s,
          const CupPongThrow(owner: 'p1', target: 'p1', hitCupId: 0),
          'p1',
        ),
        isFalse,
      );
      final after = play(s, cup: 0);
      // p1 is still up (ball 2) and cup 0 is gone — it can't be sunk twice.
      expect(after.currentPlayerId, 'p1');
      expect(game.validateMove(after, shot(after, cup: 0), 'p1'), isFalse);
      expect(game.validateMove(after, shot(after, cup: 1), 'p1'), isTrue);
    });

    test('rejects any move once the game is over', () {
      var s = fresh();
      s = s.copyWith(cups: {
        ...s.cups,
        'p2': [s.cupsOf('p2').first],
      });
      s = play(s, cup: s.cupsOf('p2').first.id);
      expect(game.outcome(s), isNotNull);
      expect(
        game.validateMove(s, shot(s), s.currentPlayerId),
        isFalse,
      );
    });
  });

  group('turn flow', () {
    test('a hit removes exactly that cup', () {
      final next = play(fresh(), cup: 4);
      expect(next.remainingOf('p2'), 9);
      expect(next.hasCup('p2', 4), isFalse);
      expect(next.hasCup('p2', 5), isTrue);
      expect(next.remainingOf('p1'), 10, reason: 'own rack untouched');
    });

    test('a miss removes nothing but still burns a ball', () {
      final next = play(fresh());
      expect(next.remainingOf('p2'), 10);
      expect(next.ballsThrown, 1);
      expect(next.ballNumber, 2);
      expect(next.currentPlayerId, 'p1');
    });

    test('the turn passes after two balls', () {
      var s = play(fresh());
      expect(s.currentPlayerId, 'p1');
      s = play(s);
      expect(s.currentPlayerId, 'p2');
      expect(s.ballsThrown, 0);
      expect(s.ballsBack, isFalse);
    });

    test('one hit and one miss still passes the turn', () {
      var s = play(fresh(), cup: 0);
      s = play(s);
      expect(s.currentPlayerId, 'p2');
      expect(s.ballsBack, isFalse);
      expect(s.remainingOf('p2'), 9);
    });

    test('balls back: two for two keeps the balls with the thrower', () {
      var s = play(fresh(), cup: 0);
      s = play(s, cup: 1);
      expect(s.currentPlayerId, 'p1', reason: 'p1 throws again');
      expect(s.ballsBack, isTrue);
      expect(s.ballsThrown, 0, reason: 'a fresh pair of balls');
      expect(s.hitsThisTurn, 0);
      expect(s.remainingOf('p2'), 8);
      // Not sticky — the next resolved ball clears the flag.
      s = play(s);
      expect(s.ballsBack, isFalse);
    });
  });

  group('re-rack', () {
    test('fires when the defender drops to 6', () {
      var s = fresh();
      var didRerack = false;
      while (s.remainingOf('p2') > 6) {
        s = play(s, cup: s.cupsOf('p2').first.id);
        didRerack = didRerack || s.didRerack;
      }
      expect(s.remainingOf('p2'), 6);
      expect(didRerack, isTrue);
      // The survivors now sit in a 1-2-3 triangle, not their old slots.
      final rack = s.cupsOf('p2');
      expect(rack.map((c) => c.id).toList(), [4, 5, 6, 7, 8, 9]);
      expect(rack.first.z, 0);
      expect(rack.map((c) => c.z).reduce((a, b) => a > b ? a : b), 2);
    });

    test('fires again at 3', () {
      var s = fresh();
      while (s.remainingOf('p2') > 3) {
        s = play(s, cup: s.cupsOf('p2').first.id);
      }
      expect(s.remainingOf('p2'), 3);
      expect(s.didRerack, isTrue);
      final rack = s.cupsOf('p2');
      expect(rack.map((c) => c.z).toList(), [0, 1, 1]);
      expect(rack.map((c) => c.x).toList(), [0, -0.5, 0.5]);
    });

    test('does not fire on non-trigger counts', () {
      final s = play(fresh(), cup: 0);
      expect(s.remainingOf('p2'), 9);
      expect(s.didRerack, isFalse);
    });
  });

  group('outcome', () {
    test('clearing the opponent wins', () {
      var s = fresh();
      for (var i = 0; i < 10; i++) {
        expect(game.outcome(s), isNull);
        s = play(s, cup: s.cupsOf('p2').first.id);
      }
      expect(s.remainingOf('p2'), 0);
      expect(game.outcome(s), const GameOutcome.win('p1'));
    });

    test('both racks empty is a draw', () {
      final empty = fresh().copyWith(cups: {'p1': const [], 'p2': const []});
      expect(game.outcome(empty)!.isDraw, isTrue);
    });
  });

  group('serialization', () {
    test('state round-trips, including positions and turn bookkeeping', () {
      var s = play(fresh(), cup: 0);
      s = play(s, cup: 1); // balls back
      final back = game.decodeState(
        game.encodeState(s),
        game.stateSchemaVersion,
      );
      expect(back.playerIds, s.playerIds);
      expect(back.currentPlayerId, s.currentPlayerId);
      expect(back.ballsThrown, s.ballsThrown);
      expect(back.hitsThisTurn, s.hitsThisTurn);
      expect(back.ballsBack, s.ballsBack);
      expect(back.didRerack, s.didRerack);
      expect(back.throws, s.throws);
      for (final p in players) {
        expect(back.cupsOf(p), s.cupsOf(p));
      }
    });

    test('state round-trips after a re-rack moves cups', () {
      var s = fresh();
      while (s.remainingOf('p2') > 6) {
        s = play(s, cup: s.cupsOf('p2').first.id);
      }
      final back = game.decodeState(
        game.encodeState(s),
        game.stateSchemaVersion,
      );
      expect(back.cupsOf('p2'), s.cupsOf('p2'));
    });

    test('move round-trips, hit and miss', () {
      const hit = CupPongThrow(
        owner: 'p1',
        target: 'p2',
        hitCupId: 7,
        ballX: 0.12,
        ballZ: 0.91,
      );
      final backHit = game.decodeMove(game.encodeMove(hit));
      expect(backHit.owner, 'p1');
      expect(backHit.target, 'p2');
      expect(backHit.hitCupId, 7);
      expect(backHit.ballX, closeTo(0.12, 1e-9));
      expect(backHit.ballZ, closeTo(0.91, 1e-9));
      expect(backHit.isHit, isTrue);

      const miss = CupPongThrow(owner: 'p2', target: 'p1', hitCupId: null);
      final backMiss = game.decodeMove(game.encodeMove(miss));
      expect(backMiss.hitCupId, isNull);
      expect(backMiss.isHit, isFalse);
    });
  });
}
