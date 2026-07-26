import 'package:minigames_core/minigames_core.dart';

import 'mini_golf_course.dart';

/// Mini-golf (GamePigeon-style stroke play) as a pure [TurnGame].
///
/// ## The trust boundary (read this first)
///
/// Mini golf is a *physics* game, but there is **no physics in this file**.
/// Following the harness seam (simulate-locally, serialize-the-outcome), the
/// player taking a putt runs the ball simulation on their own device and sends
/// the *settled outcome* of the putt as the move: where the ball came to rest,
/// whether it dropped in the cup, whether it left the green. [applyMove] is a
/// pure reducer: it trusts that outcome, counts the stroke, and advances the
/// round. It never re-simulates.
///
/// ## Match structure (multi-hole, hole-by-hole)
///
/// A match is [holeCount] holes (3 / 6 / 9; GamePigeon plays 9). Every hole is a
/// **distinct** deterministic layout — hole `i` is
/// [MiniGolfCourse.forHole]`(baseSeed, i)`, which deals hole shapes from a
/// seeded permutation of the archetypes, so a 9-hole course walks through every
/// archetype and neighbours never share one.
///
/// It is hot-seat and played **hole-by-hole**: on each hole Player 1 putts until
/// they hole out, then a handoff to Player 2, who plays the same hole; then the
/// match advances to the next hole (back to Player 1). `currentPlayerId` stays on
/// a player until they sink, then flips; when both have holed the current hole it
/// advances. Scoring is **cumulative strokes across all holes** — fewest total
/// wins, equal is a draw.
///
/// ## Par
///
/// Par is **per hole**, derived by the generator from the hole's route length
/// and archetype ([MiniGolfCourse.par]) rather than one flat number for the
/// course — a short island green is a par 2, a split fork is a par 4. The state
/// carries no par of its own; [MiniGolfState.parOf] reads it off the course.
///
/// ## Out of bounds
///
/// The green is fully enclosed by rails, so a normal putt banks and stays in
/// play — genuine OOB is only a numerical edge case (a ball resolving just
/// outside the polygon, or a timed-out putt). It's modeled anyway: an OOB putt
/// still costs its stroke, and the ball resets to the **tee** (a lightweight
/// stroke-and-distance penalty).
class MiniGolfGame extends TurnGame<MiniGolfState, MiniGolfMove> {
  /// Holes in a match (GamePigeon plays 9).
  final int holeCount;

  const MiniGolfGame({this.holeCount = 9});

  @override
  String get id => 'mini_golf';

  @override
  int get stateSchemaVersion => 3;

  /// The distinct hole seed for hole [holeIndex] of a match built on [baseSeed].
  static int holeSeed(int baseSeed, int holeIndex) =>
      MiniGolfCourse.holeSeed(baseSeed, holeIndex);

