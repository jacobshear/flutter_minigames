import 'dart:math' as math;

import 'package:flutter_minigames/src/core/core.dart';

/// Wii-Sports-Resort-style archery rules as a pure [TurnGame].
///
/// ## The trust boundary (read this first)
///
/// Archery is a *physics* game, but there is **no physics in this file**. The
/// shooter simulates their own arrow (see `ArcheryBallistics`, which imports
/// `minigames_3d`) and sends the **outcome of one arrow** as the move: where it
/// struck the target face and what that scored. [applyMove] is a pure reducer —
/// it banks the score, advances arrow → target → player → finished, and decides
/// the winner. It never re-simulates.
///
/// ## Format
///
/// Four targets, three arrows at each: **12 arrows per player**. Distance grows
/// and wind strengthens at every successive target. Both players shoot the
/// *same* four targets under the *same* winds — [conditionsForSeed] derives
/// them from the match seed alone, so the format is fair and reproducible.
///
/// Player 1 shoots all four targets, then a handoff, then player 2. Higher
/// total wins; equal totals are a draw.
///
/// ## Scoring (documented scheme)
///
/// A 122 cm FITA-style face of radius [faceRadius] split into five equal-width
/// rings, worth **10 / 8 / 6 / 4 / 2** from the gold outward; anything off the
/// face scores **0**. Max 10 per arrow → **30 per target** → **120 a match**,
/// matching the Wii Sports Resort ceiling. Ring boundaries are inclusive of the
/// *inner* (better) ring: an arrow exactly on the gold's edge scores 10.
class ArcheryGame extends TurnGame<ArcheryState, ArcheryMove> {
  const ArcheryGame();

  /// Targets played in a match.
  static const int targetCount = 4;

  /// Arrows shot at each target.
  static const int arrowsPerTarget = 3;

  /// Arrows a player shoots over a whole match.
  static const int arrowsPerPlayer = targetCount * arrowsPerTarget;

  /// Radius of the scoring face, metres (a 122 cm target face).
  static const double faceRadius = 0.61;

  /// Width of one scoring ring, metres.
  static const double ringWidth = faceRadius / 5;

  /// Point values from the gold outward.
  static const List<int> ringValues = [10, 8, 6, 4, 2];

  /// The most one player can score.
  static const int maxScore = targetCount * arrowsPerTarget * 10;

  @override
  String get id => 'archery';

  // ---------------------------------------------------------------------------
  // Pure scoring
  // ---------------------------------------------------------------------------

  /// Points for an arrow that struck the face [dx] metres right of and [dy]
  /// metres above the centre. Off the face scores 0.
  ///
  /// Boundaries favour the inner ring: `r == ringWidth` is still a 10.
  static int ringValue(double dx, double dy) =>
      ringValueForRadius(math.sqrt(dx * dx + dy * dy));

  /// Points for an arrow [radius] metres from the centre of the face.
  static int ringValueForRadius(double radius) {
    if (radius.isNaN || radius > faceRadius) return 0;
    if (radius <= 0) return ringValues.first;
    // ceil() makes the boundary belong to the inner ring; 1e-9 absorbs the
    // float noise a JSON round-trip can introduce on an exact-boundary hit.
    final band = ((radius - 1e-9) / ringWidth).ceil().clamp(1, ringValues.length + 1);
    return band > ringValues.length ? 0 : ringValues[band - 1];
  }

  /// Whether a hit at ([dx], [dy]) landed anywhere on the scoring face.
  static bool onFace(double dx, double dy) =>
      math.sqrt(dx * dx + dy * dy) <= faceRadius;

  // ---------------------------------------------------------------------------
  // Seeded conditions — identical for both players, reproducible per seed
  // ---------------------------------------------------------------------------

  /// Nominal ranges, metres. Jitter is added per seed; the ordering can never
  /// change because the jitter is smaller than half the gap between bases.
  static const List<double> baseDistances = [15, 22, 30, 38];

  /// Per-target wind-speed windows, m/s. Deliberately non-overlapping so wind
  /// is *always* stronger at a later target — the difficulty ramp is a promise,
  /// not a coin flip.
  static const List<(double, double)> windWindows = [
    (0.0, 2.0),
    (2.5, 4.0),
    (4.5, 6.0),
    (6.5, 9.0),
  ];

  /// The four targets a match played at [seed] is shot at, in order.
  ///
  /// Depends on the seed alone — no player term — so both players face
  /// identical distances and winds, and any client can rebuild them.
  static List<TargetConditions> conditionsForSeed(int seed) => [
        for (var i = 0; i < targetCount; i++) conditionsAt(seed, i),
      ];

