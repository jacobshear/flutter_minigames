import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minigames_ui/minigames_ui.dart';

/// The table's message chrome used to be an [AnimatedSwitcher] keyed on the
/// message text. A switcher keeps the outgoing child mounted next to the
/// incoming one, so a message that repeats before the previous one has
/// finished leaving — including via the empty state between two messages —
/// put two identically-keyed children in the same Stack and threw
/// "Duplicate keys found". Two consecutive refused taps do exactly that.
///
/// [GameNotice] animates a single node. These tests pin that down.
void main() {
  Widget host(String? message) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: GameNotice(
              message: message,
              tone: GameNoticeTone.warn,
            ),
          ),
        ),
      );

  testWidgets('the same message repeating inside the animation window is safe',
      (tester) async {
    const msg = 'That one will not go there';

    await tester.pumpWidget(host(msg));
    await tester.pump(const Duration(milliseconds: 40));

    // Clear and re-raise the identical message mid-flight, twice — the exact
    // sequence a player produces by jabbing the same illegal card.
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(host(null));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pumpWidget(host(msg));
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.takeException(), isNull);
    }

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(msg), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('alternating messages never leave two nodes mounted',
      (tester) async {
    const a = 'Player 2 passes — nothing to play';
    const b = 'That one will not go there';

    await tester.pumpWidget(host(a));
    await tester.pump(const Duration(milliseconds: 50));
    for (final m in const [b, a, b, a, a, b]) {
      await tester.pumpWidget(host(m));
      await tester.pump(const Duration(milliseconds: 25));
      expect(tester.takeException(), isNull);
      // One node, always: the queued message waits for the exit instead of
      // being mounted alongside it.
      expect(find.byType(Text).evaluate().length, lessThanOrEqualTo(1));
    }

    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
  });

  // The table hands GameNotice a sequence number as its token, because a
  // second refusal is a distinct event that happens to reuse the sentence.
  // Keying on the text alone made the repeat jab silent once the first had
  // auto-dismissed. This mirrors the table's wiring: same message, bumped
  // token, an autoDismiss in between.
  testWidgets('a repeated refusal fires again after the first dismissed',
      (tester) async {
    const msg = 'That one will not go there';
    Widget refusal(int seq) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: GameNotice(
                message: msg,
                tone: GameNoticeTone.warn,
                token: seq,
                autoDismiss: const Duration(milliseconds: 600),
              ),
            ),
          ),
        );

    await tester.pumpWidget(refusal(1));
    await tester.pumpAndSettle();
    expect(find.text(msg), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text(msg), findsNothing);

    // Jab the same illegal card again.
    await tester.pumpWidget(refusal(2));
    await tester.pumpAndSettle();
    expect(find.text(msg), findsOneWidget,
        reason: 'the second refusal was swallowed by message equality');
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-dismiss retracts without the caller running a timer',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GameNotice(
              message: 'Player 2 calls hearts',
              tone: GameNoticeTone.score,
              autoDismiss: const Duration(milliseconds: 300),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Player 2 calls hearts'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Player 2 calls hearts'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