  @override
  MiniGolfState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2);
    final tee = MiniGolfCourse.forHole(seed, 0).normalizedTee;
    return MiniGolfState(
      baseSeed: seed,
      holeCount: holeCount,
      playerIds: List.of(playerIds),
      currentHole: 0,
      currentPlayerId: playerIds[0],
      scorecard: {for (final p in playerIds) p: const <int>[]},
      holeStrokes: {for (final p in playerIds) p: 0},
      holedOut: {for (final p in playerIds) p: false},
      ballNx: {for (final p in playerIds) p: tee.dx},
      ballNy: {for (final p in playerIds) p: tee.dy},
    );
  }

  @override
  String currentPlayer(MiniGolfState state) => state.currentPlayerId;

  @override
  bool validateMove(MiniGolfState state, MiniGolfMove move, String playerId) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    if (move.owner != playerId) return false;
    if (state.holedOut[playerId] ?? false) return false;
    if (!move.sunk && !move.outOfBounds) {
      if (move.ballNx < 0 || move.ballNx > 1) return false;
      if (move.ballNy < 0 || move.ballNy > 1) return false;
    }
    return true;
  }

  @override
  MiniGolfState applyMove(MiniGolfState state, MiniGolfMove move) {
    final course = state.holeCourse(state.currentHole);

    final holeStrokes = Map<String, int>.of(state.holeStrokes);
    holeStrokes[move.owner] = (holeStrokes[move.owner] ?? 0) + 1;

    final holedOut = Map<String, bool>.of(state.holedOut);
    final ballNx = Map<String, double>.of(state.ballNx);
    final ballNy = Map<String, double>.of(state.ballNy);

    if (move.sunk) {
      final cup = course.normalizedCup;
      holedOut[move.owner] = true;
      ballNx[move.owner] = cup.dx;
      ballNy[move.owner] = cup.dy;
    } else if (move.outOfBounds) {
      final tee = course.normalizedTee;
      ballNx[move.owner] = tee.dx;
      ballNy[move.owner] = tee.dy;
    } else {
      ballNx[move.owner] = move.ballNx;
      ballNy[move.owner] = move.ballNy;
    }

    final other = state.playerIds.firstWhere((p) => p != move.owner);
    final ownerDone = holedOut[move.owner] ?? false;
    final otherDone = holedOut[other] ?? false;

    // Still putting this hole?
    if (!ownerDone) {
      return state.copyWith(
        currentPlayerId: move.owner,
        holeStrokes: holeStrokes,
        holedOut: holedOut,
        ballNx: ballNx,
        ballNy: ballNy,
      );
    }

    // Owner holed out but the other player hasn't played this hole yet: handoff.
    if (!otherDone) {
      return state.copyWith(
        currentPlayerId: other,
        holeStrokes: holeStrokes,
        holedOut: holedOut,
        ballNx: ballNx,
        ballNy: ballNy,
      );
    }

    // Both have holed the current hole — record it and advance.
    final scorecard = {
      for (final p in state.playerIds)
        p: [...state.scorecard[p]!, holeStrokes[p] ?? 0],
    };
    final nextHole = state.currentHole + 1;

    if (nextHole >= state.holeCount) {
      // Match over: freeze on the final hole, strokes all banked in scorecard.
      return state.copyWith(
        currentHole: nextHole,
        currentPlayerId: state.playerIds[0],
        scorecard: scorecard,
        holeStrokes: {for (final p in state.playerIds) p: 0},
        holedOut: holedOut,
        ballNx: ballNx,
        ballNy: ballNy,
      );
    }

    // Set up the next hole: fresh tee, nobody holed out, Player 1 tees off.
    final tee = MiniGolfCourse.forHole(state.baseSeed, nextHole).normalizedTee;
    return state.copyWith(
      currentHole: nextHole,
      currentPlayerId: state.playerIds[0],
      scorecard: scorecard,
      holeStrokes: {for (final p in state.playerIds) p: 0},
      holedOut: {for (final p in state.playerIds) p: false},
      ballNx: {for (final p in state.playerIds) p: tee.dx},
      ballNy: {for (final p in state.playerIds) p: tee.dy},
    );
  }

  @override
  GameOutcome? outcome(MiniGolfState state) {
    if (state.currentHole < state.holeCount) return null;
    final a = state.playerIds[0];
    final b = state.playerIds[1];
    final ta = state.totalStrokes(a);
    final tb = state.totalStrokes(b);
    if (ta == tb) return const GameOutcome.draw();
    return GameOutcome.win(ta < tb ? a : b); // fewest total strokes wins
  }

  @override
  Map<String, dynamic> encodeState(MiniGolfState state) => {
        'baseSeed': state.baseSeed,
        'holeCount': state.holeCount,
        'playerIds': state.playerIds,
        'currentHole': state.currentHole,
        'currentPlayerId': state.currentPlayerId,
        'scorecard': state.scorecard,
        'holeStrokes': state.holeStrokes,
        'holedOut': state.holedOut,
        'ballNx': state.ballNx,
        'ballNy': state.ballNy,
      };

  @override
  MiniGolfState decodeState(Map<String, dynamic> json, int version) =>
      MiniGolfState(
        baseSeed: (json['baseSeed'] as num).toInt(),
        holeCount: (json['holeCount'] as num).toInt(),
        playerIds:
            (json['playerIds'] as List).map((e) => e as String).toList(),
        currentHole: (json['currentHole'] as num).toInt(),
        currentPlayerId: json['currentPlayerId'] as String,
        scorecard: {
          for (final e in (json['scorecard'] as Map).entries)
            e.key as String:
                (e.value as List).map((v) => (v as num).toInt()).toList(),
        },
        holeStrokes: {
          for (final e in (json['holeStrokes'] as Map).entries)
            e.key as String: (e.value as num).toInt(),
        },
        holedOut: {
          for (final e in (json['holedOut'] as Map).entries)
            e.key as String: e.value as bool,
        },
        ballNx: {
          for (final e in (json['ballNx'] as Map).entries)
            e.key as String: (e.value as num).toDouble(),
        },
        ballNy: {
          for (final e in (json['ballNy'] as Map).entries)
            e.key as String: (e.value as num).toDouble(),
        },
      );

  @override
  Map<String, dynamic> encodeMove(MiniGolfMove move) => {
        'owner': move.owner,
        'ballNx': move.ballNx,
        'ballNy': move.ballNy,
        'sunk': move.sunk,
        'outOfBounds': move.outOfBounds,
      };

  @override
  MiniGolfMove decodeMove(Map<String, dynamic> json) => MiniGolfMove(
        owner: json['owner'] as String,
        ballNx: (json['ballNx'] as num).toDouble(),
        ballNy: (json['ballNy'] as num).toDouble(),
        sunk: json['sunk'] as bool? ?? false,
        outOfBounds: json['outOfBounds'] as bool? ?? false,
      );
}

