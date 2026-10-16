import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/mancala/mancala.dart';
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

/// The semantics node whose label is exactly [label].
SemanticsNode nodeLabelled(WidgetTester tester, String label) {
  SemanticsNode? found;
  void walk(SemanticsNode node) {
    if (node.label == label) found = node;
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  // ignore: deprecated_member_use
  walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return found!;
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
  testWidgets('pits are named from each player\'s own sowing order',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller =
        await makeController(tester, MancalaGame(), hotSeat: false);
    await pumpBoard(tester, MancalaBoard(controller: controller));

    final pits = controller.state!.pits;
    String seeds(int pit) =>
        '${pits[pit]} ${pits[pit] == 1 ? 'seed' : 'seeds'}';

    final labels = semanticLabels(tester);
    expect(labels, contains('Your pit 1, ${seeds(0)}, playable'));
    expect(labels, contains('Your pit 6, ${seeds(5)}, playable'));
    expect(labels, contains('Your store, 0 seeds'));
    // The opponent's pits are named from their own end, and are not
    // playable by you.
    expect(labels, contains("Player 2's pit 1, ${seeds(7)}"));
    expect(labels, contains("Player 2's pit 6, ${seeds(12)}"));
    expect(labels, contains("Player 2's store, 0 seeds"));

    tester.semantics.tap(
      find.semantics.byLabel('Your pit 3, ${seeds(2)}, playable'),
    );
    await land(tester);
    expect(controller.state!.pits[2], 0);

    await tester.pump(const Duration(seconds: 5));
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('a pit is a button only for the seat that can sow it',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller =
        await makeController(tester, MancalaGame(), hotSeat: false);
    await pumpBoard(tester, MancalaBoard(controller: controller));

    String pit(int i, {bool playable = false}) {
      final seeds = controller.state!.pits[i];
      final who = i < 6 ? 'Your pit ${i + 1}' : "Player 2's pit ${i - 6}";
      return '$who, $seeds ${seeds == 1 ? 'seed' : 'seeds'}'
          '${playable ? ', playable' : ''}';
    }

    // Your turn: your pits are buttons you can activate.
    final mine =
        nodeLabelled(tester, pit(0, playable: true)).getSemanticsData();
    expect(mine.flagsCollection.isButton, isTrue);
    expect(mine.hasAction(SemanticsAction.tap), isTrue);

    // Pit 1's last seed lands in a filled pit, so the turn passes to p2.
    tester.semantics.tap(find.semantics.byLabel(pit(0, playable: true)));
    await land(tester);
    expect(controller.state!.currentPlayerId, 'p2');
    // Past the sow: the legal pits are only shown once the stones land.
    await tester.pump(const Duration(seconds: 3));

    // Their legal pits are lit on the board, but not offered to you.
    for (var i = 7; i < 13; i++) {
      final data = nodeLabelled(tester, pit(i)).getSemanticsData();
      expect(data.flagsCollection.isButton, isFalse, reason: 'pit $i');
      expect(data.hasAction(SemanticsAction.tap), isFalse, reason: 'pit $i');
    }
    for (var i = 0; i < 6; i++) {
      final data = nodeLabelled(tester, pit(i)).getSemanticsData();
      expect(data.flagsCollection.isButton, isFalse, reason: 'pit $i');
    }

    await tester.pump(const Duration(seconds: 5));
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });
}
