import 'package:example_app/screens/gin_rummy_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/games/gin_rummy.dart';

void main() {
  testWidgets('gin rummy screen deals a hand and plays the opening turn',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: GinRummyPlayScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(GinRummyTable), findsOneWidget);
    expect(find.text('Gin Rummy'), findsOneWidget);

    // Let the deal entrance finish: hand, opponent backs, stock and discard.
    // (Cards come from minigames_cards, which example_app does not depend on
    // directly, so the assertions here stay on the chrome the screen owns.)
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.textContaining('in the stock'), findsOneWidget);
    expect(find.textContaining('Player 1'), findsWidgets);
    expect(find.textContaining('Player 2'), findsWidgets);
    expect(find.text('DEADWOOD'), findsOneWidget);

    // The app deals seven, and the match runs to the seven-card target.
    expect(find.textContaining('7 cards'), findsNWidgets(2));
    expect(find.textContaining('/ 90'), findsNWidgets(2));

    // Opening upcard offer is live for the non-dealer (seat 0 = Player 1).
    expect(find.text('Take upcard'), findsOneWidget);
    await tester.tap(find.text('Take upcard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Having taken the upcard, the player now has to discard.
    expect(find.text('Pick a card'), findsOneWidget);
    expect(find.textContaining('Knock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
