import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_mancala/minigame_mancala.dart';
import 'package:minigames_core/minigames_core.dart';

void main() {
  const game = MancalaGame(seedsPerPit: 4);
  MancalaState fresh() =>
      game.initialState(seed: 0, playerIds: const ['s', 'n']);

  group('MancalaGame', () {
    test('opening: south to move, 4 in each side pit, empty stores', () {
      final s = fresh();
      expect(game.currentPlayer(s), 's');
      expect(s.pits[MancalaState.southStore], 0);
      expect(s.pits[MancalaState.northStore], 0);
      for (var i = 0; i < 6; i++) {
        expect(s.pits[i], 4);
        expect(s.pits[7 + i], 4);
      }
      expect(game.legalPits(s, 's'), [0, 1, 2, 3, 4, 5]);
    });

    test('sow distributes and skips opponent store', () {
      // Isolated sow that ends on empty: no relay.
      final pits = List<int>.filled(14, 0);
      pits[0] = 2; // → 1, then 2 (empty land)
      pits[8] = 1; // keep north alive
      var s = MancalaState(
        pits: pits,
        playerIds: const ['s', 'n'],
        currentPlayerId: 's',
      );
      s = game.applyMove(s, const MancalaMove(0));
      expect(s.pits[0], 0);
      expect(s.pits[1], 1);
      expect(s.pits[2], 1);
      expect(s.lastPath, [1, 2]);
      expect(game.currentPlayer(s), 'n');
    });

    test('last seed in own store grants free re-pick (extra turn)', () {
      var s = fresh();
      // Pit 2 with 4 seeds: 3,4,5,6 — last in store.
      s = game.applyMove(s, const MancalaMove(2));
      expect(s.lastExtraTurn, isTrue);
      expect(game.currentPlayer(s), 's');
      expect(s.pits[MancalaState.southStore], 1);
    });

    test('last seed in occupied pit picks up stack and keeps sowing', () {
      // South pit 0 has 1 → lands on pit 1 which already has 2.
      // After land, pit 1 has 3 → pick up all 3 and continue → 2,3,4.
      final pits = List<int>.filled(14, 0);
      pits[0] = 1;
      pits[1] = 2;
      pits[9] = 1; // keep north alive (not opposite of final land 4→8)
      var s = MancalaState(
        pits: pits,
        playerIds: const ['s', 'n'],
        currentPlayerId: 's',
      );
      s = game.applyMove(s, const MancalaMove(0));
      // Path: deposit 1, pick up 3 from 1, deposit 2,3,4.
      expect(s.lastPath, [1, 2, 3, 4]);
      expect(s.pits[0], 0);
      expect(s.pits[1], 0); // emptied when picked up
      expect(s.pits[2], 1);
      expect(s.pits[3], 1);
      expect(s.pits[4], 1);
      // Ended on empty 4 → no free re-pick; turn passes.
      expect(s.lastExtraTurn, isFalse);
      expect(game.currentPlayer(s), 'n');
    });

    test('relay does not grant free re-pick mid-chain', () {
      var s = fresh();
      // Opening 5: first hand ends on occupied 9 → auto-picks 9 and continues;
      // must not just "Again!" without continuing the sow.
      s = game.applyMove(s, const MancalaMove(5));
      expect(s.lastPath.length, greaterThan(4)); // longer than single hand
      expect(s.pits[9], 0); // stack was picked up
    });

    test('last seed in empty pit ends turn (no extra) when no capture', () {
      final pits = List<int>.filled(14, 0);
      pits[0] = 1;
      pits[8] = 2; // keep north alive, not opposite of landing
      // 0 → lands on empty 1; no stones opposite (12 empty) → turn passes.
      var s = MancalaState(
        pits: pits,
        playerIds: const ['s', 'n'],
        currentPlayerId: 's',
      );
      s = game.applyMove(s, const MancalaMove(0));
      expect(s.pits[1], 1);
      expect(s.lastExtraTurn, isFalse);
      expect(s.lastWasCapture, isFalse);
      expect(game.currentPlayer(s), 'n');
    });

    test('capture from empty own pit takes opposite', () {
      // Craft: south pit 0 has 1 stone, opposite 12 has 3, rest empty on south.
      final pits = List<int>.filled(14, 0);
      pits[0] = 1;
      pits[12] = 3;
      pits[7] = 1; // north still has a move source if needed
      var s = MancalaState(
        pits: pits,
        playerIds: const ['s', 'n'],
        currentPlayerId: 's',
      );
      s = game.applyMove(s, const MancalaMove(0));
      // 1 seed goes to pit 1 — wait, from 0 with 1 seed goes to cup 1, not capture.
      // Need last land on empty own: pit 0 with 1 → lands on 1 if 1 empty.
      // For land on 0: need to sow into 0 as last — e.g. from somewhere.
      // Simpler: pit 5 has 1 seed, land on store? that's extra turn.
      // pit 4 has 1 seed → lands on 5 if 5 empty → capture opposite 7.
      final pits2 = List<int>.filled(14, 0);
      pits2[4] = 1;
      pits2[7] = 4; // opposite of 5
      // keep north playable so not terminal weirdness — actually after move
      // south pits all empty except we land on 5 then capture clears 5 and 7.
      pits2[8] = 2;
      s = MancalaState(
        pits: pits2,
        playerIds: const ['s', 'n'],
        currentPlayerId: 's',
      );
      s = game.applyMove(s, const MancalaMove(4));
      expect(s.lastWasCapture, isTrue);
      expect(s.pits[5], 0);
      expect(s.pits[7], 0);
      expect(s.pits[MancalaState.southStore], 5); // 4 opposite + 1
      expect(s.lastCaptured, 5);
    });

    test('rejects empty pit and opponent pit', () {
      final s = fresh();
      expect(game.validateMove(s, const MancalaMove(7), 's'), isFalse);
      final empty = MancalaState(
        pits: List<int>.of(s.pits)..[3] = 0,
        playerIds: s.playerIds,
        currentPlayerId: 's',
      );
      expect(game.validateMove(empty, const MancalaMove(3), 's'), isFalse);
    });

    test('side empty ends game; higher store wins', () {
      final pits = List<int>.filled(14, 0);
      pits[MancalaState.southStore] = 20;
      pits[MancalaState.northStore] = 10;
      // all side pits empty
      final s = MancalaState(
        pits: pits,
        playerIds: const ['s', 'n'],
        currentPlayerId: 's',
      );
      expect(game.outcome(s), const GameOutcome.win('s'));
    });

    test('state survives encode/decode', () {
      var s = fresh();
      s = game.applyMove(s, const MancalaMove(2));
      final back = game.decodeState(game.encodeState(s), 1);
      expect(back.pits, s.pits);
      expect(back.currentPlayerId, s.currentPlayerId);
      expect(back.lastPath, s.lastPath);
      expect(back.lastExtraTurn, s.lastExtraTurn);
    });
  });
}
