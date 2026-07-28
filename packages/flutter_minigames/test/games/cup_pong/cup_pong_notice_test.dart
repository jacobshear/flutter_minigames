import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/cup_pong/cup_pong.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

// The crash this file exists for: the board used to raise its messages through
// an AnimatedSwitcher keyed on the text. A switcher keeps the outgoing child
// mounted next to the incoming one inside a Stack, so the moment a message
// repeated before the previous one had finished leaving, both children carried
// the same key and Flutter threw "Duplicate keys found" — a red screen in the
// middle of a throw.
//
// "MISS" twice in a row is not an edge case in Cup Pong. It is Tuesday.

Future<MatchController<CupPongState, CupPongThrow>> _controller() =>
    MatchController.create<CupPongState, CupPongThrow>(
      game: const CupPongGame(),
      transport: LocalTransport(),
      matchId: 'notice',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: true,
      seed: 0,
    );

void main() {
  testWidgets('a repeated message never collides with its own exit', (
    tester,
  ) async {
    String? message;
    var tone = GameNoticeTone.warn;
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
    /// notice's 180 ms exit, so the old message is still animating out when the
    /// new one arrives. That overlap is the whole bug.
    Future<void> push(String? next, int ms) async {
      set(() => message = next);
      await tester.pump();
      await tester.pump(Duration(milliseconds: ms));
      expect(tester.takeException(), isNull);
      // The invariant underneath the crash: never two live nodes for one
      // message. If this ever reads 2, the duplicate-key throw is back.
      expect(find.text('MISS').evaluate().length, lessThanOrEqualTo(1));
    }

    // The exact sequence that crashed: same text, out, same text again, all
    // inside one exit animation.
    await push('MISS', 40);
    await push(null, 20);
    await push('MISS', 40);
    await push(null, 20);
    await push('MISS', 40);

    // And with no gap at all — a message replaced by itself.
    await push('MISS', 10);
    await push('MISS', 10);

    // A tone change on the same text is also a swap, and also survives it.
    tone = GameNoticeTone.score;
    await push('MISS', 30);

    await tester.pumpAndSettle();
    expect(find.text('MISS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a run of alternating messages never doubles up', (tester) async {
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

    // A whole turn's worth of chatter, faster than any of it can leave.
    const script = [
      'MISS',
      'MISS',
      null,
      'CUP!',
      'CUP!',
      null,
      'MISS',
      'RE-RACK',
      'MISS',
      null,
      'MISS',
    ];
    for (final m in script) {
      set(() => message = m);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));
      expect(tester.takeException(), isNull);
      for (final text in const ['MISS', 'CUP!', 'RE-RACK']) {
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
    final c = await _controller();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 620,
              child: CupPongBoard(controller: c),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Structural guard: the switcher must not come back.
    expect(
      find.descendant(
        of: find.byType(CupPongBoard),
        matching: find.byType(AnimatedSwitcher),
      ),
      findsNothing,
    );
    expect(find.byType(GameNotice), findsOneWidget);
    // Whose ball it is is *present*, so it rides in a pill, not a notice.
    expect(find.textContaining('ball 1/2'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);
  });
}
