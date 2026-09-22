import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/archery/archery.dart';
import 'package:flutter_minigames/src/core/core.dart';

const _game = ArcheryGame();
const _players = ['p1', 'p2'];

Widget _host(MatchController<ArcheryState, ArcheryMove> c) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 620,
            child: ArcheryRange(controller: c),
          ),
        ),
      ),
    );

/// Runs the range's ticker forward far enough for a full replayed arrow
/// (flight, up to 4s, + wobble settle) to resolve.
Future<void> _settle(WidgetTester tester, {int ticks = 170}) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

/// A real, solved arrow — the same [ArcheryBallistics.fire] call a local
/// loose would make against [conditions] — as the move a board would submit.
ArcheryMove _solvedArrow({
  required String shooter,
  required int targetIndex,
  required int arrowIndex,
  required TargetConditions conditions,
  double power = 0.5,
  double aimYaw = 0,
  double aimPitch = 0,
}) {
  final result = ArcheryBallistics.fire(
    conditions: conditions,
    power: power,
    aimYaw: aimYaw,
    aimPitch: aimPitch,
  );
  return ArcheryMove.fromImpact(
    shooter: shooter,
    targetIndex: targetIndex,
    arrowIndex: arrowIndex,
    offsetX: result.offsetX,
    offsetY: result.offsetY,
    power: power,
    aimYaw: aimYaw,
    aimPitch: aimPitch,
  );
}

/// Every arrow of p1's whole end (12), fired dead centre in still air — used
/// to fast-forward straight to p2's turn without a board.
ArcheryState _finishP1(ArcheryState s) {
  var state = s;
  while (state.currentPlayerId == s.playerIds.first) {
    final conditions = state.conditions;
    final move = _solvedArrow(
      shooter: state.currentPlayerId,
      targetIndex: state.targetIndex,
      arrowIndex: state.arrowIndex,
      conditions: conditions,
    );
    state = _game.applyMove(state, move);
  }
  return state;
}

