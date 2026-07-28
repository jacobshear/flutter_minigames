import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/basketball/basketball.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

// The crash this file exists for: the court used to raise its messages through
// an AnimatedSwitcher keyed on the text. A switcher keeps the outgoing child
// mounted next to the incoming one inside a Stack, so a message that repeated
// before the previous one had finished leaving gave two children the same key
// and Flutter threw "Duplicate keys found".
//
// Basketball fires a message per make, and balls land 250 ms apart. Two
// swishes in a row is the normal case, not a race.

void main() {
  testWidgets('a repeated message never collides with its own exit', (
    tester,
  ) async {
    String? message;
    var tone = GameNoticeTone.score;
    late StateSetter set;

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                set = setState;
                return GameNotice(message: message, tone: tone);
              },
            ),
          ),
        ),
      ),
    );

    /// Push [next] and let only [ms] elapse — deliberately less than the
    /// notice's 180 ms exit, so the outgoing message is still on screen when
    /// its replacement arrives. That overlap is the whole bug.
    Future<void> push(String? next, int ms) async {
      set(() => message = next);
      await tester.pump();
      await tester.pump(Duration(milliseconds: ms));
      expect(tester.takeException(), isNull);
      // Never two live nodes for one message. A 2 here is the duplicate-key
      // throw coming back.
      expect(find.text('SWISH!').evaluate().length, lessThanOrEqualTo(1));
    }

    // Exactly the sequence that crashed.
    await push('SWISH!', 40);
    await push(null, 20);
    await push('SWISH!', 40);
    await push(null, 20);
    await push('SWISH!', 40);

    // Replaced by itself, with no empty state in between.
    await push('SWISH!', 10);
    await push('SWISH!', 10);

    // A tone change on the same text is also a swap.
    tone = GameNoticeTone.warn;
    await push('SWISH!', 30);

    await tester.pumpAndSettle();
    expect(find.text('SWISH!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a run of makes and round cards never doubles up', (
    tester,
  ) async {
    String? message;
    late StateSetter set;

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                set = setState;
                return GameNotice(message: message);
              },
            ),
          ),
        ),
      ),
    );

    const script = [
      'SWISH!',
      'SWISH!',
      null,
      'BUCKET!',
      'SWISH!',
      'SWISH!',
      null,
      'ROUND 2',
      'SWISH!',
      null,
      'SWISH!',
    ];
    for (final m in script) {
      set(() => message = m);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));
      expect(tester.takeException(), isNull);
      for (final text in const ['SWISH!', 'BUCKET!', 'ROUND 2']) {
        expect(find.text(text).evaluate().length, lessThanOrEqualTo(1),
            reason: text);
      }
    }

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the board routes its chrome through GameNotice/GamePill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            height: 700,
            child: BasketballRoundBoard(
              game: const BasketballGame(),
              playerLabel: 'P1',
              opponentLabel: 'P2',
              seed: 3,
              onComplete: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    // Structural guard: the switcher must not come back.
    expect(
      find.descendant(
        of: find.byType(BasketballRoundBoard),
        matching: find.byType(AnimatedSwitcher),
      ),
      findsNothing,
    );
    // The round card is an event, so it is a notice…
    expect(find.text('ROUND 1'), findsOneWidget);
    // …and the round counter is simply present, so it is a pill.
    expect(find.byType(GamePill), findsOneWidget);
    expect(find.textContaining('Round 1/2'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // It leaves on its own once the TTL runs out — no Timer involved.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('ROUND 1'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);
  });
}
