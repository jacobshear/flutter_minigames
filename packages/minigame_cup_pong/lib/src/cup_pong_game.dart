import 'package:minigames_core/minigames_core.dart';

/// One cup in a rack: a stable [id] plus its position in **rack-local units**
/// (one unit = one cup spacing laterally, one row step in depth).
///
/// Positions live in the state rather than being derived, because a re-rack
/// *moves* cups: the same ids reform into a tighter triangle. The renderer maps
/// these units into world metres; the rules never know about metres.
class CupPongCup {
  /// Stable identity across re-racks. A throw names the cup it dropped into.
  final int id;

  /// Lateral offset from the rack centre, in cup spacings (+x = right).
  final double x;

  /// Depth from the rack apex, in row steps (+z = away from the shooter).
  final double z;

  const CupPongCup({required this.id, required this.x, required this.z});

  Map<String, dynamic> toJson() => {'id': id, 'x': x, 'z': z};

  static CupPongCup fromJson(Map<String, dynamic> j) => CupPongCup(
        id: (j['id'] as num).toInt(),
        x: (j['x'] as num).toDouble(),
        z: (j['z'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is CupPongCup && other.id == id && other.x == x && other.z == z;

  @override
  int get hashCode => Object.hash(id, x, z);

  @override
  String toString() =>
      'Cup($id @ ${x.toStringAsFixed(2)},${z.toStringAsFixed(2)})';
}

/// A Cup Pong move: the **outcome** of one thrown ball.
///
/// The thrower's device runs the ballistics; the move carries only what the
/// rules need — which opponent cup the ball dropped into (`null` = miss) — plus
/// the ball's resting spot for replay/rendering. [CupPongGame.applyMove] trusts
/// it and never re-simulates.
class CupPongThrow {
  final String owner;
  final String target;

  /// Id of the target cup the ball dropped into, or null for a miss.
  final int? hitCupId;

  /// Where the ball came to rest, in world metres (x lateral, z down-range).
  /// Carried for replay only — scoring ignores it.
  final double ballX;
  final double ballZ;

  const CupPongThrow({
    required this.owner,
    required this.target,
    required this.hitCupId,
    this.ballX = 0,
    this.ballZ = 0,
  });

  bool get isHit => hitCupId != null;
}

/// The full Cup Pong board state.
class CupPongState {
  final List<String> playerIds;
  final String currentPlayerId;

  /// Standing cups per player. A player throws at the *other* player's list.
  final Map<String, List<CupPongCup>> cups;

  /// Balls the current player has thrown this turn (0 or 1 — the second ball
  /// ends the turn and resets this).
  final int ballsThrown;

  /// Cups sunk by the current player this turn. Two makes ⇒ balls back.
  final int hitsThisTurn;

  /// True when the turn that just ended was a two-for-two and the same player
  /// keeps the balls. Presentational — drives the "Balls back!" pill.
  final bool ballsBack;

  /// True when the throw that just resolved re-racked the defender.
  final bool didRerack;

  /// Total balls thrown in the match — a monotonic tick the UI uses to tell a
  /// fresh board from a resumed one.
  final int throws;

  const CupPongState({
    required this.playerIds,
    required this.currentPlayerId,
    required this.cups,
    required this.ballsThrown,
    required this.hitsThisTurn,
    this.ballsBack = false,
    this.didRerack = false,
    this.throws = 0,
  });

  /// Cups [playerId] still has standing.
  int remainingOf(String playerId) => cups[playerId]?.length ?? 0;

  List<CupPongCup> cupsOf(String playerId) =>
      cups[playerId] ?? const <CupPongCup>[];

  bool hasCup(String playerId, int cupId) =>
      cupsOf(playerId).any((c) => c.id == cupId);

  /// The player [playerId] is throwing at.
  String opponentOf(String playerId) =>
      playerIds.firstWhere((p) => p != playerId);

  /// Which ball of the turn is up next, 1-based, for the UI.
  int get ballNumber => ballsThrown + 1;

  CupPongState copyWith({
    String? currentPlayerId,
    Map<String, List<CupPongCup>>? cups,
    int? ballsThrown,
    int? hitsThisTurn,
    bool? ballsBack,
    bool? didRerack,
    int? throws,
  }) =>
      CupPongState(
        playerIds: playerIds,
        currentPlayerId: currentPlayerId ?? this.currentPlayerId,
        cups: cups ?? this.cups,
        ballsThrown: ballsThrown ?? this.ballsThrown,
        hitsThisTurn: hitsThisTurn ?? this.hitsThisTurn,
        ballsBack: ballsBack ?? this.ballsBack,
        didRerack: didRerack ?? this.didRerack,
        throws: throws ?? this.throws,
      );
}

/// Cup Pong rules as a pure [TurnGame] — GamePigeon parity, zero rendering and
/// zero physics.
///
/// ## The trust boundary (read this first)
///
/// The shooter's device simulates the throw and sends the *result* as the move.
/// [applyMove] is a pure reducer: it removes the named cup, counts the ball,
/// applies balls-back and re-rack, flips the turn and detects the win. It never
/// re-simulates. That keeps the contract serializable and identical on both
/// sides of a transport.
///
/// ## Rules implemented
///
/// * **10 cups** per side in a 1-2-3-4 triangle, apex pointing at the shooter.
/// * **Two balls per turn.** Sink both and it's **balls back** — the same
///   player throws again with a fresh pair. This is the signature GP rule.
/// * **Re-rack** when the defender drops to [rerackAt] (6, then 3) cups: the
///   survivors reform into a tight triangle.
/// * **Win** the moment the opponent's rack is empty.
class CupPongGame extends TurnGame<CupPongState, CupPongThrow> {
  /// Cups each player starts with. 10 is the GP/regulation rack.
  final int rackSize;

  /// Balls thrown per turn before the turn passes (unless balls-back).
  static const int ballsPerTurn = 2;

  /// Remaining-cup counts that trigger a re-rack, largest first.
  static const List<int> rerackAt = [6, 3];

  const CupPongGame({this.rackSize = 10})
      : assert(rackSize > 0, 'rackSize must be positive');

  @override
  String get id => 'cup_pong';

  @override
  int get stateSchemaVersion => 2;

  // ---------------------------------------------------------------------------
  // Rack geometry (pure, unit-space)
  // ---------------------------------------------------------------------------

  /// Row sizes from the apex outward for a triangular [count]: 10 → 1,2,3,4.
  /// A non-triangular count falls back to one straight row so ids stay valid.
  static List<int> rowsFor(int count) {
    final rows = <int>[];
    var total = 0;
    var n = 1;
    while (total < count) {
      rows.add(n);
      total += n;
      n++;
    }
    return total == count ? rows : [count];
  }

  /// Positions for [count] cups in a triangle whose **apex points at the
  /// shooter** (row 0 = one cup, nearest; each deeper row one wider).
  ///
  /// Units are cup spacings laterally and row steps in depth, apex at (0, 0).
  /// A re-rack calls this with the survivor count, which is why a 6-cup rack is
  /// both narrower and shallower than a 10-cup one — that tightening is the
  /// visual tell that a re-rack happened.
  static List<({double x, double z})> rackSlots(int count) {
    final rows = rowsFor(count);
    final slots = <({double x, double z})>[];
    for (var r = 0; r < rows.length; r++) {
      final n = rows[r];
      for (var i = 0; i < n; i++) {
        slots.add((x: i - (n - 1) / 2, z: r.toDouble()));
      }
    }
    return slots;
  }

  /// Lays [ids] (in order) into the [rackSlots] for their count.
  static List<CupPongCup> rackFor(List<int> ids) {
    final slots = rackSlots(ids.length);
    return [
      for (var i = 0; i < ids.length; i++)
        CupPongCup(id: ids[i], x: slots[i].x, z: slots[i].z),
    ];
  }

  /// Reforms [cups] into a tight triangle, preserving ids in ascending order so
  /// the result is deterministic on every device.
  static List<CupPongCup> rerack(List<CupPongCup> cups) {
    final ids = [for (final c in cups) c.id]..sort();
    return rackFor(ids);
  }

  // ---------------------------------------------------------------------------
  // TurnGame
  // ---------------------------------------------------------------------------

  @override
  CupPongState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2);
    final ids = [for (var i = 0; i < rackSize; i++) i];
    return CupPongState(
      playerIds: List.of(playerIds),
      currentPlayerId: playerIds[0],
      cups: {for (final p in playerIds) p: rackFor(ids)},
      ballsThrown: 0,
      hitsThisTurn: 0,
    );
  }

  @override
  String currentPlayer(CupPongState state) => state.currentPlayerId;

  /// The player [playerId] is throwing at.
  String opponentOf(CupPongState state, String playerId) =>
      state.opponentOf(playerId);

  @override
  bool validateMove(CupPongState state, CupPongThrow move, String playerId) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    if (move.owner != playerId) return false;
    if (move.target != state.opponentOf(playerId)) return false;
    final hit = move.hitCupId;
    // A hit must name a cup that is actually still standing.
    if (hit != null && !state.hasCup(move.target, hit)) return false;
    return true;
  }

