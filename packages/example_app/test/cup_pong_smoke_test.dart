import 'package:example_app/screens/cup_pong_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cup pong play screen builds, throws, and restarts', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CupPongPlayScreen()),
    );

    // MatchController.create is async; let it wire up. The board runs a ticker
    // while a throw is live, so we pump fixed durations rather than settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    await tester.pump(const Duration(milliseconds: 32));

    // Chrome + board mounted.
    expect(find.text('Cup Pong'), findsOneWidget);
    expect(find.text('New game'), findsOneWidget);
    expect(
      find.textContaining('Swipe up from the ball', findRichText: true),
      findsOneWidget,
    );
    // Ten cups a side, read off the chips.
    expect(find.text('10'), findsWidgets);
    expect(tester.takeException(), isNull);

    // A real flick runs the 3-D sim end to end and submits the outcome.
    final start =
        tester.getCenter(find.text('Cup Pong')) + const Offset(0, 260);
    final gesture = await tester.startGesture(start);
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, -22));
      await tester.pump(const Duration(milliseconds: 12));
    }
    await gesture.up();
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(tester.takeException(), isNull);

    // Restart wires a fresh match; the key-swap tears down the old board. This
    // must NOT throw — the board builds its ticker and confetti controller in
    // initState, so dispose() never late-initializes them on a dead element.
    await tester.tap(find.text('New game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(find.text('Cup Pong'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Unmount cleanly — no teardown exception.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);
  });
}
