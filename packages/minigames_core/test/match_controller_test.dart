import 'package:minigames_core/minigames_core.dart';
import 'package:test/test.dart';

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
}
