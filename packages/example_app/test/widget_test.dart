import 'package:example_app/main.dart';
import 'package:example_app/screens/home_menu_screen.dart';
import 'package:example_app/screens/tictactoe_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_tictactoe/minigame_tictactoe.dart';

void main() {
  testWidgets('main menu lists tic-tac-toe and opens the play screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Skip DemoSfx.init (main()) — ExampleApp alone is enough for widget tests.
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(HomeMenuScreen), findsOneWidget);
    expect(find.text('Play locally'), findsOneWidget);
    expect(find.text('Tic-tac-toe'), findsOneWidget);
    expect(find.text('Coming soon'), findsWidgets);

    await tester.tap(find.text('Tic-tac-toe'));
    // MatchController.create is async.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(TicTacToePlayScreen), findsOneWidget);
    expect(find.byType(TicTacToeBoard), findsOneWidget);
    expect(find.textContaining('Tic'), findsWidgets);

    await tester.tap(find.byType(GestureDetector).first, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  });
}
