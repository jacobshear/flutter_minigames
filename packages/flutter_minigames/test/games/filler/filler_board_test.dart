import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/filler/filler.dart';
import 'package:flutter_minigames/src/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every semantics label currently in the tree.
Set<String> semanticLabels(WidgetTester tester) {
  final labels = <String>{};
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

Future<MatchController<S, M>> makeController<S, M>(
  WidgetTester tester,
  TurnGame<S, M> game, {
  bool hotSeat = true,
}) async {
  final controller = await tester.runAsync(
    () => MatchController.create<S, M>(
      game: game,
      transport: LocalTransport(),
      matchId: 'board-a11y-test',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: hotSeat,
      seed: 0,
    ),
  );
  return controller!;
}

Future<void> land(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump(const Duration(milliseconds: 900));
}

Future<void> pumpBoard(
  WidgetTester tester,
  Widget board, {
  bool hostOwnsStatus = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: hostOwnsStatus
              ? GameHostChrome(hostOwnsStatus: true, child: board)
              : board,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 900));
}

void main() {
  testWidgets('swatches are named; taken colours say so; a pick plays',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester, const FillerGame());
    await pumpBoard(tester, FillerBoard(controller: controller));

    final labels = semanticLabels(tester);
    expect(labels.where((l) => l.startsWith('Pick ')), hasLength(4));
    expect(labels.where((l) => l.endsWith('already in play')), hasLength(2));

    final pick = labels.firstWhere((l) => l.startsWith('Pick '));
    final before = controller.state!.turnIndex;
    tester.semantics.tap(find.semantics.byLabel(pick));
    await land(tester);
    expect(controller.state!.turnIndex, isNot(before));

    await tester.pump(const Duration(seconds: 3));
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('a custom palette without names is announced by number',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester, const FillerGame());
    await pumpBoard(
      tester,
      FillerBoard(
        controller: controller,
        style: FillerStyle(cellColors: List.of(kFillerCellColors)),
      ),
    );
    expect(
      semanticLabels(tester).where((l) => l.contains('colour ')),
      isNotEmpty,
    );

    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('the winner pill speaks the result; the seat chips do not',
      (tester) async {
    final handle = tester.ensureSemantics();
    const game = FillerGame();
    final controller = await makeController(tester, game);
    await pumpBoard(tester, FillerBoard(controller: controller));
    expect(
      semanticLabels(tester).where((l) => l.endsWith(', to move')),
      hasLength(1),
    );

    // Greedy self-play to a decided board.
    var guard = 0;
    while (game.outcome(controller.state!) == null && guard++ < 200) {
      final s = controller.state!;
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
      await tester.runAsync(() => controller.submitMove(best!));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(game.outcome(controller.state!)?.isWin, isTrue);
    await land(tester);
    await tester.pump(const Duration(seconds: 2));

    expect(find.textContaining('WINS'), findsOneWidget);
    final labels = semanticLabels(tester);
    expect(labels.where((l) => l.contains('winner')), isEmpty);
    expect(labels.where((l) => l.contains('to move')), isEmpty);
    expect(labels.where((l) => l.contains(' cell')), hasLength(2));

    await tester.pump(const Duration(seconds: 3));
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });
}
