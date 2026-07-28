import 'package:example_app/screens/go_fish_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/games/go_fish.dart';

void main() {
  testWidgets('go fish screen deals a hand and plays an ask', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: GoFishPlayScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(GoFishTable), findsOneWidget);
    expect(find.text('Go Fish'), findsOneWidget);

    // Let the deal entrance finish: hand, opponent backs, pond and books.
    // (Cards come from minigames_cards, which example_app does not depend on
    // directly, so the assertions here stay on the chrome the screen owns.)
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.textContaining('Player 1'), findsWidgets);
    expect(find.textContaining('Player 2'), findsWidgets);

    // Nothing is picked yet, so the ask is not offered.
    expect(find.text('Pick a rank to ask for'), findsOneWidget);

    // Every tray in the hand is a rank the player holds — tapping one is the
    // whole rank picker.
    final trays = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_RankTray',
    );
    expect(trays, findsWidgets);
    await tester.tap(trays.first, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final ask = find.textContaining('Ask for');
    expect(ask, findsOneWidget);

    await tester.tap(ask);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Either the ask hit (the turn is kept, so the picker is live again) or it
    // missed (the phone has to be passed). Which one depends on the deal.
    final kept = find.text('Pick a rank to ask for');
    final passing = find.textContaining('Pass to');
    expect(
      kept.evaluate().isNotEmpty || passing.evaluate().isNotEmpty,
      isTrue,
      reason: 'the ask resolved into either another turn or a handoff',
    );
    expect(tester.takeException(), isNull);
  });
}
