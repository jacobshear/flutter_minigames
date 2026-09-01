import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal fake game: players alternate "increment" moves; the third move ends
/// the game and its author wins. Enough to exercise the whole turn engine
/// without depending on any real game package.
class _CounterState {
  final int count;
  final List<String> playerIds;
  final String? lastMover;
  const _CounterState(this.count, this.playerIds, this.lastMover);
}

class _CounterMove {
  const _CounterMove();
}

class _CounterGame extends TurnGame<_CounterState, _CounterMove> {
  const _CounterGame();

  @override
  String get id => 'counter';

  @override
  _CounterState initialState({
    required int seed,
    required List<String> playerIds,
  }) =>
      _CounterState(0, List.of(playerIds), null);

  @override
  String currentPlayer(_CounterState state) =>
      state.playerIds[state.count % state.playerIds.length];

  @override
  bool validateMove(_CounterState state, _CounterMove move, String playerId) =>
      outcome(state) == null && currentPlayer(state) == playerId;

  @override
  _CounterState applyMove(_CounterState state, _CounterMove move) =>
      _CounterState(state.count + 1, state.playerIds, currentPlayer(state));

  @override
  GameOutcome? outcome(_CounterState state) =>
      state.count >= 3 ? GameOutcome.win(state.lastMover!) : null;

  @override
  Map<String, dynamic> encodeState(_CounterState state) => {
        'count': state.count,
        'playerIds': state.playerIds,
        'lastMover': state.lastMover,
      };

  @override
  _CounterState decodeState(Map<String, dynamic> json, int version) =>
      _CounterState(
        json['count'] as int,
        (json['playerIds'] as List).map((e) => e as String).toList(),
        json['lastMover'] as String?,
      );

  @override
  Map<String, dynamic> encodeMove(_CounterMove move) => const {};

  @override
  _CounterMove decodeMove(Map<String, dynamic> json) => const _CounterMove();
}

