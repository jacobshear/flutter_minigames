import 'package:flutter_minigames/src/core/core.dart';

/// Classic Reversi / Othello on an 8×8 board.
///
/// Place a disc so it brackets one or more opponent discs in a straight line
/// (8 directions); those discs flip. If the current player has no legal move
/// their turn is skipped. Game ends when neither can move — higher disc count
/// wins (draw if tied).
class ReversiState {
  static const int size = 8;
  static const int cellCount = size * size; // 64

  /// Row-major cells: `null` empty, otherwise player id.
  final List<String?> cells;
  final List<String> playerIds;

  /// Explicit turn — required because passes skip a player.
  final String currentPlayerId;

  /// Last placed cell index, if any (for UI).
  final int? lastCell;

  /// Cells flipped by the last move (for UI), not including [lastCell].
  final List<int> lastFlipped;

  /// True when the previous apply was a forced pass (no legal moves).
  final bool lastWasPass;

  const ReversiState({
    required this.cells,
    required this.playerIds,
    required this.currentPlayerId,
    this.lastCell,
    this.lastFlipped = const [],
    this.lastWasPass = false,
  });

  String get darkId => playerIds[0];
  String get lightId => playerIds[1];

  int scoreFor(String playerId) => cells.where((c) => c == playerId).length;

  String opponentOf(String playerId) => playerId == darkId ? lightId : darkId;

  String? cellAt(int row, int col) {
    if (row < 0 || row >= size || col < 0 || col >= size) return null;
    return cells[row * size + col];
  }

  static int index(int row, int col) => row * size + col;
}

class ReversiMove {
  /// Cell 0..63, or [pass] for an automatic/no-legal-move turn.
  final int cell;
  final bool isPass;

  const ReversiMove(this.cell) : isPass = false;
  const ReversiMove.pass()
      : cell = -1,
        isPass = true;
}

class ReversiGame extends TurnGame<ReversiState, ReversiMove> {
  const ReversiGame();

  static const int size = ReversiState.size;

  static const _dirs = <(int, int)>[
    (-1, -1),
    (-1, 0),
    (-1, 1),
    (0, -1),
    (0, 1),
    (1, -1),
    (1, 0),
    (1, 1),
  ];

  @override
  String get id => 'reversi';

