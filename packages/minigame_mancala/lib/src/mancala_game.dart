import 'package:minigames_core/minigames_core.dart';

/// GamePigeon-style Mancala (relay sowing).
///
/// Layout (indices):
/// ```
///        12 11 10  9  8  7
///   13 (N store)          (S store) 6
///         0  1  2  3  4  5
/// ```
/// South (player 0) owns pits 0–5 + store 6 and sows counterclockwise.
/// North (player 1) owns pits 7–12 + store 13. Opponent's store is always
/// skipped.
///
/// **Relay:** after a sow, if the last seed lands in a side pit that already
/// had marbles (count after drop ≥ 2), that **entire stack is picked up** and
/// sowing continues from there automatically — the player does **not** choose
/// again. This chains until the last seed lands in an empty pit or a store.
///
/// Landing in **own store** ends the chain and grants a free re-pick (extra
/// turn). Landing in an **empty own pit** captures opposite + that seed into
/// the store (turn ends). Side empty → sweep; higher store wins.
class MancalaState {
  static const int pitCount = 14;
  static const int southStore = 6;
  static const int northStore = 13;

  /// Stones in each cup (0–13).
  final List<int> pits;

  final List<String> playerIds;
  final String currentPlayerId;

  /// Pit the last move sowed from.
  final int? lastPit;

  /// Path of deposits for UI (cup indices in sow order).
  final List<int> lastPath;

  final bool lastExtraTurn;
  final bool lastWasCapture;
  final int lastCaptured;

  const MancalaState({
    required this.pits,
    required this.playerIds,
    required this.currentPlayerId,
    this.lastPit,
    this.lastPath = const [],
    this.lastExtraTurn = false,
    this.lastWasCapture = false,
    this.lastCaptured = 0,
  });

  String get southId => playerIds[0];
  String get northId => playerIds[1];

  String opponentOf(String id) => id == southId ? northId : southId;

  bool isSouth(String id) => id == southId;

  int storeOf(String id) => isSouth(id) ? southStore : northStore;

  int scoreFor(String id) => pits[storeOf(id)];

  /// First pit index owned by [id] (inclusive) and last playable pit (exclusive
  /// of store). South: 0..5, North: 7..12.
  (int start, int end) pitRange(String id) =>
      isSouth(id) ? (0, 6) : (7, 13);

  bool ownsPit(String id, int pit) {
    final (a, b) = pitRange(id);
    return pit >= a && pit < b;
  }

  static int opposite(int pit) {
    // 0↔12, 1↔11, … 5↔7. Stores have no opposite.
    if (pit == southStore || pit == northStore) return pit;
    return 12 - pit;
  }
}

/// Sow from one of your non-empty pits.
class MancalaMove {
  final int pit;

  const MancalaMove(this.pit);
}

class MancalaGame extends TurnGame<MancalaState, MancalaMove> {
  /// Seeds placed in each side pit at start.
  final int seedsPerPit;

  const MancalaGame({this.seedsPerPit = 4});

  @override
  String get id => 'mancala';

