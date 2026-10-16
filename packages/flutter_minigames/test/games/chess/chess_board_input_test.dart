import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/chess/chess.dart';
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
  Future<MatchController<ChessState, ChessMove>> makeController(
    WidgetTester tester,
  ) async {
    final controller = await tester.runAsync(
      () => MatchController.create<ChessState, ChessMove>(
        game: const ChessGame(),
        transport: LocalTransport(),
        matchId: 'chess-board-input-test',
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
    MatchController<ChessState, ChessMove> controller, {
    bool hostOwnsStatus = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget board = ChessBoard(controller: controller);
    if (hostOwnsStatus) {
      board = GameHostChrome(hostOwnsStatus: true, child: board);
    }
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: board))),
    );
    await tester.pump(const Duration(milliseconds: 700));
  }

  Future<void> land(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Screen centre of a square, by algebraic name ("e2").
  Offset square(WidgetTester tester, String name) {
    final rect = tester.getRect(
      find.descendant(
        of: find.byType(ChessBoard),
        matching: find.byType(GestureDetector),
      ),
    );
    final cell = ChessState.cellFromAlgebraic(name);
    final frame = rect.width * 0.068;
    final size = (rect.width - 2 * frame) / 8;
    return rect.topLeft +
        Offset(
          frame + (cell % 8 + 0.5) * size,
          frame + (cell ~/ 8 + 0.5) * size,
        );
  }

  testWidgets('a piece is selected when the finger lifts, not on touch-down',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester);
    await pumpBoard(tester, controller);

    final gesture = await tester.startGesture(square(tester, 'e2'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(semanticLabels(tester), contains('e2, white pawn'));

    await gesture.up();
    await tester.pump();
    expect(semanticLabels(tester), contains('e2, white pawn, selected'));
    expect(semanticLabels(tester), contains('e4, empty, legal move'));

    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets(
      'a move is played on lift-off, and a slid-off press plays nothing',
      (tester) async {
    final controller = await makeController(tester);
    await pumpBoard(tester, controller);

    await tester.tapAt(square(tester, 'e2'));
    await tester.pump();

    // Press on e4 but slide away before lifting: no move.
    final slid = await tester.startGesture(square(tester, 'e4'));
    await tester.pump(const Duration(milliseconds: 200));
    await slid.moveTo(square(tester, 'a8'));
    await slid.up();
    await land(tester);
    expect(controller.state!.history, isEmpty);

    await tester.tapAt(square(tester, 'e4'));
    await land(tester);
    expect(controller.state!.history, ['e2e4']);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('squares are named by file, rank, piece and colour',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester);
    await pumpBoard(tester, controller);

    expect(semanticLabels(tester), contains('a8, black rook'));
    expect(semanticLabels(tester), contains('e1, white king'));
    expect(semanticLabels(tester), contains('d4, empty'));

    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  // Fool's mate: black mates on move two.
  Future<void> foolsMate(
    WidgetTester tester,
    MatchController<ChessState, ChessMove> controller,
  ) async {
    for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
      await tester
          .runAsync(() => controller.submitMove(ChessMove.parseUci(uci)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the winner pill follows CHECKMATE without host chrome',
      (tester) async {
    final controller = await makeController(tester);
    await pumpBoard(tester, controller);
    await foolsMate(tester, controller);
    expect(find.text('CHECKMATE'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('PLAYER 2 WINS'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('host-owned status keeps CHECKMATE but drops the winner pill',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester);
    await pumpBoard(tester, controller, hostOwnsStatus: true);
    expect(semanticLabels(tester), contains('Player 1, white'));
    await foolsMate(tester, controller);
    expect(find.text('CHECKMATE'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('CHECKMATE'), findsNothing);
    expect(find.text('PLAYER 2 WINS'), findsNothing);
    // Seat chips keep their names, minus the result wording.
    expect(semanticLabels(tester), contains('Player 2, black'));
    expect(semanticLabels(tester), isNot(contains('Player 2, black, winner')));

    await tester.pump(const Duration(seconds: 2));
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('the promotion picker is modal to a screen reader',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await makeController(tester);
    await pumpBoard(tester, controller);

    // White's a-pawn walks to a7, where it can take the knight on b8.
    for (final uci in [
      'a2a4', 'b7b5', 'a4b5', 'h7h6', 'b5b6', 'h6h5', 'b6a7', 'h5h4', //
    ]) {
      await tester
          .runAsync(() => controller.submitMove(ChessMove.parseUci(uci)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
    }
    await tester.pump(const Duration(milliseconds: 300));

    final squareLabel = RegExp(r'^[a-h][1-8], ');
    Iterable<String> squares() =>
        semanticLabels(tester).where(squareLabel.hasMatch);
    expect(squares(), hasLength(64));

    await tester.tapAt(square(tester, 'a7'));
    await tester.pump();
    await tester.tapAt(square(tester, 'b8'));
    await tester.pump(const Duration(milliseconds: 300));

    // The picker is up: announced, reachable, and nothing behind it is.
    expect(semanticLabels(tester), contains('Choose a promotion piece'));
    for (final piece in ['queen', 'rook', 'knight', 'bishop']) {
      expect(semanticLabels(tester), contains('Promote to $piece'));
    }
    expect(squares(), isEmpty);

    // Picking plays the move and gives the board back.
    tester.semantics.tap(find.semantics.byLabel('Promote to queen'));
    await land(tester);
    expect(controller.state!.history.last, 'a7b8q');
    expect(semanticLabels(tester), isNot(contains('Choose a promotion piece')));
    expect(squares(), hasLength(64));
    expect(semanticLabels(tester), contains('b8, white queen'));

    handle.dispose();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.dispose);
  });
}
