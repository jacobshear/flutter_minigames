import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:example_app/screens/shuffleboard_play_screen.dart';

void main() {
  testWidgets('shuffleboard play screen builds, runs, and restarts', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ShuffleboardPlayScreen()),
    );

    // MatchController.create is async; let it wire up. Flame's GameWidget runs a
    // continuous loop so we pump fixed durations rather than pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    await tester.pump(const Duration(milliseconds: 32));

    // Chrome + board mounted.
    expect(find.text('Shuffleboard'), findsOneWidget);
    expect(find.text('New game'), findsOneWidget);
    expect(
      find.textContaining('drag back from the puck', findRichText: true),
      findsOneWidget,
    );
    // Nothing threw while the board was live.
    expect(tester.takeException(), isNull);

    // Restart wires a fresh match; the key-swap tears down the old board. This
    // must NOT throw — the board builds its confetti controller in initState, so
    // dispose() never late-initializes a ticker on a deactivated element.
    await tester.tap(find.text('New game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(find.text('Shuffleboard'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Unmount cleanly — no teardown exception.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);
  });
}
