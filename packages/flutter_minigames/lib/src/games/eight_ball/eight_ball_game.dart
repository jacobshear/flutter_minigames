import 'dart:math' as math;

import 'package:flutter_minigames/src/core/core.dart';

/// GamePigeon-style 8-Ball pool as a pure [TurnGame].
///
/// ## The trust boundary (read this first)
///
/// 8-Ball is a *physics* game, but there is **no physics in this file**.
/// Following the harness seam (simulate-locally, serialize-the-outcome), the
/// player taking the shot runs the break/roll simulation on their own device
/// and sends the *settled positions of every ball* — plus which ball the cue
/// contacted first — as the move. [applyMove] is a pure reducer: it trusts
/// those positions, applies pocketing, resolves solids/stripes, detects fouls,
/// and decides the 8-ball win/loss. It never re-simulates.
///
/// ## Coordinates
///
/// Positions are normalized and resolution-independent:
/// * `nx` ∈ [0,1] across the table (0 = left rail, 1 = right rail).
/// * `ny` ∈ [0,1] along the table, **0 = the far (foot/rack) rail**, 1 = the
///   near (head/break) rail the cue is struck from.
///
/// ## Rules modelled (GamePigeon fidelity is the bar)
///
/// * Rack of 15 object balls (1–7 solids, 9–15 stripes, 8 the black) + cue.
/// * **Open table** until the first *legal* pot after the break assigns the
///   shooter their group; the opponent gets the other group.
/// * **Fouls**: cue scratch (cue pocketed or driven off), and wrong-first-
///   contact (once groups are set, the cue must first strike a ball of the
///   shooter's group — or the 8 once their group is cleared). A foul passes the
///   turn *and* grants the incoming player **ball-in-hand** (place the cue
///   anywhere, then shoot).
/// * **Continuation**: legally potting one of your own balls keeps your turn;
///   a dry shot (or only sinking an opponent ball) passes it with no ball in
///   hand.
/// * **8-ball**: pocketing the 8 **after** clearing your group with no foul on
///   that stroke wins; pocketing it early, or on a scratch, loses (the opponent
///   wins). Pool has no draws.
///
/// ## Deliberate GP simplifications (documented)
///
/// * **No "call-your-pocket".** Any legal pot counts; slop counts. GP is loose
///   here too.
/// * **No no-rail foul.** Real 8-ball fouls if, after contact, no ball reaches
///   a rail. We skip that check — the harness would have to report rail hits.
/// * **No spin/english / cue-ball control** beyond aim + power.
/// * **Group split on the break/open table:** the break never assigns a group
///   (table stays open). The first *non-break* legal pot assigns; if that stroke
///   sinks balls from *both* groups the table stays open. Center-based pocket
///   capture is decided by the physics layer.
/// * **Ball-in-hand placement is validated only for in-bounds**, not for
///   overlap with a resting ball — the board nudges the ghost off overlaps.
class EightBallGame extends TurnGame<EightBallState, EightBallMove> {
  const EightBallGame();

  @override
  String get id => 'eight_ball';

  /// Cue ball's number/id sentinel.
  static const int cueNumber = 0;

  /// The black 8 ball.
  static const int eightNumber = 8;

  // -- table geometry (canonical; the renderer/physics reuse these) ---------
  //
  // The pure layer owns these because the *rack* is pure: converting a ball
  // diameter into normalized nx/ny needs the table's world size, and nx and ny
  // are on different world scales (the table is twice as long as it is wide),
  // so a single "gap" constant cannot serve both axes. Getting that wrong is
  // exactly how the rack used to open with every ball overlapping.

  /// Table width in sim world units (across nx).
  static const double tableW = 8;

  /// Table length in sim world units (along ny).
  static const double tableL = 16;

  /// Ball radius in sim world units.
  static const double ballR = 0.42;

  /// Ball diameter in sim world units — the minimum legal centre separation.
  static const double ballD = ballR * 2;

  /// One ball diameter expressed in nx units (across the table): 0.84 / 8.
  static const double ballDx = ballD / tableW;

  /// One ball diameter expressed in ny units (along the table): 0.84 / 16.
  static const double ballDy = ballD / tableL;

  /// The apex ball's ny — the foot spot. The rack fans out from here *toward*
  /// the foot rail (decreasing ny), so the apex is the ball nearest the breaker.
  static const double rackApexNy = 0.26;

  /// The head string; the cue breaks from behind it (larger ny).
  static const double headStringNy = 0.75;

