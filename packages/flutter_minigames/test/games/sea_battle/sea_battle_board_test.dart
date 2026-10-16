import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/sea_battle/sea_battle.dart';
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

void main() {
  const game = SeaBattleGame();

  Future<MatchController<SeaBattleState, SeaBattleMove>> makeController(
    WidgetTester tester, {
    required bool hotSeat,
  }) async {
    final controller = await tester.runAsync(
      () => MatchController.create<SeaBattleState, SeaBattleMove>(
        game: game,
        transport: LocalTransport(),
        matchId: 'sea-battle-board-test',
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

  Widget host(Widget board, {double? height, bool hostOwnsStatus = false}) {
    Widget child = board;
    if (hostOwnsStatus) {
      child = GameHostChrome(hostOwnsStatus: true, child: child);
    }
    if (height != null) child = SizedBox(height: height, child: child);
    return MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.topCenter, child: child)),
    );
  }

  /// Hot-seat match taken to the first shot: both fleets down, the cover
  /// between turns dismissed.
  Future<MatchController<SeaBattleState, SeaBattleMove>> battleController(
    WidgetTester tester,
  ) async {
    final controller = await makeController(tester, hotSeat: true);
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(SeaBattleBoard(controller: controller)));
    await tester.pump(const Duration(milliseconds: 700));

    await tester.runAsync(
      () => controller.submitMove(PlaceFleetMove(SeaBattleGame.randomFleet(1))),
    );
    await land(tester);
    await tester.tap(find.text('Tap when ready'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.runAsync(
      () => controller.submitMove(PlaceFleetMove(SeaBattleGame.randomFleet(2))),
    );
    await land(tester);
    await tester.tap(find.text('Tap when ready'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.state!.phase, SeaBattlePhase.battle);
    return controller;
  }

  testWidgets('the battle column fits a short band without overflowing',
      (tester) async {
    final controller = await battleController(tester);

    // Natural sizes need ~630pt; every height from 440 up must fit.
    for (final height in [440.0, 500.0, 551.0, 640.0, 800.0]) {
      await tester.pumpWidget(
        host(
          SeaBattleBoard(key: ValueKey(height), controller: controller),
          height: height,
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull, reason: 'at $height tall');
      expect(
        tester.getSize(find.byType(SeaBattleBoard)).height,
        lessThanOrEqualTo(height),
        reason: 'at $height tall',
      );
    }
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('the compact fleet map shrinks before the targeting grid',
      (tester) async {
    final controller = await battleController(tester);

    Future<(double, double)> gridSides(double height) async {
      await tester.pumpWidget(
        host(
          SeaBattleBoard(key: ValueKey(height), controller: controller),
          height: height,
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      final grids = find
          .descendant(
            of: find.byType(SeaBattleBoard),
            matching: find.byType(AspectRatio),
          )
          .evaluate()
          .map((e) => (e.renderObject! as RenderBox).size.width)
          .toList()
        ..sort();
      return (grids.first, grids.last);
    }

    final tall = await gridSides(800);
    expect(tall, (150.0, 340.0)); // natural sizes when there is room

    final mid = await gridSides(551);
    expect(mid.$1, lessThan(150)); // fleet map gave way
    expect(mid.$2, greaterThan(300)); // targeting grid barely moved

    final short = await gridSides(440);
    expect(short.$1, lessThanOrEqualTo(mid.$1));
    expect(short.$2, lessThan(mid.$2));

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('an unbounded host gets the natural sizes', (tester) async {
    final controller = await battleController(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SeaBattleBoard(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(SeaBattleBoard)).height, greaterThan(600));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('a shot is taken on lift-off over the cell, not on touch-down',
      (tester) async {
    final controller = await battleController(tester);
    final grid = find
        .descendant(
          of: find.byType(SeaBattleBoard),
          matching: find.byType(GestureDetector),
        )
        .first;
    final rect = tester.getRect(grid);
    final pad = rect.width * 0.045;
    final cell = (rect.width - rect.width * 0.09) / 10;
    Offset at(int row, int col) =>
        rect.topLeft + Offset(pad + (col + 0.5) * cell, pad + (row + 0.5) * cell);

    final gesture = await tester.startGesture(at(2, 2));
    await tester.pump(const Duration(milliseconds: 200));
    await land(tester);
    expect(controller.state!.lastShotCell, isNull);

    await gesture.up();
    await land(tester);
    expect(controller.state!.lastShotCell, 22);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('target cells are labelled hit, miss or unknown',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await battleController(tester);
    expect(semanticLabels(tester), contains('Row 1, column 1, unknown'));
    expect(semanticLabels(tester), contains('Row 10, column 10, unknown'));

    await tester.runAsync(() => controller.submitMove(const FireMove(0)));
    // Mid-flight, before the hot-seat cover rises: the shot is already in
    // the state, so the cell reads as resolved.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final cellLabel = semanticLabels(tester)
        .singleWhere((l) => l.startsWith('Row 1, column 1, '));
    final isShip = controller.state!.shipCellsOf('p2').contains(0);
    // A sunk ship says so ("hit, sunk"); open water is a plain miss.
    expect(cellLabel, isShip ? startsWith('Row 1, column 1, hit') : endsWith('miss'));
    expect(semanticLabels(tester), contains('Row 10, column 10, unknown'));
    // The own-fleet map is one summary node, not a hundred cells.
    expect(
      semanticLabels(tester),
      contains('Your fleet, 10 of 10 ships afloat'),
    );
    await tester.pump(const Duration(seconds: 2));

    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('"Waiting for the enemy fleet" is the host\'s to say',
      (tester) async {
    final controller = await makeController(tester, hotSeat: false);
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(host(SeaBattleBoard(controller: controller)));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(
      () => controller.submitMove(PlaceFleetMove(SeaBattleGame.randomFleet(1))),
    );
    await land(tester);
    expect(find.text('Waiting for the enemy fleet…'), findsOneWidget);

    await tester.pumpWidget(
      host(SeaBattleBoard(controller: controller), hostOwnsStatus: true),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Waiting for the enemy fleet…'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('placement and waiting survive a band too short for the grid',
      (tester) async {
    final controller = await makeController(tester, hotSeat: false);
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The chrome around the grid alone eats these heights: the grid used to
    // get a zero-height slot and its painter divided by zero.
    Future<void> pumpAt(Object key, double height) async {
      await tester.pumpWidget(
        host(
          SeaBattleBoard(key: ValueKey(key), controller: controller),
          height: height,
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull, reason: '$key at $height tall');
      expect(
        tester.getSize(find.byType(SeaBattleBoard)).height,
        lessThanOrEqualTo(height),
        reason: '$key at $height tall',
      );
    }

    for (final height in [200.0, 150.0]) {
      await pumpAt('place$height', height);
    }
    // The grid keeps its floor layout and scales down: it is never a
    // zero-size slot.
    final grid = find.descendant(
      of: find.byType(SeaBattleBoard),
      matching: find.byType(AspectRatio),
    );
    expect(tester.getSize(grid).width, greaterThan(0));

    await tester.runAsync(
      () => controller.submitMove(PlaceFleetMove(SeaBattleGame.randomFleet(1))),
    );
    await land(tester);
    for (final height in [200.0, 150.0]) {
      await pumpAt('wait$height', height);
    }
    expect(tester.getSize(grid).width, greaterThan(0));

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('the battle column holds its floors down to ~364pt, then scales',
      (tester) async {
    final controller = await battleController(tester);

    Future<List<double>> gridSidesAt(double height) async {
      await tester.pumpWidget(
        host(
          SeaBattleBoard(key: ValueKey(height), controller: controller),
          height: height,
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull, reason: 'battle at $height');
      expect(
        tester.getSize(find.byType(SeaBattleBoard)).height,
        lessThanOrEqualTo(height),
        reason: 'battle at $height',
      );
      return find
          .descendant(
            of: find.byType(SeaBattleBoard),
            matching: find.byType(AspectRatio),
          )
          .evaluate()
          .map((e) => (e.renderObject! as RenderBox).size.width)
          .toList()
        ..sort();
    }

    // The supported minimum: both grids at their floors, no scaling.
    expect(await gridSidesAt(364), [84.0, 140.0]);

    // Below it the same floor layout shrinks to the band, grids included.
    for (final height in [300.0, 200.0]) {
      await gridSidesAt(height);
      final grid = tester.getSize(
        find
            .descendant(
              of: find.byType(SeaBattleBoard),
              matching: find.byType(AspectRatio),
            )
            .last,
      );
      expect(grid.width, lessThan(140), reason: 'scaled at $height');
      expect(grid.width, greaterThan(0), reason: 'scaled at $height');
    }
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('a shot cell is a label only; unshot cells stay buttons',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await battleController(tester);

    SemanticsData cell(String label) =>
        nodeLabelled(tester, label).getSemanticsData();

    final open = cell('Row 10, column 10, unknown');
    expect(open.flagsCollection.isButton, isTrue);
    expect(open.hasAction(SemanticsAction.tap), isTrue);

    await tester.runAsync(() => controller.submitMove(const FireMove(0)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final shot = cell(
      semanticLabels(tester).singleWhere((l) => l.startsWith('Row 1, column 1, ')),
    );
    expect(shot.flagsCollection.isButton, isFalse);
    expect(shot.hasAction(SemanticsAction.tap), isFalse);
    final still = cell('Row 10, column 10, unknown');
    expect(still.flagsCollection.isButton, isTrue);
    expect(still.hasAction(SemanticsAction.tap), isTrue);
    await tester.pump(const Duration(seconds: 2));

    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('the winner pill speaks the result; the winner chip does not',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await battleController(tester);
    expect(semanticLabels(tester), contains('Player 1, you, to move'));

    // A hit keeps the turn, so p1 sinks the whole enemy fleet in one run.
    for (final cell in controller.state!.shipCellsOf('p2')) {
      await tester.runAsync(() => controller.submitMove(FireMove(cell)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    expect(const SeaBattleGame().outcome(controller.state!)?.isWin, isTrue);
    expect(find.text('PLAYER 1 WINS'), findsOneWidget);
    expect(semanticLabels(tester), contains('Player 1, you'));
    expect(
      semanticLabels(tester).where((l) => l.contains('winner')),
      isEmpty,
    );

    await tester.pump(const Duration(seconds: 3));
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('the placement grid fits a short band too', (tester) async {
    final controller = await makeController(tester, hotSeat: false);
    for (final height in [440.0, 551.0]) {
      await tester.pumpWidget(
        host(
          SeaBattleBoard(key: ValueKey(height), controller: controller),
          height: height,
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull, reason: 'at $height tall');
    }
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });
}
