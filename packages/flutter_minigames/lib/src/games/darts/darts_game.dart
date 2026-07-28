import 'package:flutter_minigames/src/core/core.dart';

import 'darts_board_geometry.dart';

/// Standard **501** darts as a pure [TurnGame].
///
/// ## The trust boundary (read this first)
///
/// Darts is a physics game, but there is **no physics in this file**. Following
/// the harness seam (simulate-locally, serialize-the-outcome), the thrower runs
/// the ballistic simulation on their own device, scores the landing point with
/// [DartsBoardGeometry.hitAt], and sends the *result of one dart* — a sector and
/// a multiplier — as the move. [applyMove] trusts it and applies the rules. It
/// never re-simulates, never touches a camera, and never calls `Random`.
///
/// ## Rules implemented
///
/// * Both players start at [startingScore] (501). First to exactly zero wins.
/// * Three darts per visit; each dart is its own move, subtracted as it lands.
/// * **Double-out**: the dart that reaches zero must be a double (the bullseye
///   counts, as `25 × 2`).
/// * **Bust**: a dart that would take the score below zero, to exactly 1, or to
///   zero without a double voids the *whole visit* — the score reverts to
///   [DartsState.visitStartScore] and play passes immediately.
/// * A visit ends after three darts (or a bust, or the win) and play alternates.
///
/// ## Double-in: not implemented (deliberate)
///
/// This is straight-in / double-out 501 — the pub and broadcast default. A
/// double-in variant would need a per-player "opened" flag threaded through the
/// state, the encoder and the bust rules for a mechanic that mostly makes the
/// first visit feel broken to casual players. It is out of scope rather than
/// stubbed off, so there is no dead `doubleIn: false` flag lying around.
class DartsGame extends TurnGame<DartsState, DartsMove> {
  /// Score both players start from.
  final int startingScore;

  /// Darts in one visit to the oche.
  final int dartsPerVisit;

  const DartsGame({this.startingScore = 501, this.dartsPerVisit = 3});

  @override
  String get id => 'darts';

