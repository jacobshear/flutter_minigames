import 'package:example_app/main.dart';
import 'package:example_app/screens/connect_four_play_screen.dart';
import 'package:example_app/screens/dots_and_boxes_play_screen.dart';
import 'package:example_app/screens/home_menu_screen.dart';
import 'package:example_app/screens/tictactoe_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_connect_four/minigame_connect_four.dart';
import 'package:minigame_dots_and_boxes/minigame_dots_and_boxes.dart';
import 'package:minigame_tictactoe/minigame_tictactoe.dart';

void main() {
  testWidgets('main menu lists all three games', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(HomeMenuScreen), findsOneWidget);
    expect(find.text('Play locally'), findsOneWidget);
    expect(find.text('Tic-tac-toe'), findsOneWidget);
    expect(find.text('Connect four'), findsOneWidget);
    expect(find.text('Dots and boxes'), findsOneWidget);
    expect(find.text('Coming soon'), findsNothing);
  });

  testWidgets('opens tic-tac-toe', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Tic-tac-toe'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(TicTacToePlayScreen), findsOneWidget);
    expect(find.byType(TicTacToeBoard), findsOneWidget);
  });

  testWidgets('opens connect four', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Connect four'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(ConnectFourPlayScreen), findsOneWidget);
    expect(find.byType(ConnectFourBoard), findsOneWidget);
  });

  testWidgets('opens dots and boxes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Dots and boxes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(DotsAndBoxesPlayScreen), findsOneWidget);
    expect(find.byType(DotsAndBoxesBoard), findsOneWidget);
  });
}