  /// Cue ball's opening ny, on the long axis behind the head string.
  static const double breakCueNy = 0.78;

  /// A hair of air between racked balls (0.4% of a diameter). Keeps the rack
  /// visually tight while guaranteeing the solver never starts with two bodies
  /// in contact-penetration, and keeps the no-overlap invariant strict rather
  /// than borderline-equal.
  static const double rackRelief = 1.004;

  /// Centre-to-centre spacing of neighbours *within* a rack row, in nx units.
  static const double rackColGap = ballDx * rackRelief;

  /// Perpendicular spacing between rack rows, in ny units. A tight triangular
  /// rack stacks rows `diameter × √3/2` apart, which is `(0.84 × √3/2) / 16`
  /// once converted to the ny scale.
  static final double rackRowGap = ballDy * rackRelief * math.sqrt(3) / 2;

  /// The group a numbered ball belongs to (null for cue and the 8).
  static BallGroup? groupOf(int number) {
    if (number >= 1 && number <= 7) return BallGroup.solids;
    if (number >= 9 && number <= 15) return BallGroup.stripes;
    return null; // cue (0) or the 8
  }

  /// The seven ball numbers of [group].
  static List<int> numbersOf(BallGroup group) => group == BallGroup.solids
      ? const [1, 2, 3, 4, 5, 6, 7]
      : const [9, 10, 11, 12, 13, 14, 15];

  /// True when every ball of [group] is pocketed in [balls].
  static bool groupCleared(List<Ball> balls, BallGroup group) {
    for (final n in numbersOf(group)) {
      final b = balls.firstWhere((x) => x.number == n);
      if (!b.pocketed) return false;
    }
    return true;
  }

