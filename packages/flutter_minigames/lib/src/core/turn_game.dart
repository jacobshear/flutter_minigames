import 'game_outcome.dart';

/// The contract every mini-game implements.
///
/// A [TurnGame] is a **pure reducer** over serializable state:
/// `applyMove(state, move) -> newState`. Purity is load-bearing — it's what
/// lets the same move be validated, re-applied, serialized across the wire,
/// and (for physics games) replayed. Never call `DateTime.now()` /
/// `Random()` inside these methods; derive all randomness from the `seed`
/// passed to [initialState].
///
/// `S` is the game-state type, `M` is the move type. Both must be convertible
/// to/from JSON via the `encode*`/`decode*` methods so they can travel through
/// a [transport].
abstract class TurnGame<S, M> {
  const TurnGame();

  /// Stable identifier for this game (e.g. `'tic_tac_toe'`). Persisted on the
  /// match so a client knows which game to instantiate.
  String get id;

  /// Bumped whenever [encodeState]'s shape changes; [decodeState] receives it
  /// so it can migrate older payloads forward.
  int get stateSchemaVersion => 1;

  /// The starting state for a fresh match. [seed] drives all randomness so
  /// both players reconstruct identical state; [playerIds] is turn order.
  S initialState({required int seed, required List<String> playerIds});

  /// The id of the player whose turn it currently is.
  String currentPlayer(S state);

  /// Whether [move] is legal for [playerId] in [state] — legality *and*
  /// whose-turn-it-is. Kept separate from [applyMove] so a receiver can
  /// re-verify a move it didn't originate.
  bool validateMove(S state, M move, String playerId);

  /// The next state after applying [move]. Assumes the move is valid
  /// (call [validateMove] first). Must be pure.
  S applyMove(S state, M move);

  /// The terminal outcome, or `null` if the game is still in progress.
  GameOutcome? outcome(S state);

  /// Whether one player's consecutive sub-moves form a single turn that a
  /// replay should show whole (a checkers multi-jump, a mancala extra turn,
  /// a dots-and-boxes box chain, a pool run, the darts of one visit).
  ///
  /// When true, `MatchController.submitMove` records every sub-move of the
  /// turn (`Match.prevState` is the board before the first one,
  /// `Match.turnSteps` the snapshots in between) and a replay lands the
  /// frames one after another, spaced by [replayStepDelay]. The default,
  /// false, records each sub-move on its own — right for games whose turn
  /// is always exactly one move.
  bool get replaysWholeTurn => false;

  /// How long a board needs to animate the transition [from] → [to] — the
  /// wait after landing [to] before the next frame of a replayed turn. Only
  /// consulted when [replaysWholeTurn] is true. Size it from the board's
  /// own animation constants; a board that snaps (most physics games show
  /// the opponent's shot as its settled result) wants a readable hold.
  Duration replayStepDelay(S from, S to) => const Duration(milliseconds: 700);

  /// Serialize [state] to a JSON-safe map for transport/storage.
  Map<String, dynamic> encodeState(S state);

  /// Reconstruct state from [json] produced at schema [version].
  S decodeState(Map<String, dynamic> json, int version);

  /// Serialize [move] to a JSON-safe map.
  Map<String, dynamic> encodeMove(M move);

  /// Reconstruct a move from [json].
  M decodeMove(Map<String, dynamic> json);
}