  /// Conditions at target [index] (0-based) for [seed].
  static TargetConditions conditionsAt(int seed, int index) {
    final distance =
        _round(baseDistances[index] + (_unit(seed, index * 7 + 1) * 2 - 1) * 2.0, 0.5);
    final window = windWindows[index];
    final speed = _round(
      window.$1 + (window.$2 - window.$1) * _unit(seed, index * 7 + 2),
      0.5,
    );
    final blowsRight = _unit(seed, index * 7 + 3) < 0.5;
    // Deviation off pure crosswind. Kept modest so wind stays a lateral skill
    // problem with a hint of head/tail rather than an unreadable gust.
    final deviation = (_unit(seed, index * 7 + 4) * 2 - 1) * 0.4;
    return TargetConditions(
      index: index,
      distance: distance,
      windSpeed: speed,
      windAngle: (blowsRight ? 0.0 : math.pi) + deviation,
    );
  }

  static double _round(double v, double step) => (v / step).roundToDouble() * step;

  /// splitmix32 — a deterministic, well-mixed hash. Used instead of
  /// `math.Random(seed)` so the sequence is pinned to this file rather than to
  /// an SDK implementation detail.
  static int _hash(int seed, int salt) {
    var x = (seed * 0x9E3779B1 + salt * 0x85EBCA77) & 0xFFFFFFFF;
    x = (x ^ (x >>> 16)) & 0xFFFFFFFF;
    x = (x * 0x7FEB352D) & 0xFFFFFFFF;
    x = (x ^ (x >>> 15)) & 0xFFFFFFFF;
    x = (x * 0x846CA68B) & 0xFFFFFFFF;
    return (x ^ (x >>> 16)) & 0xFFFFFFFF;
  }

  /// A deterministic 0..1 draw for ([seed], [salt]).
  static double _unit(int seed, int salt) => _hash(seed, salt) / 0x100000000;

  // ---------------------------------------------------------------------------
  // TurnGame
  // ---------------------------------------------------------------------------

  @override
  ArcheryState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2);
    return ArcheryState(
      playerIds: List.of(playerIds),
      seed: seed,
      shots: {for (final p in playerIds) p: const []},
    );
  }

  @override
  String currentPlayer(ArcheryState state) => state.currentPlayerId;

  @override
  bool validateMove(ArcheryState state, ArcheryMove move, String playerId) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    if (move.shooter != playerId) return false;
    if (move.targetIndex != state.targetIndex) return false;
    if (move.arrowIndex != state.arrowIndex) return false;
    if (!move.offsetX.isFinite || !move.offsetY.isFinite) return false;
    // The pure layer owns scoring truth: the physics layer may only report
    // *where* the arrow struck, never what that is worth.
    final expected = move.onFace ? ringValue(move.offsetX, move.offsetY) : 0;
    if (move.ring != expected) return false;
    if (move.onFace != onFace(move.offsetX, move.offsetY)) return false;
    return true;
  }

  @override
  ArcheryState applyMove(ArcheryState state, ArcheryMove move) {
    final shots = {
      for (final entry in state.shots.entries) entry.key: List.of(entry.value),
    };
    shots[move.shooter] = [
      ...?shots[move.shooter],
      ArrowShot(
        ring: move.ring,
        offsetX: move.offsetX,
        offsetY: move.offsetY,
        onFace: move.onFace,
      ),
    ];
    return ArcheryState(
      playerIds: state.playerIds,
      seed: state.seed,
      shots: shots,
    );
  }

  @override
  GameOutcome? outcome(ArcheryState state) {
    if (state.phase != ArcheryPhase.finished) return null;
    final a = state.playerIds.first;
    final b = state.playerIds.last;
    final sa = state.totalOf(a);
    final sb = state.totalOf(b);
    if (sa == sb) return const GameOutcome.draw();
    return GameOutcome.win(sa > sb ? a : b);
  }

  @override
  Map<String, dynamic> encodeState(ArcheryState state) => {
        'playerIds': state.playerIds,
        'seed': state.seed,
        'shots': {
          for (final e in state.shots.entries)
            e.key: [for (final s in e.value) s.toJson()],
        },
      };

  @override
  ArcheryState decodeState(Map<String, dynamic> json, int version) {
    final playerIds = (json['playerIds'] as List).map((e) => e as String).toList();
    final rawShots = Map<String, dynamic>.from(json['shots'] as Map);
    return ArcheryState(
      playerIds: playerIds,
      seed: (json['seed'] as num).toInt(),
      shots: {
        for (final p in playerIds)
          p: [
            for (final s in (rawShots[p] as List? ?? const []))
              ArrowShot.fromJson(Map<String, dynamic>.from(s as Map)),
          ],
      },
    );
  }

  @override
  Map<String, dynamic> encodeMove(ArcheryMove move) => {
        'shooter': move.shooter,
        'targetIndex': move.targetIndex,
        'arrowIndex': move.arrowIndex,
        'ring': move.ring,
        'offsetX': move.offsetX,
        'offsetY': move.offsetY,
        'onFace': move.onFace,
      };

  @override
  ArcheryMove decodeMove(Map<String, dynamic> json) => ArcheryMove(
        shooter: json['shooter'] as String,
        targetIndex: (json['targetIndex'] as num).toInt(),
        arrowIndex: (json['arrowIndex'] as num).toInt(),
        ring: (json['ring'] as num).toInt(),
        offsetX: (json['offsetX'] as num).toDouble(),
        offsetY: (json['offsetY'] as num).toDouble(),
        onFace: json['onFace'] as bool,
      );
}

