import 'package:example_app/screens/mini_golf_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_mini_golf/minigame_mini_golf.dart';

void main() {
  testWidgets('mini golf play screen builds, putts, and restarts', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: MiniGolfPlayScreen()),
    );

    // MatchController.create is async; let it wire up. The board runs a ticker
    // while a putt plays back, so we pump fixed durations rather than settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    // Chrome + board mounted.
    expect(find.text('Mini Golf'), findsOneWidget);
    expect(find.text('New game'), findsOneWidget);
    expect(find.text('9 holes'), findsOneWidget);
    expect(
      find.textContaining('Drag back from the ball', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // A real drag on the board hits the slingshot: aim, release, simulate, play
    // the roll back, submit the move. The putt must resolve without throwing
    // and must cost a stroke.
    await tester.drag(find.byType(MiniGolfBoard), const Offset(0, 90));
    await tester.pump();
    var sawStroke = false;
    for (var i = 0; i < 140; i++) {
      await tester.pump(const Duration(milliseconds: 32));
      if (find.text('Stroke 1').evaluate().isNotEmpty) sawStroke = true;
    }
    expect(sawStroke, isTrue,
        reason: 'the drag never resolved into a counted putt');
    expect(tester.takeException(), isNull);

    // Tearing the board down *mid-roll* is the risky path: the putt playback
    // controller and the camera ticker are both live. Neither may throw.
    await tester.drag(find.byType(MiniGolfBoard), const Offset(0, 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 64));
    await tester.tap(find.text('New game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 64));
    expect(tester.takeException(), isNull);

    // Switching course length starts a different match.
    await tester.tap(find.text('3 holes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);

    // Restart wires a fresh match; the key-swap tears down the old board. This
    // must NOT throw — the board builds its controllers in initState, so
    // dispose() never late-initializes a ticker on a deactivated element.
    await tester.tap(find.text('New game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(find.text('Mini Golf'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Unmount cleanly — no teardown exception.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);
  });
}
