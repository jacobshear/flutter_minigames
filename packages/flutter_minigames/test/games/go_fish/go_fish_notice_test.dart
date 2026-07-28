import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

import 'package:flutter_minigames/src/games/go_fish/go_fish.dart';

/// Go Fish repeats its commentary constantly — "Go fish — but the pond is
/// empty" fires on every dry ask in a row, and a book of the same rank reads
/// identically each time. The old chrome wrapped that message in an
/// [AnimatedSwitcher] keyed on the text, which keeps the outgoing child
/// mounted beside the incoming one: the repeat collided with its own
/// still-animating corpse and threw "Duplicate keys found". Keying the empty
/// branch does not help, because the collision is between a message and
/// itself.
void main() {
  Widget host(String? message) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: IntrinsicWidth(
              child: GameNotice(
                message: message,
                tone: GameNoticeTone.info,
              ),
            ),
          ),
        ),
      );

  testWidgets('a repeated commentary line never mounts two nodes',
      (tester) async {
    const line = 'Go fish — but the pond is empty';

    await tester.pumpWidget(host(line));
    await tester.pump(const Duration(milliseconds: 60));

    // message -> null -> same message, all inside the 260ms entrance and the
    // 180ms exit. Three dry asks back to back.
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(host(null));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpWidget(host(line));
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.takeException(), isNull);
      expect(find.byType(Text).evaluate().length, lessThanOrEqualTo(1));
    }

    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text(line), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the table survives the same event arriving twice',
      (tester) async {
    // A real match: two asks that both come back "go fish" produce the same
    // sentence twice in a row through the live table.
    final transport = LocalTransport();
    final controller = await MatchController.create<GoFishState, GoFishMove>(
      game: const GoFishGame(),
      transport: transport,
      matchId: 'notice-repeat',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      seed: 12345,
      hotSeat: true,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoFishTable(
            controller: controller,
            style: const GoFishStyle(handoffCover: false),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));

    // Drive several asks with no settle time between them, so each new
    // commentary line lands while the previous one is still animating.
    for (var i = 0; i < 6; i++) {
      final s = controller.state!;
      final seat = s.currentIndex;
      final hand = s.hands[seat];
      if (hand.isEmpty) break;
      await controller.submitMove(GoFishMove.ask(hand.first.rank));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.takeException(), isNull);
    }

    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
