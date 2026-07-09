/// Framework-agnostic conformance checks for [GameTransport] implementations.
///
/// [verifyGameTransportConformance] runs the entire contract as one awaitable
/// routine and throws [ConformanceFailure] on the first violation. Because it
/// imports no test framework, you can drive it from `package:test`,
/// `flutter_test`, or `integration_test` alike:
///
/// ```dart
/// test('my transport conforms', () => verifyGameTransportConformance(
///   createTransport: () => MyTransport(),
/// ));
/// ```
library;

import 'package:minigames_core/minigames_core.dart';

/// Thrown when a transport violates the [GameTransport] contract. The message
/// names the exact expectation that failed.
class ConformanceFailure implements Exception {
  final String message;
  ConformanceFailure(this.message);
  @override
  String toString() => 'ConformanceFailure: $message';
}

void _check(bool ok, String message) {
  if (!ok) throw ConformanceFailure(message);
}

/// Give async backends (a real DB) time for a round-trip; effectively instant
/// for an in-memory transport.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 50));

/// Exercises the full [GameTransport] contract against the transport returned
/// by [createTransport] (which must return a fresh, empty transport each call).
///
/// Throws [ConformanceFailure] on the first violated expectation; returns
/// normally if the transport is conformant. [tearDownTransport] is called after
/// each sub-scenario to release resources.
Future<void> verifyGameTransportConformance({
  required GameTransport Function() createTransport,
  Future<void> Function(GameTransport transport)? tearDownTransport,
}) async {
  const game = ConformanceGame();

  Future<void> withTransport(
    Future<void> Function(GameTransport transport) body,
  ) async {
    final transport = createTransport();
    try {
      await body(transport);
    } finally {
      if (tearDownTransport != null) await tearDownTransport(transport);
    }
  }

  // 1. Unknown id resolves to null.
  await withTransport((t) async {
    _check(
      await t.loadMatch('unknown-match') == null,
      'loadMatch(unknown id) must return null',
    );
  });

  // 2. createMatch then loadMatch round-trips the match and its opaque state.
  await withTransport((t) async {
    final host =
        await MatchController.create<ConformanceState, ConformanceMove>(
      game: game,
      transport: t,
      matchId: 'c1',
      playerIds: const ['a', 'b'],
      localPlayerId: 'a',
      seed: 0,
    );
    final loaded = await t.loadMatch('c1');
    _check(loaded != null, 'createMatch then loadMatch must not be null');
    _check(loaded!.gameId == game.id, 'loaded gameId must match');
    _check(loaded.currentPlayerId == 'a', 'first mover must be "a"');
    _check(loaded.turnCount == 0, 'fresh match turnCount must be 0');
    final decoded = game.decodeState(loaded.state, loaded.schemaVersion);
    _check(decoded.count == 0, 'decoded state.count must be 0');
    _check(
      decoded.playerIds.join(',') == 'a,b',
      'playerIds must survive serialization',
    );
    await host.dispose();
  });

  // 3. A turn on one client is observed by another client.
  await withTransport((t) async {
    final host =
        await MatchController.create<ConformanceState, ConformanceMove>(
      game: game,
      transport: t,
      matchId: 'c2',
      playerIds: const ['a', 'b'],
      localPlayerId: 'a',
      seed: 0,
    );
    final guest = MatchController<ConformanceState, ConformanceMove>(
      game: game,
      transport: t,
      matchId: 'c2',
      localPlayerId: 'b',
    );
    await guest.connect();
    await _settle();

    _check(host.isLocalPlayersTurn, 'host ("a") must move first');
    _check(!guest.isLocalPlayersTurn, 'guest ("b") must not move first');

    _check(
      await host.submitMove(const ConformanceMove()),
      'host move must be accepted',
    );
    await _settle();

    _check(guest.match?.turnCount == 1, 'guest must observe turnCount 1');
    _check(guest.isLocalPlayersTurn, 'guest must be to move after host');

    await host.dispose();
    await guest.dispose();
  });

  // 4. A full game reaches a terminal outcome.
  await withTransport((t) async {
    final host =
        await MatchController.create<ConformanceState, ConformanceMove>(
      game: game,
      transport: t,
      matchId: 'c3',
      playerIds: const ['a', 'b'],
      localPlayerId: 'a',
      hotSeat: true,
      seed: 0,
    );
    for (var i = 0; i < ConformanceGame.movesToWin; i++) {
      _check(
        await host.submitMove(const ConformanceMove()),
        'move $i must be accepted',
      );
      await _settle();
    }
    _check(host.match?.status == MatchStatus.ended, 'game must end');
    _check(host.outcome?.isWin == true, 'game must have a winner');
    await host.dispose();
  });
}

// ---------------------------------------------------------------------------
// A tiny transport-agnostic game used only to drive the conformance suite.
// Exported so transport implementers can reuse it in their own scratch tests.
// ---------------------------------------------------------------------------

/// State for [ConformanceGame]: a counter plus who moved last.
class ConformanceState {
  final int count;
  final List<String> playerIds;
  final String? lastMover;
  const ConformanceState(this.count, this.playerIds, this.lastMover);
}

/// The only move: increment the counter.
class ConformanceMove {
  const ConformanceMove();
}

/// A minimal [TurnGame]: players alternate increments; whoever makes the
/// [movesToWin]th move wins. Deliberately trivial — it exists to exercise a
/// transport, not to be fun.
class ConformanceGame extends TurnGame<ConformanceState, ConformanceMove> {
  const ConformanceGame();

  static const int movesToWin = 3;

  @override
  String get id => 'conformance';

  @override
  ConformanceState initialState({
    required int seed,
    required List<String> playerIds,
  }) =>
      ConformanceState(0, List.of(playerIds), null);

  @override
  String currentPlayer(ConformanceState state) =>
      state.playerIds[state.count % state.playerIds.length];

  @override
  bool validateMove(
    ConformanceState state,
    ConformanceMove move,
    String playerId,
  ) =>
      outcome(state) == null && currentPlayer(state) == playerId;

  @override
  ConformanceState applyMove(ConformanceState state, ConformanceMove move) =>
      ConformanceState(state.count + 1, state.playerIds, currentPlayer(state));

  @override
  GameOutcome? outcome(ConformanceState state) =>
      state.count >= movesToWin ? GameOutcome.win(state.lastMover!) : null;

  @override
  Map<String, dynamic> encodeState(ConformanceState state) => {
        'count': state.count,
        'playerIds': state.playerIds,
        'lastMover': state.lastMover,
      };

  @override
  ConformanceState decodeState(Map<String, dynamic> json, int version) =>
      ConformanceState(
        json['count'] as int,
        (json['playerIds'] as List).map((e) => e as String).toList(),
        json['lastMover'] as String?,
      );

  @override
  Map<String, dynamic> encodeMove(ConformanceMove move) => const {};

  @override
  ConformanceMove decodeMove(Map<String, dynamic> json) =>
      const ConformanceMove();
}
