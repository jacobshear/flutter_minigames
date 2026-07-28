import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/anagrams/anagrams.dart';
import 'package:flutter_minigames/src/core/core.dart';

void main() {
  // Small in-memory dictionary — logic tests never touch assets.
  // 6-letter words available for round generation: 'planet', 'staple'.
  final dict = WordDictionary.fromWords([
    'planet', 'staple',
    'plane', 'plant', 'petal', 'leapt', 'pleat',
    'plan', 'pale', 'peat', 'tale', 'pane', 'neat', 'lane',
    'pan', 'nap', 'ten', 'net', 'ant', 'tan', 'ale', 'pat', 'tap',
    'an', 'at', // too short to score
  ]);
  final game = AnagramsGame(dictionary: dict);
  const players = ['p1', 'p2'];

  AnagramsState fresh({int seed = 7}) =>
      game.initialState(seed: seed, playerIds: players);

  group('letter generation', () {
    test('deterministic per seed', () {
      expect(game.lettersForSeed(42), game.lettersForSeed(42));
      expect(fresh(seed: 42).letters, fresh(seed: 42).letters);
    });

    test('letters are a scramble of a real 6-letter dictionary word', () {
      final letters = game.lettersForSeed(3);
      expect(letters.length, 6);
      final sorted = (letters.split('')..sort()).join();
      final candidates = ['planet', 'staple']
          .map((w) => (w.split('')..sort()).join())
          .toList();
      expect(candidates, contains(sorted));
    });

    test('different seeds can differ', () {
      final all = {for (var s = 0; s < 20; s++) game.lettersForSeed(s)};
      expect(all.length, greaterThan(1));
    });
  });

  group('word validation in applyMove', () {
    // Force known letters by picking a seed that yields 'planet' letters.
    late AnagramsState state;

    setUp(() {
      state = fresh(seed: _seedFor(game, 'planet'));
    });

    test('valid dictionary words score', () {
      final next = game.applyMove(state, const AnagramsMove(['plane', 'ten']));
      expect(next.wordsOf('p1'), ['plane', 'ten']);
      expect(next.scoreOf('p1'), 1200 + 100);
    });

    test('words not in the dictionary are stripped', () {
      final next = game.applyMove(state, const AnagramsMove(['zzz', 'ten']));
      expect(next.wordsOf('p1'), ['ten']);
    });

    test('words violating the letter multiset are stripped', () {
      // 'tale' needs no duplicates and fits; 'staple' needs an s — none in
      // 'planet'. 'nanna' needs three n's — only one available.
      final next = game.applyMove(
        state,
        const AnagramsMove(['tale', 'staple', 'nanna']),
      );
      expect(next.wordsOf('p1'), ['tale']);
    });

    test('words under three letters are stripped', () {
      final next = game.applyMove(state, const AnagramsMove(['an', 'ant']));
      expect(next.wordsOf('p1'), ['ant']);
    });

    test('duplicates score once (case-insensitive)', () {
      final next = game.applyMove(
        state,
        const AnagramsMove(['ten', 'TEN', 'ten ', 'net']),
      );
      expect(next.wordsOf('p1'), ['ten', 'net']);
      expect(next.scoreOf('p1'), 200);
    });

    test('score is recomputed from accepted words, never trusted', () {
      // The move type carries no score at all — the only path to a score is
      // through validation. A junk-heavy list must score only its valid part.
      final next = game.applyMove(
        state,
        const AnagramsMove(['planet', 'cheatword', 'zz', 'planet']),
      );
      expect(next.scoreOf('p1'), 2000);
    });
  });

  group('scoring table', () {
    test('GP-style length scores', () {
      expect(AnagramsGame.scoreForWord('ten'), 100);
      expect(AnagramsGame.scoreForWord('tale'), 400);
      expect(AnagramsGame.scoreForWord('plane'), 1200);
      expect(AnagramsGame.scoreForWord('planet'), 2000);
      expect(AnagramsGame.scoreForWord('at'), 0);
    });
  });

  group('round flow', () {
    test('p1 then p2, then finished with the right winner', () {
      var state = fresh(seed: _seedFor(game, 'planet'));
      expect(game.currentPlayer(state), 'p1');
      expect(game.outcome(state), isNull);

      expect(
        game.validateMove(state, const AnagramsMove(['ten']), 'p2'),
        isFalse,
        reason: 'p2 cannot play before p1',
      );
      expect(
        game.validateMove(state, const AnagramsMove(['ten']), 'p1'),
        isTrue,
      );

      state = game.applyMove(state, const AnagramsMove(['ten'])); // 100
      expect(game.currentPlayer(state), 'p2');
      expect(game.outcome(state), isNull);
      expect(
        game.validateMove(state, const AnagramsMove(['net']), 'p1'),
        isFalse,
        reason: 'p1 cannot submit twice',
      );

      state = game.applyMove(state, const AnagramsMove(['plane'])); // 1200
      expect(state.isFinished, isTrue);
      expect(game.outcome(state), const GameOutcome.win('p2'));
      expect(
        game.validateMove(state, const AnagramsMove(['ant']), 'p2'),
        isFalse,
        reason: 'no moves after the match ends',
      );
    });

    test('equal scores draw', () {
      var state = fresh(seed: _seedFor(game, 'planet'));
      state = game.applyMove(state, const AnagramsMove(['ten']));
      state = game.applyMove(state, const AnagramsMove(['net']));
      expect(game.outcome(state), const GameOutcome.draw());
    });

    test('empty submissions are legal and score zero', () {
      var state = fresh(seed: _seedFor(game, 'planet'));
      state = game.applyMove(state, const AnagramsMove([]));
      state = game.applyMove(state, const AnagramsMove(['ten']));
      expect(state.scoreOf('p1'), 0);
      expect(game.outcome(state), const GameOutcome.win('p2'));
    });
  });

  group('serialization', () {
    test('state round-trips through JSON', () {
      var state = fresh(seed: _seedFor(game, 'planet'));
      state = game.applyMove(state, const AnagramsMove(['ten', 'plane']));

      final json = jsonDecode(jsonEncode(game.encodeState(state)))
          as Map<String, dynamic>;
      final decoded = game.decodeState(json, game.stateSchemaVersion);

      expect(decoded.letters, state.letters);
      expect(decoded.playerIds, state.playerIds);
      expect(decoded.wordsOf('p1'), state.wordsOf('p1'));
      expect(decoded.scoreOf('p1'), state.scoreOf('p1'));
      expect(decoded.hasSubmitted('p2'), isFalse);
      expect(game.currentPlayer(decoded), 'p2');
    });

    test('move round-trips through JSON', () {
      const move = AnagramsMove(['ten', 'plane']);
      final json =
          jsonDecode(jsonEncode(game.encodeMove(move))) as Map<String, dynamic>;
      expect(game.decodeMove(json).words, move.words);
    });
  });

  group('full match through MatchController (hot-seat)', () {
    test('validated turns land in the transport and finish the match',
        () async {
      final transport = LocalTransport();
      final controller =
          await MatchController.create<AnagramsState, AnagramsMove>(
        game: game,
        transport: transport,
        matchId: 'm1',
        playerIds: players,
        localPlayerId: 'p1',
        hotSeat: true,
        seed: _seedFor(game, 'planet'),
      );

      expect(
        await controller.submitMove(const AnagramsMove(['plane', 'junk'])),
        isTrue,
      );
      expect(
        await controller.submitMove(const AnagramsMove(['ten'])),
        isTrue,
      );

      final state = controller.state!;
      expect(state.wordsOf('p1'), ['plane']);
      expect(state.wordsOf('p2'), ['ten']);
      expect(controller.outcome, const GameOutcome.win('p1'));
      expect(
        await controller.submitMove(const AnagramsMove(['net'])),
        isFalse,
        reason: 'match is closed',
      );

      await controller.dispose();
      transport.dispose();
    });
  });
}

/// Finds a seed whose round letters scramble [base] — keeps the letter tests
/// independent of Random's internals.
int _seedFor(AnagramsGame game, String base) {
  final want = (base.split('')..sort()).join();
  for (var seed = 0; seed < 500; seed++) {
    final got = (game.lettersForSeed(seed).split('')..sort()).join();
    if (got == want) return seed;
  }
  throw StateError('no seed found for $base');
}