/// Flush pending microtasks so broadcast-stream listeners have run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('MatchController over LocalTransport', () {
    late LocalTransport transport;
    const game = _CounterGame();

    setUp(() => transport = LocalTransport());
    tearDown(() => transport.dispose());

    test('two clients on one transport see each other\'s turns', () async {
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'm1',
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        seed: 0,
      );
      final guest = MatchController<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'm1',
        localPlayerId: 'b',
      );
      await guest.connect();

      // a's turn first.
      expect(host.isLocalPlayersTurn, isTrue);
      expect(guest.isLocalPlayersTurn, isFalse);

      // a moves; the guest must observe it.
      expect(await host.submitMove(const _CounterMove()), isTrue);
      await _settle();
      expect(guest.match!.turnCount, 1);
      expect(guest.isLocalPlayersTurn, isTrue); // now b's turn

      // guest (b) plays out of turn on host — rejected.
      expect(await host.submitMove(const _CounterMove()), isFalse);

      // b moves, then a moves to end it.
      expect(await guest.submitMove(const _CounterMove()), isTrue);
      await _settle();
      expect(await host.submitMove(const _CounterMove()), isTrue);
      await _settle();

      expect(host.match!.status, MatchStatus.ended);
      expect(host.outcome, const GameOutcome.win('a'));
      expect(guest.match!.status, MatchStatus.ended);

      await host.dispose();
      await guest.dispose();
    });

    test('state survives an encode/decode round-trip through the transport',
        () async {
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'm2',
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        hotSeat: true,
        seed: 0,
      );
      await host.submitMove(const _CounterMove());
      await _settle();

      final reloaded = await transport.loadMatch('m2');
      expect(reloaded, isNotNull);
      final decoded = game.decodeState(reloaded!.state, reloaded.schemaVersion);
      expect(decoded.count, 1);
      expect(decoded.lastMover, 'a');

      await host.dispose();
    });
  });

  group('replayLastTurn', () {
    late LocalTransport transport;
    const game = _CounterGame();

    setUp(() => transport = LocalTransport());
    tearDown(() => transport.dispose());

    test(
        'submitMove records prevState and lastMoverId; a fresh match has neither',
        () async {
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'm3',
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        seed: 0,
      );
      final freshState = host.match!.state;
      expect(host.match!.prevState, isNull);
      expect(host.match!.lastMoverId, isNull);
      expect(host.match!.previousTurn, isNull);

      expect(await host.submitMove(const _CounterMove()), isTrue);
      await _settle();

      final stored = await transport.loadMatch('m3');
      expect(stored!.prevState, freshState);
      expect(stored.lastMoverId, 'a');

      await host.dispose();
    });

    test(
        'connecting with replayLastTurn after the other player moved replays '
        'then lands the real snapshot', () async {
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'm4',
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        seed: 0,
      );
      expect(await host.submitMove(const _CounterMove()), isTrue); // a moves
      await _settle();

      final stored = await transport.loadMatch('m4');
      expect(stored!.turnCount, 1);

      final guest = MatchController<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'm4',
        localPlayerId: 'b',
      );
      final emissions = <int>[];
      final sub = guest.stateStream.listen((s) => emissions.add(s.count));

      await guest.connect(replayLastTurn: true);
      await _settle();

      expect(guest.state!.count, 0);
      expect(guest.match!.turnCount, stored.turnCount - 1);
      expect(guest.isReplayingLastTurn, isTrue);
      expect(guest.canActLocally, isFalse);
      expect(await guest.submitMove(const _CounterMove()), isFalse);

      await Future.delayed(
        MatchController.replayDelay + const Duration(milliseconds: 50),
      );

      expect(guest.state!.count, 1);
      expect(guest.isReplayingLastTurn, isFalse);
      expect(emissions, [0, 1]);

      await sub.cancel();
      await host.dispose();
      await guest.dispose();
    });

    test(
        'connecting with replayLastTurn does not replay when the local '
        'player moved last', () async {
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'm5',
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        seed: 0,
      );
      expect(await host.submitMove(const _CounterMove()), isTrue); // a moves
      await _settle();

      final reconnect = MatchController<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'm5',
        localPlayerId: 'a',
      );
      await reconnect.connect(replayLastTurn: true);

      expect(reconnect.state!.count, 1);
      expect(reconnect.isReplayingLastTurn, isFalse);

      await host.dispose();
      await reconnect.dispose();
    });

    test(
        'replayLastTurn: false never replays even when the other player '
        'moved last', () async {
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'm6',
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        seed: 0,
      );
      expect(await host.submitMove(const _CounterMove()), isTrue); // a moves
      await _settle();

      final guest = MatchController<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'm6',
        localPlayerId: 'b',
      );
      await guest.connect(); // replayLastTurn defaults to false

      expect(guest.state!.count, 1);
      expect(guest.isReplayingLastTurn, isFalse);

      await host.dispose();
      await guest.dispose();
    });

    test('a newer turn arriving during the replay window abandons it',
        () async {
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'm7',
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        hotSeat: true,
        seed: 0,
      );
      expect(await host.submitMove(const _CounterMove()), isTrue); // count 0->1
      await _settle();

      final guest = MatchController<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'm7',
        localPlayerId: 'b',
      );
      final emissions = <int>[];
      final sub = guest.stateStream.listen((s) => emissions.add(s.count));

      await guest.connect(replayLastTurn: true);
      await _settle();
      expect(guest.isReplayingLastTurn, isTrue);
      expect(emissions, [0]);

      // A newer turn lands on the transport before the replay delay elapses —
      // legal because hotSeat attributes it to whoever's turn it actually is.
      expect(await host.submitMove(const _CounterMove()), isTrue); // count 1->2
      await _settle();

      expect(guest.state!.count, 2);
      expect(guest.isReplayingLastTurn, isFalse);
      expect(emissions, [0, 2]);

      await Future.delayed(
        MatchController.replayDelay + const Duration(milliseconds: 50),
      );
      // The abandoned replay timer must not have landed a stale emission.
      expect(emissions, [0, 2]);

      await sub.cancel();
      await host.dispose();
      await guest.dispose();
    });

    test('dispose during the replay window cancels the timer without error',
        () async {
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'm8',
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        seed: 0,
      );
      expect(await host.submitMove(const _CounterMove()), isTrue);
      await _settle();

      final guest = MatchController<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'm8',
        localPlayerId: 'b',
      );
      await guest.connect(replayLastTurn: true);
      expect(guest.isReplayingLastTurn, isTrue);

      await guest.dispose();

      // No exception, no late emission — reaching here is the assertion.
      await Future.delayed(
        MatchController.replayDelay + const Duration(milliseconds: 50),
      );

      await host.dispose();
    });
  });
}
