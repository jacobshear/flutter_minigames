import 'package:flutter_minigames/src/core/core.dart';

/// Table-shuffleboard rules as a pure [TurnGame].
///
/// ## The trust boundary (read this first)
///
/// Shuffleboard is a *physics* game, but there is **no physics in this file**.
/// Following the harness seam (simulate-locally, serialize-the-outcome), the
/// player taking the shot runs the slide simulation on their own device and
/// sends the *settled positions of every puck* as the move. [applyMove] is a
/// pure reducer: it trusts those positions, bins them into scoring zones, and
/// advances the turn. It never re-simulates. This is a deliberate GamePigeon-
/// style choice — the shooter is authoritative for their shot — and it is what
/// keeps the contract serializable and deterministic on the receiving side.
///
/// ## Coordinates
///
/// Positions are normalized and resolution-independent:
/// * `nx` ∈ [0,1] across the table (0 = left rail, 1 = right rail).
/// * `ny` ∈ [0,1] along the table, **0 = the far scoring edge**, 1 = the near
///   line the shooter slides from. A puck slides from high `ny` toward 0.
///
/// ## Scoring (classic table shuffleboard, far-end triangle)
///
/// Bands measured from the far edge (small `ny`):
/// * `ny` < [zone3Line] → **3** (nearest the edge — the "hangers" band)
/// * `ny` < [zone2Line] → **2**
/// * `ny` < [zone1Line] → **1**
/// * `ny` < [foulLine]  → on board, **0** (crossed the foul line, no band)
/// * `ny` ≥ [foulLine]  → **foul**, 0 (didn't travel past the foul line)
/// * slid off the open far end (`removed`) → **off the end**, 0
///
/// GP approximations (documented, deliberate):
/// * A puck is binned by its **center** `ny`, not by requiring its whole disc
///   to clear a line. "Fully cross the foul line to count" is approximated as
///   the center crossing [foulLine]. Real table shuffleboard scores the lower
///   of two straddled zones; center-binning is close and fully deterministic.
/// * Off-the-end removal is decided by the physics layer (a puck leaving the
///   table), surfaced here as [PuckStatus.offEnd].
///
/// A player has [pucksPerPlayer] pucks. Players alternate slides; when one runs
/// out the other finishes their remaining pucks. The match ends when both are
/// out — higher total score wins, equal is a draw.
class ShuffleboardGame extends TurnGame<ShuffleboardState, ShuffleboardMove> {
  /// Pucks each player slides over the frame.
  final int pucksPerPlayer;

  const ShuffleboardGame({this.pucksPerPlayer = 4});

  // Scoring band lines along ny (0 = far edge). See class doc.
  static const double zone3Line = 0.10;
  static const double zone2Line = 0.20;
  static const double zone1Line = 0.32;
  static const double foulLine = 0.60;

  @override
  String get id => 'shuffleboard';

  /// The zone value a puck at [ny] scores (0 if none). Ignores foul/off-end.
  static int zoneValue(double ny) {
    if (ny < zone3Line) return 3;
    if (ny < zone2Line) return 2;
    if (ny < zone1Line) return 1;
    return 0;
  }

  /// Classify a settled puck from its normalized [ny] and whether the physics
  /// removed it (slid off the far end).
  static PuckStatus statusFor(double ny, {required bool removed}) {
    if (removed) return PuckStatus.offEnd;
    if (ny < zone1Line) return PuckStatus.inZone;
    if (ny < foulLine) return PuckStatus.onBoard;
    return PuckStatus.foul;
  }