  @override
  CupPongState applyMove(CupPongState state, CupPongThrow move) {
    final cups = {
      for (final e in state.cups.entries) e.key: List<CupPongCup>.of(e.value),
    };

    final hit = move.hitCupId;
    var didRerack = false;
    if (hit != null) {
      final rack = cups[move.target]!;
      rack.removeWhere((c) => c.id == hit);
      // Re-rack the instant the defender drops to a trigger count. Counts only
      // ever fall by one per ball, so each trigger fires exactly once.
      if (rerackAt.contains(rack.length)) {
        cups[move.target] = rerack(rack);
        didRerack = true;
      }
    }

    final balls = state.ballsThrown + 1;
    final hits = state.hitsThisTurn + (hit != null ? 1 : 0);

    // Mid-turn: same player, second ball still to come.
    if (balls < ballsPerTurn) {
      return state.copyWith(
        cups: cups,
        ballsThrown: balls,
        hitsThisTurn: hits,
        ballsBack: false,
        didRerack: didRerack,
        throws: state.throws + 1,
      );
    }

    // Turn over. Two-for-two keeps the balls with the same player.
    final ballsBack = hits >= ballsPerTurn;
    return state.copyWith(
      currentPlayerId: ballsBack ? move.owner : move.target,
      cups: cups,
      ballsThrown: 0,
      hitsThisTurn: 0,
      ballsBack: ballsBack,
      didRerack: didRerack,
      throws: state.throws + 1,
    );
  }

