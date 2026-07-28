import 'package:flutter_minigames/src/core/core.dart';

/// GamePigeon-style Basketball as a round-submission [TurnGame].
///
/// ## The trust boundary (read this first)
///
/// Basketball is a *physics* game, but there is **no physics in this file** and
/// no import beyond `minigames_core`. Following the harness seam
/// (simulate-locally, trust-the-outcome), each player shoots both timed rounds
/// on their own device; the round UI runs the 3-D ballistic sim, counts makes
/// off a swept descending-disc test, and submits one move carrying the
/// per-round scores. [applyMove] is a pure reducer: it normalises and records
/// what it was handed, then advances the phase. It never simulates.
///
/// The reducer is nonetheless **defensive**. A submission is trusted for its
/// magnitude, not its shape: negative, absurd, short or long round lists are
/// all normalised to exactly [roundCount] entries clamped to
/// `0..maxRoundScore`. Garbage cannot corrupt the match state.
///
/// ## Rules
///
/// * **Two rounds** of [roundSeconds] seconds each. Both rounds are shot at the
///   same fixed distance — the range never changes.
/// * **One point per basket, flat.** No streak bonus, no swish bonus, no clock
///   bonus. Detection is purely geometric; whether the ball kissed the iron on
///   the way in is irrelevant.
/// * A player's score **accumulates across their two rounds** — round 2 opens
///   at their round-1 total.
/// * `playerIds[0]` shoots both rounds and submits, then `playerIds[1]` does
///   the same; higher total wins, tie = draw.
class BasketballGame extends TurnGame<BasketballState, BasketballMove> {
  /// Seconds per round. The in-game card reads "Score as many balls as you can
  /// in 45 seconds", so this is not an assumption — it is the shipped number.
  final int roundSeconds;

  /// Rounds each player shoots.
  static const int roundCount = 2;

  /// Defensive ceiling on a single round's score. A 45 s round tops out around
  /// 45 makes for elite play; anything near this is garbage.
  static const int maxRoundScore = 999;

  const BasketballGame({this.roundSeconds = 45});

  @override
  String get id => 'basketball';

  @override
  int get stateSchemaVersion => 2;

  /// Normalise a raw submitted per-round list into exactly [roundCount]
  /// non-negative, clamped entries. Short lists are padded, long lists are
  /// truncated, negatives collapse to 0.
  static List<int> normaliseRounds(List<int> raw) => [
        for (var i = 0; i < roundCount; i++)
          if (i < raw.length) raw[i].clamp(0, maxRoundScore) else 0,
      ];

  @override
  BasketballState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2);
    return BasketballState(
      playerIds: List.of(playerIds),
      submissions: const {},
    );
  }

  @override
  String currentPlayer(BasketballState state) =>
      state.nextToPlay ?? state.playerIds.last;

  /// Legal iff the match is live, it's [playerId]'s turn to shoot, the move is
  /// attributed to them, and it carries one score per round.
  @override
  bool validateMove(
    BasketballState state,
    BasketballMove move,
    String playerId,
  ) {
    if (state.isFinished) return false;
    if (playerId != state.nextToPlay) return false;
    if (move.owner != playerId) return false;
    if (move.roundScores.length != roundCount) return false;
    return true;
  }

  @override
  BasketballState applyMove(BasketballState state, BasketballMove move) {
    final playerId = state.nextToPlay!;
    return BasketballState(
      playerIds: state.playerIds,
      submissions: {
        ...state.submissions,
        playerId: normaliseRounds(move.roundScores),
      },
    );
  }

  @override
  GameOutcome? outcome(BasketballState state) {
    if (!state.isFinished) return null;
    final a = state.playerIds[0];
    final b = state.playerIds[1];
    final sa = state.scoreOf(a);
    final sb = state.scoreOf(b);
    if (sa == sb) return const GameOutcome.draw();
    return GameOutcome.win(sa > sb ? a : b);
  }

  @override
  Map<String, dynamic> encodeState(BasketballState state) => {
        'playerIds': state.playerIds,
        'submissions': {
          for (final e in state.submissions.entries) e.key: e.value,
        },
      };

  @override
  BasketballState decodeState(Map<String, dynamic> json, int version) =>
      BasketballState(
        playerIds: (json['playerIds'] as List).map((e) => e as String).toList(),
        submissions: {
          for (final e in (json['submissions'] as Map).entries)
            e.key as String: normaliseRounds(intList(e.value)),
        },
      );

  @override
  Map<String, dynamic> encodeMove(BasketballMove move) => {
        'owner': move.owner,
        'roundScores': move.roundScores,
      };

  @override
  BasketballMove decodeMove(Map<String, dynamic> json) => BasketballMove(
        owner: json['owner'] as String,
        roundScores: intList(json['roundScores']),
      );

  /// Defensive JSON list decode: anything that isn't a list of numbers becomes
  /// an empty list, which [normaliseRounds] then pads with zeroes.
  static List<int> intList(Object? raw) => raw is List
      ? [
          for (final v in raw)
            if (v is num) v.toInt() else 0,
        ]
      : const <int>[];
}

/// One player's whole shootaround: the baskets they made in each round.
/// Raw values are trusted-but-normalised by [BasketballGame.applyMove].
class BasketballMove {
  /// The player these rounds belong to.
  final String owner;

  /// Baskets per round, one entry per [BasketballGame.roundCount]. One point
  /// per basket, so these are also the points.
  final List<int> roundScores;

  const BasketballMove({required this.owner, required this.roundScores});
}

/// Round-submission state: the two seats and each player's per-round scores.
///
/// Deliberately minimal. Only players who have finished have a [submissions]
/// entry; the first seat without one is up next.
class BasketballState {
  final List<String> playerIds;

  /// Normalised per-round scores per player. Absent until that player finishes.
  final Map<String, List<int>> submissions;

  const BasketballState({
    required this.playerIds,
    required this.submissions,
  });

  bool hasSubmitted(String playerId) => submissions.containsKey(playerId);

  /// Match total for [playerId] (0 until they submit).
  int scoreOf(String playerId) =>
      roundsOf(playerId).fold(0, (a, b) => a + b);

  /// Per-round scores for [playerId], zero-filled until they submit.
  List<int> roundsOf(String playerId) =>
      submissions[playerId] ??
      List<int>.filled(BasketballGame.roundCount, 0);

  /// First player (in turn order) who hasn't submitted, or `null` when done.
  String? get nextToPlay {
    for (final id in playerIds) {
      if (!hasSubmitted(id)) return id;
    }
    return null;
  }

  bool get isFinished => nextToPlay == null;
}
