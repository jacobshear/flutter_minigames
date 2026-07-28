import 'dart:async';

import 'game_outcome.dart';
import 'match.dart';
import 'transport.dart';
import 'turn_game.dart';

/// Drives one match: owns the [TurnGame] + [GameTransport] pairing, exposes the
/// live decoded state to the UI, and turns local moves into transported turns.
///
/// This is the object a screen holds. Subscribe to [stateStream] to render;
/// call [submitMove] on a tap.
class MatchController<S, M> {
  final TurnGame<S, M> game;
  final GameTransport transport;
  final String matchId;

  /// The player this client acts as. In [hotSeat] mode this is ignored for
  /// turn-gating (the acting player is always whoever's turn it is).
  final String localPlayerId;

  /// When true, a single device plays every seat (pass-and-play). Moves are
  /// attributed to the current player rather than [localPlayerId].
  final bool hotSeat;

  MatchController({
    required this.game,
    required this.transport,
    required this.matchId,
    required this.localPlayerId,
    this.hotSeat = false,
  });

  final StreamController<S> _stateController = StreamController<S>.broadcast();
  StreamSubscription<Match>? _sub;
  Match? _match;

  /// Emits the decoded game state on every change.
  Stream<S> get stateStream => _stateController.stream;

  /// The latest raw match metadata, or `null` before [connect].
  Match? get match => _match;

  /// The latest decoded game state, or `null` before [connect].
  S? get state {
    final m = _match;
    return m == null ? null : game.decodeState(m.state, m.schemaVersion);
  }

  /// The current outcome, or `null` if the game is ongoing.
  GameOutcome? get outcome {
    final s = state;
    return s == null ? null : game.outcome(s);
  }

  /// Whether it's this client's move (always true in [hotSeat] while open).
  bool get canActLocally {
    final m = _match;
    if (m == null || !m.isOpen) return false;
    return hotSeat || m.currentPlayerId == localPlayerId;
  }

  /// True when it's specifically [localPlayerId]'s turn (ignores hot-seat).
  bool get isLocalPlayersTurn =>
      _match != null &&
      _match!.isOpen &&
      _match!.currentPlayerId == localPlayerId;

  /// Load the current snapshot (if any) and start listening for updates.
  Future<void> connect() async {
    final existing = await transport.loadMatch(matchId);
    if (existing != null) _emit(existing);
    _sub = transport.watchMatch(matchId).listen(_emit);
  }

  void _emit(Match m) {
    _match = m;
    if (!_stateController.isClosed) {
      _stateController.add(game.decodeState(m.state, m.schemaVersion));
    }
  }

  /// Validate [move], apply it, and submit the resulting turn to the transport.
  ///
  /// Returns false (and does nothing) if there's no match yet, it isn't a
  /// legal move, or it isn't this client's turn.
  Future<bool> submitMove(M move) async {
    final m = _match;
    if (m == null || !m.isOpen) return false;

    final current = game.decodeState(m.state, m.schemaVersion);
    final acting = hotSeat ? game.currentPlayer(current) : localPlayerId;

    if (!game.validateMove(current, move, acting)) return false;

    final next = game.applyMove(current, move);
    final outcome = game.outcome(next);

    final updated = Match(
      id: m.id,
      gameId: m.gameId,
      playerIds: m.playerIds,
      currentPlayerId: game.currentPlayer(next),
      status: outcome == null ? MatchStatus.open : MatchStatus.ended,
      turnCount: m.turnCount + 1,
      state: game.encodeState(next),
      schemaVersion: game.stateSchemaVersion,
      winnerId: outcome?.winnerId,
      isDraw: outcome?.isDraw ?? false,
    );

    await transport.submitTurn(updated);
    return true;
  }

  /// Create a fresh match on [transport] and return a connected controller.
  static Future<MatchController<S, M>> create<S, M>({
    required TurnGame<S, M> game,
    required GameTransport transport,
    required String matchId,
    required List<String> playerIds,
    required String localPlayerId,
    required int seed,
    bool hotSeat = false,
  }) async {
    final initial = game.initialState(seed: seed, playerIds: playerIds);
    final match = Match(
      id: matchId,
      gameId: game.id,
      playerIds: playerIds,
      currentPlayerId: game.currentPlayer(initial),
      status: MatchStatus.open,
      turnCount: 0,
      state: game.encodeState(initial),
      schemaVersion: game.stateSchemaVersion,
    );
    await transport.createMatch(match);

    final controller = MatchController<S, M>(
      game: game,
      transport: transport,
      matchId: matchId,
      localPlayerId: localPlayerId,
      hotSeat: hotSeat,
    );
    await controller.connect();
    return controller;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _stateController.close();
  }
}
