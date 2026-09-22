import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/anagrams/anagrams.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

void main() {
  // Deterministic fixture: 'cat' (3 letters -> 100 pts) then 'rose' (4
  // letters -> 400 pts), both formable from 'catrose'. Total score = 500.
  final dict = WordDictionary.fromWords(['cat', 'rose']);
  final game = AnagramsGame(dictionary: dict);

  AnagramsState buildState() => const AnagramsState(
        letters: 'catrose',
        playerIds: ['me', 'opp'],
        submissions: {
          'opp': ['cat', 'rose'],
        },
      );

  // Overshoot the pacing-formula total (0.35s for 'cat' + 0.48s for 'rose'
  // = 0.83s, unscaled since it's well under the 15s compression cap) plus
  // the ~450ms final-frame hold. 3s comfortably covers both with margin.
  const overshoot = Duration(seconds: 3);

  Widget host(AnagramsState state, RoundReplayController controller) {
    return MaterialApp(
      home: Scaffold(
        body: AnagramsRoundReplay(
          game: game,
          state: state,
          playerId: 'opp',
          viewerId: 'me',
          controller: controller,
          style: const AnagramsStyle(),
        ),
      ),
    );
  }

  testWidgets('plays the full timeline and lands on the final score',
      (tester) async {
    final state = buildState();
    final controller = RoundReplayController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(state, controller));
    await tester.pump();
    await tester.pump(overshoot);
    await tester.pump();

    expect(controller.finished, isTrue);
    expect(find.text('${state.scoreOf('opp')}'), findsOneWidget);
    // Both words landed in the found strip.
    expect(find.text('CAT'), findsOneWidget);
    expect(find.text('ROSE'), findsOneWidget);
  });

  testWidgets('skip() jumps straight to the resolved final frame',
      (tester) async {
    final state = buildState();
    final controller = RoundReplayController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(state, controller));
    await tester.pump();

    controller.skip();
    await tester.pump();

    expect(controller.finished, isTrue);
    expect(find.text('${state.scoreOf('opp')}'), findsOneWidget);
    expect(find.text('CAT'), findsOneWidget);
    expect(find.text('ROSE'), findsOneWidget);
  });

  testWidgets('viewer-found words render subdued, missed words vivid',
      (tester) async {
    // 'me' (the viewer) also found 'cat' but not 'rose'.
    const state = AnagramsState(
      letters: 'catrose',
      playerIds: ['me', 'opp'],
      submissions: {
        'opp': ['cat', 'rose'],
        'me': ['cat'],
      },
    );
    final controller = RoundReplayController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(state, controller));
    controller.skip();
    await tester.pump();

    final catText = tester.widget<Text>(find.text('CAT'));
    final roseText = tester.widget<Text>(find.text('ROSE'));
    // Subdued ("you got it too") is lower-weight than vivid ("you missed
    // it") per _FoundChip.
    expect(catText.style!.fontWeight, FontWeight.w600);
    expect(roseText.style!.fontWeight, FontWeight.w800);
  });

  testWidgets('empty round shows "No words" and finishes without hanging',
      (tester) async {
    const state = AnagramsState(
      letters: 'catrose',
      playerIds: ['me', 'opp'],
      submissions: {'opp': []},
    );
    final controller = RoundReplayController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(state, controller));
    await tester.pump();
    await tester.pump(overshoot);
    await tester.pump();

    expect(controller.finished, isTrue);
    expect(find.text('No words'), findsOneWidget);
  });
}