/// Where a match is in its pass-and-play sequence.
enum ArcheryPhase {
  /// Player 1 is working through the four targets.
  p1Shooting,

  /// Player 1 is done and player 2 has not started — cover the screen.
  handoff,

  /// Player 2 is working through the same four targets.
  p2Shooting,

  /// Everyone has shot 12 arrows.
  finished,
}

/// Range and wind for one target. Derived from the match seed, never rolled
/// per player — both shooters face exactly this.
class TargetConditions {
  /// 0-based position in the four-target sequence.
  final int index;

  /// Range from the shooting line, metres.
  final double distance;

  /// Wind speed, m/s. `ArcheryBallistics` converts this into the steady
  /// acceleration `ThrowConfig.wind` applies.
  final double windSpeed;

  /// Direction the wind blows *toward*, radians in the horizontal plane:
  /// 0 = toward +x (pushes an arrow right), π = toward −x, π/2 = down-range.
  final double windAngle;

  const TargetConditions({
    required this.index,
    required this.distance,
    required this.windSpeed,
    required this.windAngle,
  });

  /// Lateral part of the wind, m/s. Positive pushes the arrow right.
  double get crossComponent => math.cos(windAngle) * windSpeed;

  /// Down-range part, m/s. Positive is a tailwind (arrow lands high/long).
  double get alongComponent => math.sin(windAngle) * windSpeed;

  /// True when the wind is strong enough to demand a deliberate aim-off.
  bool get isSignificant => windSpeed >= 2.5;

  /// Compact HUD line, e.g. `Target 3 · 30 m · wind 5.0 →`.
  String summary() {
    final dir = crossComponent >= 0 ? '→' : '←';
    return 'Target ${index + 1} · ${distance.toStringAsFixed(0)} m · '
        'wind ${windSpeed.toStringAsFixed(1)} $dir';
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'distance': distance,
        'windSpeed': windSpeed,
        'windAngle': windAngle,
      };

  factory TargetConditions.fromJson(Map<String, dynamic> json) =>
      TargetConditions(
        index: (json['index'] as num).toInt(),
        distance: (json['distance'] as num).toDouble(),
        windSpeed: (json['windSpeed'] as num).toDouble(),
        windAngle: (json['windAngle'] as num).toDouble(),
      );
}

/// One arrow already shot: where it struck the face and what it scored.
class ArrowShot {
  /// Points banked (0 for a miss).
  final int ring;

  /// Metres right of the face centre (negative = left).
  final double offsetX;

  /// Metres above the face centre (negative = below).
  final double offsetY;

  /// Whether it stuck in the scoring face at all.
  final bool onFace;

  const ArrowShot({
    required this.ring,
    required this.offsetX,
    required this.offsetY,
    required this.onFace,
  });

  Map<String, dynamic> toJson() => {
        'ring': ring,
        'offsetX': offsetX,
        'offsetY': offsetY,
        'onFace': onFace,
      };

  factory ArrowShot.fromJson(Map<String, dynamic> json) => ArrowShot(
        ring: (json['ring'] as num).toInt(),
        offsetX: (json['offsetX'] as num).toDouble(),
        offsetY: (json['offsetY'] as num).toDouble(),
        onFace: json['onFace'] as bool,
      );
}

/// A move is the **outcome of one arrow** — never an aim, never a swipe.
class ArcheryMove {
  final String shooter;

  /// Which of the four targets this arrow was shot at.
  final int targetIndex;

  /// Which of the three arrows at that target (0-based).
  final int arrowIndex;

  /// Points scored (0 for a miss). Cross-checked against the offsets by
  /// [ArcheryGame.validateMove].
  final int ring;

  final double offsetX;
  final double offsetY;
  final bool onFace;

