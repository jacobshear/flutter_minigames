import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/gomoku/gomoku.dart';
import 'package:flutter_minigames/src/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Every semantics label currently in the tree. `find.bySemanticsLabel` does
/// not see the virtual nodes a `CustomPainter` contributes, so walk the tree.
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

void main() {
  Future<MatchController<GomokuState, GomokuMove>> makeController(
    WidgetTester tester,
  ) async {
    final controller = await tester.runAsync(
      () => MatchController.create<GomokuState, GomokuMove>(
        game: const GomokuGame(),
        transport: LocalTransport(),
        matchId: 'gomoku-board-test',
        playerIds: const ['p1', 'p2'],
        localPlayerId: 'p1',
        hotSeat: true,
        seed: 0,
      ),
    );
    return controller!;
  }

  Future<void> pumpBoard(
    WidgetTester tester,
    MatchController<GomokuState, GomokuMove> controller, {
    GomokuStyle style = const GomokuStyle(),
    bool hostOwnsStatus = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget board = GomokuBoard(controller: controller, style: style);
    if (hostOwnsStatus) {
      board = GameHostChrome(hostOwnsStatus: true, child: board);
    }
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: board))),
    );
    await tester.pump(const Duration(milliseconds: 700));
  }

  /// Let the controller's async write land, then rebuild.
  Future<void> land(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Screen position of intersection (row, col) on the 15x15 board.
  Offset intersection(WidgetTester tester, int row, int col) {
    final rect = tester.getRect(
      find.descendant(
        of: find.byType(GomokuBoard),
        matching: find.byType(GestureDetector),
      ),
    );
    final pad = rect.width * 0.055;
    final spacing = (rect.width - rect.width * 0.11) / 14;
    return rect.topLeft + Offset(pad + col * spacing, pad + row * spacing);
  }

  testWidgets('a stone is placed when the finger lifts, not on touch-down',
      (tester) async {
    final controller = await makeController(tester);
    await pumpBoard(tester, controller);
    final at = intersection(tester, 7, 7);

    final gesture = await tester.startGesture(at);
    // Long enough for the old touch-down handler to have fired.
    await tester.pump(const Duration(milliseconds: 200));
    await land(tester);
    expect(controller.state!.stoneCount, 0);

    await gesture.up();
    await land(tester);
    expect(controller.state!.stoneCount, 1);
    expect(controller.state!.cells[7 * 15 + 7], 'p1');

    await tester.runAsync(controller.dispose);
  });

  testWidgets('a press that slides off the intersection places nothing',
      (tester) async {
    final controller = await makeController(tester);
    await pumpBoard(tester, controller);

    final gesture = await tester.startGesture(intersection(tester, 7, 7));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveTo(intersection(tester, 3, 3));
    await gesture.up();
    await land(tester);
    expect(controller.state!.stoneCount, 0);

    await tester.runAsync(controller.dispose);
  });

  testWidgets('confirmPlacement: ghost on the first tap, commit on the second',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester);
    await pumpBoard(
      tester,
      controller,
      style: const GomokuStyle(confirmPlacement: true),
    );
    const pending = ', selected, tap again to place';

    await tester.tapAt(intersection(tester, 7, 7));
    await land(tester);
    expect(controller.state!.stoneCount, 0);
    expect(semanticLabels(tester), contains('Row 8, column 8, empty$pending'));

    // Tapping elsewhere moves the ghost.
    await tester.tapAt(intersection(tester, 2, 2));
    await land(tester);
    expect(controller.state!.stoneCount, 0);
    expect(semanticLabels(tester), contains('Row 8, column 8, empty'));
    expect(semanticLabels(tester), contains('Row 3, column 3, empty$pending'));

    // The same intersection again commits.
    await tester.tapAt(intersection(tester, 2, 2));
    await land(tester);
    expect(controller.state!.stoneCount, 1);
    expect(controller.state!.cells[2 * 15 + 2], 'p1');
    expect(semanticLabels(tester).where((l) => l.contains('tap again to place')), isEmpty);

    handle.dispose();
    await tester.runAsync(controller.dispose);
  });

  Future<void> blackWins(
    WidgetTester tester,
    MatchController<GomokuState, GomokuMove> controller,
  ) async {
    // Black: row 0, columns 0-4. White: row 1, columns 0-3.
    for (final cell in [0, 15, 1, 16, 2, 17, 3, 18, 4]) {
      await tester.runAsync(() => controller.submitMove(GomokuMove(cell)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the result pill and chip turn text show without host chrome',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester);
    await pumpBoard(tester, controller);
    expect(semanticLabels(tester), contains('Player 1, black, to move'));

    await blackWins(tester, controller);
    expect(find.text('PLAYER 1 WINS'), findsOneWidget);
    // The pill says who won; the chip does not say it a second time.
    expect(semanticLabels(tester), contains('Player 1, black'));
    expect(
      semanticLabels(tester).where((l) => l.contains('winner')),
      isEmpty,
    );

    await tester.pump(const Duration(seconds: 2));
    handle.dispose();
    await tester.runAsync(controller.dispose);
  });

  testWidgets('hostOwnsStatus drops the result pill and the turn wording',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester);
    await pumpBoard(tester, controller, hostOwnsStatus: true);
    // The seat chip keeps its name but not "to move".
    expect(semanticLabels(tester), contains('Player 1, black'));
    expect(semanticLabels(tester), isNot(contains('Player 1, black, to move')));

    await blackWins(tester, controller);
    expect(find.text('PLAYER 1 WINS'), findsNothing);
    expect(
      semanticLabels(tester).where((l) => l.contains('winner')),
      isEmpty,
    );
    expect(find.text('Player 1'), findsOneWidget); // the chip stays

    await tester.pump(const Duration(seconds: 2));
    handle.dispose();
    await tester.runAsync(controller.dispose);
  });

  testWidgets('every intersection is a labelled button', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester);
    await pumpBoard(tester, controller);

    expect(semanticLabels(tester), contains('Row 1, column 1, empty'));
    expect(semanticLabels(tester), contains('Row 15, column 15, empty'));

    await tester.runAsync(() => controller.submitMove(const GomokuMove(0)));
    await land(tester);
    expect(semanticLabels(tester), contains('Row 1, column 1, black stone, last move'));

    handle.dispose();
    await tester.runAsync(controller.dispose);
  });

  testWidgets('only a point that can be played is a button', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester);
    await pumpBoard(tester, controller);

    bool isButton(String label) => nodeLabelled(tester, label)
        .getSemanticsData()
        .flagsCollection
        .isButton;
    bool canTap(String label) => nodeLabelled(tester, label)
        .getSemanticsData()
        .hasAction(SemanticsAction.tap);

    expect(isButton('Row 15, column 15, empty'), isTrue);
    expect(canTap('Row 15, column 15, empty'), isTrue);

    // A stone leaves nothing to activate.
    await tester.runAsync(() => controller.submitMove(const GomokuMove(0)));
    await land(tester);
    const stone = 'Row 1, column 1, black stone, last move';
    expect(isButton(stone), isFalse);
    expect(canTap(stone), isFalse);
    expect(isButton('Row 15, column 15, empty'), isTrue);

    handle.dispose();
    await tester.runAsync(controller.dispose);
  });

  testWidgets('no point is a button once the game is over', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester);
    await pumpBoard(tester, controller);
    await blackWins(tester, controller);

    final empty = nodeLabelled(tester, 'Row 15, column 15, empty');
    expect(empty.getSemanticsData().flagsCollection.isButton, isFalse);
    expect(empty.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);

    await tester.pump(const Duration(seconds: 2));
    handle.dispose();
    await tester.runAsync(controller.dispose);
  });
}