  @override
  MancalaState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2, 'mancala is exactly 2 players');
    assert(seedsPerPit >= 1 && seedsPerPit <= 6);
    final pits = List<int>.filled(MancalaState.pitCount, 0);
    for (var i = 0; i < 6; i++) {
      pits[i] = seedsPerPit;
      pits[7 + i] = seedsPerPit;
    }
    return MancalaState(
      pits: pits,
      playerIds: List.of(playerIds),
      currentPlayerId: playerIds[0],
    );
  }

  @override
  String currentPlayer(MancalaState state) => state.currentPlayerId;

  List<int> legalPits(MancalaState state, String playerId) {
    final (a, b) = state.pitRange(playerId);
    final out = <int>[];
    for (var i = a; i < b; i++) {
      if (state.pits[i] > 0) out.add(i);
    }
    return out;
  }

  @override
  bool validateMove(MancalaState state, MancalaMove move, String playerId) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    return legalPits(state, playerId).contains(move.pit);
  }

  @override
  MancalaState applyMove(MancalaState state, MancalaMove move) {
    final player = state.currentPlayerId;
    final pits = List<int>.of(state.pits);
    final ownStore = state.storeOf(player);
    final oppStore = state.storeOf(state.opponentOf(player));

    final path = <int>[];
    var cup = move.pit;
    var hand = pits[move.pit];
    pits[move.pit] = 0;

    // Guard against pathological relay loops (full-board churn).
    var safety = 0;
    const maxSteps = 256;

    while (hand > 0 && safety < maxSteps) {
      safety++;
      cup = (cup + 1) % MancalaState.pitCount;
      if (cup == oppStore) continue; // skip opponent store
      pits[cup] += 1;
      hand -= 1;
      path.add(cup);

      if (hand > 0) continue;

      // Last seed of this hand just landed in [cup].
      final isSidePit =
          cup != MancalaState.southStore && cup != MancalaState.northStore;

      // Own store → chain ends; free re-pick (extra turn) below.
      if (cup == ownStore) break;

      // Side pit with a stack (had marbles already) → pick up ALL and keep
      // sowing from here. Player does not re-choose.
      if (isSidePit && pits[cup] >= 2) {
        hand = pits[cup];
        pits[cup] = 0;
        // Continue loop: next deposits start at the following cup.
        continue;
      }

      // Empty pit (count == 1) or anything else → chain ends.
      break;
    }

    var captured = 0;
    var wasCapture = false;

    // Capture only when the chain ends on an empty own pit.
    if (state.ownsPit(player, cup) && pits[cup] == 1) {
      final opp = MancalaState.opposite(cup);
      if (pits[opp] > 0) {
        captured = pits[opp] + 1;
        pits[ownStore] += captured;
        pits[opp] = 0;
        pits[cup] = 0;
        wasCapture = true;
      }
    }

    // Free re-pick only when the last seed of the (possibly relayed) sow
    // landed in own store — not when a stack was auto-picked mid-chain.
    final extra = !wasCapture && cup == ownStore;

    final swept = _maybeSweep(pits);
    final nextPlayer =
        (extra && !swept) ? player : state.opponentOf(player);

    return MancalaState(
      pits: pits,
      playerIds: state.playerIds,
      currentPlayerId: nextPlayer,
      lastPit: move.pit,
      lastPath: path,
      lastExtraTurn: extra && !swept,
      lastWasCapture: wasCapture,
      lastCaptured: captured,
    );
  }

  /// If either side's pits are empty, dump remaining into that side's store.
  /// Returns true if a sweep happened (game terminal).
  bool _maybeSweep(List<int> pits) {
    final southEmpty = pits.sublist(0, 6).every((n) => n == 0);
    final northEmpty = pits.sublist(7, 13).every((n) => n == 0);
    if (!southEmpty && !northEmpty) return false;
    if (southEmpty) {
      for (var i = 7; i < 13; i++) {
        pits[MancalaState.northStore] += pits[i];
        pits[i] = 0;
      }
    } else {
      for (var i = 0; i < 6; i++) {
        pits[MancalaState.southStore] += pits[i];
        pits[i] = 0;
      }
    }
    return true;
  }

  @override
  GameOutcome? outcome(MancalaState state) {
    final southEmpty = state.pits.sublist(0, 6).every((n) => n == 0);
    final northEmpty = state.pits.sublist(7, 13).every((n) => n == 0);
    // Terminal only after sweep (all side pits empty on both sides).
    if (!southEmpty || !northEmpty) {
      // If one side empty but sweep already applied, both should be empty.
      // Mid-apply always sweeps; state should already be clean. If one side
      // empty without sweep (shouldn't happen), still resolve by stores + rest.
      if (southEmpty || northEmpty) {
        // Treat as terminal: compute final stores including unswept pits.
        var s = state.scoreFor(state.southId);
        var n = state.scoreFor(state.northId);
        for (var i = 0; i < 6; i++) {
          s += state.pits[i];
        }
        for (var i = 7; i < 13; i++) {
          n += state.pits[i];
        }
        if (s > n) return GameOutcome.win(state.southId);
        if (n > s) return GameOutcome.win(state.northId);
        return const GameOutcome.draw();
      }
      return null;
    }
    final s = state.scoreFor(state.southId);
    final n = state.scoreFor(state.northId);
    if (s > n) return GameOutcome.win(state.southId);
    if (n > s) return GameOutcome.win(state.northId);
    return const GameOutcome.draw();
  }

  @override
  Map<String, dynamic> encodeState(MancalaState state) => {
        'pits': state.pits,
        'playerIds': state.playerIds,
        'currentPlayerId': state.currentPlayerId,
        if (state.lastPit != null) 'lastPit': state.lastPit,
        'lastPath': state.lastPath,
        'lastExtraTurn': state.lastExtraTurn,
        'lastWasCapture': state.lastWasCapture,
        'lastCaptured': state.lastCaptured,
      };

  @override
  MancalaState decodeState(Map<String, dynamic> json, int version) =>
      MancalaState(
        pits: (json['pits'] as List).map((e) => e as int).toList(),
        playerIds:
            (json['playerIds'] as List).map((e) => e as String).toList(),
        currentPlayerId: json['currentPlayerId'] as String,
        lastPit: json['lastPit'] as int?,
        lastPath:
            (json['lastPath'] as List? ?? const []).map((e) => e as int).toList(),
        lastExtraTurn: json['lastExtraTurn'] as bool? ?? false,
        lastWasCapture: json['lastWasCapture'] as bool? ?? false,
        lastCaptured: json['lastCaptured'] as int? ?? 0,
      );

  @override
  Map<String, dynamic> encodeMove(MancalaMove move) => {'pit': move.pit};

  @override
  MancalaMove decodeMove(Map<String, dynamic> json) =>
      MancalaMove(json['pit'] as int);
}
