import 'package:example_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_tictactoe/minigame_tictactoe.dart';

void main() {
  testWidgets('renders the themed tic-tac-toe demo and accepts a tap', (
    tester,
  ) async {
    // Phone-sized surface (default test surface is only 800x600).
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ExampleApp());
    // Let the async MatchController.create complete, then a couple of frames.
    // (The board has a looping "breathing" animation, so never pumpAndSettle.)
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('Tic · Tac · Toe'), findsOneWidget);
    expect(find.byType(TicTacToeBoard), findsOneWidget);

    // Tapping a cell shouldn't throw and should drive a frame.
    await tester.tap(find.byType(GestureDetector).first, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  });
}
