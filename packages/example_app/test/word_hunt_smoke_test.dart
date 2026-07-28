import 'package:example_app/screens/word_hunt_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/games/word_hunt.dart';

void main() {
  testWidgets('word hunt screen loads the dictionary and starts a round',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The ENABLE list is too large for the asset-bundle cache, so load it on
    // the real event loop BEFORE any widgets exist and pre-seed the screen's
    // shared future. The seeded Future MUST be created OUTSIDE runAsync so it
    // lives in the fake-async zone (a future minted in runAsync's real zone
    // never resolves under fake-async pumps). No runAsync after this point,
    // which keeps google_fonts' fetch futures dormant like widget_test.dart.
    final dict = await tester.runAsync(WordDictionary.load);
    WordHuntPlayScreen.dictionaryFuture = Future.value(dict);

    await tester.pumpWidget(const MaterialApp(home: WordHuntPlayScreen()));
    await tester.pump();
    expect(find.text('Word Hunt'), findsOneWidget);

    // Board generation + match creation resolve on fake-async microtasks.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(WordHuntBoard), findsOneWidget);
    expect(find.text('Player 1 ready?'), findsOneWidget);

    await tester.tap(find.text('Start round'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('SCORE'), findsOneWidget);

    // Tear down while the round timer is live.
    await tester.pumpWidget(Container());
  });
}
