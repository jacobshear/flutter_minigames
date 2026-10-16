import 'package:flutter/material.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/cup_pong/cup_pong.dart';
import 'package:flutter_minigames/src/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';

// Same convention as cup_pong_board_test.dart: the controller is never
// disposed, only the widget is unmounted.

Future<MatchController<CupPongState, CupPongThrow>> _controller() =>
    MatchController.create<CupPongState, CupPongThrow>(
      game: const CupPongGame(),
      transport: LocalTransport(),
      matchId: 'chrome',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: false,
      seed: 0,
    );

Widget _host(
  MatchController<CupPongState, CupPongThrow> c, {
  bool? hostOwnsStatus,
}) {
  Widget board = CupPongBoard(controller: c);
  if (hostOwnsStatus != null) {
    board = GameHostChrome(hostOwnsStatus: hostOwnsStatus, child: board);
  }
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, height: 620, child: board)),
    ),
  );
}

void main() {
  testWidgets('without a host the standing turn pill is drawn', (tester) async {
    final c = await _controller();
    await tester.pumpWidget(_host(c));
    await tester.pump();

    expect(find.textContaining('· ball'), findsOneWidget);
  });

  testWidgets('a host that owns status drops the turn pill', (tester) async {
    final c = await _controller();
    await tester.pumpWidget(_host(c, hostOwnsStatus: true));
    await tester.pump();

    expect(find.textContaining('· ball'), findsNothing);
    // The aiming hint is a rule, not status: it stays.
    expect(find.textContaining('Swipe up from the ball'), findsOneWidget);
  });

  testWidgets('the board is described for a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    final c = await _controller();
    await tester.pumpWidget(_host(c));
    await tester.pump();

    expect(
      find.bySemanticsLabel(
        RegExp(r'^Cup pong\. Their side: 10 cups\. Your side: 10 cups\.'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
