import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/filler/filler.dart';
import 'package:flutter_minigames/src/core/core.dart';

void main() {
  const game = FillerGame();
  const p1 = 'alice';
  const p2 = 'bob';

  FillerState fresh([int seed = 0]) =>
      game.initialState(seed: seed, playerIds: const [p1, p2]);

  /// Handcrafted state builder: fills the whole board with [fill], then
  /// applies overrides. Owners default to just the two start corners.
  FillerState build({
    int fill = 4,
    Map<int, int> cellOverrides = const {},
    Map<int, int> ownerOverrides = const {},
    int turnIndex = 0,
  }) {
    final cells = List<int>.filled(FillerState.cellCount, fill);
    final owners = List<int>.filled(FillerState.cellCount, -1);
    owners[FillerState.p1Start] = 0;
    owners[FillerState.p2Start] = 1;
    cellOverrides.forEach((i, c) => cells[i] = c);
    ownerOverrides.forEach((i, o) => owners[i] = o);
    return FillerState(
      cells: cells,
      owners: owners,
      playerIds: const [p1, p2],
      turnIndex: turnIndex,
    );
  }

  group('board generation', () {
    test('fresh board: 56 cells, corner ownership, scores 1-1, p1 to move', () {
      final s = fresh();
      expect(s.cells.length, 56);
      expect(s.owners.length, 56);
      expect(s.owners[FillerState.p1Start], 0);
      expect(s.owners[FillerState.p2Start], 1);
      expect(s.owners.where((o) => o != -1).length, 2);
      expect(s.scoreOf(p1), 1);
      expect(s.scoreOf(p2), 1);
      expect(game.currentPlayer(s), p1);
      expect(game.outcome(s), isNull);
    });

    test('same seed produces the identical board', () {
      for (final seed in [0, 1, 7, 42, 123456, -5]) {
        final a = fresh(seed);
        final b = fresh(seed);
        expect(a.cells, b.cells, reason: 'seed $seed');
        expect(a.owners, b.owners, reason: 'seed $seed');
      }
    });

    test('constraints hold across many seeds', () {
      for (var seed = 0; seed < 300; seed++) {
        final s = fresh(seed);
        // All colors in range.
        expect(
            s.cells.every((c) => c >= 0 && c < FillerState.colorCount), isTrue);
        // Start corners differ.
        expect(
            s.cells[FillerState.p1Start], isNot(s.cells[FillerState.p2Start]),
            reason: 'seed $seed corners match');
        // No orthogonally-adjacent same-color pair anywhere (includes the
        // corner-neighbor requirement, so turn one always has real choices).
        for (var i = 0; i < FillerState.cellCount; i++) {
          for (final n in FillerState.neighborsOf(i)) {
            expect(s.cells[i], isNot(s.cells[n]),
                reason: 'seed $seed adjacent cells $i/$n share a color');
          }
        }
      }
    });
  });

  group('move validation', () {
    test('forbids own color, opponent color, out of range, out of turn', () {
      final s = fresh(3);
      final own = s.colorOfIndex(0);
      final opp = s.colorOfIndex(1);
      expect(game.validateMove(s, FillerMove(own), p1), isFalse);
      expect(game.validateMove(s, FillerMove(opp), p1), isFalse);
      expect(game.validateMove(s, const FillerMove(-1), p1), isFalse);
      expect(game.validateMove(s, const FillerMove(6), p1), isFalse);
      final legal =
          List.generate(6, (c) => c).firstWhere((c) => c != own && c != opp);
      expect(game.validateMove(s, FillerMove(legal), p1), isTrue);
      // Not bob's turn.
      expect(game.validateMove(s, FillerMove(legal), p2), isFalse);
    });

    test('rejects any move once the game is decided', () {
      final s = build(
        ownerOverrides: {for (var i = 0; i < 30; i++) i: 0},
        cellOverrides: {for (var i = 0; i < 30; i++) i: 1},
      );
      expect(game.outcome(s), isNotNull);
      for (var c = 0; c < 6; c++) {
        expect(game.validateMove(s, FillerMove(c), p1), isFalse);
      }
    });
  });

  group('flood capture', () {
    test('cascading orthogonal capture; diagonal excluded', () {
      // Board of color 4. P1 corner (48) color 5; opponent corner (7)
      // color 0. Chain of color 2: 49 → 50 → 42 (orthogonal cascade).
      // Cell 33 is color 2 but only diagonally touches the chain (via 42);
      // its orthogonal neighbor 41 is color 4, so 33 must NOT be captured.
      final s = build(
        cellOverrides: {
          FillerState.p1Start: 5,
          FillerState.p2Start: 0,
          49: 2,
          50: 2,
          42: 2,
          33: 2,
        },
      );
      expect(game.validateMove(s, const FillerMove(2), p1), isTrue);
      final next = game.applyMove(s, const FillerMove(2));

      expect(next.owners[FillerState.p1Start], 0);
      expect(next.owners[49], 0);
      expect(next.owners[50], 0);
      expect(next.owners[42], 0, reason: 'cascade should reach 42');
      expect(next.owners[33], -1, reason: 'diagonal must not capture');
      expect(next.scoreOf(p1), 4);
      expect(next.scoreOf(p2), 1);

      // Whole territory repainted to the picked color.
      for (var i = 0; i < FillerState.cellCount; i++) {
        if (next.owners[i] == 0) expect(next.cells[i], 2);
      }
      // Unowned cells keep their colors.
      expect(next.cells[33], 2);
      expect(next.cells[0], 4);

      // Turn passed to bob.
      expect(game.currentPlayer(next), p2);
      expect(game.outcome(next), isNull);
    });

    test('a legal pick that touches nothing still repaints and passes turn',
        () {
      final s = build(
        cellOverrides: {FillerState.p1Start: 5, FillerState.p2Start: 0},
      );
      // Color 3 exists nowhere adjacent — no captures.
      final next = game.applyMove(s, const FillerMove(3));
      expect(next.scoreOf(p1), 1);
      expect(next.cells[FillerState.p1Start], 3);
      expect(next.turnIndex, 1);
    });
  });

  group('scoring and outcome', () {
    test('in progress while both are under majority with cells left', () {
      final s = build(
        ownerOverrides: {
          for (var i = 0; i < 20; i++) i: 0,
          for (var i = 20; i < 40; i++) i: 1,
          FillerState.p1Start: -1, // clear the default corner ownership
        },
        cellOverrides: {
          for (var i = 0; i < 20; i++) i: 1,
          for (var i = 20; i < 40; i++) i: 2,
        },
      );
      expect(s.scoreOf(p1), 20);
      expect(s.scoreOf(p2), 20);
      expect(s.unownedCount, 16);
      expect(game.outcome(s), isNull);
    });

    test('majority (29+) ends the game immediately', () {
      final s = build(
        ownerOverrides: {
          for (var i = 0; i < 29; i++) i: 0,
          FillerState.p1Start: -1, // exactly 29, not 29 + the corner
        },
        cellOverrides: {for (var i = 0; i < 29; i++) i: 1},
      );
      expect(s.scoreOf(p1), 29);
      expect(game.outcome(s), const GameOutcome.win(p1));
    });

    test('full board, larger territory wins', () {
      final s = build(
        ownerOverrides: {
          for (var i = 0; i < 27; i++) i: 0,
          for (var i = 27; i < 56; i++) i: 1,
        },
        cellOverrides: {
          for (var i = 0; i < 27; i++) i: 1,
          for (var i = 27; i < 56; i++) i: 2,
        },
      );
      expect(s.scoreOf(p2), 29);
      expect(game.outcome(s), const GameOutcome.win(p2));
    });

    test('28-28 full board is a draw', () {
      final s = build(
        ownerOverrides: {
          for (var i = 0; i < 28; i++) i: 0,
          for (var i = 28; i < 56; i++) i: 1,
        },
        cellOverrides: {
          for (var i = 0; i < 28; i++) i: 1,
          for (var i = 28; i < 56; i++) i: 2,
        },
      );
      expect(s.scoreOf(p1), 28);
      expect(s.scoreOf(p2), 28);
      expect(game.outcome(s), const GameOutcome.draw());
    });
  });

  group('serialization', () {
    test('state survives a JSON round trip', () {
      var s = fresh(9);
      // Advance a couple of turns so the state is non-trivial.
      for (var turn = 0; turn < 4; turn++) {
        final legal = List.generate(6, (c) => c).firstWhere(
          (c) => game.validateMove(s, FillerMove(c), s.currentPlayerId),
        );
        s = game.applyMove(s, FillerMove(legal));
      }

      final wire =
          jsonDecode(jsonEncode(game.encodeState(s))) as Map<String, dynamic>;
      final back = game.decodeState(wire, game.stateSchemaVersion);
      expect(back.cells, s.cells);
      expect(back.owners, s.owners);
      expect(back.playerIds, s.playerIds);
      expect(back.turnIndex, s.turnIndex);
      expect(game.outcome(back), game.outcome(s));
    });

    test('move survives a JSON round trip', () {
      const m = FillerMove(4);
      final wire =
          jsonDecode(jsonEncode(game.encodeMove(m))) as Map<String, dynamic>;
      expect(game.decodeMove(wire).color, 4);
    });
  });

  group('full game', () {
    test('greedy self-play from a seed terminates with a decisive outcome', () {
      for (final seed in [0, 5, 77]) {
        var s = fresh(seed);
        var guard = 0;
        while (game.outcome(s) == null && guard < 200) {
          guard++;
          FillerMove? best;
          var bestScore = -1;
          for (var c = 0; c < 6; c++) {
            final m = FillerMove(c);
            if (!game.validateMove(s, m, s.currentPlayerId)) continue;
            final gained = game.applyMove(s, m).scoreOfIndex(s.turnIndex);
            if (gained > bestScore) {
              bestScore = gained;
              best = m;
            }
          }
          expect(best, isNotNull, reason: 'seed $seed: no legal move');
          s = game.applyMove(s, best!);
        }
        final outcome = game.outcome(s);
        expect(outcome, isNotNull, reason: 'seed $seed did not terminate');
        // Scores are consistent with the declared result.
        final a = s.scoreOfIndex(0);
        final b = s.scoreOfIndex(1);
        if (outcome!.isDraw) {
          expect(a, b);
        } else {
          final winScore = outcome.winnerId == p1 ? a : b;
          final loseScore = outcome.winnerId == p1 ? b : a;
          expect(winScore, greaterThan(loseScore));
        }
      }
    });
  });
}
