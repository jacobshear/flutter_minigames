import 'package:flutter/material.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/knockout/knockout.dart';
import 'package:flutter_minigames/src/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';

// The controller is never disposed, only the widget is unmounted — see
// test/games/cup_pong/cup_pong_board_test.dart for why.

Future<MatchController<KnockoutState, KnockoutMove>> _controller() =>
    MatchController.create<KnockoutState, KnockoutMove>(
      game: const KnockoutGame(),
      transport: LocalTransport(),
      matchId: 'chrome',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: false,
      seed: 0,
    );

Widget _host(
  MatchController<KnockoutState, KnockoutMove> c, {
  bool? hostOwnsStatus,
}) {
  Widget board = KnockoutBoard(controller: c);
  if (hostOwnsStatus != null) {
    board = GameHostChrome(hostOwnsStatus: hostOwnsStatus, child: board);
  }
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, height: 640, child: board)),
    ),
  );
}

void main() {
  testWidgets('without a host the standing turn pill is drawn', (tester) async {
    final c = await _controller();
    await tester.pumpWidget(_host(c));
    await tester.pump();

    expect(find.textContaining('’s turn'), findsOneWidget);
  });

  testWidgets('a host that owns status drops the turn pill', (tester) async {
    final c = await _controller();
    await tester.pumpWidget(_host(c, hostOwnsStatus: true));
    await tester.pump();

    expect(find.textContaining('’s turn'), findsNothing);
    // The wind-up count is the board's own rule line: it stays.
    expect(find.textContaining('to wind up'), findsOneWidget);
  });

  testWidgets('the platform is described for a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    final c = await _controller();
    await tester.pumpWidget(_host(c));
    await tester.pump();

    expect(
      find.bySemanticsLabel(
        RegExp(r'^Knockout\. 5 pucks on the platform for you, 5 pucks for'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
