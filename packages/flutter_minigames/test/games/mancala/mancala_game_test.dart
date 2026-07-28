import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/mancala/mancala.dart';
import 'package:flutter_minigames/src/core/core.dart';

const capture = MancalaGame(seedsPerPit: 4, mode: MancalaMode.capture);
const avalanche = MancalaGame(seedsPerPit: 4, mode: MancalaMode.avalanche);

MancalaState fresh([MancalaGame g = capture, int seed = 0]) =>
    g.initialState(seed: seed, playerIds: const ['s', 'n']);

/// A board built from explicit pit counts, so a rule can be tested in isolation
/// rather than by playing into the situation.
MancalaState board(Map<int, int> counts, {String turn = 's'}) {
  final pits = List<int>.filled(MancalaState.pitCount, 0);
  counts.forEach((k, v) => pits[k] = v);
  return MancalaState(
    pits: pits,
    playerIds: const ['s', 'n'],
    currentPlayerId: turn,
  );
}

void main() {
  group('opening', () {
    test('is scattered, not four flat', () {
      final s = fresh();
      final south = [for (var i = 0; i < 6; i++) s.pits[i]];
      expect(south.toSet().length, greaterThan(1),
          reason: 'a flat opening is the old behaviour');
    });

    test('both sides get the same counts, so nobody starts ahead', () {
      for (final seed in [0, 1, 7, 42, 1234]) {
        final s = fresh(capture, seed);
        for (var i = 0; i < 6; i++) {
          expect(s.pits[i], s.pits[7 + i],
              reason: 'seed $seed: pit $i is not mirrored');
        }
      }
    });

    test('the total is preserved and every pit is playable', () {
      for (final seed in [0, 3, 9, 77, 5000]) {
        final s = fresh(capture, seed);
        var south = 0;
        for (var i = 0; i < 6; i++) {
          expect(s.pits[i], greaterThan(0),
              reason: 'seed $seed: pit $i is empty at the start');
          south += s.pits[i];
        }
        expect(south, 24, reason: 'seed $seed: side total drifted');
        expect(s.pits[MancalaState.southStore], 0);
        expect(s.pits[MancalaState.northStore], 0);
      }
    });

    test('is deterministic per seed and differs between seeds', () {
      expect(MancalaGame.scatterOpening(seed: 5),
          MancalaGame.scatterOpening(seed: 5));
      var different = 0;
      for (var seed = 1; seed <= 30; seed++) {
        if (MancalaGame.scatterOpening(seed: seed).toString() !=
            MancalaGame.scatterOpening(seed: 0).toString()) {
          different++;
        }
      }
      expect(different, greaterThan(20), reason: 'seeds barely vary the board');
    });

    test('south is to move and may play any pit', () {
      final s = fresh();
      expect(capture.currentPlayer(s), 's');
      expect(capture.legalPits(s, 's'), [0, 1, 2, 3, 4, 5]);
    });
  });

  group('shared by both modes', () {
    test('sowing skips the opponent store', () {
      // South sows 3 from pit 5: store(6), 7, 8 — never 13.
      // Pit 0 keeps south alive; emptying a whole side triggers the sweep and
      // would clear north before we could look at it.
      var s = board({5: 3, 0: 1, 9: 1}, turn: 's');
      s = capture.applyMove(s, const MancalaMove(5));
      expect(s.pits[MancalaState.southStore], 1);
      expect(s.pits[7], 1);
      expect(s.pits[8], 1);
      expect(s.pits[MancalaState.northStore], 0);
    });

    test('last seed in your own store grants an extra turn', () {
      for (final g in [capture, avalanche]) {
        var s = board({4: 2, 9: 1}, turn: 's'); // 5, then store
        s = g.applyMove(s, const MancalaMove(4));
        expect(s.pits[MancalaState.southStore], 1, reason: '${g.mode}');
        expect(s.lastExtraTurn, isTrue, reason: '${g.mode}');
        expect(g.currentPlayer(s), 's', reason: '${g.mode}');
      }
    });

    test('a side running dry sweeps the other side and ends the game', () {
      // South plays its last seed into its store; north still holds seeds.
      var s = board({5: 1, 8: 2, 10: 3}, turn: 's');
      s = capture.applyMove(s, const MancalaMove(5));
      for (var i = 7; i < 13; i++) {
        expect(s.pits[i], 0, reason: 'north should have been swept');
      }
      expect(s.pits[MancalaState.northStore], 5);
      expect(capture.outcome(s), isNotNull);
    });

    test('higher store wins once both sides are empty', () {
      final s = board({
        MancalaState.southStore: 20,
        MancalaState.northStore: 10,
      });
      expect(capture.outcome(s), const GameOutcome.win('s'));
    });

    test('rejects an empty pit, opponent pits, and out-of-turn play', () {
      final s = board({0: 0, 1: 3, 8: 2}, turn: 's');
      expect(capture.validateMove(s, const MancalaMove(0), 's'), isFalse);
      expect(capture.validateMove(s, const MancalaMove(8), 's'), isFalse);
      expect(capture.validateMove(s, const MancalaMove(1), 'n'), isFalse);
      expect(capture.validateMove(s, const MancalaMove(1), 's'), isTrue);
    });
  });

  group('capture mode', () {
    test('landing in an empty own pit takes it and the pit opposite', () {
      // Pit 0 has 1 → lands in empty pit 1. Opposite of 1 is 11.
      var s = board({0: 1, 11: 4, 9: 1}, turn: 's');
      s = capture.applyMove(s, const MancalaMove(0));
      expect(s.lastWasCapture, isTrue);
      expect(s.lastCaptured, 5, reason: '4 opposite + the landing seed');
      expect(s.pits[MancalaState.southStore], 5);
      expect(s.pits[1], 0);
      expect(s.pits[11], 0);
      expect(capture.currentPlayer(s), 'n', reason: 'a capture ends the turn');
    });

    test('an empty own pit with nothing opposite is not a capture', () {
      var s = board({0: 1, 11: 0, 9: 1}, turn: 's');
      s = capture.applyMove(s, const MancalaMove(0));
      expect(s.lastWasCapture, isFalse);
      expect(s.pits[1], 1, reason: 'the seed stays put');
      expect(capture.currentPlayer(s), 'n');
    });

    test('landing in an occupied pit does NOT relay — one sow, one pass', () {
      // Pit 0 has 1 → lands on pit 1 which already holds 2, making it 3.
      // Avalanche would scoop those 3 and carry on; capture must not.
      var s = board({0: 1, 1: 2, 9: 1}, turn: 's');
      s = capture.applyMove(s, const MancalaMove(0));
      expect(s.pits[1], 3, reason: 'the stack was scooped — that is avalanche');
      expect(s.pits[2], 0);
      expect(s.lastPath, [1]);
      expect(capture.currentPlayer(s), 'n');
    });

    test('landing on the opponent side never captures', () {
      // Pit 5 has 3: store, 7, 8. Pit 8 is empty and belongs to north.
      var s = board({5: 3, 2: 1, 8: 0}, turn: 's');
      s = capture.applyMove(s, const MancalaMove(5));
      expect(s.lastWasCapture, isFalse);
      expect(s.pits[8], 1);
    });
  });

  group('avalanche mode', () {
    test('landing on an occupied pit scoops it and keeps sowing', () {
      // Pit 0 has 1 → pit 1 (2 → 3) → scoop 3 → pits 2, 3, 4.
      var s = board({0: 1, 1: 2, 9: 1}, turn: 's');
      s = avalanche.applyMove(s, const MancalaMove(0));
      expect(s.pits[1], 0, reason: 'the landing pit was scooped');
      expect(s.pits[2], 1);
      expect(s.pits[3], 1);
      expect(s.pits[4], 1);
      expect(s.lastPath, [1, 2, 3, 4]);
    });

    test('the chain ends when a seed lands in an empty pit', () {
      var s = board({0: 1, 1: 0, 9: 1}, turn: 's');
      s = avalanche.applyMove(s, const MancalaMove(0));
      expect(s.pits[1], 1);
      expect(avalanche.currentPlayer(s), 'n');
    });

    test('it relays off the opponent pits too, not just your own', () {
      // Pit 5 has 2: store(6) then 7. Pit 7 holds 1 → 2 → scoop → 8, 9.
      // Pit 0 keeps south alive so the sweep doesn't fire mid-assertion.
      var s = board({5: 2, 0: 1, 7: 1, 11: 1}, turn: 's');
      s = avalanche.applyMove(s, const MancalaMove(5));
      expect(s.pits[7], 0, reason: 'north pit should have been scooped');
      expect(s.pits[8], 1);
      expect(s.pits[9], 1);
    });

    test('there is no capturing at all', () {
      // The capture-mode setup: lands in an empty own pit with 4 opposite.
      var s = board({0: 1, 11: 4, 9: 1}, turn: 's');
      s = avalanche.applyMove(s, const MancalaMove(0));
      expect(s.lastWasCapture, isFalse);
      expect(s.lastCaptured, 0);
      expect(s.pits[11], 4, reason: 'the opposite pit must be untouched');
      expect(s.pits[MancalaState.southStore], 0);
    });

    test('a chain conserves seeds — nothing is created or lost', () {
      var s = board({4: 3, 1: 2, 9: 1}, turn: 's');
      final before = s.pits.reduce((a, b) => a + b);
      s = avalanche.applyMove(s, const MancalaMove(4));
      expect(s.pits.reduce((a, b) => a + b), before);
    });
  });

  group('serialization', () {
    test('state survives encode/decode in both modes', () {
      for (final g in [capture, avalanche]) {
        var s = fresh(g);
        s = g.applyMove(s, MancalaMove(g.legalPits(s, 's').first));
        final back = g.decodeState(g.encodeState(s), g.stateSchemaVersion);
        expect(back.pits, s.pits, reason: '${g.mode}');
        expect(back.currentPlayerId, s.currentPlayerId);
        expect(back.lastPath, s.lastPath);
        expect(back.lastWasCapture, s.lastWasCapture);
        expect(back.lastCaptured, s.lastCaptured);
      }
    });

    test('move round-trips', () {
      expect(
          capture.decodeMove(capture.encodeMove(const MancalaMove(3))).pit, 3);
    });
  });

  test('a full match runs to a result in either mode', () async {
    for (final g in [capture, avalanche]) {
      final controller =
          await MatchController.create<MancalaState, MancalaMove>(
        game: g,
        transport: LocalTransport(),
        matchId: 'mc-${g.mode.name}',
        playerIds: const ['s', 'n'],
        localPlayerId: 's',
        hotSeat: true,
        seed: 4,
      );
      var guard = 0;
      while (g.outcome(controller.state!) == null && guard < 400) {
        guard++;
        final s = controller.state!;
        final legal = g.legalPits(s, s.currentPlayerId);
        if (legal.isEmpty) break;
        await controller.submitMove(MancalaMove(legal.first));
      }
      expect(g.outcome(controller.state!), isNotNull,
          reason: '${g.mode} never terminated');
    }
  });
}
