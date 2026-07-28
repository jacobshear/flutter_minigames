import 'package:example_app/screens/word_bites_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/games/word_bites.dart';
import 'package:flutter_minigames/words.dart';

void main() {
  testWidgets('word bites: ready cover, round board, early end to handoff',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dict = WordDictionary.fromWords(['the', 'ten', 'net', 'rat']);
    await tester.pumpWidget(
      MaterialApp(home: WordBitesPlayScreen(dictionary: dict)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Word Bites'), findsOneWidget);
    expect(find.text('Player 1 ready?'), findsOneWidget);

    await tester.tap(find.text('Start round'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(WordBitesBoard), findsOneWidget);
    expect(find.text('Player 1'), findsOneWidget);
    expect(find.text('1:30'), findsOneWidget);

    // End player 1's round early — hand-off cover appears.
    await tester.tap(find.text('End round'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('Pass to Player 2'), findsOneWidget);

    // Tear down while the screen (and its 90 s ticker) is disposed cleanly.
    await tester.pumpWidget(const SizedBox());
  });
}
