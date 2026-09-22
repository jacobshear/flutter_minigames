/// Lifecycle status of a [Match].
enum MatchStatus { open, ended }

/// A single game session between players — the unit a [transport] persists and
/// synchronizes. The game-specific state lives inside [state] as an opaque,
/// already-encoded JSON map (see `TurnGame.encodeState`); everything else here
/// is transport-level metadata the framework manages.
class Match {
  /// Unique match id (also the transport key, e.g. an RTDB node path).
  final String id;

  /// Which game this is — matches `TurnGame.id`.
  final String gameId;

  /// Players in turn order.
  final List<String> playerIds;

  /// Whose turn it is right now.
  final String currentPlayerId;

  /// Open (in progress) or ended.
  final MatchStatus status;

  /// Number of moves applied so far. Doubles as an optimistic-concurrency
  /// guard: a transport can reject a write whose turnCount didn't advance.
  final int turnCount;

  /// The encoded game state (`TurnGame.encodeState` output).
  final Map<String, dynamic> state;

  /// Schema version of [state] (`TurnGame.stateSchemaVersion`).
  final int schemaVersion;

  /// Winner id once [status] is ended and it wasn't a draw.
  final String? winnerId;

  /// Whether the ended match was a draw.
  final bool isDraw;

  /// The encoded state as it stood BEFORE the most recent turn, or `null` on
  /// a fresh match. Written by [MatchController.submitMove] alongside [state]
  /// so a client that opens the match cold can replay the last turn
  /// (see `MatchController.connect(replayLastTurn:)`) — the board is shown
  /// this snapshot first, then [state] lands through the normal stream path
  /// and animates exactly as it would have live.
  ///
  /// A "turn" here is the whole run of consecutive sub-moves one player made
  /// before the seat passed (a checkers multi-jump, a mancala extra turn,
  /// a dots-and-boxes box chain), for games that opt in through
  /// `TurnGame.replayStepDelay`. For those, this is the board before the
  /// FIRST sub-move and [turnSteps] holds the snapshots in between. Games
  /// that don't opt in record each sub-move on its own.
  final Map<String, dynamic>? prevState;

  /// The encoded states after each sub-move of the most recent turn except
  /// the last (which is [state]), oldest first — or `null` when the turn was
  /// a single sub-move. Replaying [prevState] → each of these → [state] in
  /// order shows the whole turn. See [prevState].
  final List<Map<String, dynamic>>? turnSteps;

  /// Who submitted the most recent turn, or `null` on a fresh match. Paired
  /// with [prevState]: a replay only makes sense for a turn someone ELSE
  /// took, and in games with extra turns [currentPlayerId] alone can't say
  /// who moved last.
  final String? lastMoverId;

  const Match({
    required this.id,
    required this.gameId,
    required this.playerIds,
    required this.currentPlayerId,
    required this.status,
    required this.turnCount,
    required this.state,
    required this.schemaVersion,
    this.winnerId,
    this.isDraw = false,
    this.prevState,
    this.turnSteps,
    this.lastMoverId,
  });

  bool get isOpen => status == MatchStatus.open;
  bool get isEnded => status == MatchStatus.ended;

  Match copyWith({
    String? currentPlayerId,
    MatchStatus? status,
    int? turnCount,
    Map<String, dynamic>? state,
    String? winnerId,
    bool? isDraw,
    Map<String, dynamic>? prevState,
    List<Map<String, dynamic>>? turnSteps,
    String? lastMoverId,
  }) {
    return Match(
      id: id,
      gameId: gameId,
      playerIds: playerIds,
      currentPlayerId: currentPlayerId ?? this.currentPlayerId,
      status: status ?? this.status,
      turnCount: turnCount ?? this.turnCount,
      state: state ?? this.state,
      schemaVersion: schemaVersion,
      winnerId: winnerId ?? this.winnerId,
      isDraw: isDraw ?? this.isDraw,
      prevState: prevState ?? this.prevState,
      turnSteps: turnSteps ?? this.turnSteps,
      lastMoverId: lastMoverId ?? this.lastMoverId,
    );
  }

  /// The match as it stood before the most recent turn, or `null` when no
  /// turn has been recorded with a [prevState]. Metadata is rolled back too
  /// (turn count, mover, open status) so a consumer holding this snapshot
  /// sees a coherent "their move is pending" match, not the current
  /// outcome with an older board. For a multi-step turn this is the board
  /// before the first sub-move; see [replayFrames] for the rest.
  Match? get previousTurn {
    final prev = prevState;
    final mover = lastMoverId;
    if (prev == null || mover == null || turnCount == 0) return null;
    final steps = turnSteps?.length ?? 0;
    return _frame(prev, mover, turnCount - 1 - steps);
  }

  /// Every snapshot of the most recent turn in order — [previousTurn], then
  /// one match per entry of [turnSteps], then this match itself. Emitting
  /// these one after another replays the whole turn; a single-step turn
  /// yields `[previousTurn, this]`. Empty when there is nothing to replay.
  List<Match> get replayFrames {
    final first = previousTurn;
    if (first == null) return const [];
    final mover = lastMoverId!;
    final steps = turnSteps ?? const [];
    return [
      first,
      for (var i = 0; i < steps.length; i++)
        _frame(steps[i], mover, first.turnCount + 1 + i),
      this,
    ];
  }

  Match _frame(Map<String, dynamic> snapshot, String mover, int turn) => Match(
        id: id,
        gameId: gameId,
        playerIds: playerIds,
        currentPlayerId: mover,
        status: MatchStatus.open,
        turnCount: turn < 0 ? 0 : turn,
        state: snapshot,
        schemaVersion: schemaVersion,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'gameId': gameId,
        'playerIds': playerIds,
        'currentPlayerId': currentPlayerId,
        'status': status.name,
        'turnCount': turnCount,
        'state': state,
        'schemaVersion': schemaVersion,
        'winnerId': winnerId,
        'isDraw': isDraw,
        'prevState': prevState,
        'turnSteps': turnSteps,
        'lastMoverId': lastMoverId,
      };

  factory Match.fromJson(Map<String, dynamic> json) => Match(
        id: json['id'] as String,
        gameId: json['gameId'] as String,
        playerIds: (json['playerIds'] as List).map((e) => e as String).toList(),
        currentPlayerId: json['currentPlayerId'] as String,
        status: MatchStatus.values.byName(json['status'] as String),
        turnCount: json['turnCount'] as int,
        state: Map<String, dynamic>.from(json['state'] as Map),
        schemaVersion: json['schemaVersion'] as int,
        winnerId: json['winnerId'] as String?,
        isDraw: json['isDraw'] as bool? ?? false,
        prevState: json['prevState'] == null
            ? null
            : Map<String, dynamic>.from(json['prevState'] as Map),
        turnSteps: json['turnSteps'] == null
            ? null
            : (json['turnSteps'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
        lastMoverId: json['lastMoverId'] as String?,
      );
}
