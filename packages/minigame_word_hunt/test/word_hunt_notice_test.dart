import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_word_hunt/minigame_word_hunt.dart';
import 'package:minigames_core/minigames_core.dart';

/// Word Hunt produces the same message over and over by design: trace a word
/// you already have and it says "already found", trace it again and it says
/// exactly the same thing. The old chrome animated that through a hand-rolled
/// popup, and the shared version of the same idea — an [AnimatedSwitcher]
/// keyed on the text — keeps the outgoing child mounted next to the incoming
/// one and throws "Duplicate keys found" on the repeat. This pins the fix.
void main() {
  const letters = [
    'o', 'u', 'r', 's', //
    'a', 'b', 'c', 'd', //
    'e', 'f', 'g', 'h', //
    'i', 'j', 'k', 'l', //
  ];

  testWidgets('tracing the same word repeatedly never throws', (tester) async {
    await tester.binding.setSurfaceSize(const Size(402, 798));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dict = WordDictionary.fromWords(['our', 'ours']);
    final game = WordHuntGame(dictionary: dict, minSolutions: 0);
    final transport = LocalTransport();
    final controller =
        await MatchController.create<WordHuntState, WordHuntMove>(
      game: game,
      transport: transport,
      matchId: 'notice-repeat',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      seed: 1,
      hotSeat: true,
    );
    addTearDown(controller.dispose);

    // Hand-built grid so O-U-R is the top row and always traceable.
    await transport.submitTurn(
      Match(
        id: 'notice-repeat',
        gameId: game.id,
        playerIds: const ['p1', 'p2'],
        currentPlayerId: 'p1',
        status: MatchStatus.open,
        turnCount: 0,
        state: game.encodeState(
          WordHuntState(
            letters: letters,
            playerIds: const ['p1', 'p2'],
            found: const {},
            submitted: const [],
          ),
        ),
        schemaVersion: game.stateSchemaVersion,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: WordHuntBoard(controller: controller, game: game),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Start round'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final o = tester.getCenter(find.text('O'));
    final u = tester.getCenter(find.text('U'));
    final r = tester.getCenter(find.text('R'));

    // Four traces of OUR back to back: the first scores, the rest are
    // duplicates and all read identically. Each lands well inside the
    // previous message's 260ms entrance.
    for (var i = 0; i < 4; i++) {
      final gesture = await tester.startGesture(o);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(u);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(r);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.takeException(), isNull, reason: 'trace $i');
    }

    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);

    // The word scored exactly once, however many times it was traced.
    expect(find.text('WORDS'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // Tear down while the round timer is still live.
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