  @override
  GameOutcome? outcome(CupPongState state) {
    final a = state.playerIds[0];
    final b = state.playerIds[1];
    final aCleared = state.remainingOf(a) == 0;
    final bCleared = state.remainingOf(b) == 0;
    // You win by clearing your OPPONENT's rack.
    if (aCleared && bCleared) return const GameOutcome.draw();
    if (bCleared) return GameOutcome.win(a);
    if (aCleared) return GameOutcome.win(b);
    return null;
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> encodeState(CupPongState state) => {
        'playerIds': state.playerIds,
        'currentPlayerId': state.currentPlayerId,
        'cups': {
          for (final e in state.cups.entries)
            e.key: [for (final c in e.value) c.toJson()],
        },
        'ballsThrown': state.ballsThrown,
        'hitsThisTurn': state.hitsThisTurn,
        'ballsBack': state.ballsBack,
        'didRerack': state.didRerack,
        'throws': state.throws,
      };

  @override
  CupPongState decodeState(Map<String, dynamic> json, int version) =>
      CupPongState(
        playerIds: [for (final p in json['playerIds'] as List) p as String],
        currentPlayerId: json['currentPlayerId'] as String,
        cups: {
          for (final e in (json['cups'] as Map).entries)
            e.key as String: [
              for (final c in e.value as List)
                CupPongCup.fromJson((c as Map).cast<String, dynamic>()),
            ],
        },
        ballsThrown: (json['ballsThrown'] as num?)?.toInt() ?? 0,
        hitsThisTurn: (json['hitsThisTurn'] as num?)?.toInt() ?? 0,
        ballsBack: json['ballsBack'] as bool? ?? false,
        didRerack: json['didRerack'] as bool? ?? false,
        throws: (json['throws'] as num?)?.toInt() ?? 0,
      );

  @override
  Map<String, dynamic> encodeMove(CupPongThrow move) => {
        'owner': move.owner,
        'target': move.target,
        'hitCupId': move.hitCupId,
        'ballX': move.ballX,
        'ballZ': move.ballZ,
      };

  @override
  CupPongThrow decodeMove(Map<String, dynamic> json) => CupPongThrow(
        owner: json['owner'] as String,
        target: json['target'] as String,
        hitCupId: (json['hitCupId'] as num?)?.toInt(),
        ballX: (json['ballX'] as num?)?.toDouble() ?? 0,
        ballZ: (json['ballZ'] as num?)?.toDouble() ?? 0,
      );
}
