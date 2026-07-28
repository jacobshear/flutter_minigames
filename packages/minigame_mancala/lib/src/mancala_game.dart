import 'package:minigames_core/minigames_core.dart';

/// Mancala in the two modes GamePigeon offers: [MancalaMode.capture] and
/// [MancalaMode.avalanche].
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
/// Common to both modes: landing the last seed in your **own store** grants a
/// free re-pick (extra turn). When either side runs out of seeds the other
/// side's remainder is swept into its store and the higher store wins.
///
/// The modes differ in what happens when the last seed lands in a side pit —
/// and they are mutually exclusive, not combined:
///
/// * **Capture** — the classic Kalah rule. There is no relay: a sow is one
///   pass. If the last seed lands in an **empty pit on your own side**, you
///   capture it together with everything in the pit directly opposite. Landing
///   anywhere else simply ends the turn.
/// * **Avalanche** — there is no capturing at all. If the last seed lands in a
///   pit that **already had seeds** (either side), you scoop that whole pit up
///   and keep sowing automatically, chaining until a seed finally lands in an
///   **empty** pit, which ends the turn.
enum MancalaMode {
  /// Land in an empty own pit to take it plus the pit opposite. No relay.
  capture,

  /// Land on a non-empty pit to scoop it and keep sowing. No capturing.
  avalanche;

  String get label => switch (this) {
        MancalaMode.capture => 'Capture',
        MancalaMode.avalanche => 'Avalanche',
      };
}
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
  /// Average seeds per side pit. The opening is scattered around this rather
  /// than dealt flat — see [initialState].
  final int seedsPerPit;

  /// Which rule set is in play. See [MancalaMode].
  final MancalaMode mode;

  const MancalaGame({
    this.seedsPerPit = 4,
    this.mode = MancalaMode.capture,
  });

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
    final opening = scatterOpening(seed: seed, perPit: seedsPerPit);
    for (var i = 0; i < 6; i++) {
      pits[i] = opening[i];
      pits[7 + i] = opening[6 + i];
    }
    return MancalaState(
      pits: pits,
      playerIds: List.of(playerIds),
      currentPlayerId: playerIds[0],
    );
  }

  /// Twelve pit counts (south 0–5 then north 0–5) scattered from [seed].
  ///
  /// A flat 4-per-pit opening makes every game start identically, so the first
  /// few moves are memorised rather than read. This scatters the same total
  /// instead, which keeps the sides exactly equal — **both players get the same
  /// multiset of counts, mirrored** — while making every board a fresh problem.
  ///
  /// Mirroring matters: an asymmetric random opening would hand one player an
  /// advantage before a move is played. Here south's six pits are shuffled and
  /// north receives the identical six, so the position is balanced by
  /// construction, not by luck.
  ///
  /// Pure and deterministic (a splitmix-style hash, not `Random`), so both
  /// clients rebuild the same board from the match seed.
  static List<int> scatterOpening({required int seed, int perPit = 4}) {
    final total = perPit * 6;
    // Keep every pit playable and no pit hoarding the side.
    final minPer = perPit <= 2 ? 1 : 2;
    final maxPer = perPit + 3;

    final side = List<int>.filled(6, minPer);
    var left = total - minPer * 6;
    var h = _mix(seed * 0x9E3779B1 + 0x85EBCA77);
    // Hand the surplus out one seed at a time to a pit that still has room.
    var guard = 0;
    while (left > 0 && guard < 4096) {
      guard++;
      h = _mix(h);
      final i = (h % 6).toInt();
      if (side[i] >= maxPer) continue;
      side[i] += 1;
      left -= 1;
    }
    // Fisher–Yates so the *arrangement* varies too, not just the split.
    for (var i = 5; i > 0; i--) {
      h = _mix(h);
      final j = (h % (i + 1)).toInt();
      final t = side[i];
      side[i] = side[j];
      side[j] = t;
    }
    return [...side, ...side]; // north mirrors south — equal by construction
  }

  /// splitmix32-style avalanche, masked to stay non-negative.
  static int _mix(int x) {
    var v = x & 0x7fffffff;
    v = (v ^ (v >> 16)) * 0x7feb352d;
    v &= 0x7fffffff;
    v = (v ^ (v >> 15)) * 0x846ca68b;
    v &= 0x7fffffff;
    return (v ^ (v >> 16)) & 0x7fffffff;
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

      // Avalanche only: a side pit that already held seeds (so it now holds at
      // least 2) is scooped up and sowing continues from there. The player does
      // not re-choose, and either side counts. Capture mode never relays — one
      // sow is one pass — which is the whole difference between the rule sets.
      if (mode == MancalaMode.avalanche && isSidePit && pits[cup] >= 2) {
        hand = pits[cup];
        pits[cup] = 0;
        // Continue loop: next deposits start at the following cup.
        continue;
      }

      // Landed in an empty pit (count == 1), or capture mode: the sow is over.
      break;
    }

    var captured = 0;
    var wasCapture = false;

    // Capture mode only. Avalanche has no capturing at all — its payoff is the
    // chain, and bolting capture on top would make it strictly better than the
    // other mode rather than a different one.
    if (mode == MancalaMode.capture &&
        state.ownsPit(player, cup) &&
        pits[cup] == 1) {
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
