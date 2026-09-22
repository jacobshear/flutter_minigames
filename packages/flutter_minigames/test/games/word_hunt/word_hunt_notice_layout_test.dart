import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/word_hunt/word_hunt.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

/// Regression for GitHub issue #1: the scored-word [GameNotice] used to sit
/// in the grid's own Stack, directly over the top row, because the stat row
/// left no gutter above the grid to move it into. It now lives in a
/// dedicated strip between the stat row and the grid, structurally outside
/// the grid's paint area — this pins that down by rect, not by reading code.
void main() {
  const letters = [
    'o', 'u', 'r', 's', //
    'a', 'b', 'c', 'd', //
    'e', 'f', 'g', 'h', //
    'i', 'j', 'k', 'l', //
  ];

  testWidgets('the traced-word notice never overlaps a grid tile',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dict = WordDictionary.fromWords(['ours']);
    final game = WordHuntGame(dictionary: dict, minSolutions: 0);
    final transport = LocalTransport();
    final controller =
        await MatchController.create<WordHuntState, WordHuntMove>(
      game: game,
      transport: transport,
      matchId: 'notice-layout',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      seed: 1,
      hotSeat: true,
    );
    addTearDown(controller.dispose);

    // Hand-built grid so O-U-R-S is the top row and always traceable.
    await transport.submitTurn(
      Match(
        id: 'notice-layout',
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
    final s = tester.getCenter(find.text('S'));

    final gesture = await tester.startGesture(o);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(u);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(r);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(s);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();

    // Let the pan-end setState land, then advance well past the notice's
    // 260ms entrance so it is fully up (still well inside its 1400ms life).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(tester.takeException(), isNull);

    // The notice is up and says what was just scored.
    expect(find.textContaining('OURS'), findsWidgets);
    final noticeRect = tester.getRect(find.byType(GameNotice));

    // Every tile on the board — the notice must clear all sixteen, not just
    // the top row it used to sit on.
    for (var i = 0; i < letters.length; i++) {
      final tileFinder = find.byKey(ValueKey('word_hunt_tile_$i'));
      expect(tileFinder, findsOneWidget, reason: 'tile $i missing a key');
      final tileRect = tester.getRect(tileFinder);
      expect(
        noticeRect.overlaps(tileRect),
        isFalse,
        reason: 'notice $noticeRect overlaps tile $i at $tileRect',
      );
    }
  });
}