/// A putt outcome: where the ball settled and how the putt resolved. This is the
/// serialized physics result — the pure reducer trusts it.
class MiniGolfMove {
  final String owner;

  /// Settled ball position (normalized to the hole's bounding box). For a
  /// [sunk] putt this is the cup; for an [outOfBounds] putt it is ignored (the
  /// ball resets to the tee).
  final double ballNx;
  final double ballNy;

  /// The ball dropped in the cup — this player has holed out on the current hole.
  final bool sunk;

  /// The ball left the green (penalty). Costs the stroke; ball resets to tee.
  final bool outOfBounds;

  const MiniGolfMove({
    required this.owner,
    required this.ballNx,
    required this.ballNy,
    this.sunk = false,
    this.outOfBounds = false,
  });
}

/// Full match state across a multi-hole course.
class MiniGolfState {
  /// Match seed; each hole's layout is `MiniGolfCourse.forHole(baseSeed, i)`.
  final int baseSeed;

  /// Holes in the match.
  final int holeCount;

  final List<String> playerIds;

  /// Hole currently in play (0-based). Equals [holeCount] once the match ends.
  final int currentHole;

  final String currentPlayerId;

  /// Completed holes' strokes per player. `scorecard[p][h]` is player p's strokes
  /// on hole h; length is the number of holes that player has finished.
  final Map<String, List<int>> scorecard;

  /// Strokes taken on the *current* hole, per player.
  final Map<String, int> holeStrokes;

  /// Whether each player has holed out on the *current* hole.
  final Map<String, bool> holedOut;

  /// Each player's current ball position (normalized) on the current hole.
  final Map<String, double> ballNx;
  final Map<String, double> ballNy;

  const MiniGolfState({
    required this.baseSeed,
    required this.holeCount,
    required this.playerIds,
    required this.currentHole,
    required this.currentPlayerId,
    required this.scorecard,
    required this.holeStrokes,
    required this.holedOut,
    required this.ballNx,
    required this.ballNy,
  });

  MiniGolfState copyWith({
    int? currentHole,
    String? currentPlayerId,
    Map<String, List<int>>? scorecard,
    Map<String, int>? holeStrokes,
    Map<String, bool>? holedOut,
    Map<String, double>? ballNx,
    Map<String, double>? ballNy,
  }) =>
      MiniGolfState(
        baseSeed: baseSeed,
        holeCount: holeCount,
        playerIds: playerIds,
        currentHole: currentHole ?? this.currentHole,
        currentPlayerId: currentPlayerId ?? this.currentPlayerId,
        scorecard: scorecard ?? this.scorecard,
        holeStrokes: holeStrokes ?? this.holeStrokes,
        holedOut: holedOut ?? this.holedOut,
        ballNx: ballNx ?? this.ballNx,
        ballNy: ballNy ?? this.ballNy,
      );

  /// Strokes recorded on completed holes plus the in-progress current hole.
  int totalStrokes(String playerId) {
    final banked =
        (scorecard[playerId] ?? const []).fold<int>(0, (sum, s) => sum + s);
    return banked + (holeStrokes[playerId] ?? 0);
  }

  /// Strokes on the current hole (before it's banked).
  int holeStrokesOf(String playerId) => holeStrokes[playerId] ?? 0;

  /// Whether [playerId] has holed the current hole.
  bool holedOutOf(String playerId) => holedOut[playerId] ?? false;

  /// Number of holes [playerId] has fully finished.
  int holesCompleted(String playerId) =>
      (scorecard[playerId] ?? const []).length;

  /// The course for hole [i].
  MiniGolfCourse holeCourse(int i) => MiniGolfCourse.forHole(baseSeed, i);

  /// The course for the hole in play (clamped so a finished match shows the
  /// final hole rather than running off the end).
  MiniGolfCourse get currentCourse =>
      holeCourse(currentHole.clamp(0, holeCount - 1));

  /// Par for hole [i], read off that hole's generated layout.
  int parOf(int i) => holeCourse(i).par;

  /// Par for the hole in play.
  int get currentPar => parOf(currentHole.clamp(0, holeCount - 1));

  /// Total par for the match — the sum of the individual holes', since par
  /// varies hole to hole.
  int get totalPar {
    var sum = 0;
    for (var i = 0; i < holeCount; i++) {
      sum += parOf(i);
    }
    return sum;
  }

  /// The acting player's ball on the current hole, in world `(x, z)`.
  ({double x, double z}) ballWorld(String playerId) {
    final c = currentCourse;
    final p = c.denormalize(
      ballNx[playerId] ?? c.normalizedTee.dx,
      ballNy[playerId] ?? c.normalizedTee.dy,
    );
    return (x: p.dx, z: p.dy);
  }
}
