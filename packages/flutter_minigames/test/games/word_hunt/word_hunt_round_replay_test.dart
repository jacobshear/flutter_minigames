import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/word_hunt/word_hunt.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

void main() {
  // Hand-built 4×4 grid (row-major), same fixture as word_hunt_game_test.dart:
  //   c a t s
  //   o d e r
  //   g x x x
  //   x x x x
  const letters = [
    'c',
    'a',
    't',
    's',
    'o',
    'd',
    'e',
    'r',
    'g',
    'x',
    'x',
    'x',
    'x',
    'x',
    'x',
    'x',
  ];

  final dict = WordDictionary.fromWords(['cat', 'rest']);

  WordHuntGame game() => WordHuntGame(dictionary: dict, minSolutions: 0);

  // Total timeline for cat (3 letters, 0.35s) + rest (4 letters, 0.48s) is
  // well under the 15s scaling threshold, plus a 0.45s hold — overshoot it
  // generously.
  const overshoot = Duration(seconds: 5);

  Widget host(WordHuntGame g, WordHuntState state, RoundReplayController c) {
    return MaterialApp(
      home: Scaffold(
        body: WordHuntRoundReplay(
          game: g,
          state: state,
          playerId: 'p2',
          viewerId: 'p1',
          controller: c,
        ),
      ),
    );
  }

  group('WordHuntRoundReplay', () {
    testWidgets('plays through recorded paths and lands on the final score',
        (tester) async {
      final g = game();
      final state = WordHuntState(
        letters: letters,
        playerIds: const ['p1', 'p2'],
        found: const {
          'p1': ['cat'],
          'p2': ['cat', 'rest'],
        },
        submitted: const ['p1', 'p2'],
        paths: const {
          'p2': [
            [0, 1, 2],
            [7, 6, 3, 2],
          ],
        },
      );
      final controller = RoundReplayController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(g, state, controller));
      await tester.pump();
      expect(controller.finished, isFalse);

      await tester.pump(overshoot);
      await tester.pump();

      expect(controller.finished, isTrue);
      // 100 (cat) + 400 (rest) = 500, the exact final score for p2.
      expect(find.text('500'), findsOneWidget);
    });

    testWidgets(
        'falls back to DFS-reconstructed paths when state.paths is null',
        (tester) async {
      final g = game();
      final state = WordHuntState(
        letters: letters,
        playerIds: const ['p1', 'p2'],
        found: const {
          'p2': ['cat'],
        },
        submitted: const ['p1', 'p2'],
        paths: null,
      );
      final controller = RoundReplayController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(g, state, controller));
      await tester.pump();
      await tester.pump(overshoot);
      await tester.pump();

      expect(controller.finished, isTrue);
      // '100' is both the final score pill and the sole word's point badge
      // in the found strip — both legitimately show it.
      expect(find.text('100'), findsWidgets);
    });

    testWidgets('skip jumps straight to the final score', (tester) async {
      final g = game();
      final state = WordHuntState(
        letters: letters,
        playerIds: const ['p1', 'p2'],
        found: const {
          'p2': ['cat', 'rest'],
        },
        submitted: const ['p1', 'p2'],
        paths: const {
          'p2': [
            [0, 1, 2],
            [7, 6, 3, 2],
          ],
        },
      );
      final controller = RoundReplayController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(g, state, controller));
      await tester.pump();
      expect(controller.finished, isFalse);

      controller.skip();
      await tester.pump();

      expect(controller.finished, isTrue);
      expect(find.text('500'), findsOneWidget);
    });

    testWidgets('an opponent with no words settles immediately with no hang',
        (tester) async {
      final g = game();
      final state = WordHuntState(
        letters: letters,
        playerIds: const ['p1', 'p2'],
        found: const {},
        submitted: const ['p1', 'p2'],
        paths: const {},
      );
      final controller = RoundReplayController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(g, state, controller));
      await tester.pump();
      await tester.pump();

      expect(controller.finished, isTrue);
      expect(find.text('No words'), findsOneWidget);
    });
  });
}
