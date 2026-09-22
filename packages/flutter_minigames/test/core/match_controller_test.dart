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

/// A player takes TWO consecutive sub-moves before the turn passes (like a
/// checkers multi-jump or a mancala extra turn): a, a, b, b, a, a … The game
/// ends after six sub-moves. [chain] is what it reports as
/// [TurnGame.replaysWholeTurn]; [stepDelay] as [TurnGame.replayStepDelay].
class _RunGame extends TurnGame<_CounterState, _CounterMove> {
  final bool chain;
  final Duration stepDelay;
  const _RunGame({this.chain = true, required this.stepDelay});

  @override
  String get id => 'run';

  @override
  _CounterState initialState({
    required int seed,
    required List<String> playerIds,
  }) =>
      _CounterState(0, List.of(playerIds), null);

  @override
  String currentPlayer(_CounterState state) =>
      state.playerIds[(state.count ~/ 2) % state.playerIds.length];

  @override
  bool validateMove(_CounterState state, _CounterMove move, String playerId) =>
      outcome(state) == null && currentPlayer(state) == playerId;

  @override
  _CounterState applyMove(_CounterState state, _CounterMove move) =>
      _CounterState(state.count + 1, state.playerIds, currentPlayer(state));

  @override
  GameOutcome? outcome(_CounterState state) =>
      state.count >= 6 ? GameOutcome.win(state.lastMover!) : null;

  @override
  bool get replaysWholeTurn => chain;

  @override
  Duration replayStepDelay(_CounterState from, _CounterState to) => stepDelay;

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

  group('replay fast-forward', () {
    late LocalTransport transport;
    const game = _CounterGame();

    setUp(() => transport = LocalTransport());
    tearDown(() => transport.dispose());

    Future<MatchController<_CounterState, _CounterMove>> replayingGuest(
      String matchId,
    ) async {
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: matchId,
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        seed: 0,
      );
      addTearDown(host.dispose);
      expect(await host.submitMove(const _CounterMove()), isTrue);
      await _settle();
      final guest = MatchController<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: matchId,
        localPlayerId: 'b',
      );
      addTearDown(guest.dispose);
      return guest;
    }

    test(
        'setReplaySpeed shortens the hold already in flight and keeps the '
        'speed through the tail', () async {
      final guest = await replayingGuest('ff1');
      final activity = <bool>[];
      final sub = guest.replayActivity.listen(activity.add);
      await guest.connect(replayLastTurn: true);
      await _settle();
      expect(guest.isReplayingLastTurn, isTrue);

      guest.setReplaySpeed(4);
      expect(guest.replaySpeed, 4);
      await Future.delayed(
        MatchController.replayDelay * (1 / 4) +
            const Duration(milliseconds: 60),
      );

      // The real snapshot has landed and the match is live, but the board is
      // still animating it: playback (and the speed) runs through the tail.
      expect(guest.isReplayingLastTurn, isFalse);
      expect(guest.canActLocally, isTrue);
      expect(guest.state!.count, 1);
      expect(guest.isReplayPlaybackActive, isTrue);
      expect(guest.replaySpeed, 4);
      expect(activity, [true]);

      await Future.delayed(
        const Duration(milliseconds: 700) * (1 / 4) +
            const Duration(milliseconds: 60),
      );
      expect(guest.isReplayPlaybackActive, isFalse);
      expect(guest.replaySpeed, 1, reason: 'speed resets when playback ends');
      expect(activity, [true, false]);
      await sub.cancel();
    });

    test('skipReplay during the tail ends playback', () async {
      final guest = await replayingGuest('ff4');
      await guest.connect(replayLastTurn: true);
      await Future.delayed(
        MatchController.replayDelay + const Duration(milliseconds: 60),
      );
      expect(guest.isReplayingLastTurn, isFalse);
      expect(guest.isReplayPlaybackActive, isTrue);
      expect(guest.skipReplay(), isTrue);
      expect(guest.isReplayPlaybackActive, isFalse);
      expect(guest.state!.count, 1);
    });

