import 'package:example_app/screens/anagrams_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_anagrams/minigame_anagrams.dart';

void main() {
  testWidgets('anagrams hot-seat flow reaches player 2 handoff',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Load the bundled ENABLE dictionary on real async time BEFORE pumping
    // any widgets (google_fonts kicks off font fetches at first build that
    // would otherwise explode inside a later runAsync window).
    late WordDictionary dict;
    await tester.runAsync(() async {
      dict = await WordDictionary.load();
    });
    expect(dict.length, greaterThan(100000));

    await tester
        .pumpWidget(MaterialApp(home: AnagramsPlayScreen(dictionary: dict)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Player 1 pre-round cover.
    expect(find.text('Player 1 ready?'), findsOneWidget);
    await tester.tap(find.text('Start round'));
    await tester.pump(const Duration(milliseconds: 600));

    // Round board is live: submit + end-early controls and the timer bar.
    expect(find.text('Enter'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Ending the round hands off to player 2.
    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Player 2 ready?'), findsOneWidget);
    expect(find.text('Pass the phone'), findsOneWidget);
  });
}
