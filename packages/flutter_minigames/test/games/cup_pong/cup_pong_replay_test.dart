import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/cup_pong/cup_pong.dart';
import 'package:flutter_minigames/src/core/core.dart';

// NOTE: mirrors cup_pong_board_test.dart — these tests deliberately never
// `await controller.dispose()` (it hangs inside testWidgets' fake-async
// zone); unmounting the widget is what actually needs covering.

const _game = CupPongGame();
const _players = ['p1', 'p2'];

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

/// Runs the board's ticker forward far enough for a full replayed throw
/// (flight + drop/splash + removal) to resolve.
Future<void> _settle(WidgetTester tester, {int ticks = 150}) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

/// A real, solved throw at [cups] — the same velocity `CupPongAim` would
/// hand a local swipe — plus the outcome that velocity actually produces
/// (headless [CupPongThrowSim.run]), so a replay driven by it is exactly as
/// deterministic as a local one.
CupPongThrow _solvedThrow({
  required String owner,
  required String target,
  required List<CupPongCup> cups,
}) {
  final aim = CupPongAim();
  final solution = aim.solve(cups: cups, dx: 0, dy: -200)!;
  final sim = CupPongThrowSim(cups: cups, velocity: solution.velocity);
  sim.run();
  return CupPongThrow(
    owner: owner,
    target: target,
    hitCupId: sim.hitCupId,
    ballX: sim.position.x,
    ballZ: sim.position.z,
    velocityX: solution.velocity.x,
    velocityY: solution.velocity.y,
    velocityZ: solution.velocity.z,
  );
}

