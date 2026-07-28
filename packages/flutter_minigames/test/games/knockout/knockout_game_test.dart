import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/knockout/knockout.dart';
import 'package:flutter_minigames/src/core/core.dart';

void main() {
  const game = KnockoutGame(pucksPerPlayer: 3);

  KnockoutState fresh() =>
      game.initialState(seed: 0, playerIds: const ['p1', 'p2']);

  // Snapshot every current live puck as a carried-over (unmoved) position.
  List<KnockoutPosition> carry(KnockoutState s, {Set<String> fell = const {}}) =>
      [
        for (final p in s.pucks)
          KnockoutPosition(
            id: p.id,
            owner: p.owner,
            nx: p.nx,
            ny: p.ny,
            fell: fell.contains(p.id),
          ),
      ];

  // A flick by [owner] of [flickedId] whose settled outcome is every current
  // puck in place, except those in [fell] (removed off the platform).
  KnockoutMove flick(
    KnockoutState s,
    String owner,
    String flickedId, {
    Set<String> fell = const {},
  }) =>
      KnockoutMove(
        flickedPuckId: flickedId,
        owner: owner,
        positions: carry(s, fell: fell),
      );

  group('setup + turn flow', () {
    test('opens with 3 pucks each, p1 to move, no outcome', () {
      final s = fresh();
      expect(s.liveCountOf('p1'), 3);
      expect(s.liveCountOf('p2'), 3);
      expect(game.currentPlayer(s), 'p1');
      expect(game.outcome(s), isNull);
      // Halves are separated: p1 near (high ny), p2 far (low ny).
      expect(s.pucksOf('p1').every((p) => p.ny > 0.5), isTrue);
      expect(s.pucksOf('p2').every((p) => p.ny < 0.5), isTrue);
    });

    test('turns alternate on a flick that changes nothing', () {
      var s = fresh();
      s = game.applyMove(s, flick(s, 'p1', 'p1-0'));
      expect(game.currentPlayer(s), 'p2');
      s = game.applyMove(s, flick(s, 'p2', 'p2-0'));
      expect(game.currentPlayer(s), 'p1');
    });
  });

  group('fall removal (the core reducer)', () {
    test('an opponent puck knocked off is eliminated', () {
      var s = fresh();
      s = game.applyMove(s, flick(s, 'p1', 'p1-0', fell: {'p2-1'}));
      expect(s.pucks.any((p) => p.id == 'p2-1'), isFalse);
      expect(s.liveCountOf('p2'), 2);
      expect(s.liveCountOf('p1'), 3, reason: 'no own puck lost');
    });

    test('an own puck knocked off is eliminated (own goal)', () {
      var s = fresh();
      // p1 flicks p1-0 and it flies off the far lip itself.
      s = game.applyMove(s, flick(s, 'p1', 'p1-0', fell: {'p1-0'}));
      expect(s.pucks.any((p) => p.id == 'p1-0'), isFalse);
      expect(s.liveCountOf('p1'), 2);
      expect(s.liveCountOf('p2'), 3);
    });

    test('a flick can knock off both an own and an opponent puck', () {
      var s = fresh();
      s = game.applyMove(s, flick(s, 'p1', 'p1-0', fell: {'p1-0', 'p2-2'}));
      expect(s.liveCountOf('p1'), 2);
      expect(s.liveCountOf('p2'), 2);
    });
  });

  group('shot classification', () {
    test('clean hit vs own goal vs miss', () {
      final s = fresh();
      final clean = game.classifyShot(s, flick(s, 'p1', 'p1-0', fell: {'p2-0'}));
      expect(clean.isCleanHit, isTrue);
      expect(clean.oppKnocked, 1);

      final own = game.classifyShot(s, flick(s, 'p1', 'p1-0', fell: {'p1-1'}));
      expect(own.isOwnGoal, isTrue);
      expect(own.ownLost, 1);

      final miss = game.classifyShot(s, flick(s, 'p1', 'p1-0'));
      expect(miss.isMiss, isTrue);
    });
  });

  group('win detection', () {
    test('clearing the opponent to zero wins', () {
      var s = fresh();
      // p1 clears all three of p2's pucks over successive flicks.
      s = game.applyMove(s, flick(s, 'p1', 'p1-0', fell: {'p2-0'}));
      s = game.applyMove(s, flick(s, 'p2', 'p2-1')); // p2 does nothing
      s = game.applyMove(s, flick(s, 'p1', 'p1-1', fell: {'p2-1'}));
      expect(game.outcome(s), isNull);
      s = game.applyMove(s, flick(s, 'p2', 'p2-2'));
      s = game.applyMove(s, flick(s, 'p1', 'p1-2', fell: {'p2-2'}));
      expect(s.liveCountOf('p2'), 0);
      expect(game.outcome(s), const GameOutcome.win('p1'));
    });

    test('knocking off your own last puck hands the win to the opponent', () {
      var s = game.initialState(seed: 0, playerIds: const ['p1', 'p2']);
      // Reduce p1 to a single puck, then p1 knocks that one off.
      s = game.applyMove(s, flick(s, 'p1', 'p1-0', fell: {'p1-1', 'p1-2'}));
      s = game.applyMove(s, flick(s, 'p2', 'p2-0'));
      expect(s.liveCountOf('p1'), 1);
      s = game.applyMove(s, flick(s, 'p1', 'p1-0', fell: {'p1-0'}));
      expect(s.liveCountOf('p1'), 0);
      expect(game.outcome(s), const GameOutcome.win('p2'));
    });

    test('both sides cleared on the same flick is a draw', () {
      var s = game.initialState(seed: 0, playerIds: const ['p1', 'p2']);
      // Whittle both down to one puck each without ending the game.
      s = game.applyMove(s, flick(s, 'p1', 'p1-0', fell: {'p1-1', 'p1-2'}));
      s = game.applyMove(s, flick(s, 'p2', 'p2-0', fell: {'p2-1', 'p2-2'}));
      expect(s.liveCountOf('p1'), 1);
      expect(s.liveCountOf('p2'), 1);
      // p1's flick clears both last pucks (own + opponent) simultaneously.
      s = game.applyMove(s, flick(s, 'p1', 'p1-0', fell: {'p1-0', 'p2-0'}));
      expect(game.outcome(s), const GameOutcome.draw());
    });
  });

  group('validation', () {
    test('accepts a well-formed flick of an own live puck', () {
      final s = fresh();
      expect(game.validateMove(s, flick(s, 'p1', 'p1-0'), 'p1'), isTrue);
    });

    test('rejects out-of-turn', () {
      final s = fresh();
      expect(game.validateMove(s, flick(s, 'p2', 'p2-0'), 'p2'), isFalse);
    });

    test('rejects flicking an opponent puck', () {
      final s = fresh();
      final bad = KnockoutMove(
        flickedPuckId: 'p2-0', // not p1's
        owner: 'p1',
        positions: carry(s),
      );
      expect(game.validateMove(s, bad, 'p1'), isFalse);
    });

    test('rejects flicking a dead puck', () {
      var s = fresh();
      s = game.applyMove(s, flick(s, 'p1', 'p1-0', fell: {'p1-0'}));
      s = game.applyMove(s, flick(s, 'p2', 'p2-0'));
      // p1-0 is gone; p1 tries to flick it again.
      final bad = KnockoutMove(
        flickedPuckId: 'p1-0',
        owner: 'p1',
        positions: carry(s),
      );
      expect(game.validateMove(s, bad, 'p1'), isFalse);
    });

    test('rejects a move that drops a live puck from the report', () {
      final s = fresh();
      final incomplete = KnockoutMove(
        flickedPuckId: 'p1-0',
        owner: 'p1',
        positions: carry(s).where((p) => p.id != 'p2-0').toList(),
      );
      expect(game.validateMove(s, incomplete, 'p1'), isFalse);
    });

    test('rejects out-of-bounds on-platform positions', () {
      final s = fresh();
      final bad = KnockoutMove(
        flickedPuckId: 'p1-0',
        owner: 'p1',
        positions: [
          for (final p in carry(s))
            if (p.id == 'p1-0')
              KnockoutPosition(
                  id: p.id, owner: p.owner, nx: 1.4, ny: 0.5, fell: false)
            else
              p,
        ],
      );
      expect(game.validateMove(s, bad, 'p1'), isFalse);
    });

    test('rejects moves once the game is over', () {
      var s = game.initialState(seed: 0, playerIds: const ['p1', 'p2']);
      s = game.applyMove(s, flick(s, 'p1', 'p1-0', fell: {'p2-0', 'p2-1', 'p2-2'}));
      expect(game.outcome(s), isNotNull);
      expect(game.validateMove(s, flick(s, 'p2', 'p2-0'), 'p2'), isFalse);
    });
  });

  group('serialization', () {
    test('state round-trips through JSON', () {
      var s = fresh();
      s = game.applyMove(s, flick(s, 'p1', 'p1-0', fell: {'p2-0'}));
      final decoded =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(decoded.pucks.length, s.pucks.length);
      expect(decoded.currentPlayerId, s.currentPlayerId);
      expect(decoded.liveCountOf('p2'), s.liveCountOf('p2'));
      expect(decoded.frame, s.frame);
      expect(decoded.pucksPerPlayer, s.pucksPerPlayer);
    });

    test('move round-trips through JSON', () {
      final s = fresh();
      final move = flick(s, 'p1', 'p1-0', fell: {'p2-1'});
      final decoded = game.decodeMove(game.encodeMove(move));
      expect(decoded.flickedPuckId, move.flickedPuckId);
      expect(decoded.owner, move.owner);
      expect(decoded.positions.length, move.positions.length);
      expect(
        decoded.positions.firstWhere((p) => p.id == 'p2-1').fell,
        isTrue,
      );
    });
  });
}