  @override
  ReversiState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2);
    final dark = playerIds[0];
    final light = playerIds[1];
    final cells = List<String?>.filled(ReversiState.cellCount, null);
    // Standard opening: light NW-SE, dark NE-SW in the center 2×2.
    cells[ReversiState.index(3, 3)] = light;
    cells[ReversiState.index(3, 4)] = dark;
    cells[ReversiState.index(4, 3)] = dark;
    cells[ReversiState.index(4, 4)] = light;
    return ReversiState(
      cells: cells,
      playerIds: List.of(playerIds),
      currentPlayerId: dark,
    );
  }

  @override
  String currentPlayer(ReversiState state) => state.currentPlayerId;

  /// All cells the player can legally place on.
  List<int> legalMoves(ReversiState state, String playerId) {
    final out = <int>[];
    for (var i = 0; i < ReversiState.cellCount; i++) {
      if (state.cells[i] != null) continue;
      if (_flipsFor(state, i, playerId).isNotEmpty) out.add(i);
    }
    return out;
  }

  List<int> _flipsFor(ReversiState state, int cell, String playerId) {
    final row = cell ~/ size;
    final col = cell % size;
    if (state.cells[cell] != null) return const [];
    final opp = state.opponentOf(playerId);
    final flips = <int>[];
    for (final (dr, dc) in _dirs) {
      final line = <int>[];
      var r = row + dr;
      var c = col + dc;
      while (r >= 0 && r < size && c >= 0 && c < size) {
        final id = state.cells[ReversiState.index(r, c)];
        if (id == null) break;
        if (id == opp) {
          line.add(ReversiState.index(r, c));
          r += dr;
          c += dc;
          continue;
        }
        if (id == playerId && line.isNotEmpty) {
          flips.addAll(line);
        }
        break;
      }
    }
    return flips;
  }

  @override
  bool validateMove(ReversiState state, ReversiMove move, String playerId) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    final legal = legalMoves(state, playerId);
    if (move.isPass) {
      // Pass is only legal when there are no moves (auto-pass).
      return legal.isEmpty;
    }
    if (move.cell < 0 || move.cell >= ReversiState.cellCount) return false;
    return legal.contains(move.cell);
  }

  @override
  ReversiState applyMove(ReversiState state, ReversiMove move) {
    final player = state.currentPlayerId;
    final opp = state.opponentOf(player);

    if (move.isPass) {
      // Hand turn to opponent (who must have a move, or game ends on next check).
      return ReversiState(
        cells: state.cells,
        playerIds: state.playerIds,
        currentPlayerId: opp,
        lastCell: null,
        lastFlipped: const [],
        lastWasPass: true,
      );
    }

    final flips = _flipsFor(state, move.cell, player);
    final next = List<String?>.of(state.cells);
    next[move.cell] = player;
    for (final f in flips) {
      next[f] = player;
    }

    // Next player: opponent if they can move, else player if they can, else opp
    // (terminal — outcome will catch neither movable).
    final oppState = ReversiState(
      cells: next,
      playerIds: state.playerIds,
      currentPlayerId: opp,
    );
    final nextPlayer = legalMoves(oppState, opp).isNotEmpty
        ? opp
        : (legalMoves(
            ReversiState(
              cells: next,
              playerIds: state.playerIds,
              currentPlayerId: player,
            ),
            player,
          ).isNotEmpty
            ? player
            : opp);

    return ReversiState(
      cells: next,
      playerIds: state.playerIds,
      currentPlayerId: nextPlayer,
      lastCell: move.cell,
      lastFlipped: flips,
      lastWasPass: false,
    );
  }

  @override
  GameOutcome? outcome(ReversiState state) {
    final a = state.darkId;
    final b = state.lightId;
    // Terminal only when neither player has a legal placement.
    if (legalMoves(state, a).isNotEmpty || legalMoves(state, b).isNotEmpty) {
      return null;
    }
    final sa = state.scoreFor(a);
    final sb = state.scoreFor(b);
    if (sa > sb) return GameOutcome.win(a);
    if (sb > sa) return GameOutcome.win(b);
    return const GameOutcome.draw();
  }

  /// Whether [playerId] must pass (no legal placement).
  bool mustPass(ReversiState state, String playerId) =>
      legalMoves(state, playerId).isEmpty &&
      legalMoves(state, state.opponentOf(playerId)).isNotEmpty;

  @override
  Map<String, dynamic> encodeState(ReversiState state) => {
        'cells': state.cells,
        'playerIds': state.playerIds,
        'currentPlayerId': state.currentPlayerId,
        if (state.lastCell != null) 'lastCell': state.lastCell,
        'lastFlipped': state.lastFlipped,
        'lastWasPass': state.lastWasPass,
      };

  @override
  ReversiState decodeState(Map<String, dynamic> json, int version) =>
      ReversiState(
        cells: (json['cells'] as List).map((e) => e as String?).toList(),
        playerIds: (json['playerIds'] as List).map((e) => e as String).toList(),
        currentPlayerId: json['currentPlayerId'] as String,
        lastCell: json['lastCell'] as int?,
        lastFlipped: (json['lastFlipped'] as List? ?? const [])
            .map((e) => e as int)
            .toList(),
        lastWasPass: json['lastWasPass'] as bool? ?? false,
      );

  @override
  Map<String, dynamic> encodeMove(ReversiMove move) => {
        'cell': move.cell,
        'isPass': move.isPass,
      };

  @override
  ReversiMove decodeMove(Map<String, dynamic> json) {
    if (json['isPass'] == true) return const ReversiMove.pass();
    return ReversiMove(json['cell'] as int);
  }
}
