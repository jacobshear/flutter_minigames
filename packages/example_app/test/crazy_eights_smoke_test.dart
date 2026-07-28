import 'package:example_app/screens/crazy_eights_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/games/crazy_eights.dart';

void main() {
  testWidgets('crazy 8s play screen deals a hand and shows the table',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: CrazyEightsPlayScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CrazyEightsTable), findsOneWidget);
    expect(find.text('Crazy 8s'), findsOneWidget);

    // Let the deal entrance finish; the fan (8 cards), opponent backs (8),
    // stock stack, and discard top should all be present.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byType(PlayingCardView), findsWidgets);

    // Player chips render with card counts.
    expect(find.textContaining('Player 1'), findsOneWidget);
    expect(find.textContaining('Player 2'), findsOneWidget);
  });
}
