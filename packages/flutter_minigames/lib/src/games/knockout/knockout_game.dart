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
/// ## A round is one SIMULTANEOUS release
///
/// Both sides wind up every puck they still have — one aim per puck, in any
/// order — and nothing moves until both have committed. Then all ten pucks are
/// released in the same frame and crash into each other.
///
/// A round is therefore two [KnockoutMove]s:
/// 1. **The opening commit.** The round's opener sends only their [aims] (an
///    impulse per live puck). `positions` is empty: nothing has moved, so the
///    board is untouched. The aims park in [KnockoutState.pendingAims] and the
///    turn passes.
/// 2. **The resolving commit.** The responder sends their own aims *and* the
///    settled positions. They hold both aim sets, so they are the side that
///    runs the simultaneous simulation — the same simulate-locally,
///    serialize-the-outcome seam a single flick used before, just with every
///    puck launched at once. [applyMove] trusts those positions exactly as it
///    always has.
///
/// The resolver opens the next round, so the first-mover advantage alternates.
///
/// ### Information asymmetry (known, documented)
///
/// The opener's aims sit in shared state before the responder commits, so a
/// determined responder could read them. The board deliberately never renders
/// them, but this is UI-level blinding, not secrecy — closing it properly needs
/// the transport to withhold the opening aims until the responder's own commit
/// has landed.
///
/// ## Win condition (documented simplification)
///
/// **Elimination, not a rounds cap.** The match ends the instant a side has no
/// pucks left: if the opponent is cleared you win; if your last puck was your
/// own that fell (own goal) the opponent wins; if the *same* flick clears both
/// sides to zero it is a draw. There is no fixed number of rounds — play
/// continues, alternating rounds, until someone is wiped out. A win lands
/// mid-round if that is when the last puck goes over: [outcome] does not wait
/// for the shooter to finish their remaining flicks.
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
          nx: n == 1 ? 0.5 : _laneInset + (i / (n - 1)) * (1 - 2 * _laneInset),
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
      pendingAims: const [],
      pendingAimOwner: null,
    );
  }

  @override
  String currentPlayer(KnockoutState state) => state.currentPlayerId;

  @override
  bool validateMove(KnockoutState state, KnockoutMove move, String playerId) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    if (move.owner != playerId) return false;

    // Exactly one aim per live puck the mover owns — a round is ALL of them or
    // nothing, so a partial wind-up is not a legal commit.
    final myLive = {
      for (final p in state.pucks)
        if (p.owner == playerId) p.id,
    };
    final aimed = {for (final a in move.aims) a.puckId};
    if (aimed.length != move.aims.length) return false; // no dupes
    if (aimed.length != myLive.length) return false;
    if (!myLive.containsAll(aimed)) return false;

    if (!state.awaitingResolution) {
      // Opening commit: nothing has moved yet, so it may not claim positions.
      return move.positions.isEmpty;
    }

    // Resolving commit: the opener must not also be the resolver, and every
    // live puck must be accounted for (no phantom pucks, no omissions).
    if (state.pendingAimOwner == playerId) return false;
    final live = {for (final p in state.pucks) p.id};
    final reported = {for (final p in move.positions) p.id};
    if (reported.length != move.positions.length) return false;
    if (!reported.containsAll(live)) return false;
    if (!live.containsAll(reported)) return false;

    for (final p in move.positions) {
      if (p.fell) continue;
      if (p.nx < 0 || p.nx > 1 || p.ny < 0 || p.ny > 1) return false;
    }
    return true;
  }

  @override
  KnockoutState applyMove(KnockoutState state, KnockoutMove move) {
    final other = state.playerIds.firstWhere((p) => p != move.owner);

    // Opening commit: park the aims and hand over. The board does not move —
    // pucks only travel when the round resolves.
    if (!state.awaitingResolution) {
      return KnockoutState(
        pucks: state.pucks,
        playerIds: state.playerIds,
        currentPlayerId: other,
        frame: state.frame + 1,
        pucksPerPlayer: state.pucksPerPlayer,
        pendingAims: List.of(move.aims),
        pendingAimOwner: move.owner,
      );
    }

    // Resolving commit: trust the settled positions, survivors are the pucks
    // that did not fall. The resolver opens the next round, so whoever commits
    // first alternates.
    final pucks = [
      for (final p in move.positions)
        if (!p.fell) KnockoutPuck(id: p.id, owner: p.owner, nx: p.nx, ny: p.ny),
    ];

    return KnockoutState(
      pucks: pucks,
      playerIds: state.playerIds,
      currentPlayerId: move.owner,
      frame: state.frame + 1,
      pucksPerPlayer: state.pucksPerPlayer,
      pendingAims: const [],
      pendingAimOwner: null,
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

  /// Summarize what a resolving [move] did to the board it was played on — how
  /// many of the mover's own pucks fell (own goals) and how many opponent pucks
  /// were knocked off. Pure; drives the UI pill + SFX, not the reducer. An
  /// opening commit carries no positions and classifies as a clean no-op.
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
        'pendingAims': [for (final a in state.pendingAims) a.toJson()],
        'pendingAimOwner': state.pendingAimOwner,
      };

  @override
  KnockoutState decodeState(Map<String, dynamic> json, int version) =>
      KnockoutState(
        pucks: [
          for (final p in (json['pucks'] as List))
            KnockoutPuck.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
        playerIds: (json['playerIds'] as List).map((e) => e as String).toList(),
        currentPlayerId: json['currentPlayerId'] as String,
        frame: (json['frame'] as num).toInt(),
        pucksPerPlayer: (json['pucksPerPlayer'] as num).toInt(),
        pendingAims: [
          for (final a in (json['pendingAims'] as List? ?? const []))
            KnockoutAim.fromJson(Map<String, dynamic>.from(a as Map)),
        ],
        pendingAimOwner: json['pendingAimOwner'] as String?,
      );

  @override
  Map<String, dynamic> encodeMove(KnockoutMove move) => {
        'owner': move.owner,
        'aims': [for (final a in move.aims) a.toJson()],
        'positions': [for (final p in move.positions) p.toJson()],
      };

  @override
  KnockoutMove decodeMove(Map<String, dynamic> json) => KnockoutMove(
        owner: json['owner'] as String,
        aims: [
          for (final a in (json['aims'] as List? ?? const []))
            KnockoutAim.fromJson(Map<String, dynamic>.from(a as Map)),
        ],
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

/// One puck's wind-up: the impulse it carries when the round releases.
///
/// Normalized sim units, the same space [KnockoutPuck] positions live in, so a
/// replay on the other device reproduces the shot from the same numbers.
class KnockoutAim {
  final String puckId;
  final double ix;
  final double iy;

  const KnockoutAim({
    required this.puckId,
    required this.ix,
    required this.iy,
  });

  Map<String, dynamic> toJson() => {'puckId': puckId, 'ix': ix, 'iy': iy};

  factory KnockoutAim.fromJson(Map<String, dynamic> json) => KnockoutAim(
        puckId: json['puckId'] as String,
        ix: (json['ix'] as num).toDouble(),
        iy: (json['iy'] as num).toDouble(),
      );
}

/// A knockout move = one side's commit for the round.
///
/// [aims] is always the mover's full wind-up (one impulse per live puck they
/// own). [positions] is empty on the OPENING commit — nothing has moved yet —
/// and carries the settled position of every live puck on the RESOLVING commit,
/// which is the one that actually runs the simultaneous release.
class KnockoutMove {
  final String owner;
  final List<KnockoutAim> aims;
  final List<KnockoutPosition> positions;

  const KnockoutMove({
    required this.owner,
    required this.aims,
    this.positions = const [],
  });

  /// True when this commit resolves the round (it carries the outcome).
  bool get isResolution => positions.isNotEmpty;
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

  /// The opener's wind-up for this round, held until the responder commits and
  /// resolves. Empty when no one has committed yet.
  final List<KnockoutAim> pendingAims;

  /// Who committed [pendingAims]. Null when the round is fresh.
  final String? pendingAimOwner;

  const KnockoutState({
    required this.pucks,
    required this.playerIds,
    required this.currentPlayerId,
    required this.frame,
    required this.pucksPerPlayer,
    this.pendingAims = const [],
    this.pendingAimOwner,
  });

  /// True once one side has committed: the next commit resolves the round.
  bool get awaitingResolution => pendingAims.isNotEmpty;

  /// True when [playerId] has already wound up and is waiting on the other.
  bool hasCommitted(String playerId) => pendingAimOwner == playerId;

  /// Live pucks belonging to [playerId].
  int liveCountOf(String playerId) =>
      pucks.where((p) => p.owner == playerId).length;

  /// Pucks belonging to [playerId].
  List<KnockoutPuck> pucksOf(String playerId) =>
      pucks.where((p) => p.owner == playerId).toList();

  /// Pucks the current player must wind up before they can commit — all of
  /// them, since a round is every puck at once.
  List<KnockoutPuck> pendingPucks() => pucksOf(currentPlayerId);

  /// How many wind-ups the current player owes this round.
  int get shotsThisRound => pendingPucks().length;
}