  @override
  DartsState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2);
    return DartsState(
      playerIds: List.of(playerIds),
      scores: {for (final p in playerIds) p: startingScore},
      currentPlayerId: playerIds.first,
      visit: const [],
      visitStartScore: startingScore,
      lastVisit: null,
      winnerId: null,
      dartsThrown: 0,
      dartsPerVisit: dartsPerVisit,
    );
  }

  @override
  String currentPlayer(DartsState state) => state.currentPlayerId;

  @override
  bool validateMove(DartsState state, DartsMove move, String playerId) {
    if (state.winnerId != null) return false;
    if (playerId != state.currentPlayerId) return false;
    if (move.playerId != state.currentPlayerId) return false;
    if (!move.hit.isWellFormed) return false;
    if (state.visit.length >= state.dartsPerVisit) return false;
    return true;
  }

  @override
  DartsState applyMove(DartsState state, DartsMove move) {
    final player = move.playerId;
    final hit = move.hit;
    final before = state.scoreOf(player);
    final visit = [...state.visit, hit];
    final after = before - hit.value;

    // Bust: below zero, stranded on 1 (no double available), or zero without a
    // double. The whole visit is void.
    final bust = after < 0 || after == 1 || (after == 0 && !hit.isDouble);
    if (bust) {
      final scores = Map<String, int>.of(state.scores)
        ..[player] = state.visitStartScore;
      return _passTurn(
        state,
        scores: scores,
        finished: DartsVisit(
          playerId: player,
          darts: visit,
          busted: true,
          startScore: state.visitStartScore,
        ),
      );
    }

    final scores = Map<String, int>.of(state.scores)..[player] = after;

    // Checkout: exactly zero on a double.
    if (after == 0) {
      return state.copyWith(
        scores: scores,
        visit: visit,
        winnerId: player,
        dartsThrown: state.dartsThrown + 1,
        lastVisit: DartsVisit(
          playerId: player,
          darts: visit,
          busted: false,
          startScore: state.visitStartScore,
        ),
      );
    }

    if (visit.length >= state.dartsPerVisit) {
      return _passTurn(
        state,
        scores: scores,
        finished: DartsVisit(
          playerId: player,
          darts: visit,
          busted: false,
          startScore: state.visitStartScore,
        ),
      );
    }

    return state.copyWith(
      scores: scores,
      visit: visit,
      dartsThrown: state.dartsThrown + 1,
    );
  }

  /// Close the current visit and hand the oche to the other player.
  DartsState _passTurn(
    DartsState state, {
    required Map<String, int> scores,
    required DartsVisit finished,
  }) {
    final next = state.playerIds.firstWhere((p) => p != finished.playerId);
    return state.copyWith(
      scores: scores,
      currentPlayerId: next,
      visit: const [],
      visitStartScore: scores[next] ?? 0,
      lastVisit: finished,
      dartsThrown: state.dartsThrown + 1,
    );
  }

  /// 501 has no draw — the match runs until somebody checks out.
  @override
  GameOutcome? outcome(DartsState state) =>
      state.winnerId == null ? null : GameOutcome.win(state.winnerId!);

  @override
  Map<String, dynamic> encodeState(DartsState state) => {
        'playerIds': state.playerIds,
        'scores': state.scores,
        'currentPlayerId': state.currentPlayerId,
        'visit': [for (final d in state.visit) d.toJson()],
        'visitStartScore': state.visitStartScore,
        'lastVisit': state.lastVisit?.toJson(),
        'winnerId': state.winnerId,
        'dartsThrown': state.dartsThrown,
        'dartsPerVisit': state.dartsPerVisit,
      };

  @override
  DartsState decodeState(Map<String, dynamic> json, int version) => DartsState(
        playerIds: [for (final p in json['playerIds'] as List) p as String],
        scores: {
          for (final e in (json['scores'] as Map).entries)
            e.key as String: (e.value as num).toInt(),
        },
        currentPlayerId: json['currentPlayerId'] as String,
        visit: [
          for (final d in json['visit'] as List)
            DartHit.fromJson(Map<String, dynamic>.from(d as Map)),
        ],
        visitStartScore: (json['visitStartScore'] as num).toInt(),
        lastVisit: json['lastVisit'] == null
            ? null
            : DartsVisit.fromJson(
                Map<String, dynamic>.from(json['lastVisit'] as Map)),
        winnerId: json['winnerId'] as String?,
        dartsThrown: (json['dartsThrown'] as num).toInt(),
        dartsPerVisit: (json['dartsPerVisit'] as num?)?.toInt() ?? 3,
      );

  @override
  Map<String, dynamic> encodeMove(DartsMove move) => {
        'playerId': move.playerId,
        'hit': move.hit.toJson(),
      };

  @override
  DartsMove decodeMove(Map<String, dynamic> json) => DartsMove(
        playerId: json['playerId'] as String,
        hit: DartHit.fromJson(Map<String, dynamic>.from(json['hit'] as Map)),
      );
}

/// One dart's *outcome* — the serialized result of a local simulation.
class DartsMove {
  final String playerId;
  final DartHit hit;

  const DartsMove({required this.playerId, required this.hit});

  @override
  String toString() => 'DartsMove($playerId, ${hit.label})';
}

/// A completed visit to the oche, kept for the scoreboard after play has moved
/// on (the classic "last score" panel).
class DartsVisit {
  final String playerId;
  final List<DartHit> darts;
  final bool busted;

  /// The player's score before the first dart of this visit.
  final int startScore;

  const DartsVisit({
    required this.playerId,
    required this.darts,
    required this.busted,
    required this.startScore,
  });

  /// Points actually subtracted — zero for a bust.
  int get total =>
      busted ? 0 : darts.fold(0, (sum, d) => sum + d.value);

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'darts': [for (final d in darts) d.toJson()],
        'busted': busted,
        'startScore': startScore,
      };

  static DartsVisit fromJson(Map<String, dynamic> json) => DartsVisit(
        playerId: json['playerId'] as String,
        darts: [
          for (final d in json['darts'] as List)
            DartHit.fromJson(Map<String, dynamic>.from(d as Map)),
        ],
        busted: json['busted'] as bool,
        startScore: (json['startScore'] as num).toInt(),
      );
}