  @override
  ShuffleboardState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2);
    return ShuffleboardState(
      pucks: const [],
      playerIds: List.of(playerIds),
      currentPlayerId: playerIds[0],
      remaining: {for (final p in playerIds) p: pucksPerPlayer},
      scores: {for (final p in playerIds) p: 0},
      frame: 0,
      pucksPerPlayer: pucksPerPlayer,
    );
  }

  @override
  String currentPlayer(ShuffleboardState state) => state.currentPlayerId;

  @override
  bool validateMove(
    ShuffleboardState state,
    ShuffleboardMove move,
    String playerId,
  ) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    if (move.owner != playerId) return false;
    if ((state.remaining[playerId] ?? 0) <= 0) return false;

    // The launched puck must be this player's, and a *fresh* one (not already
    // resting on the board).
    if (state.pucks.any((p) => p.id == move.launchedPuckId)) return false;
    final launched =
        move.positions.where((p) => p.id == move.launchedPuckId).toList();
    if (launched.length != 1) return false;
    if (launched.first.owner != playerId) return false;

    // Every existing on-board puck must still be accounted for in the outcome.
    final reported = {for (final p in move.positions) p.id};
    for (final existing in state.pucks) {
      if (!reported.contains(existing.id)) return false;
    }

    // On-board positions must be inside the table.
    for (final p in move.positions) {
      if (p.removed) continue;
      if (p.nx < 0 || p.nx > 1 || p.ny < 0 || p.ny > 1) return false;
    }
    return true;
  }

  @override
  ShuffleboardState applyMove(ShuffleboardState state, ShuffleboardMove move) {
    // Trust the settled positions: record every puck, classify, score.
    final pucks = [
      for (final p in move.positions)
        ShuffleboardPuck(
          id: p.id,
          owner: p.owner,
          nx: p.nx,
          ny: p.ny,
          status: statusFor(p.ny, removed: p.removed),
        ),
    ];

    final remaining = Map<String, int>.of(state.remaining);
    remaining[move.owner] = (remaining[move.owner] ?? 0) - 1;

    final scores = {for (final p in state.playerIds) p: 0};
    for (final puck in pucks) {
      if (puck.status == PuckStatus.inZone) {
        scores[puck.owner] = (scores[puck.owner] ?? 0) + puck.value;
      }
    }

    // Alternate; if the other player is out, the current one keeps sliding.
    final other = state.playerIds.firstWhere((p) => p != move.owner);
    final String next;
    if ((remaining[other] ?? 0) > 0) {
      next = other;
    } else {
      next = move.owner; // other is out; finish this player's pucks (or over)
    }

    return ShuffleboardState(
      pucks: pucks,
      playerIds: state.playerIds,
      currentPlayerId: next,
      remaining: remaining,
      scores: scores,
      frame: state.frame + 1,
      pucksPerPlayer: state.pucksPerPlayer,
    );
  }

  @override
  GameOutcome? outcome(ShuffleboardState state) {
    final allOut = state.playerIds.every((p) => (state.remaining[p] ?? 0) <= 0);
    if (!allOut) return null;
    final a = state.playerIds[0];
    final b = state.playerIds[1];
    final sa = state.scores[a] ?? 0;
    final sb = state.scores[b] ?? 0;
    if (sa == sb) return const GameOutcome.draw();
    return GameOutcome.win(sa > sb ? a : b);
  }

  @override
  Map<String, dynamic> encodeState(ShuffleboardState state) => {
        'pucks': [for (final p in state.pucks) p.toJson()],
        'playerIds': state.playerIds,
        'currentPlayerId': state.currentPlayerId,
        'remaining': state.remaining,
        'scores': state.scores,
        'frame': state.frame,
        'pucksPerPlayer': state.pucksPerPlayer,
      };

  @override
  ShuffleboardState decodeState(Map<String, dynamic> json, int version) =>
      ShuffleboardState(
        pucks: [
          for (final p in (json['pucks'] as List))
            ShuffleboardPuck.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
        playerIds: (json['playerIds'] as List).map((e) => e as String).toList(),
        currentPlayerId: json['currentPlayerId'] as String,
        remaining: {
          for (final e in (json['remaining'] as Map).entries)
            e.key as String: (e.value as num).toInt(),
        },
        scores: {
          for (final e in (json['scores'] as Map).entries)
            e.key as String: (e.value as num).toInt(),
        },
        frame: (json['frame'] as num).toInt(),
        pucksPerPlayer: (json['pucksPerPlayer'] as num).toInt(),
      );

  @override
  Map<String, dynamic> encodeMove(ShuffleboardMove move) => {
        'launchedPuckId': move.launchedPuckId,
        'owner': move.owner,
        'positions': [for (final p in move.positions) p.toJson()],
      };

  @override
  ShuffleboardMove decodeMove(Map<String, dynamic> json) => ShuffleboardMove(
        launchedPuckId: json['launchedPuckId'] as String,
        owner: json['owner'] as String,
        positions: [
          for (final p in (json['positions'] as List))
            PuckPosition.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
      );
}

/// How a settled puck rests relative to the scoring geometry.
enum PuckStatus {
  /// Past the foul line but not in a scoring band (0 points).
  onBoard,

  /// Inside a scoring band (see [ShuffleboardPuck.value] for 1/2/3).
  inZone,

  /// Slid off the open far end and was removed (0 points).
  offEnd,

  /// Stopped short of the foul line (0 points).
  foul,
}

/// A puck at rest in the board state.
class ShuffleboardPuck {
  final String id;
  final String owner;

  /// Normalized position: nx ∈ [0,1] across, ny ∈ [0,1] along (0 = far edge).
  final double nx;
  final double ny;

  final PuckStatus status;

  const ShuffleboardPuck({
    required this.id,
    required this.owner,
    required this.nx,
    required this.ny,
    required this.status,
  });

  /// Points this puck is worth (only nonzero when [status] is [PuckStatus.inZone]).
  int get value =>
      status == PuckStatus.inZone ? ShuffleboardGame.zoneValue(ny) : 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'owner': owner,
        'nx': nx,
        'ny': ny,
        'status': status.name,
      };

  factory ShuffleboardPuck.fromJson(Map<String, dynamic> json) =>
      ShuffleboardPuck(
        id: json['id'] as String,
        owner: json['owner'] as String,
        nx: (json['nx'] as num).toDouble(),
        ny: (json['ny'] as num).toDouble(),
        status: PuckStatus.values.byName(json['status'] as String),
      );
}

