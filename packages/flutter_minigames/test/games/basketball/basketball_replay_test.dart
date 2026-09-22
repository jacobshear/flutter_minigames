import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/basketball/basketball.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

/// [BasketballRoundReplay] is driven entirely by its own [Ticker] plus the
/// [RoundReplayController] contract — no [Timer]/`Future.delayed` anywhere in
/// it — so every test here drives time the same way `basketball_render_test`
/// drives the live board: `tester.pump(duration)` slices, which advance
/// TestWidgetsFlutterBinding's virtual clock (and therefore the ticker)
/// deterministically. No real wall-clock waiting occurs.
void main() {
  const game = BasketballGame();
  const players = ['p1', 'p2'];

  /// A round's worth of shots for 'p1': [perRound] shots per round, one make
  /// (the first) and the rest misses — so `roundsOf('p1')` should read
  /// `[1, 1, ...]`, one make per round.
  List<BasketballShot> sampleShots({int rounds = 2, int perRound = 5}) => [
        for (var round = 0; round < rounds; round++)
          for (var i = 0; i < perRound; i++)
            BasketballShot(
              round: round,
              tMs: i * 4000,
              spawnX: (i.isEven ? 1 : -1) * 0.15,
              aim: i == 0 ? 0 : (i.isEven ? 0.6 : -0.6),
              made: i == 0,
              points: i == 0 ? 1 : 0,
              ballIndex: round * perRound + i,
            ),
      ];

  BasketballState stateWithShots({
    required List<BasketballShot> p1Shots,
    List<int> p1Rounds = const [1, 1],
  }) =>
      BasketballState(
        playerIds: players,
        submissions: {
          'p1': p1Rounds,
          'p2': const [3, 2],
        },
        shots: {'p1': p1Shots},
      );

  Widget harness(Widget child) => MaterialApp(
        home: Material(
          child: SizedBox(height: 700, child: child),
        ),
      );

  testWidgets(
    'replays a logged round to completion and calls markFinished',
    (tester) async {
      final controller = RoundReplayController();
      final state = stateWithShots(p1Shots: sampleShots());

      await tester.pumpWidget(harness(BasketballRoundReplay(
        game: game,
        state: state,
        playerId: 'p1',
        viewerId: 'p2',
        controller: controller,
      )));
      await tester.pump();
      expect(controller.finished, isFalse);

      // The whole replay is budgeted to ~BasketballRoundReplay.capSeconds;
      // pump well past that in slices.
      for (var i = 0; i < 250 && !controller.finished; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.finished, isTrue,
          reason: 'a bounded replay must reach markFinished on its own');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a busy round (many shots) still finishes within the capped budget',
    (tester) async {
      final controller = RoundReplayController();
      // 30 shots/round x 2 rounds — well above the "20-60 a round" note, to
      // exercise the uniform scale-down fallback in the planner.
      final state = stateWithShots(
        p1Shots: sampleShots(perRound: 30),
        p1Rounds: const [6, 6],
      );

      await tester.pumpWidget(harness(BasketballRoundReplay(
        game: game,
        state: state,
        playerId: 'p1',
        viewerId: 'p2',
        controller: controller,
      )));
      await tester.pump();

      // Real time is not the axis under test (fast-forward already fast
      // forwards it) — pump comfortably past the ~15s cap plus reveal/
      // transition overhead and confirm it still lands on markFinished.
      for (var i = 0; i < 250 && !controller.finished; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.finished, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'skip() finishes immediately, well before natural completion would',
    (tester) async {
      final controller = RoundReplayController();
      final state = stateWithShots(p1Shots: sampleShots());

      await tester.pumpWidget(harness(BasketballRoundReplay(
        game: game,
        state: state,
        playerId: 'p1',
        viewerId: 'p2',
        controller: controller,
      )));
      await tester.pump();
      // A couple of frames into the flight, well before any shot resolves.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.finished, isFalse);

      controller.skip();
      // One frame is enough: the controller listener reacts synchronously,
      // and the ticker-driven fallback would also catch it on the next tick.
      await tester.pump(const Duration(milliseconds: 16));

      expect(controller.finished, isTrue,
          reason: 'skip() must jump straight to the final score');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a LEGACY state with no shot log falls back to a plain score reveal',
    (tester) async {
      final controller = RoundReplayController();
      final state = BasketballState(
        playerIds: players,
        submissions: {
          'p1': const [3, 4],
          'p2': const [2, 2],
        },
        // No 'p1' entry in shots at all — exactly what a pre-replay match's
        // decoded state looks like.
      );
      expect(state.shotsOf('p1'), isEmpty);

      await tester.pumpWidget(harness(BasketballRoundReplay(
        game: game,
        state: state,
        playerId: 'p1',
        viewerId: 'p2',
        controller: controller,
      )));
      await tester.pump();

      for (var i = 0; i < 60 && !controller.finished; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.finished, isTrue,
          reason: 'the legacy score-reveal path must still reach finished');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('honours mode: a moving-hoop round renders without throwing', (
    tester,
  ) async {
    final controller = RoundReplayController();
    final shots = [
      for (var i = 0; i < 4; i++)
        BasketballShot(
          round: 0,
          tMs: i * 3000,
          spawnX: 0,
          aim: BasketballAim.leadAim(BasketballHoopMode.moving, 0, i * 3.0),
          made: i.isEven,
          points: i.isEven ? 1 : 0,
          ballIndex: i,
        ),
    ];
    final state = BasketballState(
      playerIds: players,
      submissions: {
        'p1': const [2, 0],
        'p2': const [1, 1],
      },
      shots: {'p1': shots},
    );

    await tester.pumpWidget(harness(BasketballRoundReplay(
      game: game,
      state: state,
      playerId: 'p1',
      viewerId: 'p2',
      controller: controller,
      mode: BasketballHoopMode.moving,
    )));
    await tester.pump();
    for (var i = 0; i < 100 && !controller.finished; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.finished, isTrue);
    expect(tester.takeException(), isNull);
  });
}
