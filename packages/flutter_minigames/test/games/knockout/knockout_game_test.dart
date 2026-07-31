import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/knockout/knockout.dart';
import 'package:flutter_minigames/src/core/core.dart';

/// Knockout is a SIMULTANEOUS-release game: both sides wind up every puck they
/// own, and only the second commit (the resolution) moves anything. These tests
/// pin that two-commit round, since the reducer is the trust boundary — it
/// takes the resolver's settled positions on faith and never re-simulates.
void main() {
  const game = KnockoutGame(pucksPerPlayer: 3);

  KnockoutState fresh() =>
      game.initialState(seed: 0, playerIds: const ['p1', 'p2']);

  // Snapshot every current live puck as a carried-over (unmoved) position.
  List<KnockoutPosition> carry(KnockoutState s,
          {Set<String> fell = const {}}) =>
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

  // A full wind-up for [owner]: one aim per live puck they own.
  List<KnockoutAim> aimsFor(KnockoutState s, String owner) => [
        for (final p in s.pucksOf(owner))
          KnockoutAim(puckId: p.id, ix: 0, iy: -1),
      ];

  /// The opening commit — aims only, nothing moves.
  KnockoutMove open(KnockoutState s, String owner) =>
      KnockoutMove(owner: owner, aims: aimsFor(s, owner));

  /// The resolving commit — aims plus the settled outcome.
  KnockoutMove resolve(
    KnockoutState s,
    String owner, {
    Set<String> fell = const {},
  }) =>
      KnockoutMove(
        owner: owner,
        aims: aimsFor(s, owner),
        positions: carry(s, fell: fell),
      );

  /// Play one whole round: opener commits, responder resolves with [fell].
  KnockoutState playRound(KnockoutState s, {Set<String> fell = const {}}) {
    final opener = s.currentPlayerId;
    final responder = s.playerIds.firstWhere((p) => p != opener);
    s = game.applyMove(s, open(s, opener));
    return game.applyMove(s, resolve(s, responder, fell: fell));
  }

  group('setup + round flow', () {
    test('opens with 3 pucks each, p1 to move, no outcome', () {
      final s = fresh();
      expect(s.liveCountOf('p1'), 3);
      expect(s.liveCountOf('p2'), 3);
      expect(game.currentPlayer(s), 'p1');
      expect(game.outcome(s), isNull);
      expect(s.awaitingResolution, isFalse);
      // Halves are separated: p1 near (high ny), p2 far (low ny).
      expect(s.pucksOf('p1').every((p) => p.ny > 0.5), isTrue);
      expect(s.pucksOf('p2').every((p) => p.ny < 0.5), isTrue);
    });

    test('the opening commit moves nothing and parks the aims', () {
      var s = fresh();
      final before = {for (final p in s.pucks) p.id: (p.nx, p.ny)};

      s = game.applyMove(s, open(s, 'p1'));

      expect(game.currentPlayer(s), 'p2',
          reason: 'turn passes to the responder');
      expect(s.awaitingResolution, isTrue);
      expect(s.hasCommitted('p1'), isTrue);
      expect(s.pendingAims.length, 3, reason: 'one aim per live puck');
      for (final p in s.pucks) {
        expect((p.nx, p.ny), before[p.id],
            reason: 'nothing moves until the round releases');
      }
    });

    test('the resolving commit applies the outcome and clears the aims', () {
      var s = fresh();
      s = game.applyMove(s, open(s, 'p1'));
      s = game.applyMove(s, resolve(s, 'p2', fell: {'p1-0'}));

      expect(s.awaitingResolution, isFalse);
      expect(s.pendingAims, isEmpty);
      expect(s.pendingAimOwner, isNull);
      expect(s.liveCountOf('p1'), 2, reason: 'the fallen puck is gone');
    });

    test('the resolver opens the next round, so first-mover alternates', () {
      var s = fresh();
      s = playRound(s); // p1 opened, p2 resolved
      expect(game.currentPlayer(s), 'p2');
      s = playRound(s); // p2 opened, p1 resolved
      expect(game.currentPlayer(s), 'p1');
    });

    test('losing pucks shortens the next wind-up', () {
      var s = fresh();
      s = playRound(s, fell: {'p2-0'});
      expect(s.liveCountOf('p2'), 2);
      expect(s.pendingPucks().length, 2,
          reason: 'p2 winds up only the pucks they still have');
    });
  });

  group('fall removal (the core reducer)', () {
    test('a puck knocked off is eliminated, whoever owns it', () {
      var s = fresh();
      s = playRound(s, fell: {'p2-1', 'p1-0'});
      expect(s.pucks.any((p) => p.id == 'p2-1'), isFalse);
      expect(s.pucks.any((p) => p.id == 'p1-0'), isFalse);
      expect(s.liveCountOf('p2'), 2);
      expect(s.liveCountOf('p1'), 2);
    });

    test('a simultaneous release can clear several pucks at once', () {
      var s = fresh();
      s = playRound(s, fell: {'p2-0', 'p2-1', 'p1-2'});
      expect(s.liveCountOf('p2'), 1);
      expect(s.liveCountOf('p1'), 2);
    });
  });

  group('shot classification', () {
    test('clean hit vs own goal vs miss, relative to the resolver', () {
      var s = fresh();
      s = game.applyMove(s, open(s, 'p1'));

      final clean = game.classifyShot(s, resolve(s, 'p2', fell: {'p1-0'}));
      expect(clean.isCleanHit, isTrue);
      expect(clean.oppKnocked, 1);

      final own = game.classifyShot(s, resolve(s, 'p2', fell: {'p2-1'}));
      expect(own.isOwnGoal, isTrue);
      expect(own.ownLost, 1);

      final miss = game.classifyShot(s, resolve(s, 'p2'));
      expect(miss.isMiss, isTrue);
    });
  });

  group('win detection', () {
    test('clearing the opponent to zero wins', () {
      var s = fresh();
      s = playRound(s, fell: {'p2-0', 'p2-1', 'p2-2'});
      expect(s.liveCountOf('p2'), 0);
      expect(game.outcome(s), const GameOutcome.win('p1'));
    });

    test('losing your own last pucks hands the win to the opponent', () {
      var s = fresh();
      s = playRound(s, fell: {'p1-0', 'p1-1', 'p1-2'});
      expect(s.liveCountOf('p1'), 0);
      expect(game.outcome(s), const GameOutcome.win('p2'));
    });

    test('both sides cleared in the same release is a draw', () {
      var s = fresh();
      s = playRound(s, fell: {
        'p1-0', 'p1-1', 'p1-2', //
        'p2-0', 'p2-1', 'p2-2',
      });
      expect(game.outcome(s), const GameOutcome.draw());
    });
  });

  group('validation', () {
    test('accepts a full wind-up from the player to move', () {
      final s = fresh();
      expect(game.validateMove(s, open(s, 'p1'), 'p1'), isTrue);
    });

    test('rejects out-of-turn', () {
      final s = fresh();
      expect(game.validateMove(s, open(s, 'p2'), 'p2'), isFalse);
    });

    test('rejects a partial wind-up — a round is all pucks or nothing', () {
      final s = fresh();
      final partial = KnockoutMove(
        owner: 'p1',
        aims: aimsFor(s, 'p1').take(2).toList(),
      );
      expect(game.validateMove(s, partial, 'p1'), isFalse);
    });

    test('rejects aiming a puck you do not own', () {
      final s = fresh();
      final bad = KnockoutMove(
        owner: 'p1',
        aims: const [
          KnockoutAim(puckId: 'p1-0', ix: 0, iy: -1),
          KnockoutAim(puckId: 'p1-1', ix: 0, iy: -1),
          KnockoutAim(puckId: 'p2-0', ix: 0, iy: -1), // not p1's
        ],
      );
      expect(game.validateMove(s, bad, 'p1'), isFalse);
    });

    test('rejects two aims for the same puck', () {
      final s = fresh();
      final bad = KnockoutMove(
        owner: 'p1',
        aims: const [
          KnockoutAim(puckId: 'p1-0', ix: 0, iy: -1),
          KnockoutAim(puckId: 'p1-0', ix: 1, iy: 0),
          KnockoutAim(puckId: 'p1-1', ix: 0, iy: -1),
        ],
      );
      expect(game.validateMove(s, bad, 'p1'), isFalse);
    });

    test('rejects an opening commit that claims positions', () {
      final s = fresh();
      final bad = KnockoutMove(
        owner: 'p1',
        aims: aimsFor(s, 'p1'),
        positions: carry(s, fell: {'p2-0'}),
      );
      expect(
        game.validateMove(s, bad, 'p1'),
        isFalse,
        reason: 'the opener cannot move pucks — nothing has released yet',
      );
    });

    test('rejects a resolution that drops a live puck from the report', () {
      var s = fresh();
      s = game.applyMove(s, open(s, 'p1'));
      final incomplete = KnockoutMove(
        owner: 'p2',
        aims: aimsFor(s, 'p2'),
        positions: carry(s).where((p) => p.id != 'p1-0').toList(),
      );
      expect(game.validateMove(s, incomplete, 'p2'), isFalse);
    });

    test('rejects out-of-bounds on-platform positions', () {
      var s = fresh();
      s = game.applyMove(s, open(s, 'p1'));
      final bad = KnockoutMove(
        owner: 'p2',
        aims: aimsFor(s, 'p2'),
        positions: [
          for (final p in carry(s))
            if (p.id == 'p2-0')
              KnockoutPosition(
                  id: p.id, owner: p.owner, nx: 1.4, ny: 0.5, fell: false)
            else
              p,
        ],
      );
      expect(game.validateMove(s, bad, 'p2'), isFalse);
    });

    test('rejects moves once the game is over', () {
      var s = fresh();
      s = playRound(s, fell: {'p2-0', 'p2-1', 'p2-2'});
      expect(game.outcome(s), isNotNull);
      expect(game.validateMove(s, open(s, 'p2'), 'p2'), isFalse);
    });
  });

  group('serialization', () {
    test('a mid-round state round-trips with its pending aims', () {
      var s = fresh();
      s = game.applyMove(s, open(s, 'p1'));

      final decoded =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);

      expect(decoded.pucks.length, s.pucks.length);
      expect(decoded.currentPlayerId, s.currentPlayerId);
      expect(decoded.frame, s.frame);
      expect(decoded.pucksPerPlayer, s.pucksPerPlayer);
      // The parked wind-up MUST survive the trip: it is the only copy of the
      // opener's shots, and the responder needs it to run the release.
      expect(decoded.pendingAimOwner, 'p1');
      expect(decoded.pendingAims.length, 3);
      expect(decoded.awaitingResolution, isTrue);
      final a = decoded.pendingAims.firstWhere((a) => a.puckId == 'p1-0');
      final b = s.pendingAims.firstWhere((a) => a.puckId == 'p1-0');
      expect(a.ix, b.ix);
      expect(a.iy, b.iy);
    });

    test('a resolving move round-trips with aims and positions', () {
      var s = fresh();
      s = game.applyMove(s, open(s, 'p1'));
      final move = resolve(s, 'p2', fell: {'p1-1'});

      final decoded = game.decodeMove(game.encodeMove(move));

      expect(decoded.owner, move.owner);
      expect(decoded.isResolution, isTrue);
      expect(decoded.aims.length, move.aims.length);
      expect(decoded.positions.length, move.positions.length);
      expect(decoded.positions.firstWhere((p) => p.id == 'p1-1').fell, isTrue);
    });

    test('an opening move round-trips as a non-resolution', () {
      final s = fresh();
      final decoded = game.decodeMove(game.encodeMove(open(s, 'p1')));
      expect(decoded.isResolution, isFalse);
      expect(decoded.positions, isEmpty);
      expect(decoded.aims.length, 3);
    });
  });
}
