import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/reversi/reversi.dart';
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
  testWidgets('cells are named and the legal moves say so', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester, const ReversiGame());
    await pumpBoard(tester, ReversiBoard(controller: controller));

    final labels = semanticLabels(tester);
    expect(labels.where((l) => l.endsWith('legal move')), hasLength(4));
    expect(labels.where((l) => l.contains('dark disc')), hasLength(2));
    expect(labels.where((l) => l.contains('light disc')), hasLength(2));

    final move = labels.firstWhere((l) => l.endsWith('legal move'));
    tester.semantics.tap(find.semantics.byLabel(move));
    await land(tester);
    expect(
      controller.state!.cells.where((c) => c != null),
      hasLength(5),
    );

    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('the turn text goes quiet under host-owned status; scores stay',
      (tester) async {
    final controller = await makeController(tester, const ReversiGame());
    await pumpBoard(tester, ReversiBoard(controller: controller));
    expect(find.text('to play'), findsOneWidget);

    await pumpBoard(
      tester,
      ReversiBoard(controller: controller),
      hostOwnsStatus: true,
    );
    expect(find.text('to play'), findsNothing);
    expect(find.text('Dark'), findsOneWidget); // the score chip stays

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });
}
