import 'package:flutter/material.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/shuffleboard/shuffleboard.dart';
import 'package:flutter_minigames/src/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';

// The controller is never disposed, only the widget is unmounted — see
// test/games/cup_pong/cup_pong_board_test.dart for why.

Future<MatchController<ShuffleboardState, ShuffleboardMove>>
    _controller() =>
        MatchController.create<ShuffleboardState, ShuffleboardMove>(
          game: const ShuffleboardGame(),
          transport: LocalTransport(),
          matchId: 'chrome',
          playerIds: const ['p1', 'p2'],
          localPlayerId: 'p1',
          hotSeat: false,
          seed: 0,
        );

Widget _host(
  MatchController<ShuffleboardState, ShuffleboardMove> c, {
  bool? hostOwnsStatus,
}) {
  Widget board = ShuffleboardBoard(controller: c);
  if (hostOwnsStatus != null) {
    board = GameHostChrome(hostOwnsStatus: hostOwnsStatus, child: board);
  }
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 340, height: 640, child: board)),
    ),
  );
}

void main() {
  testWidgets('without a host the standing turn pill is drawn', (tester) async {
    final c = await _controller();
    await tester.pumpWidget(_host(c));
    await tester.pump();

    expect(find.textContaining('’s slide'), findsOneWidget);
  });

  testWidgets('a host that owns status drops the turn pill', (tester) async {
    final c = await _controller();
    await tester.pumpWidget(_host(c, hostOwnsStatus: true));
    await tester.pump();

    expect(find.textContaining('’s slide'), findsNothing);
    // The aiming hint is a rule, not status: it stays.
    expect(find.textContaining('Slide to aim'), findsOneWidget);
  });

  testWidgets('the lane is described for a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    final c = await _controller();
    await tester.pumpWidget(_host(c));
    await tester.pump();

    expect(
      find.bySemanticsLabel(RegExp(r'^Shuffleboard\. Score 0 to 0\.')),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
