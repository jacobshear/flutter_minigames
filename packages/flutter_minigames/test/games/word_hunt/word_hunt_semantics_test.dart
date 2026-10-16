import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/word_hunt/word_hunt.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

/// Every semantics label currently in the tree, in tree order.
List<String> _labels(WidgetTester tester) {
  final labels = <String>[];
  void walk(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  // ignore: deprecated_member_use
  walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return labels;
}

/// The grid's container label names every letter, so the tile Texts inside it
/// must not merge in and be read a second time.
void _expectGridReadOnce(
  WidgetTester tester,
  String gridLabelStart,
  List<String> letters,
) {
  final labels = _labels(tester);
  final grid = labels.where((l) => l.startsWith(gridLabelStart)).toList();
  expect(grid, hasLength(1), reason: 'the grid label appears once');
  // Nothing was merged in behind the label: it is exactly the row-by-row
  // reading and ends at its last full stop.
  expect(grid.single.trim().endsWith('.'), isTrue, reason: grid.single);
  expect(grid.single.contains('\n'), isFalse, reason: grid.single);
  for (final letter in letters.toSet()) {
    expect(
      labels.contains(letter.toUpperCase()),
      isFalse,
      reason: 'the tile "$letter" is not a separate node',
    );
  }
}

void main() {
  const letters = [
    'o', 'u', 'r', 's', //
    'a', 'b', 'c', 'd', //
    'e', 'f', 'g', 'h', //
    'i', 'j', 'k', 'l', //
  ];

  testWidgets('the live grid reads its letters once', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(402, 798));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dict = WordDictionary.fromWords(['our', 'ours']);
    final game = WordHuntGame(dictionary: dict, minSolutions: 0);
    final transport = LocalTransport();
    final controller =
        await MatchController.create<WordHuntState, WordHuntMove>(
      game: game,
      transport: transport,
      matchId: 'semantics',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      seed: 1,
      hotSeat: true,
    );
    addTearDown(controller.dispose);
    await transport.submitTurn(
      Match(
        id: 'semantics',
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

    _expectGridReadOnce(tester, 'Word hunt. Letter grid', letters);
    handle.dispose();
  });

  testWidgets('the replay grid reads its letters once', (tester) async {
    final handle = tester.ensureSemantics();
    final dict = WordDictionary.fromWords(['cat']);
    final game = WordHuntGame(dictionary: dict, minSolutions: 0);
    const replayLetters = [
      'c', 'a', 't', 's', //
      'o', 'd', 'e', 'r', //
      'g', 'x', 'x', 'x', //
      'x', 'x', 'x', 'x', //
    ];
    final state = WordHuntState(
      letters: replayLetters,
      playerIds: const ['p1', 'p2'],
      found: const {
        'p2': ['cat'],
      },
      submitted: const ['p1', 'p2'],
      paths: const {
        'p2': [
          [0, 1, 2],
        ],
      },
    );
    final controller = RoundReplayController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WordHuntRoundReplay(
            game: game,
            state: state,
            playerId: 'p2',
            viewerId: 'p1',
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pump();

    _expectGridReadOnce(tester, 'Word hunt replay of', replayLetters);
    handle.dispose();
  });
}
