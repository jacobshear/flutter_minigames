import 'package:flutter_minigames/src/core/core.dart';

/// GamePigeon-style **Knockout** as a pure [TurnGame].
///
/// ## The trust boundary (read this first)
///
/// Knockout is a *physics* game, but there is **no physics in this file**.
/// Following the harness seam (simulate-locally, serialize-the-outcome), the
/// player taking the shot runs the flick simulation on their own device and
/// sends the *settled positions of every puck* — plus which ones fell off — as
/// the move. [applyMove] is a pure reducer: it trusts those positions, drops the
/// fallen pucks (of **either** colour), and advances the turn. It never
/// re-simulates. This is the same GamePigeon-style choice shuffleboard makes:
/// the shooter is authoritative for their shot, which keeps the contract
/// serializable and deterministic on the receiving side.
///
/// ## Coordinates
///
/// Positions are normalized and resolution-independent over the square
/// platform:
/// * `nx` ∈ [0,1] across the platform (0 = left lip, 1 = right lip).
/// * `ny` ∈ [0,1] down the platform (0 = far/top lip, 1 = near/bottom lip).
///
/// Player 1 owns the **near** (bottom) half, player 2 the **far** (top) half.
/// All four edges are open — a puck whose *center* leaves the platform falls
/// into the void and is eliminated. That includes your own pucks: knock one of
/// yours off and it is gone (an own goal), so aim carefully.
///
/// ## Win condition (documented simplification)
///
/// **Elimination, not a rounds cap.** The match ends the instant a side has no
/// pucks left: if the opponent is cleared you win; if your last puck was your
/// own that fell (own goal) the opponent wins; if the *same* flick clears both
/// sides to zero it is a draw. There is no fixed number of rounds — play
/// continues, strictly alternating, until someone is wiped out.
///
/// ## Other deliberate GP approximations
///
/// * Pucks start in a single evenly-spaced row on each half (a clean, fully
///   deterministic setup rather than a scattered cluster). [seed] is unused for
///   placement — the opening position is fixed.
/// * Off-platform removal is decided by the physics layer (a puck whose center
///   leaves the platform), surfaced here only as the `fell` flag on a position.
class KnockoutGame extends TurnGame<KnockoutState, KnockoutMove> {
  /// Pucks each player starts with on their half.
  final int pucksPerPlayer;

  const KnockoutGame({this.pucksPerPlayer = 5});

  // Placement geometry (see [_layoutHalf]).
  static const double _laneInset = 0.16;
  static const double _nearRowNy = 0.82; // player 1 (bottom)
  static const double _farRowNy = 0.18; // player 2 (top)

  @override
  String get id => 'knockout';

  /// One evenly-spaced row of [n] pucks for [owner] on the near or far half.
  static List<KnockoutPuck> _layoutHalf(String owner, int n, bool near) {
    final ny = near ? _nearRowNy : _farRowNy;
    return [
      for (var i = 0; i < n; i++)
        KnockoutPuck(
          id: '$owner-$i',
          owner: owner,
          nx: n == 1
              ? 0.5
              : _laneInset + (i / (n - 1)) * (1 - 2 * _laneInset),
          ny: ny,
        ),
    ];
  }

