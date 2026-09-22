// Regression coverage for GitHub issue #2: MancalaBoard used to hard-cap
// itself at a fixed 560pt regardless of how much vertical room its host
// actually gave it, stranding ~110pt of empty felt on a tall phone. It now
// scales with the real budget and only clamps at the top end (tablets) —
// see MancalaBoard._resolveBoardMaxHeight in mancala_board.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/mancala/mancala.dart';
import 'package:flutter_minigames/src/core/core.dart';

Future<MatchController<MancalaState, MancalaMove>> _controller() =>
    MatchController.create<MancalaState, MancalaMove>(
      game: const MancalaGame(seedsPerPit: 4, mode: MancalaMode.capture),
      transport: LocalTransport(),
      matchId: 'sizing-test',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: true,
      seed: 0,
    );

/// Mirrors how both hosts place the board: `GameMatchScaffold` hands it
/// `BoxConstraints.loose(area.size)` and centres it in what's left of the
/// screen; `Center` inside a sized box produces the same loose-but-finite
/// constraints here.
Widget _loose(
  MatchController<MancalaState, MancalaMove> controller, {
  required double width,
  required double height,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: height,
          child: Center(child: MancalaBoard(controller: controller)),
        ),
      ),
    );

void main() {
  testWidgets(
    'phone band (402x874-ish, 650pt available): board fills most of it',
    (tester) async {
      final c = await _controller();
      const available = 650.0;
      await tester.pumpWidget(_loose(c, width: 402, height: available));
      await tester.pump(const Duration(milliseconds: 700));

      final size = tester.getSize(find.byType(MancalaBoard));
      expect(tester.takeException(), isNull);
      // The 560pt fixed cap used to leave ~110pt of dead felt on a phone
      // this tall; the board must now use the great majority of what it
      // was actually given.
      expect(size.height, greaterThanOrEqualTo(available * 0.85),
          reason: 'board should scale up to fill the available band, '
              'not sit under a fixed cap');
      expect(size.height, lessThanOrEqualTo(available));
    },
  );

  testWidgets('tablet band (1024x1366): board is still clamped',
      (tester) async {
    final c = await _controller();
    const available = 1300.0;
    await tester.pumpWidget(_loose(c, width: 1024, height: available));
    await tester.pump(const Duration(milliseconds: 700));

    final size = tester.getSize(find.byType(MancalaBoard));
    expect(tester.takeException(), isNull);
    // The cap exists precisely so a tablet's wide-open band doesn't grow
    // the felt tray absurdly tall — it must NOT scale proportionally with
    // the huge budget on offer.
    expect(size.height, lessThan(available * 0.7),
        reason: 'a tablet-sized band should still hit the top-end clamp');
    // Generous slack over the ceiling constant for the Row's own padding.
    expect(size.height, lessThanOrEqualTo(800));
  });

  testWidgets(
    'unbounded height (host inside a scroll view): finite, non-zero size',
    (tester) async {
      final c = await _controller();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 402,
              // A vertical SingleChildScrollView hands its child unbounded
              // height — the scenario the MediaQuery fallback in
              // _resolveBoardMaxHeight exists for.
              child: SingleChildScrollView(
                child: MancalaBoard(controller: c),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(MancalaBoard));
      expect(size.height.isFinite, isTrue,
          reason: 'unbounded incoming height must not make the board '
              'try to grow to infinity');
      expect(size.height, greaterThan(0));
      expect(size.width, greaterThan(0));
    },
  );
}
