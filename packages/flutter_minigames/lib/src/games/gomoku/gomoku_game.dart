import 'package:flutter_minigames/src/core/core.dart';

/// Freestyle Gomoku (five in a row) on a square board (default 15×15).
///
/// Players alternate placing stones on empty intersections; the first to make
/// an unbroken row of five or more of their own stones (horizontal, vertical,
/// or diagonal) wins. Board full with no five is a draw. Black
/// (`playerIds[0]`) moves first. No passes, no captures.
class GomokuState {
  /// Row-major intersections: `null` empty, otherwise player id.
  final List<String?> cells;
  final List<String> playerIds;

  /// Board side length (intersections per row).
  final int size;

  /// Last placed cell index, if any (for UI).
  final int? lastCell;

  const GomokuState({
    required this.cells,
    required this.playerIds,
    required this.size,
    this.lastCell,
  });

  String get blackId => playerIds[0];
  String get whiteId => playerIds[1];

  int get stoneCount => cells.where((c) => c != null).length;

  /// Turn is derived from parity: black placed first, so equal counts means
  /// black to move.
  String get currentPlayerId {
    final black = cells.where((c) => c == blackId).length;
    final white = cells.where((c) => c == whiteId).length;
    return black == white ? blackId : whiteId;
  }

  String? cellAt(int row, int col) {
    if (row < 0 || row >= size || col < 0 || col >= size) return null;
    return cells[row * size + col];
  }

  int index(int row, int col) => row * size + col;
}

class GomokuMove {
  /// Intersection index `row * size + col`.
  final int cell;

  const GomokuMove(this.cell);
}

class GomokuGame extends TurnGame<GomokuState, GomokuMove> {
  /// Intersections per side. 15 is the classic gomoku board.
  final int boardSize;

  const GomokuGame({this.boardSize = 15});

  /// Row/col steps for the four line orientations (the reverse directions are
  /// covered by scanning both ways from a stone).
  static const _dirs = <(int, int)>[(0, 1), (1, 0), (1, 1), (1, -1)];

  @override
  String get id => 'gomoku';

  @override
  GomokuState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2);
    return GomokuState(
      cells: List<String?>.filled(boardSize * boardSize, null),
      playerIds: List.of(playerIds),
      size: boardSize,
    );
  }

  @override
  String currentPlayer(GomokuState state) => state.currentPlayerId;

  @override
  bool validateMove(GomokuState state, GomokuMove move, String playerId) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    if (move.cell < 0 || move.cell >= state.cells.length) return false;
    return state.cells[move.cell] == null;
  }

  @override
  GomokuState applyMove(GomokuState state, GomokuMove move) {
    final next = List<String?>.of(state.cells);
    next[move.cell] = state.currentPlayerId;
    return GomokuState(
      cells: next,
      playerIds: state.playerIds,
      size: state.size,
      lastCell: move.cell,
    );
  }

  /// The unbroken run of 5+ stones through [cell], or empty if none.
  List<int> _runThrough(GomokuState state, int cell) {
    final owner = state.cells[cell];
    if (owner == null) return const [];
    final n = state.size;
    final row = cell ~/ n;
    final col = cell % n;
    for (final (dr, dc) in _dirs) {
      final run = <int>[cell];
      for (final sign in const [1, -1]) {
        var r = row + dr * sign;
        var c = col + dc * sign;
        while (state.cellAt(r, c) == owner) {
          run.add(state.index(r, c));
          r += dr * sign;
          c += dc * sign;
        }
      }
      if (run.length >= 5) {
        run.sort();
        return run;
      }
    }
    return const [];
  }

  /// The winning run of 5+ cells, or empty while the game is live/drawn.
  /// Scans the whole board so it works on any decoded state.
  List<int> winningLine(GomokuState state) {
    // The last stone placed is the only one that can have completed a line.
    final last = state.lastCell;
    if (last != null) return _runThrough(state, last);
    for (var i = 0; i < state.cells.length; i++) {
      final run = _runThrough(state, i);
      if (run.isNotEmpty) return run;
    }
    return const [];
  }

  @override
  GameOutcome? outcome(GomokuState state) {
    final line = winningLine(state);
    if (line.isNotEmpty) return GameOutcome.win(state.cells[line.first]!);
    if (state.stoneCount == state.cells.length) return const GameOutcome.draw();
    return null;
  }

  @override
  Map<String, dynamic> encodeState(GomokuState state) => {
        'cells': state.cells,
        'playerIds': state.playerIds,
        'size': state.size,
        if (state.lastCell != null) 'lastCell': state.lastCell,
      };

  @override
  GomokuState decodeState(Map<String, dynamic> json, int version) =>
      GomokuState(
        cells: (json['cells'] as List).map((e) => e as String?).toList(),
        playerIds: (json['playerIds'] as List).map((e) => e as String).toList(),
        size: json['size'] as int,
        lastCell: json['lastCell'] as int?,
      );

  @override
  Map<String, dynamic> encodeMove(GomokuMove move) => {'cell': move.cell};

  @override
  GomokuMove decodeMove(Map<String, dynamic> json) =>
      GomokuMove(json['cell'] as int);
}