void main() {
  group('serialization', () {
    test('lastShot round-trips through encode/decode', () {
      final s = _game.initialState(seed: 0, playerIds: _players);
      final move = _solvedArrow(
        shooter: 'p1',
        targetIndex: s.targetIndex,
        arrowIndex: s.arrowIndex,
        conditions: s.conditions,
      );
      final next = _game.applyMove(s, move);

      expect(next.lastShot, isNotNull);
      final back = _game.decodeState(
        _game.encodeState(next),
        _game.stateSchemaVersion,
      );
      expect(back.lastShot, isNotNull);
      expect(back.lastShot!.shooter, next.lastShot!.shooter);
      expect(back.lastShot!.targetIndex, next.lastShot!.targetIndex);
      expect(back.lastShot!.arrowIndex, next.lastShot!.arrowIndex);
      expect(back.lastShot!.power, closeTo(next.lastShot!.power, 1e-9));
      expect(back.lastShot!.aimYaw, closeTo(next.lastShot!.aimYaw, 1e-9));
      expect(back.lastShot!.aimPitch, closeTo(next.lastShot!.aimPitch, 1e-9));
      expect(back.totalShots, next.totalShots);

      final moveBack = _game.decodeMove(_game.encodeMove(move));
      expect(moveBack.power, closeTo(move.power!, 1e-9));
      expect(moveBack.aimYaw, closeTo(move.aimYaw!, 1e-9));
      expect(moveBack.aimPitch, closeTo(move.aimPitch!, 1e-9));
      expect(moveBack.hasAim, isTrue);
    });

    test('a state encoded before lastShot existed decodes it to null', () {
      final s = _game.initialState(seed: 0, playerIds: _players);
      final move = _solvedArrow(
        shooter: 'p1',
        targetIndex: s.targetIndex,
        arrowIndex: s.arrowIndex,
        conditions: s.conditions,
      );
      final next = _game.applyMove(s, move);

      final json = _game.encodeState(next);
      json.remove('lastShot'); // LEGACY payload
      final back = _game.decodeState(json, _game.stateSchemaVersion);
      expect(back.lastShot, isNull);
      expect(back.totalShots, next.totalShots);
      expect(back.totalOf('p1'), next.totalOf('p1'));
    });

    test('a move without a draw leaves lastShot null', () {
      final s = _game.initialState(seed: 0, playerIds: _players);
      final next = _game.applyMove(
        s,
        ArcheryMove.miss(shooter: 'p1', targetIndex: 0, arrowIndex: 0),
      );
      expect(next.lastShot, isNull);
    });
  });

  group('applyMove', () {
    test('records the arrow that just resolved', () {
      final s = _game.initialState(seed: 0, playerIds: _players);
      final move = _solvedArrow(
        shooter: 'p1',
        targetIndex: s.targetIndex,
        arrowIndex: s.arrowIndex,
        conditions: s.conditions,
      );
      final next = _game.applyMove(s, move);

      expect(next.lastShot!.shooter, 'p1');
      expect(next.lastShot!.targetIndex, 0);
      expect(next.lastShot!.arrowIndex, 0);
      expect(next.totalShots, 1);
    });

    test('totalShots is monotonic across both players', () {
      var s = _game.initialState(seed: 0, playerIds: _players);
      s = _finishP1(s);
      expect(s.totalShots, ArcheryGame.arrowsPerPlayer);
      final move = _solvedArrow(
        shooter: 'p2',
        targetIndex: s.targetIndex,
        arrowIndex: s.arrowIndex,
        conditions: s.conditions,
      );
      s = _game.applyMove(s, move);
      expect(s.totalShots, ArcheryGame.arrowsPerPlayer + 1);
      expect(s.lastShot!.shooter, 'p2');
    });
  });

  group('board replay', () {
    testWidgets(
      "an opponent's arrow arrives as a real flight and lands on the "
      'authoritative result',
      (tester) async {
        final transport = LocalTransport();

        // p1's whole end (12 arrows) happens before the board ever mounts,
        // so the cold mount below shows p2's turn beginning already:
        // nothing here should replay.
        var seed = _game.initialState(seed: 2, playerIds: _players);
        seed = _finishP1(seed);
        expect(seed.currentPlayerId, 'p2');

        await transport.createMatch(Match(
          id: 'a1',
          gameId: _game.id,
          playerIds: _players,
          currentPlayerId: seed.currentPlayerId,
          status: MatchStatus.open,
          turnCount: ArcheryGame.arrowsPerPlayer,
          state: _game.encodeState(seed),
          schemaVersion: _game.stateSchemaVersion,
          lastMoverId: 'p1',
        ));

        final a = MatchController<ArcheryState, ArcheryMove>(
          game: _game,
          transport: transport,
          matchId: 'a1',
          localPlayerId: 'p1',
        );
        await a.connect();
        final b = MatchController<ArcheryState, ArcheryMove>(
          game: _game,
          transport: transport,
          matchId: 'a1',
          localPlayerId: 'p2',
        );
        await b.connect();

        await tester.pumpWidget(_host(a));
        await tester.pump();
        expect(a.state!.totalShots, ArcheryGame.arrowsPerPlayer);

        final move = _solvedArrow(
          shooter: 'p2',
          targetIndex: a.state!.targetIndex,
          arrowIndex: a.state!.arrowIndex,
          conditions: a.state!.conditions,
        );
        await b.submitMove(move);

        await tester.pump();
        expect(tester.takeException(), isNull);

        await _settle(tester);
        expect(tester.takeException(), isNull);

        expect(a.state!.totalShots, ArcheryGame.arrowsPerPlayer + 1);
        expect(a.state!.shotsOf('p2').single.ring, move.ring);
        expect(
          a.state!.shotsOf('p2').single.offsetX,
          closeTo(move.offsetX, 1e-9),
        );
      },
    );

    testWidgets('a miss off the face replays too and scores nothing',
        (tester) async {
      final transport = LocalTransport();
      var seed = _game.initialState(seed: 6, playerIds: _players);
      seed = _finishP1(seed);

      await transport.createMatch(Match(
        id: 'a2',
        gameId: _game.id,
        playerIds: _players,
        currentPlayerId: seed.currentPlayerId,
        status: MatchStatus.open,
        turnCount: ArcheryGame.arrowsPerPlayer,
        state: _game.encodeState(seed),
        schemaVersion: _game.stateSchemaVersion,
        lastMoverId: 'p1',
      ));

      final a = MatchController<ArcheryState, ArcheryMove>(
        game: _game,
        transport: transport,
        matchId: 'a2',
        localPlayerId: 'p1',
      );
      await a.connect();
      final b = MatchController<ArcheryState, ArcheryMove>(
        game: _game,
        transport: transport,
        matchId: 'a2',
        localPlayerId: 'p2',
      );
      await b.connect();

      await tester.pumpWidget(_host(a));
      await tester.pump();

      // A wild, fully-drawn shot aimed hard off to the side — well clear of
      // the face at any range this format shoots.
      final move = _solvedArrow(
        shooter: 'p2',
        targetIndex: a.state!.targetIndex,
        arrowIndex: a.state!.arrowIndex,
        conditions: a.state!.conditions,
        power: 1,
        aimYaw: 0.5,
      );
      expect(move.onFace, isFalse, reason: 'the whole point of this throw');
      await b.submitMove(move);

      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(a.state!.shotsOf('p2').single.onFace, isFalse);
      expect(a.state!.shotsOf('p2').single.ring, 0);
      expect(a.state!.totalShots, ArcheryGame.arrowsPerPlayer + 1);
    });

    testWidgets('cold mount does not replay the state already on screen',
        (tester) async {
      final transport = LocalTransport();
      var seed = _game.initialState(seed: 8, playerIds: _players);
      final move = _solvedArrow(
        shooter: 'p1',
        targetIndex: seed.targetIndex,
        arrowIndex: seed.arrowIndex,
        conditions: seed.conditions,
      );
      seed = _game.applyMove(seed, move);

      await transport.createMatch(Match(
        id: 'a3',
        gameId: _game.id,
        playerIds: _players,
        currentPlayerId: seed.currentPlayerId,
        status: MatchStatus.open,
        turnCount: 1,
        state: _game.encodeState(seed),
        schemaVersion: _game.stateSchemaVersion,
        lastMoverId: 'p1',
      ));

      final a = MatchController<ArcheryState, ArcheryMove>(
        game: _game,
        transport: transport,
        matchId: 'a3',
        localPlayerId: 'p1',
      );
      await a.connect();

      await tester.pumpWidget(_host(a));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(a.state!.totalShots, seed.totalShots);
    });
  });
}