  @override
  EightBallState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2);
    return EightBallState(
      balls: rackedBalls(),
      playerIds: List.of(playerIds),
      currentPlayerId: playerIds[0],
      groups: const {},
      ballInHand: false,
      shotsTaken: 0,
      over: false,
      winnerId: null,
    );
  }

  /// The standard opening layout: cue behind the head string, 15 racked at the
  /// foot with the apex on the foot spot and the 8 in the centre of the third
  /// row (a legal rack). Pure — no randomness, so both clients reconstruct it
  /// identically.
  ///
  /// Geometry, in world units (diameter `ballD` = 0.84):
  /// * within a row, neighbours are one diameter apart → `ballD / tableW`
  ///   = 0.105 in **nx**;
  /// * between rows, a tight triangle stacks `ballD × √3/2` = 0.7275 apart
  ///   perpendicular → `0.7275 / tableL` = 0.04547 in **ny**.
  ///
  /// The two axes get different numbers because the table is twice as long as
  /// it is wide; a single shared "gap" constant is what made the old rack
  /// overlap by ~40% across each row.
  static List<Ball> rackedBalls() {
    // Row-by-row rack order that keeps the 8 in the middle of row 3 and mixes
    // solids/stripes like a real rack. Corners of the back row are one of each.
    const rows = <List<int>>[
      [1], // apex, on the foot spot
      [9, 2],
      [10, 8, 3], // 8 dead centre
      [11, 4, 12, 5],
      [6, 13, 7, 14, 15], // corners: 6 (solid) and 15 (stripe)
    ];
    final balls = <Ball>[];
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      // Rows recede from the apex toward the foot rail (ny → 0).
      final ny = rackApexNy - r * rackRowGap;
      final count = row.length;
      final startNx = 0.5 - (count - 1) * rackColGap / 2;
      for (var c = 0; c < count; c++) {
        balls.add(Ball(
          number: row[c],
          nx: startNx + c * rackColGap,
          ny: ny,
          pocketed: false,
        ));
      }
    }
    // Cue on the head spot, behind the head string.
    balls.add(
      const Ball(number: cueNumber, nx: 0.5, ny: breakCueNy, pocketed: false),
    );
    balls.sort((a, b) => a.number.compareTo(b.number));
    return balls;
  }

  /// Centre-to-centre distance between two balls in **world units** — the only
  /// frame in which "are these overlapping?" is a meaningful question, since
  /// nx and ny are scaled differently.
  static double worldGap(Ball a, Ball b) {
    final dx = (a.nx - b.nx) * tableW;
    final dy = (a.ny - b.ny) * tableL;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  String currentPlayer(EightBallState state) => state.currentPlayerId;

  String _opponent(EightBallState state, String player) =>
      state.playerIds.firstWhere((p) => p != player);

  @override
  bool validateMove(EightBallState state, EightBallMove move, String playerId) {
    if (state.over) return false;
    if (playerId != state.currentPlayerId) return false;
    if (move.owner != playerId) return false;

    if (move.kind == MoveKind.place) {
      if (!state.ballInHand) return false;
      final nx = move.cueNx, ny = move.cueNy;
      if (nx == null || ny == null) return false;
      return nx >= 0 && nx <= 1 && ny >= 0 && ny <= 1;
    }

    // Shot: must have resolved ball-in-hand first (place, then shoot).
    if (state.ballInHand) return false;
    final positions = move.positions;
    if (positions == null || positions.isEmpty) return false;
    // Every currently-on-table ball must be accounted for in the outcome.
    final reported = {for (final p in positions) p.number};
    for (final b in state.balls) {
      if (!reported.contains(b.number)) return false;
    }
    for (final p in positions) {
      if (p.pocketed) continue;
      if (p.nx < 0 || p.nx > 1 || p.ny < 0 || p.ny > 1) return false;
    }
    return true;
  }

  @override
  EightBallState applyMove(EightBallState state, EightBallMove move) {
    if (move.kind == MoveKind.place) return _applyPlacement(state, move);
    return _applyShot(state, move);
  }

  EightBallState _applyPlacement(EightBallState state, EightBallMove move) {
    // Reposition the cue and clear ball-in-hand. Same player now shoots.
    final balls = [
      for (final b in state.balls)
        if (b.number == cueNumber)
          Ball(
            number: cueNumber,
            nx: move.cueNx!,
            ny: move.cueNy!,
            pocketed: false,
          )
        else
          b,
    ];
    return state.copyWith(balls: balls, ballInHand: false);
  }

  EightBallState _applyShot(EightBallState state, EightBallMove move) {
    final shooter = move.owner;
    final opponent = _opponent(state, shooter);
    final shooterGroup = state.groups[shooter];
    final tableOpenBefore = state.groups.isEmpty;
    final isBreak = state.shotsTaken == 0;

    final wasPocketed = {
      for (final b in state.balls)
        if (b.pocketed) b.number,
    };

    // Trust the settled positions.
    final balls = [
      for (final p in move.positions!)
        Ball(
          number: p.number,
          nx: p.nx.clamp(0.0, 1.0),
          ny: p.ny.clamp(0.0, 1.0),
          pocketed: p.pocketed,
        ),
    ]..sort((a, b) => a.number.compareTo(b.number));

    final newlyPotted = [
      for (final b in balls)
        if (b.pocketed && !wasPocketed.contains(b.number)) b.number,
    ];
    final cueScratched = newlyPotted.contains(cueNumber);
    final objectPotted =
        newlyPotted.where((n) => n != cueNumber).toList(growable: false);
    final eightPotted = objectPotted.contains(eightNumber);

    // -- foul: wrong first contact --
    final firstHit = move.firstHitNumber;
    final shooterOnEight =
        shooterGroup != null && groupCleared(state.balls, shooterGroup);
    bool contactFoul;
    if (firstHit == null) {
      contactFoul = true; // cue struck nothing
    } else if (tableOpenBefore) {
      // Open table: legal to strike any group first, but never the 8 first.
      contactFoul = firstHit == eightNumber;
    } else if (shooterOnEight) {
      contactFoul = firstHit != eightNumber;
    } else {
      contactFoul = groupOf(firstHit) != shooterGroup;
    }
    final foul = cueScratched || contactFoul;

    // -- 8-ball terminal check --
    if (eightPotted) {
      final clearedBefore =
          shooterGroup != null && groupCleared(state.balls, shooterGroup);
      final legalWin = clearedBefore && !foul;
      return state.copyWith(
        balls: balls,
        over: true,
        winnerId: legalWin ? shooter : opponent,
        currentPlayerId: shooter,
        ballInHand: false,
        shotsTaken: state.shotsTaken + 1,
        // groups are irrelevant once over, keep them.
      );
    }

    // -- group assignment (open table, first non-break legal pot) --
    var groups = state.groups;
    if (tableOpenBefore && !isBreak && !foul) {
      final potGroups = <BallGroup>{
        for (final n in objectPotted)
          if (groupOf(n) != null) groupOf(n)!,
      };
      if (potGroups.length == 1) {
        final mine = potGroups.first;
        final theirs =
            mine == BallGroup.solids ? BallGroup.stripes : BallGroup.solids;
        groups = {shooter: mine, opponent: theirs};
      }
      // Both groups potted → stays open (bar rule).
    }

    final shooterGroupAfter = groups[shooter];

    // -- continuation: did the shooter legally sink one of "their" balls? --
    final tableOpenAfterAssign = groups.isEmpty;
    bool madeOwn = false;
    if (!foul) {
      for (final n in objectPotted) {
        if (n == eightNumber) continue;
        final belongs =
            tableOpenAfterAssign ? true : groupOf(n) == shooterGroupAfter;
        if (belongs) {
          madeOwn = true;
          break;
        }
      }
    }

    final String next;
    final bool ballInHand;
    if (foul) {
      next = opponent;
      ballInHand = true;
    } else if (madeOwn) {
      next = shooter; // keep the table
      ballInHand = false;
    } else {
      next = opponent;
      ballInHand = false;
    }

    return state.copyWith(
      balls: balls,
      groups: groups,
      currentPlayerId: next,
      ballInHand: ballInHand,
      shotsTaken: state.shotsTaken + 1,
    );
  }

  @override
  GameOutcome? outcome(EightBallState state) =>
      state.over && state.winnerId != null
          ? GameOutcome.win(state.winnerId!)
          : null;

  // -- serialization --

  @override
  Map<String, dynamic> encodeState(EightBallState state) => {
        'balls': [for (final b in state.balls) b.toJson()],
        'playerIds': state.playerIds,
        'currentPlayerId': state.currentPlayerId,
        'groups': {
          for (final e in state.groups.entries) e.key: e.value.name,
        },
        'ballInHand': state.ballInHand,
        'shotsTaken': state.shotsTaken,
        'over': state.over,
        'winnerId': state.winnerId,
      };

  @override
  EightBallState decodeState(Map<String, dynamic> json, int version) =>
      EightBallState(
        balls: [
          for (final b in (json['balls'] as List))
            Ball.fromJson(Map<String, dynamic>.from(b as Map)),
        ],
        playerIds: (json['playerIds'] as List).map((e) => e as String).toList(),
        currentPlayerId: json['currentPlayerId'] as String,
        groups: {
          for (final e in (json['groups'] as Map).entries)
            e.key as String: BallGroup.values.byName(e.value as String),
        },
        ballInHand: json['ballInHand'] as bool? ?? false,
        shotsTaken: (json['shotsTaken'] as num?)?.toInt() ?? 0,
        over: json['over'] as bool? ?? false,
        winnerId: json['winnerId'] as String?,
      );

  @override
  Map<String, dynamic> encodeMove(EightBallMove move) => {
        'kind': move.kind.name,
        'owner': move.owner,
        if (move.positions != null)
          'positions': [for (final p in move.positions!) p.toJson()],
        if (move.firstHitNumber != null) 'firstHitNumber': move.firstHitNumber,
        if (move.cueNx != null) 'cueNx': move.cueNx,
        if (move.cueNy != null) 'cueNy': move.cueNy,
      };

  @override
  EightBallMove decodeMove(Map<String, dynamic> json) => EightBallMove(
        kind: MoveKind.values.byName(json['kind'] as String),
        owner: json['owner'] as String,
        positions: json['positions'] == null
            ? null
            : [
                for (final p in (json['positions'] as List))
                  BallPosition.fromJson(Map<String, dynamic>.from(p as Map)),
              ],
        firstHitNumber: (json['firstHitNumber'] as num?)?.toInt(),
        cueNx: (json['cueNx'] as num?)?.toDouble(),
        cueNy: (json['cueNy'] as num?)?.toDouble(),
      );
}