void main() {
  group('serialization', () {
    test('lastThrow round-trips through encode/decode', () {
      final s = _game.initialState(seed: 0, playerIds: _players);
      final rack = s.cupsOf('p2');
      final move = _solvedThrow(owner: 'p1', target: 'p2', cups: rack);
      final next = _game.applyMove(s, move);

      expect(next.lastThrow, isNotNull);
      final back = _game.decodeState(
        _game.encodeState(next),
        _game.stateSchemaVersion,
      );
      expect(back.lastThrow, isNotNull);
      expect(back.lastThrow!.owner, next.lastThrow!.owner);
      expect(back.lastThrow!.target, next.lastThrow!.target);
      expect(back.lastThrow!.hitCupId, next.lastThrow!.hitCupId);
      expect(
          back.lastThrow!.velocityX, closeTo(next.lastThrow!.velocityX, 1e-9));
      expect(
          back.lastThrow!.velocityY, closeTo(next.lastThrow!.velocityY, 1e-9));
      expect(
          back.lastThrow!.velocityZ, closeTo(next.lastThrow!.velocityZ, 1e-9));
      expect(back.lastThrow!.throwId, next.lastThrow!.throwId);
      expect(back.throws, next.throws);

      final moveBack = _game.decodeMove(_game.encodeMove(move));
      expect(moveBack.velocityX, closeTo(move.velocityX!, 1e-9));
      expect(moveBack.velocityY, closeTo(move.velocityY!, 1e-9));
      expect(moveBack.velocityZ, closeTo(move.velocityZ!, 1e-9));
      expect(moveBack.hasVelocity, isTrue);
    });

    test('a state encoded before lastThrow existed decodes it to null', () {
      final s = _game.initialState(seed: 0, playerIds: _players);
      final rack = s.cupsOf('p2');
      final move = _solvedThrow(owner: 'p1', target: 'p2', cups: rack);
      final next = _game.applyMove(s, move);

      final json = _game.encodeState(next);
      json.remove('lastThrow'); // LEGACY payload
      final back = _game.decodeState(json, _game.stateSchemaVersion);
      expect(back.lastThrow, isNull);
      // Everything else about the state is unaffected.
      expect(back.throws, next.throws);
      expect(back.cupsOf('p2'), next.cupsOf('p2'));
    });

    test('a move without a velocity leaves lastThrow null', () {
      final s = _game.initialState(seed: 0, playerIds: _players);
      const miss = CupPongThrow(owner: 'p1', target: 'p2', hitCupId: null);
      final next = _game.applyMove(s, miss);
      expect(next.lastThrow, isNull);
    });
  });

  group('applyMove', () {
    test('records the throw that just resolved, with a fresh throwId', () {
      final s = _game.initialState(seed: 0, playerIds: _players);
      final rack = s.cupsOf('p2');
      final move = _solvedThrow(owner: 'p1', target: 'p2', cups: rack);
      final next = _game.applyMove(s, move);

      expect(next.lastThrow!.owner, 'p1');
      expect(next.lastThrow!.target, 'p2');
      expect(next.lastThrow!.throwId, next.throws);
      expect(next.lastThrow!.hitCupId, move.hitCupId);
    });

    test('a second throw overwrites lastThrow rather than accumulating', () {
      var s = _game.initialState(seed: 0, playerIds: _players);
      final t1 = _solvedThrow(owner: 'p1', target: 'p2', cups: s.cupsOf('p2'));
      s = _game.applyMove(s, t1);
      final firstThrowId = s.lastThrow!.throwId;

      final t2 = _solvedThrow(owner: 'p1', target: 'p2', cups: s.cupsOf('p2'));
      s = _game.applyMove(s, t2);
      expect(s.lastThrow!.throwId, greaterThan(firstThrowId));
    });
  });

  group('board replay', () {
    testWidgets(
      "an opponent's throw arrives as a real flight and lands on the "
      'authoritative result',
      (tester) async {
        final transport = LocalTransport();

        // p1's own opening turn (two misses — no balls back) happens before
        // the board ever mounts, so the cold mount below shows p2's turn
        // beginning already: nothing here should replay.
        var seed = _game.initialState(seed: 3, playerIds: _players);
        seed = _game.applyMove(
          seed,
          const CupPongThrow(owner: 'p1', target: 'p2', hitCupId: null),
        );
        seed = _game.applyMove(
          seed,
          const CupPongThrow(owner: 'p1', target: 'p2', hitCupId: null),
        );
        expect(seed.currentPlayerId, 'p2', reason: 'turn passed without a hit');

        await transport.createMatch(Match(
          id: 'm1',
          gameId: _game.id,
          playerIds: _players,
          currentPlayerId: seed.currentPlayerId,
          status: MatchStatus.open,
          turnCount: 2,
          state: _game.encodeState(seed),
          schemaVersion: _game.stateSchemaVersion,
          lastMoverId: 'p1',
        ));

        final a = MatchController<CupPongState, CupPongThrow>(
          game: _game,
          transport: transport,
          matchId: 'm1',
          localPlayerId: 'p1',
        );
        await a.connect();
        final b = MatchController<CupPongState, CupPongThrow>(
          game: _game,
          transport: transport,
          matchId: 'm1',
          localPlayerId: 'p2',
        );
        await b.connect();

        await tester.pumpWidget(_host(a));
        await tester.pump();
        expect(a.state!.throws, 2);

        // p2 — the "opponent" from a's point of view — throws for real,
        // dead centre on the nearest cup, and submits through its own
        // (unmounted) controller, exactly like a networked opponent would.
        final rack = a.state!.cupsOf('p1');
        final move = _solvedThrow(owner: 'p2', target: 'p1', cups: rack);
        await b.submitMove(move);

        // The move lands on the controller (the reducer is instant — only
        // the board's own animation is what needs the settle below), and
        // the board must not throw picking it up mid-flight.
        await tester.pump();
        expect(tester.takeException(), isNull);

        await _settle(tester);
        expect(tester.takeException(), isNull);

        // Now the whole replay — flight, drop/splash, removal — has run its
        // course and the board's own state matches the controller's
        // authoritative one.
        expect(a.state!.throws, seed.throws + 1);
        if (move.hitCupId != null) {
          expect(a.state!.hasCup('p1', move.hitCupId!), isFalse);
        }
      },
    );

    testWidgets(
        'a newer throw arriving mid-flight lands the abandoned throw first',
        (tester) async {
      final transport = LocalTransport();
      var seed = _game.initialState(seed: 3, playerIds: _players);
      seed = _game.applyMove(
        seed,
        const CupPongThrow(owner: 'p1', target: 'p2', hitCupId: null),
      );
      seed = _game.applyMove(
        seed,
        const CupPongThrow(owner: 'p1', target: 'p2', hitCupId: null),
      );
      await transport.createMatch(Match(
        id: 'm-supersede',
        gameId: _game.id,
        playerIds: _players,
        currentPlayerId: seed.currentPlayerId,
        status: MatchStatus.open,
        turnCount: 2,
        state: _game.encodeState(seed),
        schemaVersion: _game.stateSchemaVersion,
        lastMoverId: 'p1',
      ));
      final a = MatchController<CupPongState, CupPongThrow>(
        game: _game,
        transport: transport,
        matchId: 'm-supersede',
        localPlayerId: 'p1',
      );
      await a.connect();
      final b = MatchController<CupPongState, CupPongThrow>(
        game: _game,
        transport: transport,
        matchId: 'm-supersede',
        localPlayerId: 'p2',
      );
      await b.connect();
      await tester.pumpWidget(_host(a));
      await tester.pump();

      final first =
          _solvedThrow(owner: 'p2', target: 'p1', cups: a.state!.cupsOf('p1'));
      expect(first.hitCupId, isNotNull, reason: 'sanity: a dead-centre hit');
      await b.submitMove(first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 64));
      final board = tester.state(find.byType(CupPongBoard)) as dynamic;
      expect(board.debugIsReplaying as bool, isTrue,
          reason: 'the first throw is still in the air');

      // The opponent's second throw lands while the first is mid-flight.
      final second =
          _solvedThrow(owner: 'p2', target: 'p1', cups: b.state!.cupsOf('p1'));
      await b.submitMove(second);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // The abandoned throw's result is on the table at once — its cup is
      // gone — and the second throw is what is flying now.
      final shown = board.debugState as CupPongState;
      expect(shown.throws, seed.throws + 1);
      expect(shown.hasCup('p1', first.hitCupId!), isFalse);
      expect(board.debugIsReplaying as bool, isTrue);

      await _settle(tester);
      expect(tester.takeException(), isNull);
      final end = board.debugState as CupPongState;
      expect(end.throws, seed.throws + 2);
    });

    testWidgets('a miss replays too and leaves the rack untouched',
        (tester) async {
      final transport = LocalTransport();
      var seed = _game.initialState(seed: 9, playerIds: _players);
      seed = _game.applyMove(
        seed,
        const CupPongThrow(owner: 'p1', target: 'p2', hitCupId: null),
      );
      seed = _game.applyMove(
        seed,
        const CupPongThrow(owner: 'p1', target: 'p2', hitCupId: null),
      );

      await transport.createMatch(Match(
        id: 'm2',
        gameId: _game.id,
        playerIds: _players,
        currentPlayerId: seed.currentPlayerId,
        status: MatchStatus.open,
        turnCount: 2,
        state: _game.encodeState(seed),
        schemaVersion: _game.stateSchemaVersion,
        lastMoverId: 'p1',
      ));

      final a = MatchController<CupPongState, CupPongThrow>(
        game: _game,
        transport: transport,
        matchId: 'm2',
        localPlayerId: 'p1',
      );
      await a.connect();
      final b = MatchController<CupPongState, CupPongThrow>(
        game: _game,
        transport: transport,
        matchId: 'm2',
        localPlayerId: 'p2',
      );
      await b.connect();

      await tester.pumpWidget(_host(a));
      await tester.pump();

      // A deliberately short, weak flick that cannot reach the rack.
      final aim = CupPongAim();
      final rack = a.state!.cupsOf('p1');
      final solution = aim.solve(cups: rack, dx: 0, dy: -20)!;
      final sim = CupPongThrowSim(
        cups: rack,
        velocity: solution.velocity * 0.05,
      );
      sim.run();
      expect(sim.hitCupId, isNull, reason: 'the whole point of this throw');

      final move = CupPongThrow(
        owner: 'p2',
        target: 'p1',
        hitCupId: null,
        ballX: sim.position.x,
        ballZ: sim.position.z,
        velocityX: solution.velocity.x * 0.05,
        velocityY: solution.velocity.y * 0.05,
        velocityZ: solution.velocity.z * 0.05,
      );
      final before = a.state!.remainingOf('p1');
      await b.submitMove(move);

      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(a.state!.remainingOf('p1'), before);
      expect(a.state!.throws, seed.throws + 1);
    });

    testWidgets('cold mount does not replay the state already on screen',
        (tester) async {
      final transport = LocalTransport();
      var seed = _game.initialState(seed: 5, playerIds: _players);
      final t1 =
          _solvedThrow(owner: 'p1', target: 'p2', cups: seed.cupsOf('p2'));
      seed = _game.applyMove(seed, t1);

      await transport.createMatch(Match(
        id: 'm3',
        gameId: _game.id,
        playerIds: _players,
        currentPlayerId: seed.currentPlayerId,
        status: MatchStatus.open,
        turnCount: 1,
        state: _game.encodeState(seed),
        schemaVersion: _game.stateSchemaVersion,
        lastMoverId: 'p1',
      ));

      final a = MatchController<CupPongState, CupPongThrow>(
        game: _game,
        transport: transport,
        matchId: 'm3',
        localPlayerId: 'p1',
      );
      await a.connect();

      // A cold mount on a state that already carries a lastThrow must render
      // it as-is — no flight, no exception — never replay into it.
      await tester.pumpWidget(_host(a));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(a.state!.throws, seed.throws);
    });
  });
}
