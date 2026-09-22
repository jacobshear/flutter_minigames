import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/shuffleboard/shuffleboard.dart';
import 'package:flutter_minigames/src/core/core.dart';

// NOTE: mirrors test/games/cup_pong/cup_pong_board_test.dart's convention —
// these widget tests deliberately never `await controller.dispose()`, since
// MatchController.dispose() awaits a StreamController.close() that does not
// complete inside testWidgets' fake-async zone. Unmounting the widget is
// what actually needs covering.

Widget _host(MatchController<ShuffleboardState, ShuffleboardMove> c) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 340,
            height: 640,
            child: ShuffleboardBoard(controller: c),
          ),
        ),
      ),
    );

/// Advances the fake clock in small increments so both `MatchController`'s
/// real `Timer`-based replay pacing AND the board's Flame ticker (which caps
/// physics steps per `update()` call — see ShuffleboardScene.update) make
/// forward progress, mirroring cup_pong_board_test.dart's `_settle`.
Future<void> _settle(WidgetTester tester, {int iterations = 260}) async {
  for (var i = 0; i < iterations; i++) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

void main() {
  group('opponent shot replay', () {
    testWidgets(
        'a remote shot with recorded launch input replays via physics and '
        'reconciles to the authoritative outcome', (tester) async {
      final transport = LocalTransport();
      const game = ShuffleboardGame(pucksPerPlayer: 2);

      final host =
          await MatchController.create<ShuffleboardState, ShuffleboardMove>(
        game: game,
        transport: transport,
        matchId: 'rep1',
        playerIds: const ['p1', 'p2'],
        localPlayerId: 'p1',
        seed: 0,
      );

      // p1 takes a shot, recording the launch input a real board would.
      final shotMove = ShuffleboardMove(
        launchedPuckId: 'p1-0',
        owner: 'p1',
        positions: const [
          PuckPosition(id: 'p1-0', owner: 'p1', nx: 0.5, ny: 0.15),
        ],
        launchStartNx: 0.5,
        launchImpulseX: 0,
        launchImpulseY: -9,
      );
      expect(await host.submitMove(shotMove), isTrue);

      final expectedMatch = await transport.loadMatch('rep1');
      final expectedState =
          game.decodeState(expectedMatch!.state, expectedMatch.schemaVersion);
      expect(expectedState.lastShot, isNotNull);

      // p2 opens the match cold, after p1 already moved — MatchController
      // exposes the pre-shot snapshot first, then replays the real turn.
      final guest = MatchController<ShuffleboardState, ShuffleboardMove>(
        game: game,
        transport: transport,
        matchId: 'rep1',
        localPlayerId: 'p2',
      );
      await guest.connect(replayLastTurn: true);
      expect(guest.isReplayingLastTurn, isTrue);

      await tester.pumpWidget(_host(guest));
      await tester.pump();

      // Cold mount: the board must show the pre-shot snapshot, not have
      // started any physics replay yet.
      final boardState =
          tester.state(find.byType(ShuffleboardBoard)) as dynamic;
      expect((boardState.debugState as ShuffleboardState).pucks, isEmpty);
      expect(boardState.debugIsReplaying as bool, isFalse);

      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(guest.isReplayingLastTurn, isFalse,
          reason: 'the controller-level replay should have landed by now');
      expect(boardState.debugIsReplaying as bool, isFalse,
          reason: 'the board physics replay should have settled by now');

      final shown = boardState.debugState as ShuffleboardState;
      expect(shown.pucks.length, expectedState.pucks.length);
      for (final expectedPuck in expectedState.pucks) {
        final shownPuck =
            shown.pucks.firstWhere((p) => p.id == expectedPuck.id);
        expect(shownPuck.nx, closeTo(expectedPuck.nx, 1e-6));
        expect(shownPuck.ny, closeTo(expectedPuck.ny, 1e-6));
        expect(shownPuck.status, expectedPuck.status);
      }
      expect(shown.scoreOf('p1'), expectedState.scoreOf('p1'));
      expect(shown.currentPlayerId, expectedState.currentPlayerId);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a remote shot with NO recorded launch input (legacy move) never '
        'replays — the board just snaps to the authoritative state',
        (tester) async {
      final transport = LocalTransport();
      const game = ShuffleboardGame(pucksPerPlayer: 2);

      final host =
          await MatchController.create<ShuffleboardState, ShuffleboardMove>(
        game: game,
        transport: transport,
        matchId: 'rep2',
        playerIds: const ['p1', 'p2'],
        localPlayerId: 'p1',
        seed: 0,
      );

      // A legacy-shaped move: no launch fields at all.
      final legacyMove = ShuffleboardMove(
        launchedPuckId: 'p1-0',
        owner: 'p1',
        positions: const [
          PuckPosition(id: 'p1-0', owner: 'p1', nx: 0.5, ny: 0.15),
        ],
      );
      expect(await host.submitMove(legacyMove), isTrue);

      final guest = MatchController<ShuffleboardState, ShuffleboardMove>(
        game: game,
        transport: transport,
        matchId: 'rep2',
        localPlayerId: 'p2',
      );
      await guest.connect(replayLastTurn: true);

      await tester.pumpWidget(_host(guest));
      await tester.pump();
      // MatchController's own pipeline runs a `replayDelay` wait (700ms)
      // THEN a `replayStepDelay` tail (4000ms, see ShuffleboardGame) before
      // it fully settles — even though this move never triggers a board
      // physics replay, we still need to outlast the controller's own
      // timers so none are left pending at test teardown.
      await _settle(tester, iterations: 170);

      expect(tester.takeException(), isNull);
      final boardState =
          tester.state(find.byType(ShuffleboardBoard)) as dynamic;
      expect(boardState.debugIsReplaying as bool, isFalse,
          reason: 'no launch input was recorded, so there is nothing to '
              'physics-replay');
      final shown = boardState.debugState as ShuffleboardState;
      expect(shown.pucks.single.nx, closeTo(0.5, 1e-9));
      expect(shown.pucks.single.ny, closeTo(0.15, 1e-9));
    });
  });
}
