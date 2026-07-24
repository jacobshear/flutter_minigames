import 'package:example_app/screens/sea_battle_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_sea_battle/minigame_sea_battle.dart';

void main() {
  testWidgets('sea battle: placement → handoff → battle', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: SeaBattlePlayScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SeaBattleBoard), findsOneWidget);
    // Player 1 is placing: shuffle + ready controls visible.
    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);

    // Shuffle re-rolls without blowing up.
    await tester.tap(find.text('Shuffle'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Ready'), findsOneWidget);

    // Commit player 1's fleet → handoff cover for player 2.
    await tester.tap(find.text('Ready'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pass to Player 2'), findsOneWidget);

    await tester.tap(find.text('Pass to Player 2'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Ready'), findsOneWidget);

    // Commit player 2's fleet → handoff back to player 1 for battle.
    await tester.tap(find.text('Ready'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pass to Player 1'), findsOneWidget);

    await tester.tap(find.text('Pass to Player 1'));
    await tester.pump(const Duration(milliseconds: 700));

    // Battle phase: placement controls gone, board still up.
    expect(find.text('Ready'), findsNothing);
    expect(find.text('Shuffle'), findsNothing);
    expect(find.byType(SeaBattleBoard), findsOneWidget);

    // New game resets to placement.
    await tester.tap(find.text('New game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ready'), findsOneWidget);
  });
}