/// One settled puck position inside a [ShuffleboardMove] — the raw physics
/// output before the pure layer classifies it.
class PuckPosition {
  final String id;
  final String owner;
  final double nx;
  final double ny;

  /// True if the physics removed the puck (slid off the far end).
  final bool removed;

  const PuckPosition({
    required this.id,
    required this.owner,
    required this.nx,
    required this.ny,
    this.removed = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'owner': owner,
        'nx': nx,
        'ny': ny,
        'removed': removed,
      };

  factory PuckPosition.fromJson(Map<String, dynamic> json) => PuckPosition(
        id: json['id'] as String,
        owner: json['owner'] as String,
        nx: (json['nx'] as num).toDouble(),
        ny: (json['ny'] as num).toDouble(),
        removed: json['removed'] as bool? ?? false,
      );
}

/// A shuffleboard move = the settled outcome of one slide: which puck was
/// launched, plus the resting position of **every** puck on the table after
/// the slide (the serialized physics outcome).
class ShuffleboardMove {
  final String launchedPuckId;
  final String owner;
  final List<PuckPosition> positions;

  const ShuffleboardMove({
    required this.launchedPuckId,
    required this.owner,
    required this.positions,
  });
}

/// The full board state.
class ShuffleboardState {
  final List<ShuffleboardPuck> pucks;
  final List<String> playerIds;
  final String currentPlayerId;

  /// Pucks each player has left to slide.
  final Map<String, int> remaining;

  /// Running score per player (recomputed from [pucks] every move).
  final Map<String, int> scores;

  /// Slides played so far.
  final int frame;

  final int pucksPerPlayer;

  const ShuffleboardState({
    required this.pucks,
    required this.playerIds,
    required this.currentPlayerId,
    required this.remaining,
    required this.scores,
    required this.frame,
    required this.pucksPerPlayer,
  });

  int scoreOf(String playerId) => scores[playerId] ?? 0;
  int remainingOf(String playerId) => remaining[playerId] ?? 0;

  /// Pucks belonging to [playerId], nearest-scoring first.
  List<ShuffleboardPuck> pucksOf(String playerId) =>
      pucks.where((p) => p.owner == playerId).toList();
}
