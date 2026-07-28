import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/sea_battle/sea_battle.dart';
import 'package:flutter_minigames/src/core/core.dart';

void main() {
  const game = SeaBattleGame();
  const p1 = 'p1';
  const p2 = 'p2';

  SeaBattleState fresh() =>
      game.initialState(seed: 0, playerIds: const [p1, p2]);

  /// A fixed hand-built legal fleet (rows of ships separated by water):
  /// 4 @ r0c0-3 · 3 @ r2c0-2 · 3 @ r2c4-6 · 2 @ r4c0-1 · 2 @ r4c3-4 ·
  /// 2 @ r4c6-7 · 1 @ r6c0 · 1 @ r6c2 · 1 @ r6c4 · 1 @ r6c6
  List<ShipPlacement> fixedFleet() => [
        ShipPlacement(row: 0, col: 0, length: 4, horizontal: true),
        ShipPlacement(row: 2, col: 0, length: 3, horizontal: true),
        ShipPlacement(row: 2, col: 4, length: 3, horizontal: true),
        ShipPlacement(row: 4, col: 0, length: 2, horizontal: true),
        ShipPlacement(row: 4, col: 3, length: 2, horizontal: true),
        ShipPlacement(row: 4, col: 6, length: 2, horizontal: true),
        ShipPlacement(row: 6, col: 0, length: 1, horizontal: true),
        ShipPlacement(row: 6, col: 2, length: 1, horizontal: true),
        ShipPlacement(row: 6, col: 4, length: 1, horizontal: true),
        ShipPlacement(row: 6, col: 6, length: 1, horizontal: true),
      ];

  /// Both players placed (identical fixed layouts), p1 to fire.
  SeaBattleState battleReady() {
    var s = fresh();
    s = game.applyMove(s, PlaceFleetMove(fixedFleet()));
    s = game.applyMove(s, PlaceFleetMove(fixedFleet()));
    return s;
  }

  SeaBattleState fire(SeaBattleState s, int cell) {
    final move = FireMove(cell);
    expect(game.validateMove(s, move, s.currentPlayerId), isTrue,
        reason: 'shot at $cell should be legal');
    return game.applyMove(s, move);
  }

  group('fleet legality', () {
    test('fixed fleet is valid', () {
      expect(SeaBattleGame.isFleetValid(fixedFleet()), isTrue);
    });

    test('wrong ship counts rejected', () {
      final tooFew = fixedFleet()..removeLast();
      expect(SeaBattleGame.isFleetValid(tooFew), isFalse);

      // Right count, wrong multiset: swap a 1-ship for an extra 2-ship.
      final wrongMix = fixedFleet()
        ..removeLast()
        ..add(const ShipPlacement(row: 8, col: 0, length: 2, horizontal: true));
      expect(SeaBattleGame.isFleetValid(wrongMix), isFalse);
    });

    test('out-of-bounds ships rejected', () {
      final fleet = fixedFleet();
      fleet[0] =
          const ShipPlacement(row: 0, col: 7, length: 4, horizontal: true);
      expect(SeaBattleGame.isFleetValid(fleet), isFalse);
      fleet[0] =
          const ShipPlacement(row: 8, col: 0, length: 4, horizontal: false);
      expect(SeaBattleGame.isFleetValid(fleet), isFalse);
    });

    test('overlapping ships rejected', () {
      final fleet = fixedFleet();
      // Move the first 3-ship on top of the 4-ship.
      fleet[1] =
          const ShipPlacement(row: 0, col: 2, length: 3, horizontal: true);
      expect(SeaBattleGame.isFleetValid(fleet), isFalse);
    });

    test('edge-adjacent ships rejected', () {
      final fleet = fixedFleet();
      // Directly below the 4-ship (row 1 touches row 0).
      fleet[1] =
          const ShipPlacement(row: 1, col: 0, length: 3, horizontal: true);
      expect(SeaBattleGame.isFleetValid(fleet), isFalse);
    });

    test('diagonally-adjacent ships rejected', () {
      final fleet = fixedFleet();
      // 1-ship diagonal to the 4-ship's tail (0,3) at (1,4).
      fleet[6] =
          const ShipPlacement(row: 1, col: 4, length: 1, horizontal: true);
      expect(SeaBattleGame.isFleetValid(fleet), isFalse);
    });

    test('randomFleet is valid across many seeds', () {
      for (var seed = 0; seed < 250; seed++) {
        final fleet = SeaBattleGame.randomFleet(seed);
        expect(SeaBattleGame.isFleetValid(fleet), isTrue,
            reason: 'seed $seed produced an illegal fleet');
      }
    });

    test('randomFleet is deterministic per seed', () {
      expect(SeaBattleGame.randomFleet(42), SeaBattleGame.randomFleet(42));
    });
  });

  group('placement phase', () {
    test('opens in placement, p1 places first', () {
      final s = fresh();
      expect(s.phase, SeaBattlePhase.placement);
      expect(game.currentPlayer(s), p1);
      expect(game.outcome(s), isNull);
    });

    test('placement rides the move contract and hands off to p2', () {
      var s = fresh();
      final move = PlaceFleetMove(fixedFleet());
      expect(game.validateMove(s, move, p1), isTrue);
      expect(game.validateMove(s, move, p2), isFalse, reason: 'not p2 turn');
      s = game.applyMove(s, move);
      expect(s.phase, SeaBattlePhase.placement);
      expect(game.currentPlayer(s), p2);
      // p1 cannot place twice.
      expect(game.validateMove(s, move, p1), isFalse);
      s = game.applyMove(s, PlaceFleetMove(fixedFleet()));
      expect(s.phase, SeaBattlePhase.battle);
      expect(game.currentPlayer(s), p1, reason: 'p1 fires first');
    });

    test('illegal fleet rejected as a move', () {
      final s = fresh();
      final bad = fixedFleet()..removeLast();
      expect(game.validateMove(s, PlaceFleetMove(bad), p1), isFalse);
    });

    test('firing is illegal during placement', () {
      final s = fresh();
      expect(game.validateMove(s, const FireMove(0), p1), isFalse);
    });
  });

  group('battle phase', () {
    test('miss passes the turn', () {
      var s = battleReady();
      s = fire(s, 99); // (9,9) is water in the fixed fleet.
      expect(game.currentPlayer(s), p2);
      expect(s.shots[p2], contains(99));
      expect(s.lastShotCell, 99);
      expect(s.lastShotTarget, p2);
    });

    test('hit grants another shot', () {
      var s = battleReady();
      s = fire(s, 0); // (0,0) is the 4-ship's bow.
      expect(game.currentPlayer(s), p1);
      expect(s.shots[p2], contains(0));
    });

    test('cannot fire the same cell twice or out of turn', () {
      var s = battleReady();
      s = fire(s, 0); // hit, p1 again
      expect(game.validateMove(s, const FireMove(0), p1), isFalse);
      expect(game.validateMove(s, const FireMove(50), p2), isFalse);
      expect(game.validateMove(s, const FireMove(-1), p1), isFalse);
      expect(game.validateMove(s, const FireMove(100), p1), isFalse);
    });

    test('sinking reveals the surrounding water as misses', () {
      var s = battleReady();
      // Sink the 1-ship at (6,0) = cell 60.
      s = fire(s, 60);
      expect(s.sunkShipsOf(p2).map((x) => x.length), contains(1));
      // Halo: (5,0),(5,1),(6,1),(7,0),(7,1) all auto-revealed.
      expect(s.shots[p2], containsAll([50, 51, 61, 70, 71]));
      // Auto-revealed cells cannot be fired at again.
      expect(game.validateMove(s, const FireMove(51), p1), isFalse);
      // Still p1's turn — a sink is a hit.
      expect(game.currentPlayer(s), p1);
    });

    test('sinking a mid-board ship reveals its full ring', () {
      var s = battleReady();
      // Sink the 2-ship at (4,3)-(4,4): cells 43, 44.
      s = fire(s, 43);
      expect(game.currentPlayer(s), p1);
      s = fire(s, 44);
      expect(s.sunkShipsOf(p2).map((x) => x.length), contains(2));
      expect(
        s.shots[p2],
        containsAll([32, 33, 34, 35, 42, 45, 52, 53, 54, 55]),
      );
    });

    test('game ends when the whole fleet is sunk', () {
      var s = battleReady();
      final targetCells = s.shipCellsOf(p2).toList()..sort();
      for (final cell in targetCells) {
        expect(game.outcome(s), isNull);
        s = fire(s, cell);
        expect(game.currentPlayer(s), p1,
            reason: 'every shot is a hit, so p1 keeps the turn');
      }
      expect(s.allSunk(p2), isTrue);
      expect(game.outcome(s), const GameOutcome.win(p1));
      // No moves after the game ends.
      expect(game.validateMove(s, const FireMove(99), p1), isFalse);
    });
  });

  group('serialization', () {
    test('state round-trips mid-placement', () {
      var s = fresh();
      s = game.applyMove(s, PlaceFleetMove(fixedFleet()));
      final decoded =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(decoded.playerIds, s.playerIds);
      expect(decoded.fleets[p1], s.fleets[p1]);
      expect(decoded.fleets[p2], isNull);
      expect(decoded.currentPlayerId, p2);
      expect(decoded.phase, SeaBattlePhase.placement);
    });

    test('state round-trips mid-battle with shots and sunk ships', () {
      var s = battleReady();
      s = fire(s, 60); // sink the 1-ship
      s = fire(s, 99); // miss, turn passes
      final decoded =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(decoded.shots[p2], s.shots[p2]);
      expect(decoded.shots[p1], isEmpty);
      expect(decoded.currentPlayerId, p2);
      expect(decoded.lastShotCell, 99);
      expect(decoded.lastShotTarget, p2);
      expect(decoded.sunkShipsOf(p2).length, 1);
      expect(game.outcome(decoded), isNull);
    });

    test('moves round-trip', () {
      final place = PlaceFleetMove(fixedFleet());
      final decodedPlace = game.decodeMove(game.encodeMove(place));
      expect(decodedPlace, isA<PlaceFleetMove>());
      expect((decodedPlace as PlaceFleetMove).ships, place.ships);

      final shot = game.decodeMove(game.encodeMove(const FireMove(37)));
      expect(shot, isA<FireMove>());
      expect((shot as FireMove).cell, 37);
    });

    test('encoded state is JSON-safe (no sets, no custom objects)', () {
      var s = battleReady();
      s = fire(s, 60);
      void checkJsonSafe(Object? value) {
        if (value == null || value is num || value is String || value is bool) {
          return;
        }
        if (value is List) {
          for (final v in value) {
            checkJsonSafe(v);
          }
          return;
        }
        if (value is Map) {
          for (final e in value.entries) {
            expect(e.key, isA<String>());
            checkJsonSafe(e.value);
          }
          return;
        }
        fail('non-JSON value of type ${value.runtimeType}');
      }

      checkJsonSafe(game.encodeState(s));
    });
  });

  group('full match via MatchController', () {
    test('hot-seat placement + battle to a win', () async {
      final transport = LocalTransport();
      final controller =
          await MatchController.create<SeaBattleState, SeaBattleMove>(
        game: game,
        transport: transport,
        matchId: 'test-sb',
        playerIds: const [p1, p2],
        localPlayerId: p1,
        hotSeat: true,
        seed: 7,
      );

      expect(await controller.submitMove(PlaceFleetMove(fixedFleet())), isTrue);
      expect(
          await controller
              .submitMove(PlaceFleetMove(SeaBattleGame.randomFleet(3))),
          isTrue);
      expect(controller.state!.phase, SeaBattlePhase.battle);

      // p1 mows down p2's fleet (hits only, so the turn never passes).
      final cells = controller.state!.shipCellsOf(p2).toList()..sort();
      for (final cell in cells) {
        if ((controller.state!.shots[p2] ?? const {}).contains(cell)) {
          continue; // auto-revealed by an earlier sink
        }
        expect(await controller.submitMove(FireMove(cell)), isTrue);
      }
      expect(controller.outcome, const GameOutcome.win(p1));
      expect(controller.match!.isEnded, isTrue);

      await controller.dispose();
      transport.dispose();
    });
  });
}
