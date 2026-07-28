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
    );
  }

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
      };

  factory Match.fromJson(Map<String, dynamic> json) => Match(
        id: json['id'] as String,
        gameId: json['gameId'] as String,
        playerIds:
            (json['playerIds'] as List).map((e) => e as String).toList(),
        currentPlayerId: json['currentPlayerId'] as String,
        status: MatchStatus.values.byName(json['status'] as String),
        turnCount: json['turnCount'] as int,
        state: Map<String, dynamic>.from(json['state'] as Map),
        schemaVersion: json['schemaVersion'] as int,
        winnerId: json['winnerId'] as String?,
        isDraw: json['isDraw'] as bool? ?? false,
      );
}
