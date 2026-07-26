import 'package:example_app/screens/darts_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('darts play screen builds, throws a dart, and restarts',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DartsPlayScreen()));

    // MatchController.create is async; let it wire up. The board runs a ticker
    // while a dart is in the air, so we pump fixed durations, not pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    // Chrome + scene mounted, both players on 501.
    expect(find.text('Darts'), findsOneWidget);
    expect(find.text('New game'), findsOneWidget);
    expect(find.text('501'), findsNWidgets(2));
    expect(
      find.textContaining('Swipe up to throw', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // Swipe up to throw: a real flick, simulated by the real physics, scored by
    // the real geometry, submitted through the controller. The drag starts over
    // the board face on purpose — there is no aiming mode any more, so a swipe
    // anywhere on the scene is a throw.
    final box = tester.getRect(find.byType(DartsPlayScreen));
    final from = Offset(box.center.dx, box.center.dy);
    final gesture = await tester.startGesture(from);
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(from + Offset(3.0 * i, -25.0 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    // Let the dart fly: ~0.4 s of flight at 60 fps, then the state update.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
    // One of the two 501s has been replaced by a lower score.
    expect(find.text('501'), findsOneWidget);

    // Restart wires a fresh match; the key-swap tears down the old board. This
    // must NOT throw — the board builds its controllers in initState, so
    // dispose() never late-initializes a ticker on a deactivated element.
    await tester.tap(find.text('New game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(find.text('Darts'), findsOneWidget);
    expect(find.text('501'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    // Unmount cleanly — no teardown exception.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);
  });
}