/// Full 501 state: both remaining scores, whose turn it is, the darts already
/// thrown this visit, and the score the visit started from (the value a bust
/// reverts to).
class DartsState {
  final List<String> playerIds;
  final Map<String, int> scores;
  final String currentPlayerId;

  /// Darts thrown so far in the current visit (0..[dartsPerVisit]).
  final List<DartHit> visit;

  /// The current player's score before their first dart this visit.
  final int visitStartScore;

  /// The previous completed visit, for the scoreboard.
  final DartsVisit? lastVisit;

  final String? winnerId;

  /// Total darts thrown in the match (a stable turn counter).
  final int dartsThrown;

  final int dartsPerVisit;

  const DartsState({
    required this.playerIds,
    required this.scores,
    required this.currentPlayerId,
    required this.visit,
    required this.visitStartScore,
    required this.lastVisit,
    required this.winnerId,
    required this.dartsThrown,
    required this.dartsPerVisit,
  });

  int scoreOf(String playerId) => scores[playerId] ?? 0;

  /// Darts left in the current visit.
  int get dartsLeft => dartsPerVisit - visit.length;

  /// Points subtracted so far this visit.
  int get visitTotal => visit.fold(0, (sum, d) => sum + d.value);

  /// The suggested finish for the current player with the darts they have
  /// left, or null when there isn't one.
  List<DartHit>? get checkout =>
      DartsCheckout.suggest(scoreOf(currentPlayerId), dartsLeft: dartsLeft);

  /// The checkout as a compact label (`T20 D20`), or null.
  String? get checkoutHint =>
      hintFor(scoreOf(currentPlayerId), dartsLeft: dartsLeft);

  /// The checkout label for an arbitrary score — the HUD's formatter, exposed
  /// so it can be read (and tested) without a whole state.
  static String? hintFor(int remaining, {int dartsLeft = 3}) {
    final route = DartsCheckout.suggest(remaining, dartsLeft: dartsLeft);
    return route?.map((d) => d.label).join(' ');
  }

  DartsState copyWith({
    Map<String, int>? scores,
    String? currentPlayerId,
    List<DartHit>? visit,
    int? visitStartScore,
    DartsVisit? lastVisit,
    String? winnerId,
    int? dartsThrown,
  }) =>
      DartsState(
        playerIds: playerIds,
        scores: scores ?? this.scores,
        currentPlayerId: currentPlayerId ?? this.currentPlayerId,
        visit: visit ?? this.visit,
        visitStartScore: visitStartScore ?? this.visitStartScore,
        lastVisit: lastVisit ?? this.lastVisit,
        winnerId: winnerId ?? this.winnerId,
        dartsThrown: dartsThrown ?? this.dartsThrown,
        dartsPerVisit: dartsPerVisit,
      );
}

/// Checkout routes: the shortest way to finish [remaining] on a double.
///
/// Computed rather than tabulated, so it is correct for every reachable score
/// and needs no 170-row constant. The search finds every route of the minimum
/// number of darts, then ranks them the way a player would:
///
/// 1. no double or bull thrown as a *setup* dart (nobody calls "double ten,
///    double twenty" when "twenty, double twenty" is the same finish),
/// 2. finish on the most-preferred double — D20, D16, D18, … with the bull
///    last, since it is only ever the right call when nothing else reaches,
/// 3. biggest first dart.
///
/// That reproduces the standard table for the common finishes: 40 → `D20`,
/// 60 → `20 D20`, 100 → `T20 D20`, 141 → `T20 T15 D18`, 158 → `T20 T20 D19`,
/// 167 → `T20 T19 BULL`, 170 → `T20 T20 BULL`.
abstract final class DartsCheckout {
  /// Highest score finishable with three darts.
  static const int maxCheckout = 170;

  /// Preference order for the *finishing* double, by sector (25 = bullseye).
  static const List<int> _doublePreference = [
    20, 16, 18, 12, 10, 8, 4, 2, 14, 6, //
    1, 19, 17, 15, 13, 11, 9, 7, 5, 3, 25,
  ];

