import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/chess/chess.dart';
import 'package:flutter_minigames/src/core/core.dart';

void main() {
  testWidgets('win pill shows CHECKMATE, then the winner name',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const game = ChessGame();
    final controller = await tester.runAsync(
      () => MatchController.create<ChessState, ChessMove>(
        game: game,
        transport: LocalTransport(),
        matchId: 'pill-test',
        playerIds: const ['p1', 'p2'],
        localPlayerId: 'p1',
        hotSeat: true,
        seed: 0,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: ChessBoard(controller: controller!)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    for (final uci in [
      'e2e4', 'e7e5', 'f1c4', 'b8c6', 'd1h5', 'g8f6', 'h5f7',
    ]) {
      await tester.runAsync(
          () => controller.submitMove(ChessMove.parseUci(uci)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
    }

    // Mate just landed: CHECKMATE flashes first.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('CHECKMATE'), findsOneWidget);
    expect(find.text('PLAYER 1 WINS'), findsNothing);

    // After the flash, the winner takes over (white = Player 1 delivered it).
    // Extra pump lets the AnimatedSwitcher crossfade finish.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('CHECKMATE'), findsNothing);
    expect(find.text('PLAYER 1 WINS'), findsOneWidget);

    // Let confetti finish so no tickers outlive the test.
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => controller.dispose());
  });
}