  const ArcheryMove({
    required this.shooter,
    required this.targetIndex,
    required this.arrowIndex,
    required this.ring,
    required this.offsetX,
    required this.offsetY,
    required this.onFace,
  });

  /// Builds the move for a hit at ([offsetX], [offsetY]) metres from centre,
  /// scoring it with the pure ring rules.
  factory ArcheryMove.fromImpact({
    required String shooter,
    required int targetIndex,
    required int arrowIndex,
    required double offsetX,
    required double offsetY,
  }) {
    final on = ArcheryGame.onFace(offsetX, offsetY);
    return ArcheryMove(
      shooter: shooter,
      targetIndex: targetIndex,
      arrowIndex: arrowIndex,
      ring: on ? ArcheryGame.ringValue(offsetX, offsetY) : 0,
      offsetX: offsetX,
      offsetY: offsetY,
      onFace: on,
    );
  }

  /// A clean miss — the arrow never touched the face.
  factory ArcheryMove.miss({
    required String shooter,
    required int targetIndex,
    required int arrowIndex,
    double offsetX = 0,
    double offsetY = 0,
  }) =>
      ArcheryMove(
        shooter: shooter,
        targetIndex: targetIndex,
        arrowIndex: arrowIndex,
        ring: 0,
        offsetX: offsetX,
        offsetY: offsetY,
        onFace: false,
      );
}

/// Full match state: who has shot what, and nothing else. Everything about the
/// *format* (whose turn, which target, which arrow, the phase) is derived, so
/// there is exactly one source of truth and no counter can drift.
class ArcheryState {
  final List<String> playerIds;

  /// Match seed — kept in state so any client can rebuild the four targets.
  final int seed;

  /// Arrows shot so far, in order, per player.
  final Map<String, List<ArrowShot>> shots;

  const ArcheryState({
    required this.playerIds,
    required this.seed,
    required this.shots,
  });

  List<ArrowShot> shotsOf(String playerId) => shots[playerId] ?? const [];

  int arrowsShotBy(String playerId) => shotsOf(playerId).length;

  bool isDone(String playerId) =>
      arrowsShotBy(playerId) >= ArcheryGame.arrowsPerPlayer;

  /// Running total for [playerId].
  int totalOf(String playerId) {
    var sum = 0;
    for (final s in shotsOf(playerId)) {
      sum += s.ring;
    }
    return sum;
  }

  /// Per-target subtotals (always [ArcheryGame.targetCount] long; targets not
  /// yet reached read 0). Drives the results breakdown.
  List<int> targetTotalsOf(String playerId) {
    final totals = List.filled(ArcheryGame.targetCount, 0);
    final list = shotsOf(playerId);
    for (var i = 0; i < list.length; i++) {
      totals[i ~/ ArcheryGame.arrowsPerTarget] += list[i].ring;
    }
    return totals;
  }

  /// Arrows [playerId] has already put into target [targetIndex].
  List<ArrowShot> arrowsAt(String playerId, int targetIndex) {
    final list = shotsOf(playerId);
    final start = targetIndex * ArcheryGame.arrowsPerTarget;
    final end =
        math.min(start + ArcheryGame.arrowsPerTarget, list.length);
    if (start >= end) return const [];
    return list.sublist(start, end);
  }

  /// Player 1 shoots all four targets first, then player 2.
  String get currentPlayerId =>
      isDone(playerIds.first) ? playerIds.last : playerIds.first;

  /// Target the current shooter is on (clamped once they're finished).
  int get targetIndex => math.min(
        arrowsShotBy(currentPlayerId) ~/ ArcheryGame.arrowsPerTarget,
        ArcheryGame.targetCount - 1,
      );

  /// Which arrow of the current end is next (0..2).
  int get arrowIndex =>
      arrowsShotBy(currentPlayerId) % ArcheryGame.arrowsPerTarget;

  /// Arrows the current shooter has left at this target.
  int get arrowsLeftAtTarget => ArcheryGame.arrowsPerTarget - arrowIndex;

  ArcheryPhase get phase {
    final p1Done = isDone(playerIds.first);
    final p2Done = isDone(playerIds.last);
    if (p1Done && p2Done) return ArcheryPhase.finished;
    if (!p1Done) return ArcheryPhase.p1Shooting;
    if (arrowsShotBy(playerIds.last) == 0) return ArcheryPhase.handoff;
    return ArcheryPhase.p2Shooting;
  }

  /// Conditions the current shooter is facing.
  TargetConditions get conditions =>
      ArcheryGame.conditionsAt(seed, targetIndex);

  /// All four targets for this match.
  List<TargetConditions> get allConditions =>
      ArcheryGame.conditionsForSeed(seed);
}