  /// Every hit a single dart can produce, biggest first.
  static final List<DartHit> allHits = () {
    final hits = <DartHit>[
      for (var s = 1; s <= 20; s++) ...[
        DartHit(s, 3),
        DartHit(s, 2),
        DartHit(s, 1),
      ],
      const DartHit(25, 2),
      const DartHit(25, 1),
    ];
    hits.sort((a, b) => b.value.compareTo(a.value));
    return List<DartHit>.unmodifiable(hits);
  }();

  /// Every legal finishing dart (doubles + the bullseye).
  static final List<DartHit> finishers = List<DartHit>.unmodifiable([
    for (var s = 1; s <= 20; s++) DartHit(s, 2),
    const DartHit(25, 2),
  ]);

  static int _doubleRank(DartHit d) {
    final i = _doublePreference.indexOf(d.sector);
    return i < 0 ? _doublePreference.length : i;
  }

  /// Memo keyed by `remaining * 4 + darts`. The 3-dart search is ~80 k
  /// combinations; the HUD asks for a hint on every rebuild, so it is cached.
  static final Map<int, List<DartHit>?> _memo = {};

  /// The suggested finish for [remaining] using at most [dartsLeft] darts, or
  /// null when there is no checkout (score too high, or an impossible one such
  /// as 169 / 168 / 166 / 165 / 163 / 162 / 159, or a bare 1).
  static List<DartHit>? suggest(int remaining, {int dartsLeft = 3}) {
    if (dartsLeft <= 0 || remaining < 2 || remaining > maxCheckout) return null;
    final maxDarts = dartsLeft.clamp(1, 3);
    final key = remaining * 4 + maxDarts;
    if (_memo.containsKey(key)) return _memo[key];

    List<DartHit>? found;
    for (var n = 1; n <= maxDarts && found == null; n++) {
      final best = _bestRouteOfLength(remaining, n);
      if (best != null) found = List<DartHit>.unmodifiable(best);
    }
    _memo[key] = found;
    return found;
  }

  /// Setup darts that a caller would never actually call for: a double or a
  /// bull thrown to *set up* a finish rather than to take it.
  static int _awkwardSetups(List<DartHit> route) => route
      .take(route.length - 1)
      .where((d) => d.sector == 25 || d.multiplier == 2)
      .length;

  static int _compareRoutes(List<DartHit> a, List<DartHit> b) {
    final bySetup = _awkwardSetups(a).compareTo(_awkwardSetups(b));
    if (bySetup != 0) return bySetup;
    final byDouble = _doubleRank(a.last).compareTo(_doubleRank(b.last));
    if (byDouble != 0) return byDouble;
    return b.first.value.compareTo(a.first.value);
  }

  /// Finisher lookup by exact value (doubles are unique per value, plus bull).
  static final Map<int, DartHit> _finisherByValue = {
    for (final f in finishers) f.value: f,
  };

  /// The best route of exactly [darts] darts, or null if none exists. Keeps a
  /// single running best instead of materialising every route.
  static List<DartHit>? _bestRouteOfLength(int remaining, int darts) {
    List<DartHit>? best;
    void consider(List<DartHit> route) {
      if (best == null || _compareRoutes(route, best!) < 0) best = route;
    }

    if (darts == 1) {
      final f = _finisherByValue[remaining];
      if (f != null) consider([f]);
      return best;
    }
    if (darts == 2) {
      for (final a in allHits) {
        final rest = remaining - a.value;
        if (rest < 2) continue;
        final f = _finisherByValue[rest];
        if (f != null) consider([a, f]);
      }
      return best;
    }
    for (final a in allHits) {
      final afterA = remaining - a.value;
      if (afterA < 4) continue; // needs at least 2 + a double after
      for (final b in allHits) {
        final rest = afterA - b.value;
        if (rest < 2) continue;
        final f = _finisherByValue[rest];
        if (f != null) consider([a, b, f]);
      }
    }
    return best;
  }
}
