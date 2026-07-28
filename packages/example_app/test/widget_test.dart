import 'package:example_app/main.dart';
import 'package:example_app/screens/checkers_play_screen.dart';
import 'package:example_app/screens/chess_play_screen.dart';
import 'package:example_app/screens/connect_four_play_screen.dart';
import 'package:example_app/screens/dots_and_boxes_play_screen.dart';
import 'package:example_app/screens/gomoku_play_screen.dart';
import 'package:example_app/screens/home_menu_screen.dart';
import 'package:example_app/screens/mancala_play_screen.dart';
import 'package:example_app/screens/reversi_play_screen.dart';
import 'package:example_app/screens/tictactoe_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/games/checkers.dart';
import 'package:flutter_minigames/games/chess.dart';
import 'package:flutter_minigames/games/connect_four.dart';
import 'package:flutter_minigames/games/dots_and_boxes.dart';
import 'package:flutter_minigames/games/gomoku.dart';
import 'package:flutter_minigames/games/mancala.dart';
import 'package:flutter_minigames/games/reversi.dart';
import 'package:flutter_minigames/games/tictactoe.dart';

void main() {
  testWidgets('launcher grid lists all games', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(HomeMenuScreen), findsOneWidget);
    expect(find.text('Games'), findsOneWidget);
    expect(find.text('Tic-Tac-Toe'), findsOneWidget);
    expect(find.text('4 in a Row'), findsOneWidget);
    expect(find.text('Dots & Boxes'), findsOneWidget);
    expect(find.text('Reversi'), findsOneWidget);
    expect(find.text('Checkers'), findsOneWidget);
    expect(find.text('Mancala'), findsOneWidget);
    expect(find.text('Gomoku'), findsOneWidget);
    expect(find.text('Chess'), findsOneWidget);
  });

  testWidgets('opens tic-tac-toe', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Tic-Tac-Toe'));
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

    await tester.tap(find.text('4 in a Row'));
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

    await tester.tap(find.text('Dots & Boxes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(DotsAndBoxesPlayScreen), findsOneWidget);
    expect(find.byType(DotsAndBoxesBoard), findsOneWidget);
  });

  testWidgets('opens reversi', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Reversi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(ReversiPlayScreen), findsOneWidget);
    expect(find.byType(ReversiBoard), findsOneWidget);
  });

  testWidgets('opens checkers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Checkers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(CheckersPlayScreen), findsOneWidget);
    expect(find.byType(CheckersBoard), findsOneWidget);
  });

  testWidgets('opens mancala', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Mancala'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(MancalaPlayScreen), findsOneWidget);
    expect(find.byType(MancalaBoard), findsOneWidget);
  });

  testWidgets('opens gomoku', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Gomoku'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(GomokuPlayScreen), findsOneWidget);
    expect(find.byType(GomokuBoard), findsOneWidget);
  });

  testWidgets('opens chess', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Chess'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(ChessPlayScreen), findsOneWidget);
    expect(find.byType(ChessBoard), findsOneWidget);
  });
}
