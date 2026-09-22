import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/knockout/knockout.dart';
import 'package:flutter_minigames/src/core/core.dart';

// NOTE: mirrors test/games/shuffleboard/shuffleboard_replay_test.dart's
// convention — these widget tests deliberately never `await
// controller.dispose()`, since MatchController.dispose() awaits a
// StreamController.close() that does not complete inside testWidgets' fake
// -async zone. Unmounting the widget is what actually needs covering.

Widget _host(MatchController<KnockoutState, KnockoutMove> c) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 620,
            child: KnockoutBoard(controller: c),
          ),
        ),
      ),
    );

/// Advances the fake clock in small increments so both `MatchController`'s
/// real `Timer`-based replay pacing AND the board's Flame ticker (which caps
/// physics steps per `update()` call — see KnockoutScene.update) make forward
/// progress, mirroring cup_pong_board_test.dart's `_settle`.
Future<void> _settle(WidgetTester tester, {int iterations = 260}) async {
  for (var i = 0; i < iterations; i++) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

/// A full wind-up for [owner]: one aim per live puck they own. Small
/// magnitudes settle fast, which keeps the test's pump budget modest.
List<KnockoutAim> _aimsFor(KnockoutState s, String owner) => [
      for (final p in s.pucksOf(owner))
        KnockoutAim(puckId: p.id, ix: 0, iy: -1),
    ];

void main() {
  group('opponent resolution replay', () {
    testWidgets(
        'a remote resolution replays via physics and reconciles to the '
        'authoritative outcome', (tester) async {
      final transport = LocalTransport();
      const game = KnockoutGame(pucksPerPlayer: 2);

      final p1 = await MatchController.create<KnockoutState, KnockoutMove>(
        game: game,
        transport: transport,
        matchId: 'rep1',
        playerIds: const ['p1', 'p2'],
        localPlayerId: 'p1',
        seed: 0,
      );

      // p1 opens the round (aims only, nothing moves).
      final open = p1.state!;
      expect(
        await p1.submitMove(
          KnockoutMove(owner: 'p1', aims: _aimsFor(open, 'p1')),
        ),
        isTrue,
      );

      // p2 resolves it: their own aims plus the settled outcome — one of
      // p1's pucks fell, matching a real board's move shape.
      final p2 = MatchController<KnockoutState, KnockoutMove>(
        game: game,
        transport: transport,
        matchId: 'rep1',
        localPlayerId: 'p2',
      );
      await p2.connect();
      final beforeResolve = p2.state!;
      final resolvedPositions = [
        for (final puck in beforeResolve.pucks)
          KnockoutPosition(
            id: puck.id,
            owner: puck.owner,
            nx: puck.nx,
            ny: puck.ny,
            fell: puck.id == 'p1-0',
          ),
      ];
      expect(
        await p2.submitMove(KnockoutMove(
          owner: 'p2',
          aims: _aimsFor(beforeResolve, 'p2'),
          positions: resolvedPositions,
        )),
        isTrue,
      );

      final expectedMatch = await transport.loadMatch('rep1');
      final expectedState =
          game.decodeState(expectedMatch!.state, expectedMatch.schemaVersion);
      expect(expectedState.lastResolution, isNotNull);
      expect(expectedState.liveCountOf('p1'), 1,
          reason: 'p1-0 was reported as fallen');

      // p1 opens the match cold, after p2 already resolved — MatchController
      // exposes the pre-resolve snapshot first, then replays the real turn.
      final guest = MatchController<KnockoutState, KnockoutMove>(
        game: game,
        transport: transport,
        matchId: 'rep1',
        localPlayerId: 'p1',
      );
      await guest.connect(replayLastTurn: true);
      expect(guest.isReplayingLastTurn, isTrue);

      await tester.pumpWidget(_host(guest));
      await tester.pump();

      // Cold mount: the board must show the pre-resolve snapshot (every
      // puck still on the table) and must not have started any physics
      // replay yet — see contract point 2's cold-mount rule.
      final boardState = tester.state(find.byType(KnockoutBoard)) as dynamic;
      final coldPucks = (boardState.debugState as KnockoutState).pucks;
      expect(coldPucks.length, 4, reason: 'nothing has fallen yet on screen');
      expect(boardState.debugIsReplaying as bool, isFalse);

      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(guest.isReplayingLastTurn, isFalse,
          reason: 'the controller-level replay should have landed by now');
      expect(boardState.debugIsReplaying as bool, isFalse,
          reason: 'the board physics replay should have settled by now');

      final shown = boardState.debugState as KnockoutState;
      expect(shown.pucks.length, expectedState.pucks.length);
      for (final expectedPuck in expectedState.pucks) {
        final shownPuck =
            shown.pucks.firstWhere((p) => p.id == expectedPuck.id);
        expect(shownPuck.nx, closeTo(expectedPuck.nx, 1e-6));
        expect(shownPuck.ny, closeTo(expectedPuck.ny, 1e-6));
      }
      expect(shown.liveCountOf('p1'), expectedState.liveCountOf('p1'));
      expect(shown.currentPlayerId, expectedState.currentPlayerId);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a legacy state with no lastResolution never replays — the board '
        'just snaps to the authoritative state', (tester) async {
      final transport = LocalTransport();
      const game = KnockoutGame(pucksPerPlayer: 2);

      final p1 = await MatchController.create<KnockoutState, KnockoutMove>(
        game: game,
        transport: transport,
        matchId: 'rep2',
        playerIds: const ['p1', 'p2'],
        localPlayerId: 'p1',
        seed: 0,
      );
      final open = p1.state!;
      await p1.submitMove(
        KnockoutMove(owner: 'p1', aims: _aimsFor(open, 'p1')),
      );

      final p2 = MatchController<KnockoutState, KnockoutMove>(
        game: game,
        transport: transport,
        matchId: 'rep2',
        localPlayerId: 'p2',
      );
      await p2.connect();
      final beforeResolve = p2.state!;
      await p2.submitMove(KnockoutMove(
        owner: 'p2',
        aims: _aimsFor(beforeResolve, 'p2'),
        positions: [
          for (final puck in beforeResolve.pucks)
            KnockoutPosition(
                id: puck.id, owner: puck.owner, nx: puck.nx, ny: puck.ny)
        ],
      ));

      // Simulate a legacy-shaped payload: strip the resolution field that a
      // pre-replay-support write would never have had, then push it back
      // onto the transport exactly as the match otherwise stood.
      final match = (await transport.loadMatch('rep2'))!;
      final legacyState = Map<String, dynamic>.from(match.state)
        ..remove('lastResolution');
      final legacyPrevState = match.prevState == null
          ? null
          : (Map<String, dynamic>.from(match.prevState!)
            ..remove('lastResolution'));
      await transport.submitTurn(Match(
        id: match.id,
        gameId: match.gameId,
        playerIds: match.playerIds,
        currentPlayerId: match.currentPlayerId,
        status: match.status,
        turnCount: match.turnCount,
        state: legacyState,
        schemaVersion: match.schemaVersion,
        winnerId: match.winnerId,
        isDraw: match.isDraw,
        prevState: legacyPrevState,
        turnSteps: match.turnSteps,
        lastMoverId: match.lastMoverId,
      ));

      final guest = MatchController<KnockoutState, KnockoutMove>(
        game: game,
        transport: transport,
        matchId: 'rep2',
        localPlayerId: 'p1',
      );
      await guest.connect(replayLastTurn: true);

      await tester.pumpWidget(_host(guest));
      await tester.pump();
      // MatchController's own pipeline runs a `replayDelay` wait (700ms)
      // before it fully settles — this match has exactly one recorded turn
      // (prelaunch + final), so it lands in one hop with no
      // `replayStepDelay` tail. Even though this state never triggers a
      // board physics replay, we still need to outlast that timer so none
      // are left pending at test teardown.
      await _settle(tester, iterations: 60);

      expect(tester.takeException(), isNull);
      final boardState = tester.state(find.byType(KnockoutBoard)) as dynamic;
      expect(boardState.debugIsReplaying as bool, isFalse,
          reason: 'no resolution was recorded, so there is nothing to '
              'physics-replay');
      final shown = boardState.debugState as KnockoutState;
      final expected = game.decodeState(legacyState, match.schemaVersion);
      expect(shown.pucks.length, expected.pucks.length);
      for (final expectedPuck in expected.pucks) {
        final shownPuck =
            shown.pucks.firstWhere((p) => p.id == expectedPuck.id);
        expect(shownPuck.nx, closeTo(expectedPuck.nx, 1e-9));
        expect(shownPuck.ny, closeTo(expectedPuck.ny, 1e-9));
      }
    });
  });
}
