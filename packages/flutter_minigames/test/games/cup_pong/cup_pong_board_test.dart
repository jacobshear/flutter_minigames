import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/cup_pong/cup_pong.dart';
import 'package:flutter_minigames/src/core/core.dart';

// NOTE: these tests deliberately never `await controller.dispose()`.
// MatchController.dispose() awaits a StreamController.close() that does not
// complete inside testWidgets' fake-async zone — it hangs the run. No test in
// this repo awaits it; unmounting the widget is what actually needs covering.

Future<MatchController<CupPongState, CupPongThrow>> _controller(
  LocalTransport transport, {
  String id = 'm1',
}) =>
    MatchController.create<CupPongState, CupPongThrow>(
      game: const CupPongGame(),
      transport: transport,
      matchId: id,
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: true,
      seed: 0,
    );

Widget _host(MatchController<CupPongState, CupPongThrow> c) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 620,
            child: CupPongBoard(controller: c),
          ),
        ),
      ),
    );

/// Runs the board's ticker forward far enough for a throw to resolve.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

/// Unmounts the board and asserts teardown is clean — the ticker, the pill
/// timer and the confetti controller all have to come down without throwing.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump(const Duration(milliseconds: 32));
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('builds, shows both racks, and unmounts cleanly', (tester) async {
    final c = await _controller(LocalTransport());
    await tester.pumpWidget(_host(c));
    await tester.pump();

    expect(find.byType(CustomPaint), findsWidgets);
    // Chips carry the remaining-cup counts; a fresh match is 10 apiece.
    expect(find.text('10'), findsWidgets);
    expect(tester.takeException(), isNull);

    await _unmount(tester);
  });

  testWidgets('a flick throws, resolves, and submits the outcome',
      (tester) async {
    final c = await _controller(LocalTransport());
    await tester.pumpWidget(_host(c));
    await tester.pump();
    expect(c.state!.throws, 0);

    // Flick up-screen from the lower middle of the board.
    final start =
        tester.getCenter(find.byType(CupPongBoard)) + const Offset(0, 180);
    final gesture = await tester.startGesture(start);
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, -22));
      await tester.pump(const Duration(milliseconds: 12));
    }
    await gesture.up();
    await _settle(tester);

    expect(c.state!.throws, greaterThan(0),
        reason: 'the sim resolved and the board submitted a move');
    expect(tester.takeException(), isNull);

    await _unmount(tester);
  });

  testWidgets(
      'the drop/removal animation runs its full duration without altering '
      'the recorded outcome', (tester) async {
    final c = await _controller(LocalTransport());
    await tester.pumpWidget(_host(c));
    await tester.pump();

    final start =
        tester.getCenter(find.byType(CupPongBoard)) + const Offset(0, 180);
    final gesture = await tester.startGesture(start);
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, -22));
      await tester.pump(const Duration(milliseconds: 12));
    }
    await gesture.up();
    await _settle(tester);

    // Whatever the sim decided, it is decided: the board submits once and the
    // ball-in-the-cup animation, the splash and the cup's removal are all
    // purely visual over it. Pumping through every one of them — well past the
    // 0.40 s drop and the 0.85 s removal — must not move a single number.
    final afterResolve = c.state!;
    final throws = afterResolve.throws;
    final cups = {
      for (final p in afterResolve.playerIds) p: afterResolve.remainingOf(p),
    };
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(c.state!.throws, throws,
        reason: 'the animation must not resubmit or replay the throw');
    for (final p in c.state!.playerIds) {
      expect(c.state!.remainingOf(p), cups[p]);
    }
    expect(tester.takeException(), isNull);

    await _unmount(tester);
  });

  testWidgets('a downward drag never throws', (tester) async {
    final c = await _controller(LocalTransport());
    await tester.pumpWidget(_host(c));
    await tester.pump();

    for (final drag in const [Offset(0, 120), Offset(90, 200)]) {
      await tester.drag(find.byType(CupPongBoard), drag);
      await _settle(tester);
    }
    expect(c.state!.throws, 0);
    expect(tester.takeException(), isNull);

    await _unmount(tester);
  });

  testWidgets('a tap alone never throws', (tester) async {
    final c = await _controller(LocalTransport());
    await tester.pumpWidget(_host(c));
    await tester.pump();

    // Tapping the ball, and tapping the rack. Neither is a swipe, so neither
    // is a throw — there is no cursor to place and nothing to select.
    final centre = tester.getCenter(find.byType(CupPongBoard));
    for (final at in [centre + const Offset(0, 180), centre]) {
      await tester.tapAt(at);
      await _settle(tester);
    }
    expect(c.state!.throws, 0);
    expect(tester.takeException(), isNull);

    await _unmount(tester);
  });

  testWidgets('a nudge shorter than the dead zone never throws',
      (tester) async {
    final c = await _controller(LocalTransport());
    await tester.pumpWidget(_host(c));
    await tester.pump();

    const tuning = CupPongTuning();
    final start =
        tester.getCenter(find.byType(CupPongBoard)) + const Offset(0, 180);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(Offset(0, -tuning.deadZone * 0.6));
    await tester.pump(const Duration(milliseconds: 12));
    await gesture.up();
    await _settle(tester);

    expect(c.state!.throws, 0);
    expect(tester.takeException(), isNull);

    await _unmount(tester);
  });

  testWidgets('a swipe at an angle still throws — steering is not a gate',
      (tester) async {
    // The angle picks the cup (asserted directly on the solver in
    // cup_pong_sim_test.dart); at board level what matters is that a diagonal
    // swipe is still a throw, in both directions, with no target to select
    // first.
    for (final dx in const [-180.0, 180.0]) {
      final c = await _controller(LocalTransport(), id: 'steer$dx');
      await tester.pumpWidget(_host(c));
      await tester.pump();
      final start =
          tester.getCenter(find.byType(CupPongBoard)) + const Offset(0, 180);
      final gesture = await tester.startGesture(start);
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(Offset(dx / 8, -22));
        await tester.pump(const Duration(milliseconds: 12));
      }
      await gesture.up();
      await _settle(tester);
      expect(c.state!.throws, greaterThan(0), reason: 'dx = $dx');
    }
    expect(tester.takeException(), isNull);

    await _unmount(tester);
  });

  testWidgets('rebinding to a new controller does not throw', (tester) async {
    final transport = LocalTransport();
    final a = await _controller(transport, id: 'a');
    await tester.pumpWidget(_host(a));
    await tester.pump();

    final b = await _controller(transport, id: 'b');
    await tester.pumpWidget(_host(b));
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);

    await _unmount(tester);
  });

  testWidgets('a won match shows the sticky win pill', (tester) async {
    final c = await _controller(LocalTransport());
    await tester.pumpWidget(_host(c));
    await tester.pump();

    // Drive the match to a win through the controller, exactly as the board
    // would: every ball sinks a cup, so p1 keeps getting the balls back.
    const game = CupPongGame();
    while (game.outcome(c.state!) == null) {
      final s = c.state!;
      final owner = s.currentPlayerId;
      await c.submitMove(CupPongThrow(
        owner: owner,
        target: s.opponentOf(owner),
        hitCupId: s.cupsOf(s.opponentOf(owner)).first.id,
      ));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('WINS'), findsOneWidget);
    expect(find.text('0'), findsWidgets, reason: 'the cleared rack reads 0');
    expect(tester.takeException(), isNull);

    await _unmount(tester);
  });
}
