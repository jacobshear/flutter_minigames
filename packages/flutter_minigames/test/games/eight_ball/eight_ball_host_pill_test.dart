import 'package:flutter/material.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/eight_ball/eight_ball.dart';
import 'package:flutter_minigames/src/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';

// The controller is never disposed, only the widget is unmounted — see
// test/games/cup_pong/cup_pong_board_test.dart for why.

const _hint = 'Drag back from the cue ball to aim and shoot';

/// A fresh match, or one with [shotsTaken] strokes already played.
Future<MatchController<EightBallState, EightBallMove>> _controller({
  int shotsTaken = 0,
}) async {
  const game = EightBallGame();
  final transport = LocalTransport();
  final c = await MatchController.create<EightBallState, EightBallMove>(
    game: game,
    transport: transport,
    matchId: 'host-pill',
    playerIds: const ['p1', 'p2'],
    localPlayerId: 'p1',
    hotSeat: false,
    seed: 0,
  );
  if (shotsTaken > 0) {
    final later = c.state!.copyWith(shotsTaken: shotsTaken);
    await transport.submitTurn(
      Match(
        id: 'host-pill',
        gameId: game.id,
        playerIds: const ['p1', 'p2'],
        currentPlayerId: 'p1',
        status: MatchStatus.open,
        turnCount: 1,
        state: game.encodeState(later),
        schemaVersion: game.stateSchemaVersion,
      ),
    );
  }
  return c;
}

Widget _host(
  MatchController<EightBallState, EightBallMove> c, {
  bool? hostOwnsStatus,
}) {
  Widget board = EightBallBoard(controller: c);
  if (hostOwnsStatus != null) {
    board = GameHostChrome(hostOwnsStatus: hostOwnsStatus, child: board);
  }
  // Wide enough that the hint stays on one line in the test font, so the
  // row's height is the pill's when there is one and the text's when there is
  // not — the difference this test is about.
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 900, height: 640, child: board)),
    ),
  );
}

/// The standing row beside the hint, and the table above it.
(Size row, Size table) _measure(WidgetTester tester) {
  final row =
      find.ancestor(of: find.text(_hint), matching: find.byType(Row)).first;
  return (tester.getSize(row), tester.getSize(find.byType(AspectRatio).first));
}

void main() {
  testWidgets(
      'a host that owns status does not resize the table when the phase pill '
      'comes and goes', (tester) async {
    final semantics = tester.ensureSemantics();
    // "To break" still shows under the host; "To shoot" does not. The row
    // beside the hint, and so the table, must be the same height in both.
    final fresh = await _controller();
    await tester.pumpWidget(_host(fresh, hostOwnsStatus: true));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('To break'), findsOneWidget);
    final atBreak = _measure(tester);

    final mid = await _controller(shotsTaken: 1);
    await tester.pumpWidget(_host(mid, hostOwnsStatus: true));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('To break'), findsNothing);
    // The hidden pill keeps its room but is neither painted nor read: the
    // host owns whose shot it is.
    expect(find.bySemanticsLabel('To shoot'), findsNothing);
    expect(
      tester.widget<Visibility>(find.byType(Visibility)).visible,
      isFalse,
    );
    final midMatch = _measure(tester);

    expect(midMatch.$1.height, atBreak.$1.height);
    expect(midMatch.$2, atBreak.$2);
    semantics.dispose();
  });

  testWidgets('without a host the phase pill is drawn as before',
      (tester) async {
    final mid = await _controller(shotsTaken: 1);
    await tester.pumpWidget(_host(mid));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('To shoot'), findsOneWidget);
  });
}
