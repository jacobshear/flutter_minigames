import 'package:example_app/screens/archery_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('archery play screen builds, shoots, and restarts', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ArcheryPlayScreen()));

    // MatchController.create is async; the range runs a continuous ticker, so
    // pump fixed durations rather than pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    await tester.pump(const Duration(milliseconds: 32));

    // Chrome + range mounted, both chips on zero.
    expect(find.text('Archery'), findsOneWidget);
    expect(find.text('New game'), findsOneWidget);
    expect(find.text('Player 1'), findsOneWidget);
    expect(
      find.textContaining('Hold to draw', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // Draw and loose one arrow: press, hold past full draw, release.
    final range = find.byType(CustomPaint).first;
    final gesture = await tester.startGesture(tester.getCenter(range));
    // ~1.44 s of hold: full draw plus the settle, which is where the shot
    // ripens to the solved centre speed — and well short of a focus break.
    for (var i = 0; i < 45; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    await gesture.up();
    // Let the flight animate and the impact resolve.
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(tester.takeException(), isNull);
    // The arrow was scored: player 1's chip is no longer on a fresh 0 total
    // *or* the arrow missed — either way the end has advanced, so the hint is
    // back to the aiming copy rather than stuck on 'Watch it fly'.
    expect(
      find.textContaining('Hold to draw', findRichText: true),
      findsOneWidget,
    );

    // Restart wires a fresh match; the key-swap tears down the old range. This
    // must NOT throw — every AnimationController is built in initState, so
    // dispose() never late-initializes a ticker on a deactivated element.
    await tester.tap(find.text('New game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(find.text('Archery'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Unmount cleanly — no teardown exception.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);
  });
}
