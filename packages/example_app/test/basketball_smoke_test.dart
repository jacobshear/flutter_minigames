import 'package:example_app/screens/basketball_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('basketball: cover → shooting → mode picker → clean teardown', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BasketballPlayScreen()));

    // MatchController.create is async; let it wire up. The board runs a
    // continuous Ticker, so we pump fixed durations rather than pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    expect(find.text('Basketball'), findsOneWidget);
    expect(find.text('Player 1 ready?'), findsOneWidget);
    expect(find.textContaining('Two rounds of 45 seconds'), findsOneWidget);
    // The hoop mode is a match option, offered before anyone shoots.
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Moving hoop'), findsOneWidget);
    expect(find.text('Start match'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Pick the moving hoop, then start — this mounts the live court.
    await tester.tap(find.text('Moving hoop'));
    await tester.pump();
    await tester.tap(find.text('Start match'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    // Round chip and the aim hint are up, and the sim ticked without throwing.
    expect(find.textContaining('Round 1/2'), findsOneWidget);
    expect(find.textContaining('Drag left or right'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Flick the court: a horizontal drag should be accepted as a shot.
    await tester.drag(
      find.byType(CustomPaint).first,
      const Offset(70, -10),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 32));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    // Unmount mid-round: the Ticker and both AnimationControllers are built in
    // initState, so teardown must not late-init anything.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);
  });

  testWidgets('basketball: ending both rounds hands off to player 2', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BasketballPlayScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    await tester.tap(find.text('Start match'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    // "End round" short-circuits the clock; two of them finish the player's
    // turn and submit both scores.
    for (var round = 0; round < 2; round++) {
      await tester.tap(find.text('End round'));
      // Outro tail, then the between-rounds card. The board clamps a single
      // tick to 0.1 s (frame-spike protection), so real time has to be fed in
      // slices no larger than that.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    await tester.pump(const Duration(milliseconds: 32));

    expect(find.text('Player 2 ready?'), findsOneWidget);
    expect(find.text('Pass the phone'), findsOneWidget);
    // Player 1 scored nothing, so there is nothing to chase.
    expect(find.text('0 to beat'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);
  });
}