/// Solids (1–7) or stripes (9–15).
enum BallGroup { solids, stripes }

/// A shot move carries a settled position per ball; a placement move carries a
/// new cue position.
enum MoveKind { shot, place }

/// A ball at rest in the board state.
class Ball {
  /// 0 = cue, 1–7 solids, 8 the black, 9–15 stripes.
  final int number;
  final double nx;
  final double ny;
  final bool pocketed;

  const Ball({
    required this.number,
    required this.nx,
    required this.ny,
    required this.pocketed,
  });

  bool get isCue => number == EightBallGame.cueNumber;
  bool get isEight => number == EightBallGame.eightNumber;
  BallGroup? get group => EightBallGame.groupOf(number);

  Ball copyWith({double? nx, double? ny, bool? pocketed}) => Ball(
        number: number,
        nx: nx ?? this.nx,
        ny: ny ?? this.ny,
        pocketed: pocketed ?? this.pocketed,
      );

  Map<String, dynamic> toJson() => {
        'number': number,
        'nx': nx,
        'ny': ny,
        'pocketed': pocketed,
      };

  factory Ball.fromJson(Map<String, dynamic> json) => Ball(
        number: (json['number'] as num).toInt(),
        nx: (json['nx'] as num).toDouble(),
        ny: (json['ny'] as num).toDouble(),
        pocketed: json['pocketed'] as bool? ?? false,
      );
}

