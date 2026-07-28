import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/darts/darts.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

/// Regression cover for the crash the shared chrome exists to kill.
///
/// The board used to wrap its centre message in an `AnimatedSwitcher`, which
/// keeps the outgoing child mounted beside the incoming one and keys both by
/// the child's key inside a `Stack`. Any message that repeated before the
/// previous one had finished leaving — including the empty state between two
/// messages — collided with its own still-animating corpse and threw
/// "Duplicate keys found", red-screening the game. Two visits that score the
/// same total, or two misses in a row, are completely ordinary darts, so this
/// was not a rare race.
///
/// Both tests below drive exactly that sequence *inside* the animation window.
void main() {
  testWidgets(
      'the same message, cleared and raised again inside the animation '
      'window, never duplicates a key', (tester) async {
    final driver = _NoticeDriver(
      // Exactly how DartsBoardWidget configures its centre notice.
      build: (message) => GameNotice(
        message: message,
        tone: GameNoticeTone.score,
        accent: const Color(0xFFE0533D),
        autoDismiss: const Duration(milliseconds: 1500),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: Center(child: driver)));

    // message -> null -> same message, each step well inside the 260ms
    // entrance and the 180ms exit. Repeated, because the first cycle alone
    // would not catch a corpse that outlives two swaps.
    for (var cycle = 0; cycle < 4; cycle++) {
      driver.set('60 SCORED');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      driver.set(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      driver.set('60 SCORED');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.takeException(), isNull);
      // The whole point: one node, never two.
      expect(find.text('60 SCORED').evaluate().length, lessThanOrEqualTo(1));
    }

    // Let it retract on its own — the notice owns its timer, the caller does
    // not, so nothing here cancels anything.
    driver.set(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // Unmount mid-animation: the controller is built in initState, never as a
    // late field initialiser, so teardown must not look up a deactivated
    // element's ancestor.
    driver.set('60 SCORED');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);
  });

  testWidgets('two visits scoring the same total do not crash the board',
      (tester) async {
    final transport = LocalTransport();
    final controller = await MatchController.create<DartsState, DartsMove>(
      game: const DartsGame(),
      transport: transport,
      matchId: 'notice-regression',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      seed: 7,
      hotSeat: true,
    );
    addTearDown(() {
      controller.dispose();
      transport.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
          home: Scaffold(body: DartsBoardWidget(controller: controller))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    // Four visits, every one of them scoring exactly 60: the board raises the
    // identical "60 SCORED" notice four times, with only a few frames between
    // them. Under the old AnimatedSwitcher this threw on the second visit.
    for (var visit = 0; visit < 4; visit++) {
      for (var dart = 0; dart < 3; dart++) {
        await controller.submitMove(
          DartsMove(
            playerId: controller.state!.currentPlayerId,
            hit: const DartHit(20, 1),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      // Exactly one — present (so the test is not vacuously green), and never
      // two (which is the crash).
      expect(find.text('60 SCORED'), findsOneWidget);
    }

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);
  });
}

/// A widget whose child message can be swapped from the test body without
/// rebuilding the whole tree — so the notice keeps its state across swaps,
/// which is the only way to reproduce the collision.
class _NoticeDriver extends StatefulWidget {
  final Widget Function(String? message) build;

  _NoticeDriver({required this.build});

  final _NoticeDriverState _state = _NoticeDriverState();

  void set(String? message) => _state._set(message);

  // The test needs a handle on the state to drive it, so createState hands
  // back the instance it was given rather than making one.
  @override
  // ignore: no_logic_in_create_state
  State<_NoticeDriver> createState() => _state;
}

class _NoticeDriverState extends State<_NoticeDriver> {
  String? _message;

  void _set(String? message) {
    if (!mounted) return;
    setState(() => _message = message);
  }

  @override
  Widget build(BuildContext context) => widget.build(_message);
}
