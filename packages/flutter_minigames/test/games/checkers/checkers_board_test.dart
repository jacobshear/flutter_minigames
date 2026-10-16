import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/checkers/checkers.dart';
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
  testWidgets('playable squares are named; selecting shows legal moves',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester, const CheckersGame());
    await pumpBoard(
      tester,
      CheckersBoard(controller: controller, showStatusBanner: false),
    );

    expect(semanticLabels(tester), contains('Row 6, column 1, dark man'));
    expect(semanticLabels(tester), contains('Row 3, column 2, red man'));
    expect(semanticLabels(tester), contains('Row 4, column 1, empty'));
    // Light squares never hold a piece, so they stay out of the reading order.
    expect(
      semanticLabels(tester).where((l) => l.startsWith('Row 1, column 1,')),
      isEmpty,
    );

    tester.semantics.tap(find.semantics.byLabel('Row 6, column 1, dark man'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      semanticLabels(tester),
      contains('Row 6, column 1, dark man, selected'),
    );
    expect(
      semanticLabels(tester),
      contains('Row 5, column 2, empty, legal move'),
    );

    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('host-owned status turns the banner off', (tester) async {
    final controller = await makeController(tester, const CheckersGame());
    await pumpBoard(tester, CheckersBoard(controller: controller));
    expect(find.text('to play'), findsOneWidget);

    await pumpBoard(
      tester,
      CheckersBoard(controller: controller),
      hostOwnsStatus: true,
    );
    expect(find.text('to play'), findsNothing);
    expect(find.text('Dark'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });
}
