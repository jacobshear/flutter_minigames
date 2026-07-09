import 'package:minigames_core/minigames_core.dart';

/// Classic Connect Four: 7 columns × 6 rows. Gravity drops a disc into the
/// lowest empty cell of a chosen column. Four in a row (any direction) wins.
class ConnectFourState {
  static const int cols = 7;
  static const int rows = 6;
  static const int cellCount = cols * rows; // 42

  /// Row-major cells, length 42. **Row 0 is the bottom** (gravity sits here).
  /// Index = `row * cols + col`. `null` = empty, otherwise a player id.
  final List<String?> cells;

  /// Players in turn order: index 0 moves first (typically red / primary).
  final List<String> playerIds;

  /// Column of the most recent drop, or `null` at the start of a match.
  /// The UI uses this to stage the gravity animation.
  final int? lastCol;

  /// Row of the most recent drop (bottom = 0), or `null` before any move.
  final int? lastRow;

  const ConnectFourState({
    required this.cells,
    required this.playerIds,
    this.lastCol,
    this.lastRow,
  });

  int get filledCount => cells.where((c) => c != null).length;

  String get currentPlayerId => playerIds[filledCount % 2];

  bool get isPlayer0Turn => filledCount % 2 == 0;

  String? cellAt(int row, int col) {
    if (row < 0 || row >= rows || col < 0 || col >= cols) return null;
    return cells[row * cols + col];
  }

  /// Lowest empty row in [col], or `null` if the column is full.
  int? dropRow(int col) {
    if (col < 0 || col >= cols) return null;
    for (var row = 0; row < rows; row++) {
      if (cells[row * cols + col] == null) return row;
    }
    return null;
  }

  bool get isColumnOpen => List.generate(cols, dropRow).any((r) => r != null);

  ConnectFourState drop(int col, String playerId) {
    final row = dropRow(col);
    if (row == null) {
      throw StateError('Column $col is full');
    }
    final next = List<String?>.of(cells);
    next[row * cols + col] = playerId;
    return ConnectFourState(
      cells: next,
      playerIds: playerIds,
      lastCol: col,
      lastRow: row,
    );
  }
}

/// A move: the column (0..6) the player drops into.
class ConnectFourMove {
  final int column;
  const ConnectFourMove(this.column);
}

/// Four-in-a-row as a [TurnGame]. Pure logic — no Flutter import.
class ConnectFourGame extends TurnGame<ConnectFourState, ConnectFourMove> {
  const ConnectFourGame();

  static const int cols = ConnectFourState.cols;
  static const int rows = ConnectFourState.rows;

  /// Directions for win scan: right, up, up-right, up-left.
  static const List<(int dr, int dc)> _dirs = [
    (0, 1),
    (1, 0),
    (1, 1),
    (1, -1),
  ];

  @override
  String get id => 'connect_four';

  @override
  ConnectFourState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2, 'connect four is exactly 2 players');
    return ConnectFourState(
      cells: List<String?>.filled(ConnectFourState.cellCount, null),
      playerIds: List.of(playerIds),
    );
  }

  @override
  String currentPlayer(ConnectFourState state) => state.currentPlayerId;

  @override
  bool validateMove(
    ConnectFourState state,
    ConnectFourMove move,
    String playerId,
  ) {
    if (outcome(state) != null) return false;
    if (move.column < 0 || move.column >= cols) return false;
    if (state.dropRow(move.column) == null) return false;
    return state.currentPlayerId == playerId;
  }

  @override
  ConnectFourState applyMove(ConnectFourState state, ConnectFourMove move) =>
      state.drop(move.column, state.currentPlayerId);

  @override
  GameOutcome? outcome(ConnectFourState state) {
    final line = winningLine(state);
    if (line != null) {
      final id = state.cells[line.first];
      if (id != null) return GameOutcome.win(id);
    }
    if (state.cells.every((c) => c != null)) return const GameOutcome.draw();
    return null;
  }

  /// The four cell indices of a winning line, or `null` if none.
  /// Prefer a line that includes the last drop when present (UI highlights it).
  List<int>? winningLine(ConnectFourState state) {
    List<int>? found;
    final last =
        state.lastRow != null && state.lastCol != null
            ? state.lastRow! * cols + state.lastCol!
            : null;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final start = row * cols + col;
        final id = state.cells[start];
        if (id == null) continue;
        for (final (dr, dc) in _dirs) {
          final line = <int>[start];
          for (var step = 1; step < 4; step++) {
            final r = row + dr * step;
            final c = col + dc * step;
            if (r < 0 || r >= rows || c < 0 || c >= cols) break;
            if (state.cells[r * cols + c] != id) break;
            line.add(r * cols + c);
          }
          if (line.length == 4) {
            if (last != null && line.contains(last)) return line;
            found ??= line;
          }
        }
      }
    }
    return found;
  }

  @override
  Map<String, dynamic> encodeState(ConnectFourState state) => {
        'cells': state.cells,
        'playerIds': state.playerIds,
        if (state.lastCol != null) 'lastCol': state.lastCol,
        if (state.lastRow != null) 'lastRow': state.lastRow,
      };

  @override
  ConnectFourState decodeState(Map<String, dynamic> json, int version) =>
      ConnectFourState(
        cells: (json['cells'] as List).map((e) => e as String?).toList(),
        playerIds:
            (json['playerIds'] as List).map((e) => e as String).toList(),
        lastCol: json['lastCol'] as int?,
        lastRow: json['lastRow'] as int?,
      );

  @override
  Map<String, dynamic> encodeMove(ConnectFourMove move) =>
      {'column': move.column};

  @override
  ConnectFourMove decodeMove(Map<String, dynamic> json) =>
      ConnectFourMove(json['column'] as int);
}