/// One settled ball position inside an [EightBallMove] — the raw physics output
/// before the pure layer classifies it. [pocketed] is set when the physics
/// captured the ball in a pocket (or drove the cue off).
class BallPosition {
  final int number;
  final double nx;
  final double ny;
  final bool pocketed;

  const BallPosition({
    required this.number,
    required this.nx,
    required this.ny,
    this.pocketed = false,
  });

  Map<String, dynamic> toJson() => {
        'number': number,
        'nx': nx,
        'ny': ny,
        'pocketed': pocketed,
      };

  factory BallPosition.fromJson(Map<String, dynamic> json) => BallPosition(
        number: (json['number'] as num).toInt(),
        nx: (json['nx'] as num).toDouble(),
        ny: (json['ny'] as num).toDouble(),
        pocketed: json['pocketed'] as bool? ?? false,
      );
}

/// A move: either the settled outcome of one **shot** (every ball's resting
/// position + the first ball the cue struck), or a ball-in-hand **placement**
/// of the cue.
class EightBallMove {
  final MoveKind kind;
  final String owner;

  /// Shot only: resting position of every ball on the table after the stroke.
  final List<BallPosition>? positions;

  /// Shot only: the number of the first ball the cue contacted, or null if the
  /// cue struck nothing (a foul).
  final int? firstHitNumber;

  /// Placement only: where the cue is placed.
  final double? cueNx;
  final double? cueNy;

  const EightBallMove({
    required this.kind,
    required this.owner,
    this.positions,
    this.firstHitNumber,
    this.cueNx,
    this.cueNy,
  });

  /// The settled outcome of a stroke.
  const EightBallMove.shot({
    required this.owner,
    required List<BallPosition> this.positions,
    required this.firstHitNumber,
  })  : kind = MoveKind.shot,
        cueNx = null,
        cueNy = null;

  /// A ball-in-hand cue placement.
  const EightBallMove.place({
    required this.owner,
    required double this.cueNx,
    required double this.cueNy,
  })  : kind = MoveKind.place,
        positions = null,
        firstHitNumber = null;
}

/// The full table state.
class EightBallState {
  final List<Ball> balls;
  final List<String> playerIds;
  final String currentPlayerId;

  /// Assigned groups. Empty = open table; otherwise both players are present.
  final Map<String, BallGroup> groups;

  /// True when the incoming player must place the cue before shooting.
  final bool ballInHand;

  /// Strokes played (0 = the break is up next).
  final int shotsTaken;

  final bool over;
  final String? winnerId;

  const EightBallState({
    required this.balls,
    required this.playerIds,
    required this.currentPlayerId,
    required this.groups,
    required this.ballInHand,
    required this.shotsTaken,
    required this.over,
    required this.winnerId,
  });

  bool get isOpenTable => groups.isEmpty;

  BallGroup? groupOfPlayer(String playerId) => groups[playerId];

  Ball ball(int number) => balls.firstWhere((b) => b.number == number);

  Ball get cue => ball(EightBallGame.cueNumber);

  /// On-table (not pocketed) balls of [group].
  List<Ball> remainingOf(BallGroup group) => [
        for (final n in EightBallGame.numbersOf(group))
          if (!ball(n).pocketed) ball(n),
      ];

  /// How many of a player's group balls are still on the table (7 if unset).
  int remainingCountOf(String playerId) {
    final g = groups[playerId];
    if (g == null) return 7;
    return remainingOf(g).length;
  }

  EightBallState copyWith({
    List<Ball>? balls,
    String? currentPlayerId,
    Map<String, BallGroup>? groups,
    bool? ballInHand,
    int? shotsTaken,
    bool? over,
    String? winnerId,
  }) =>
      EightBallState(
        balls: balls ?? this.balls,
        playerIds: playerIds,
        currentPlayerId: currentPlayerId ?? this.currentPlayerId,
        groups: groups ?? this.groups,
        ballInHand: ballInHand ?? this.ballInHand,
        shotsTaken: shotsTaken ?? this.shotsTaken,
        over: over ?? this.over,
        winnerId: winnerId ?? this.winnerId,
      );
}
