import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_darts/minigame_darts.dart';
import 'package:minigames_core/minigames_core.dart';

const game = DartsGame();
const players = ['p1', 'p2'];

DartsState fresh() => game.initialState(seed: 0, playerIds: players);

/// Apply a run of darts for whoever is at the oche, asserting each is legal.
DartsState play(DartsState state, List<DartHit> darts) {
  var s = state;
  for (final d in darts) {
    final move = DartsMove(playerId: s.currentPlayerId, hit: d);
    expect(game.validateMove(s, move, s.currentPlayerId), isTrue,
        reason: 'move ${d.label} should be legal');
    s = game.applyMove(s, move);
  }
  return s;
}

/// Force a player's remaining score (test scaffolding — the rules never do
/// this, but reaching 40 from 501 through the reducer would be a pointless
/// 20-dart preamble in every test).
DartsState scored(DartsState s, {int? p1, int? p2, String? turn}) {
  final scores = Map<String, int>.of(s.scores);
  if (p1 != null) scores['p1'] = p1;
  if (p2 != null) scores['p2'] = p2;
  final current = turn ?? s.currentPlayerId;
  return s.copyWith(
    scores: scores,
    currentPlayerId: current,
    visitStartScore: scores[current],
    visit: const [],
  );
}

void main() {
  group('501 flow', () {
    test('both players start on 501 and player one throws first', () {
      final s = fresh();
      expect(s.scoreOf('p1'), 501);
      expect(s.scoreOf('p2'), 501);
      expect(game.currentPlayer(s), 'p1');
      expect(s.visit, isEmpty);
      expect(s.dartsLeft, 3);
      expect(game.outcome(s), isNull);
    });

    test('each dart subtracts as it lands', () {
      var s = play(fresh(), [const DartHit(20, 3)]);
      expect(s.scoreOf('p1'), 441);
      expect(s.visitTotal, 60);
      expect(s.dartsLeft, 2);
      s = play(s, [const DartHit(20, 1)]);
      expect(s.scoreOf('p1'), 421);
      expect(s.visitTotal, 80);
      expect(game.currentPlayer(s), 'p1');
    });

    test('three darts end the visit and pass the oche', () {
      final s = play(fresh(), [
        const DartHit(20, 3),
        const DartHit(20, 3),
        const DartHit(20, 1),
      ]);
      expect(s.scoreOf('p1'), 501 - 140);
      expect(game.currentPlayer(s), 'p2');
      expect(s.visit, isEmpty);
      expect(s.visitStartScore, 501, reason: 'now p2’s visit start');
      expect(s.lastVisit!.playerId, 'p1');
      expect(s.lastVisit!.total, 140);
      expect(s.lastVisit!.busted, isFalse);
    });

    test('a miss is a legal dart worth nothing', () {
      final s = play(fresh(), [DartHit.miss]);
      expect(s.scoreOf('p1'), 501);
      expect(s.visit.single, DartHit.miss);
      expect(s.dartsLeft, 2);
    });

    test('visits alternate', () {
      var s = fresh();
      s = play(s, [const DartHit(1, 1), const DartHit(1, 1), DartHit.miss]);
      expect(game.currentPlayer(s), 'p2');
      s = play(s, [const DartHit(1, 1), const DartHit(1, 1), DartHit.miss]);
      expect(game.currentPlayer(s), 'p1');
      expect(s.scoreOf('p1'), 499);
      expect(s.scoreOf('p2'), 499);
    });
  });

  group('bust', () {
    test('going below zero voids the whole visit', () {
      var s = scored(fresh(), p1: 100);
      s = play(s, [const DartHit(20, 3)]); // 40 left
      expect(s.scoreOf('p1'), 40);
      s = play(s, [const DartHit(20, 3)]); // would be -20
      expect(s.scoreOf('p1'), 100, reason: 'reverts to the visit start');
      expect(game.currentPlayer(s), 'p2');
      expect(s.lastVisit!.busted, isTrue);
      expect(s.lastVisit!.total, 0);
    });

    test('landing on exactly 1 busts — there is no double 0.5', () {
      var s = scored(fresh(), p1: 21);
      s = play(s, [const DartHit(20, 1)]);
      expect(s.scoreOf('p1'), 21);
      expect(game.currentPlayer(s), 'p2');
      expect(s.lastVisit!.busted, isTrue);
    });

    test('reaching zero without a double busts', () {
      var s = scored(fresh(), p1: 20);
      s = play(s, [const DartHit(20, 1)]);
      expect(s.scoreOf('p1'), 20);
      expect(game.outcome(s), isNull);
      expect(game.currentPlayer(s), 'p2');
      expect(s.lastVisit!.busted, isTrue);
    });

    test('a treble that reaches zero also busts — only doubles finish', () {
      var s = scored(fresh(), p1: 60);
      s = play(s, [const DartHit(20, 3)]);
      expect(s.scoreOf('p1'), 60);
      expect(game.outcome(s), isNull);
    });

    test('the outer bull cannot finish, the bullseye can', () {
      var s = scored(fresh(), p1: 25);
      s = play(s, [const DartHit(25, 1)]);
      expect(s.scoreOf('p1'), 25, reason: '25 is not a double');
      expect(game.outcome(s), isNull);

      var t = scored(fresh(), p1: 50);
      t = play(t, [const DartHit(25, 2)]);
      expect(t.scoreOf('p1'), 0);
      expect(game.outcome(t), isA<GameOutcome>());
    });

    test('a bust discards darts already scored in the same visit', () {
      var s = scored(fresh(), p1: 130);
      s = play(s, [const DartHit(20, 3), const DartHit(20, 3)]); // 10 left
      expect(s.scoreOf('p1'), 10);
      s = play(s, [const DartHit(19, 1)]); // -9
      expect(s.scoreOf('p1'), 130);
      expect(s.lastVisit!.darts.length, 3);
      expect(s.lastVisit!.total, 0);
    });
  });

  group('checkout', () {
    test('a double on exactly zero wins', () {
      var s = scored(fresh(), p1: 40);
      s = play(s, [const DartHit(20, 2)]);
      expect(s.scoreOf('p1'), 0);
      expect(s.winnerId, 'p1');
      final outcome = game.outcome(s);
      expect(outcome, isNotNull);
      expect(outcome!.winnerId, 'p1');
      expect(outcome.isDraw, isFalse);
    });

    test('the second player can win too', () {
      var s = scored(fresh(), p2: 32, turn: 'p2');
      s = play(s, [const DartHit(16, 2)]);
      expect(game.outcome(s)!.winnerId, 'p2');
    });

    test('a finished match refuses further darts', () {
      var s = scored(fresh(), p1: 40);
      s = play(s, [const DartHit(20, 2)]);
      expect(
        game.validateMove(
          s,
          const DartsMove(playerId: 'p1', hit: DartHit(20, 1)),
          'p1',
        ),
        isFalse,
      );
    });

    test('a win mid-visit keeps the visit on the scoreboard', () {
      var s = scored(fresh(), p1: 100);
      s = play(s, [const DartHit(20, 3), const DartHit(20, 2)]);
      expect(s.winnerId, 'p1');
      expect(s.visit.length, 2);
    });
  });

  group('checkout hints', () {
    test('the classic finishes', () {
      expect(DartsState.hintFor(40), 'D20');
      expect(DartsState.hintFor(32), 'D16');
      expect(DartsState.hintFor(50), 'BULL');
      expect(DartsState.hintFor(100), 'T20 D20');
      expect(DartsState.hintFor(170), 'T20 T20 BULL');
      expect(DartsState.hintFor(2), 'D1');
      // These are the ones a naive search gets wrong: it wants to *set up*
      // with a double or take a bull when a plain single or a D19 is the call.
      expect(DartsState.hintFor(60), '20 D20');
      expect(DartsState.hintFor(120), 'T20 20 D20');
      expect(DartsState.hintFor(141), 'T20 T15 D18');
      expect(DartsState.hintFor(158), 'T20 T20 D19');
      expect(DartsState.hintFor(167), 'T20 T19 BULL');
      expect(DartsState.hintFor(96), 'T20 D18');
    });

    test('scores with no finish have no hint', () {
      expect(DartsCheckout.suggest(501), isNull);
      expect(DartsCheckout.suggest(171), isNull);
      expect(DartsCheckout.suggest(1), isNull);
      for (final impossible in [169, 168, 166, 165, 163, 162, 159]) {
        expect(DartsCheckout.suggest(impossible), isNull,
            reason: '$impossible is not a checkout');
      }
    });

    test('the hint shortens as darts are used', () {
      expect(DartsCheckout.suggest(100, dartsLeft: 2)!.length, 2);
      expect(DartsCheckout.suggest(100, dartsLeft: 1), isNull);
      expect(DartsCheckout.suggest(170, dartsLeft: 2), isNull);
      expect(DartsCheckout.suggest(40, dartsLeft: 1)!.single,
          const DartHit(20, 2));
    });

    test('every suggested route actually adds up and ends on a double', () {
      for (var n = 2; n <= DartsCheckout.maxCheckout; n++) {
        final route = DartsCheckout.suggest(n);
        if (route == null) continue;
        expect(route.fold(0, (sum, d) => sum + d.value), n, reason: 'route $n');
        expect(route.last.isDouble, isTrue, reason: 'route $n must double out');
        expect(route.length, lessThanOrEqualTo(3));
      }
    });

    test('the live state exposes the hint for the player at the oche', () {
      final s = scored(fresh(), p1: 40);
      expect(s.checkoutHint, 'D20');
      expect(s.checkout!.single, const DartHit(20, 2));
      expect(fresh().checkoutHint, isNull);
    });
  });

  group('validation', () {
    test('only the player at the oche may throw', () {
      final s = fresh();
      expect(
        game.validateMove(
          s,
          const DartsMove(playerId: 'p2', hit: DartHit(20, 1)),
          'p2',
        ),
        isFalse,
      );
    });

    test('malformed hits are rejected', () {
      final s = fresh();
      for (final bad in [
        const DartHit(25, 3),
        const DartHit(21, 1),
        const DartHit(0, 2),
      ]) {
        expect(
          game.validateMove(s, DartsMove(playerId: 'p1', hit: bad), 'p1'),
          isFalse,
          reason: '${bad.sector}x${bad.multiplier}',
        );
      }
    });
  });

  group('serialization', () {
    test('state round-trips through json', () {
      var s = play(fresh(), [
        const DartHit(20, 3),
        const DartHit(5, 1),
        const DartHit(25, 2),
      ]);
      s = play(s, [const DartHit(19, 3)]);
      final decoded =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(decoded.scores, s.scores);
      expect(decoded.currentPlayerId, s.currentPlayerId);
      expect(decoded.visit, s.visit);
      expect(decoded.visitStartScore, s.visitStartScore);
      expect(decoded.dartsThrown, s.dartsThrown);
      expect(decoded.dartsPerVisit, s.dartsPerVisit);
      expect(decoded.lastVisit!.playerId, s.lastVisit!.playerId);
      expect(decoded.lastVisit!.darts, s.lastVisit!.darts);
      expect(decoded.lastVisit!.busted, s.lastVisit!.busted);
      expect(decoded.lastVisit!.total, s.lastVisit!.total);
      expect(decoded.winnerId, isNull);
    });

    test('a finished state round-trips with its winner', () {
      var s = scored(fresh(), p1: 40);
      s = play(s, [const DartHit(20, 2)]);
      final decoded =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(decoded.winnerId, 'p1');
      expect(game.outcome(decoded)!.winnerId, 'p1');
    });

    test('a fresh state round-trips with no last visit', () {
      final decoded = game.decodeState(
          game.encodeState(fresh()), game.stateSchemaVersion);
      expect(decoded.lastVisit, isNull);
      expect(decoded.scoreOf('p2'), 501);
    });

    test('moves round-trip through json', () {
      for (final hit in [
        const DartHit(20, 3),
        const DartHit(25, 2),
        DartHit.miss,
      ]) {
        const playerId = 'p1';
        final move = DartsMove(playerId: playerId, hit: hit);
        final decoded = game.decodeMove(game.encodeMove(move));
        expect(decoded.playerId, playerId);
        expect(decoded.hit, hit);
      }
    });

    test('the game id is stable', () {
      expect(game.id, 'darts');
    });
  });

  test('a whole match can be driven through a MatchController', () async {
    final transport = LocalTransport();
    final controller = await MatchController.create<DartsState, DartsMove>(
      game: game,
      transport: transport,
      matchId: 'm1',
      playerIds: players,
      localPlayerId: 'p1',
      hotSeat: true,
      seed: 1,
    );
    expect(
      await controller.submitMove(
        const DartsMove(playerId: 'p1', hit: DartHit(20, 3)),
      ),
      isTrue,
    );
    expect(controller.state!.scoreOf('p1'), 441);
    // A move attributed to the wrong seat is rejected by the reducer.
    expect(
      await controller.submitMove(
        const DartsMove(playerId: 'p2', hit: DartHit(20, 3)),
      ),
      isFalse,
    );
    await controller.dispose();
    transport.dispose();
  });
}
