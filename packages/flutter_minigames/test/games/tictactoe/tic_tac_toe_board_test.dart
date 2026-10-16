import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/tictactoe/tictactoe.dart';
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
  testWidgets('every cell is a labelled button that plays the move',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester, const TicTacToeGame());
    await pumpBoard(tester, TicTacToeBoard(controller: controller));

    expect(semanticLabels(tester), contains('Row 1, column 1, empty'));
    expect(semanticLabels(tester), contains('Row 3, column 3, empty'));

    tester.semantics.tap(find.semantics.byLabel('Row 2, column 2, empty'));
    await land(tester);
    expect(controller.state!.cells[4], 'p1');
    expect(semanticLabels(tester), contains('Row 2, column 2, X'));

    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('the banner is spoken as one sentence; host status drops it',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester, const TicTacToeGame());
    await pumpBoard(tester, TicTacToeBoard(controller: controller));
    expect(find.text('to move'), findsOneWidget);
    expect(semanticLabels(tester), contains('X to move'));

    await pumpBoard(
      tester,
      TicTacToeBoard(controller: controller),
      hostOwnsStatus: true,
    );
    expect(find.text('to move'), findsNothing);
    expect(semanticLabels(tester), isNot(contains('X to move')));

    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });
}
