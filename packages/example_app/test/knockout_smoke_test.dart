import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_knockout/minigame_knockout.dart';

import 'package:example_app/screens/knockout_play_screen.dart';

void main() {
  testWidgets('Knockout play screen builds and shows both player chips',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: KnockoutPlayScreen()),
    );
    // Let the async MatchController.create + first frame settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(KnockoutBoard), findsOneWidget);
    expect(find.text('Player 1'), findsOneWidget);
    expect(find.text('Player 2'), findsOneWidget);
    expect(find.text('New game'), findsOneWidget);

    // Clean teardown (dispose closes controller + transport).
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