  @override
  KnockoutState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2);
    final near = playerIds[0];
    final far = playerIds[1];
    return KnockoutState(
      pucks: [
        ..._layoutHalf(near, pucksPerPlayer, true),
        ..._layoutHalf(far, pucksPerPlayer, false),
      ],
      playerIds: List.of(playerIds),
      currentPlayerId: near,
      frame: 0,
      pucksPerPlayer: pucksPerPlayer,
    );
  }

  @override
  String currentPlayer(KnockoutState state) => state.currentPlayerId;

  @override
  bool validateMove(KnockoutState state, KnockoutMove move, String playerId) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    if (move.owner != playerId) return false;

    // The flicked puck must be this player's and still alive.
    final flicked =
        state.pucks.where((p) => p.id == move.flickedPuckId).toList();
    if (flicked.length != 1) return false;
    if (flicked.first.owner != playerId) return false;

    // Every live puck must be accounted for in the outcome, and every reported
    // id must correspond to a live puck (no phantom pucks).
    final live = {for (final p in state.pucks) p.id};
    final reported = {for (final p in move.positions) p.id};
    if (reported.length != move.positions.length) return false; // no dupes
    if (!reported.containsAll(live)) return false;
    if (!live.containsAll(reported)) return false;

    // On-platform (non-fallen) positions must be inside the platform.
    for (final p in move.positions) {
      if (p.fell) continue;
      if (p.nx < 0 || p.nx > 1 || p.ny < 0 || p.ny > 1) return false;
    }
    return true;
  }

  @override
  KnockoutState applyMove(KnockoutState state, KnockoutMove move) {
    // Trust the settled positions: survivors are the pucks that did not fall.
    final pucks = [
      for (final p in move.positions)
        if (!p.fell)
          KnockoutPuck(id: p.id, owner: p.owner, nx: p.nx, ny: p.ny),
    ];

    // Turn always passes to the other player; [outcome] decides if it is over.
    final other = state.playerIds.firstWhere((p) => p != move.owner);

    return KnockoutState(
      pucks: pucks,
      playerIds: state.playerIds,
      currentPlayerId: other,
      frame: state.frame + 1,
      pucksPerPlayer: state.pucksPerPlayer,
    );
  }

  @override
  GameOutcome? outcome(KnockoutState state) {
    final a = state.playerIds[0];
    final b = state.playerIds[1];
    final la = state.liveCountOf(a);
    final lb = state.liveCountOf(b);
    if (la > 0 && lb > 0) return null; // still in play
    if (la == 0 && lb == 0) return const GameOutcome.draw();
    return GameOutcome.win(la > 0 ? a : b);
  }

  /// Summarize what a [move] did to the board it was played on — how many of the
  /// mover's own pucks fell (own goals) and how many opponent pucks were knocked
  /// off. Pure; drives the UI pill + SFX, not the reducer.
  KnockoutShotResult classifyShot(KnockoutState before, KnockoutMove move) {
    final ownerOf = {for (final p in before.pucks) p.id: p.owner};
    var ownLost = 0;
    var oppKnocked = 0;
    for (final p in move.positions) {
      if (!p.fell) continue;
      final owner = ownerOf[p.id];
      if (owner == null) continue;
      if (owner == move.owner) {
        ownLost++;
      } else {
        oppKnocked++;
      }
    }
    return KnockoutShotResult(ownLost: ownLost, oppKnocked: oppKnocked);
  }

  @override
  Map<String, dynamic> encodeState(KnockoutState state) => {
        'pucks': [for (final p in state.pucks) p.toJson()],
        'playerIds': state.playerIds,
        'currentPlayerId': state.currentPlayerId,
        'frame': state.frame,
        'pucksPerPlayer': state.pucksPerPlayer,
      };

  @override
  KnockoutState decodeState(Map<String, dynamic> json, int version) =>
      KnockoutState(
        pucks: [
          for (final p in (json['pucks'] as List))
            KnockoutPuck.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
        playerIds:
            (json['playerIds'] as List).map((e) => e as String).toList(),
        currentPlayerId: json['currentPlayerId'] as String,
        frame: (json['frame'] as num).toInt(),
        pucksPerPlayer: (json['pucksPerPlayer'] as num).toInt(),
      );

  @override
  Map<String, dynamic> encodeMove(KnockoutMove move) => {
        'flickedPuckId': move.flickedPuckId,
        'owner': move.owner,
        'positions': [for (final p in move.positions) p.toJson()],
      };

  @override
  KnockoutMove decodeMove(Map<String, dynamic> json) => KnockoutMove(
        flickedPuckId: json['flickedPuckId'] as String,
        owner: json['owner'] as String,
        positions: [
          for (final p in (json['positions'] as List))
            KnockoutPosition.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
      );
}

/// What one flick did to the board (for UI + SFX, not the pure reducer).
class KnockoutShotResult {
  /// The mover's own pucks that fell off (own goals).
  final int ownLost;

  /// Opponent pucks knocked off.
  final int oppKnocked;

  const KnockoutShotResult({required this.ownLost, required this.oppKnocked});

  bool get isCleanHit => oppKnocked > 0 && ownLost == 0;
  bool get isOwnGoal => ownLost > 0;
  bool get isMiss => ownLost == 0 && oppKnocked == 0;
}

/// A puck at rest on the platform.
class KnockoutPuck {
  final String id;
  final String owner;

  /// Normalized position: nx ∈ [0,1] across, ny ∈ [0,1] down (0 = far lip).
  final double nx;
  final double ny;

  const KnockoutPuck({
    required this.id,
    required this.owner,
    required this.nx,
    required this.ny,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'owner': owner,
        'nx': nx,
        'ny': ny,
      };

  factory KnockoutPuck.fromJson(Map<String, dynamic> json) => KnockoutPuck(
        id: json['id'] as String,
        owner: json['owner'] as String,
        nx: (json['nx'] as num).toDouble(),
        ny: (json['ny'] as num).toDouble(),
      );
}

/// One settled puck position inside a [KnockoutMove] — the raw physics output
/// before the pure layer drops the fallen ones.
class KnockoutPosition {
  final String id;
  final String owner;
  final double nx;
  final double ny;

  /// True if the physics removed the puck (its center left the platform).
  final bool fell;

  const KnockoutPosition({
    required this.id,
    required this.owner,
    required this.nx,
    required this.ny,
    this.fell = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'owner': owner,
        'nx': nx,
        'ny': ny,
        'fell': fell,
      };

  factory KnockoutPosition.fromJson(Map<String, dynamic> json) =>
      KnockoutPosition(
        id: json['id'] as String,
        owner: json['owner'] as String,
        nx: (json['nx'] as num).toDouble(),
        ny: (json['ny'] as num).toDouble(),
        fell: json['fell'] as bool? ?? false,
      );
}

/// A knockout move = the settled outcome of one flick: which puck was flicked,
/// plus the resting position of **every** puck that was live before the flick
/// (each flagged `fell` if it left the platform).
class KnockoutMove {
  final String flickedPuckId;
  final String owner;
  final List<KnockoutPosition> positions;

  const KnockoutMove({
    required this.flickedPuckId,
    required this.owner,
    required this.positions,
  });
}

/// The full board state.
class KnockoutState {
  /// Live pucks currently on the platform (fallen ones are dropped).
  final List<KnockoutPuck> pucks;
  final List<String> playerIds;
  final String currentPlayerId;

  /// Flicks played so far.
  final int frame;

  final int pucksPerPlayer;

  const KnockoutState({
    required this.pucks,
    required this.playerIds,
    required this.currentPlayerId,
    required this.frame,
    required this.pucksPerPlayer,
  });

  /// Live pucks belonging to [playerId].
  int liveCountOf(String playerId) =>
      pucks.where((p) => p.owner == playerId).length;

  /// Pucks belonging to [playerId].
  List<KnockoutPuck> pucksOf(String playerId) =>
      pucks.where((p) => p.owner == playerId).toList();
}
