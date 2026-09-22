import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/darts/darts.dart';
import 'package:flutter_minigames/src/core/core.dart';

const _game = DartsGame();
const _players = ['p1', 'p2'];

Widget _host(MatchController<DartsState, DartsMove> c) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 620,
            child: DartsBoardWidget(controller: c),
          ),
        ),
      ),
    );

/// Runs the board's ticker forward far enough for a full replayed dart
/// (flight + wobble settle) to resolve.
Future<void> _settle(WidgetTester tester, {int ticks = 80}) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

/// A real, solved dart at the bull — the same velocity `DartsAim` would hand
/// a local swipe — plus the impact it actually produces (headless
/// [DartsFlight.simulate]), so a replay driven by it is exactly as
/// deterministic as a local one.
DartsMove _solvedDart(String playerId) {
  final velocity = DartsAim.launch(aimX: 0, aimY: 0, power: 0.5, swipeDx: 0)!;
  final impact = DartsFlight.simulate(velocity);
  return DartsMove(
    playerId: playerId,
    hit: impact.hit,
    velocityX: velocity.x,
    velocityY: velocity.y,
    velocityZ: velocity.z,
  );
}

void main() {
  group('serialization', () {
    test('lastThrow round-trips through encode/decode', () {
      final s = _game.initialState(seed: 0, playerIds: _players);
      final move = _solvedDart('p1');
      final next = _game.applyMove(s, move);

      expect(next.lastThrow, isNotNull);
      final back = _game.decodeState(
        _game.encodeState(next),
        _game.stateSchemaVersion,
      );
      expect(back.lastThrow, isNotNull);
      expect(back.lastThrow!.playerId, next.lastThrow!.playerId);
      expect(back.lastThrow!.hit.sector, next.lastThrow!.hit.sector);
      expect(back.lastThrow!.hit.multiplier, next.lastThrow!.hit.multiplier);
      expect(
          back.lastThrow!.velocityX, closeTo(next.lastThrow!.velocityX, 1e-9));
      expect(
          back.lastThrow!.velocityY, closeTo(next.lastThrow!.velocityY, 1e-9));
      expect(
          back.lastThrow!.velocityZ, closeTo(next.lastThrow!.velocityZ, 1e-9));
      expect(back.lastThrow!.throwId, next.lastThrow!.throwId);
      expect(back.dartsThrown, next.dartsThrown);

      final moveBack = _game.decodeMove(_game.encodeMove(move));
      expect(moveBack.velocityX, closeTo(move.velocityX!, 1e-9));
      expect(moveBack.hasVelocity, isTrue);
    });

    test('a state encoded before lastThrow existed decodes it to null', () {
      final s = _game.initialState(seed: 0, playerIds: _players);
      final move = _solvedDart('p1');
      final next = _game.applyMove(s, move);

      final json = _game.encodeState(next);
      json.remove('lastThrow'); // LEGACY payload
      final back = _game.decodeState(json, _game.stateSchemaVersion);
      expect(back.lastThrow, isNull);
      expect(back.dartsThrown, next.dartsThrown);
      expect(back.scoreOf('p1'), next.scoreOf('p1'));
    });

    test('a move without a velocity leaves lastThrow null', () {
      final s = _game.initialState(seed: 0, playerIds: _players);
      final next = _game.applyMove(
        s,
        const DartsMove(playerId: 'p1', hit: DartHit(20, 1)),
      );
      expect(next.lastThrow, isNull);
    });
  });

  group('applyMove', () {
    test('records the dart that just resolved, with a fresh throwId', () {
      final s = _game.initialState(seed: 0, playerIds: _players);
      final move = _solvedDart('p1');
      final next = _game.applyMove(s, move);

      expect(next.lastThrow!.playerId, 'p1');
      expect(next.lastThrow!.throwId, next.dartsThrown);
      expect(next.lastThrow!.hit.value, move.hit.value);
    });

    test('records a throw even on a bust', () {
      // Force a score of 1 — no dart can leave exactly 1, so any dart busts.
      var s = _game.initialState(seed: 0, playerIds: _players);
      s = DartsState(
        playerIds: s.playerIds,
        scores: {'p1': 1, 'p2': 501},
        currentPlayerId: 'p1',
        visit: const [],
        visitStartScore: 1,
        lastVisit: null,
        winnerId: null,
        dartsThrown: 0,
        dartsPerVisit: 3,
      );
      final move = _solvedDart('p1');
      final next = _game.applyMove(s, move);
      expect(next.lastVisit!.busted, isTrue);
      expect(next.lastThrow, isNotNull, reason: 'even a bust dart replays');
      expect(next.lastThrow!.hit.value, move.hit.value);
    });
  });

  group('board replay', () {
    testWidgets(
      "an opponent's dart arrives as a real flight and sticks on the "
      'authoritative result',
      (tester) async {
        final transport = LocalTransport();

        // p1 throws a whole visit (three darts) before the board ever
        // mounts, so the cold mount below shows p2's visit beginning
        // already: nothing here should replay.
        var seed = _game.initialState(seed: 1, playerIds: _players);
        for (var i = 0; i < 3; i++) {
          seed = _game.applyMove(
            seed,
            const DartsMove(playerId: 'p1', hit: DartHit(1, 1)),
          );
        }
        expect(seed.currentPlayerId, 'p2');
        expect(seed.visit, isEmpty);

        await transport.createMatch(Match(
          id: 'd1',
          gameId: _game.id,
          playerIds: _players,
          currentPlayerId: seed.currentPlayerId,
          status: MatchStatus.open,
          turnCount: 3,
          state: _game.encodeState(seed),
          schemaVersion: _game.stateSchemaVersion,
          lastMoverId: 'p1',
        ));

        final a = MatchController<DartsState, DartsMove>(
          game: _game,
          transport: transport,
          matchId: 'd1',
          localPlayerId: 'p1',
        );
        await a.connect();
        final b = MatchController<DartsState, DartsMove>(
          game: _game,
          transport: transport,
          matchId: 'd1',
          localPlayerId: 'p2',
        );
        await b.connect();

        await tester.pumpWidget(_host(a));
        await tester.pump();
        expect(a.state!.dartsThrown, 3);

        final move = _solvedDart('p2');
        await b.submitMove(move);

        await tester.pump();
        expect(tester.takeException(), isNull);

        await _settle(tester);
        expect(tester.takeException(), isNull);

        expect(a.state!.dartsThrown, seed.dartsThrown + 1);
        expect(a.state!.visit.length, 1);
        expect(a.state!.visit.first.value, move.hit.value);
      },
    );

    testWidgets('cold mount does not replay the state already on screen',
        (tester) async {
      final transport = LocalTransport();
      var seed = _game.initialState(seed: 4, playerIds: _players);
      seed = _game.applyMove(seed, _solvedDart('p1'));

      await transport.createMatch(Match(
        id: 'd2',
        gameId: _game.id,
        playerIds: _players,
        currentPlayerId: seed.currentPlayerId,
        status: MatchStatus.open,
        turnCount: 1,
        state: _game.encodeState(seed),
        schemaVersion: _game.stateSchemaVersion,
        lastMoverId: 'p1',
      ));

      final a = MatchController<DartsState, DartsMove>(
        game: _game,
        transport: transport,
        matchId: 'd2',
        localPlayerId: 'p1',
      );
      await a.connect();

      await tester.pumpWidget(_host(a));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(a.state!.dartsThrown, seed.dartsThrown);
    });
  });
}