    test('skipReplay lands the real snapshot immediately', () async {
      final guest = await replayingGuest('ff2');
      final emissions = <int>[];
      final sub = guest.stateStream.listen((s) => emissions.add(s.count));
      await guest.connect(replayLastTurn: true);
      await _settle();

      expect(guest.skipReplay(), isTrue);
      expect(guest.isReplayingLastTurn, isFalse);
      expect(guest.isReplayPlaybackActive, isFalse);
      expect(guest.canActLocally, isTrue);
      expect(guest.state!.count, 1);
      await _settle();
      expect(emissions, [0, 1]);
      expect(guest.skipReplay(), isFalse, reason: 'nothing left to skip');
      await sub.cancel();
    });

    test('setReplaySpeed outside a replay is a no-op', () async {
      final guest = await replayingGuest('ff3');
      await guest.connect();
      guest.setReplaySpeed(4);
      expect(guest.replaySpeed, 1);
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

  group('multi-step turns', () {
    late LocalTransport transport;
    const stepDelay = Duration(milliseconds: 40);
    const game = _RunGame(stepDelay: stepDelay);

    setUp(() => transport = LocalTransport());
    tearDown(() => transport.dispose());

    test(
        'consecutive sub-moves by one player chain: prevState stays the '
        'pre-turn snapshot and turnSteps collects the intermediates', () async {
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'r1',
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        seed: 0,
      );
      final fresh = host.match!.state;

      expect(await host.submitMove(const _CounterMove()), isTrue); // a: 0->1
      await _settle();
      final afterFirst = (await transport.loadMatch('r1'))!;
      expect(afterFirst.prevState, fresh);
      expect(afterFirst.turnSteps, isNull);

      expect(await host.submitMove(const _CounterMove()), isTrue); // a: 1->2
      await _settle();
      final afterSecond = (await transport.loadMatch('r1'))!;
      expect(afterSecond.turnCount, 2);
      expect(afterSecond.lastMoverId, 'a');
      expect(afterSecond.prevState, fresh, reason: 'still the pre-turn board');
      expect(afterSecond.turnSteps, [afterFirst.state]);
      expect(afterSecond.previousTurn!.turnCount, 0);
      expect(afterSecond.previousTurn!.currentPlayerId, 'a');

      await host.dispose();
    });

    test('the chain resets when the turn passes to the other player', () async {
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'r2',
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        hotSeat: true,
        seed: 0,
      );
      await host.submitMove(const _CounterMove()); // a
      await host.submitMove(const _CounterMove()); // a
      await _settle();
      final endOfA = (await transport.loadMatch('r2'))!;

      await host.submitMove(const _CounterMove()); // b
      await _settle();
      final firstB = (await transport.loadMatch('r2'))!;
      expect(firstB.lastMoverId, 'b');
      expect(firstB.prevState, endOfA.state);
      expect(firstB.turnSteps, isNull);

      await host.dispose();
    });

    test('a game that does not replay whole turns never chains', () async {
      const unchained = _RunGame(chain: false, stepDelay: stepDelay);
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: unchained,
        transport: transport,
        matchId: 'r3',
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        seed: 0,
      );
      await host.submitMove(const _CounterMove());
      await _settle();
      final afterFirst = (await transport.loadMatch('r3'))!;
      await host.submitMove(const _CounterMove());
      await _settle();
      final afterSecond = (await transport.loadMatch('r3'))!;
      expect(afterSecond.prevState, afterFirst.state);
      expect(afterSecond.turnSteps, isNull);

      await host.dispose();
    });

    test('a cold open replays every frame of a chained turn in order',
        () async {
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'r4',
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        seed: 0,
      );
      await host.submitMove(const _CounterMove()); // a: 0->1
      await host.submitMove(const _CounterMove()); // a: 1->2
      await _settle();

      final guest = MatchController<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'r4',
        localPlayerId: 'b',
      );
      final emissions = <int>[];
      final sub = guest.stateStream.listen((s) => emissions.add(s.count));

      await guest.connect(replayLastTurn: true);
      await _settle();
      expect(guest.state!.count, 0);
      expect(guest.match!.turnCount, 0);
      expect(guest.isReplayingLastTurn, isTrue);
      expect(emissions, [0]);

      await Future.delayed(
        MatchController.replayDelay + const Duration(milliseconds: 20),
      );
      expect(emissions, [0, 1]);
      expect(guest.match!.turnCount, 1);
      expect(guest.match!.currentPlayerId, 'a');
      expect(guest.isReplayingLastTurn, isTrue);
      expect(guest.canActLocally, isFalse);

      await Future.delayed(stepDelay + const Duration(milliseconds: 20));
      expect(emissions, [0, 1, 2]);
      expect(guest.match!.turnCount, 2);
      expect(guest.isReplayingLastTurn, isFalse);
      expect(guest.canActLocally, isTrue);

      await sub.cancel();
      await host.dispose();
      await guest.dispose();
    });

    test(
        'replayLastTurn() rewinds without emitting, then lands the frames; '
        'it is refused while a replay is already running', () async {
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'r5',
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        seed: 0,
      );
      await host.submitMove(const _CounterMove()); // a: 0->1
      await host.submitMove(const _CounterMove()); // a: 1->2
      await _settle();

      final guest = MatchController<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'r5',
        localPlayerId: 'b',
      );
      await guest.connect(); // no replay on open
      final emissions = <int>[];
      final sub = guest.stateStream.listen((s) => emissions.add(s.count));
      expect(guest.state!.count, 2);
      expect(guest.canReplayLastTurn, isTrue);

      expect(guest.replayLastTurn(), isTrue);
      await _settle();
      // Rewound in place: [state]/[match] show the pre-turn snapshot, but no
      // board was asked to animate backwards.
      expect(guest.state!.count, 0);
      expect(guest.match!.currentPlayerId, 'a');
      expect(emissions, isEmpty);
      expect(guest.isReplayingLastTurn, isTrue);
      expect(guest.canReplayLastTurn, isFalse);
      expect(guest.replayLastTurn(), isFalse);
      expect(await guest.submitMove(const _CounterMove()), isFalse);

      await Future.delayed(
        MatchController.replayDelay +
            stepDelay +
            const Duration(milliseconds: 40),
      );
      expect(emissions, [1, 2]);
      expect(guest.state!.count, 2);
      expect(guest.isReplayingLastTurn, isFalse);
      expect(guest.canReplayLastTurn, isTrue);
      expect(guest.canActLocally, isTrue);

      await sub.cancel();
      await host.dispose();
      await guest.dispose();
    });

    test('a fresh match has nothing to replay', () async {
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'r6',
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        seed: 0,
      );
      expect(host.canReplayLastTurn, isFalse);
      expect(host.replayLastTurn(), isFalse);
      await host.dispose();
    });

    test('a newer turn arriving mid-chain abandons the remaining frames',
        () async {
      final host = await MatchController.create<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'r7',
        playerIds: const ['a', 'b'],
        localPlayerId: 'a',
        hotSeat: true,
        seed: 0,
      );
      await host.submitMove(const _CounterMove()); // a: 0->1
      await host.submitMove(const _CounterMove()); // a: 1->2
      await _settle();

      final guest = MatchController<_CounterState, _CounterMove>(
        game: game,
        transport: transport,
        matchId: 'r7',
        localPlayerId: 'b',
      );
      final emissions = <int>[];
      final sub = guest.stateStream.listen((s) => emissions.add(s.count));
      await guest.connect(replayLastTurn: true);
      await Future.delayed(
        MatchController.replayDelay + const Duration(milliseconds: 20),
      );
      expect(emissions, [0, 1]);

      // b moves on the host before the second frame lands.
      expect(await host.submitMove(const _CounterMove()), isTrue); // b: 2->3
      await _settle();
      expect(guest.state!.count, 3);
      expect(guest.isReplayingLastTurn, isFalse);
      expect(emissions, [0, 1, 3]);

      await Future.delayed(stepDelay + const Duration(milliseconds: 40));
      expect(emissions, [0, 1, 3], reason: 'no stale frame after abandon');

      await sub.cancel();
      await host.dispose();
      await guest.dispose();
    });
  });
}
