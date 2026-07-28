import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/archery/archery.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

/// Regression cover for the crash the shared chrome exists to kill.
///
/// The range used to wrap its centre message in an `AnimatedSwitcher`, which
/// keeps the outgoing child mounted beside the incoming one and keys both by
/// the child's key inside a `Stack`. A message that repeated before the
/// previous one had finished leaving — including the empty state between two
/// messages — collided with its own still-animating corpse and threw
/// "Duplicate keys found". Two arrows that both miss, or two that both score
/// an 8, is ordinary shooting, so this was not a rare race.
void main() {
  testWidgets(
      'the same message, cleared and raised again inside the animation '
      'window, never duplicates a key', (tester) async {
    final driver = _NoticeDriver(
      // Exactly how ArcheryRange configures its centre notice for a miss —
      // the warn tone, which also shakes on entry.
      build: (message) => GameNotice(
        message: message,
        tone: GameNoticeTone.warn,
        autoDismiss: const Duration(milliseconds: 1800),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: Center(child: driver)));

    // message -> null -> same message, each step well inside the 260ms
    // entrance and the 180ms exit.
    for (var cycle = 0; cycle < 4; cycle++) {
      driver.set('MISS');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('MISS'), findsOneWidget);
      driver.set(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      driver.set('MISS');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.takeException(), isNull);
      // The whole point: one node, never two. (Re-raising the identical text
      // while the previous copy is still retracting is a no-op inside
      // GameNotice, so this can legitimately be zero — what it can never be
      // is two, which is what used to throw.)
      expect(find.text('MISS').evaluate().length, lessThanOrEqualTo(1));
      // Let the retract finish so the next cycle starts from a clean slate.
      driver.set(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.text('MISS'), findsNothing);
    expect(tester.takeException(), isNull);

    // Unmount mid-animation: the controller is built in initState, never as a
    // late field initialiser, so teardown must not look up a deactivated
    // element's ancestor.
    driver.set('MISS');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);
  });

  testWidgets('two arrows in a row raise their notice without colliding',
      (tester) async {
    final transport = LocalTransport();
    final controller = await MatchController.create<ArcheryState, ArcheryMove>(
      game: const ArcheryGame(),
      transport: transport,
      matchId: 'notice-regression',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      seed: 3,
      hotSeat: true,
    );
    addTearDown(() {
      controller.dispose();
      transport.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ArcheryRange(controller: controller))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    // Exactly one notice node on the range, whatever it is showing.
    expect(find.byType(GameNotice), findsOneWidget);
    // And no switcher left anywhere in the range's chrome.
    expect(find.byType(AnimatedSwitcher), findsNothing);

    // Loose two arrows back to back with the aim shoved hard off the face, so
    // both resolve the same way and the second notice lands on top of the
    // first's exit.
    for (var shot = 0; shot < 2; shot++) {
      final scene = tester.getCenter(find.byType(ArcheryRange));
      final gesture = await tester.startGesture(scene);
      await gesture.moveBy(const Offset(220, -140));
      for (var i = 0; i < 45; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      await gesture.up();
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(GameNotice), findsOneWidget);
    }

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 32));
    expect(tester.takeException(), isNull);
  });
}

/// A widget whose message can be swapped from the test body without rebuilding
/// the whole tree — so the notice keeps its state across swaps, which is the
/// only way to reproduce the collision.
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
