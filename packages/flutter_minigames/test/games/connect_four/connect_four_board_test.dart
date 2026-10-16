import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/connect_four/connect_four.dart';
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

void main() {
  Future<MatchController<ConnectFourState, ConnectFourMove>> makeController(
    WidgetTester tester,
  ) async {
    final controller = await tester.runAsync(
      () => MatchController.create<ConnectFourState, ConnectFourMove>(
        game: const ConnectFourGame(),
        transport: LocalTransport(),
        matchId: 'connect-four-board-test',
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
    MatchController<ConnectFourState, ConnectFourMove> controller, {
    bool showStatusBanner = false,
    bool hostOwnsStatus = false,
    bool reduceMotion = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget board = ConnectFourBoard(
      controller: controller,
      showStatusBanner: showStatusBanner,
    );
    if (hostOwnsStatus) {
      board = GameHostChrome(hostOwnsStatus: true, child: board);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(body: Center(child: board)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));
  }

  /// Player 1 stacks column 0 four high; player 2 answers in column 1.
  Future<void> playerOneWins(
    WidgetTester tester,
    MatchController<ConnectFourState, ConnectFourMove> controller,
  ) async {
    for (final col in [0, 1, 0, 1, 0, 1, 0]) {
      await tester.runAsync(() => controller.submitMove(ConnectFourMove(col)));
      await tester.pump(const Duration(milliseconds: 900));
    }
  }

  testWidgets('the win pulse is idle until a game is won', (tester) async {
    final controller = await makeController(tester);
    await pumpBoard(tester, controller);
    // A pulse looping from the field initialiser would never settle.
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.runAsync(controller.dispose);
  });

  testWidgets('a win starts the pulse', (tester) async {
    final controller = await makeController(tester);
    await pumpBoard(tester, controller);
    await playerOneWins(tester, controller);
    await tester.pump(const Duration(seconds: 3)); // confetti and drops done
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets(
      'under Reduce Motion a win settles: no looping pulse, no confetti',
      (tester) async {
    final controller = await makeController(tester);
    await pumpBoard(tester, controller, reduceMotion: true);
    await playerOneWins(tester, controller);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('each column is a labelled drop button', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester);
    await pumpBoard(tester, controller);
    expect(semanticLabels(tester), contains('Column 1, 0 discs, drop'));
    expect(semanticLabels(tester), contains('Column 7, 0 discs, drop'));

    await tester.runAsync(() => controller.submitMove(ConnectFourMove(0)));
    await tester.pump(const Duration(milliseconds: 900));
    expect(semanticLabels(tester), contains('Column 1, 1 disc, drop'));

    // Activating a column through accessibility plays the same drop.
    final target = find.semantics.byLabel('Column 2, 0 discs, drop');
    expect(target, findsOneWidget);
    tester.semantics.tap(target);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(controller.state!.cells[1], 'p2');

    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('the banner says "to drop"; host-owned status drops it',
      (tester) async {
    final controller = await makeController(tester);
    await pumpBoard(tester, controller, showStatusBanner: true);
    expect(find.text('to drop'), findsOneWidget);

    await pumpBoard(
      tester,
      controller,
      showStatusBanner: true,
      hostOwnsStatus: true,
    );
    expect(find.text('to drop'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('distinctMarks draws a ring on the second seat only',
      (tester) async {
    Future<ui.Image> render(bool marked) async {
      final recorder = ui.PictureRecorder();
      paintCheckerDisc(
        Canvas(recorder),
        const Offset(50, 50),
        40,
        const Color(0xFFE6B422),
        marked: marked,
      );
      return recorder.endRecording().toImageSync(100, 100);
    }

    final plain = await tester.runAsync(() => render(false));
    final marked = await tester.runAsync(() => render(true));
    final plainBytes = (await tester.runAsync(plain!.toByteData))!;
    final markedBytes = (await tester.runAsync(marked!.toByteData))!;

    int pixel(ByteData data, int x, int y) => data.getUint32((y * 100 + x) * 4);
    // The ring sits at 0.40 of the radius from the centre (16px here).
    expect(pixel(markedBytes, 66, 50), isNot(pixel(plainBytes, 66, 50)));
    // The rest of the disc is untouched: a point outside the ring matches.
    expect(pixel(markedBytes, 85, 50), pixel(plainBytes, 85, 50));
  });
}
