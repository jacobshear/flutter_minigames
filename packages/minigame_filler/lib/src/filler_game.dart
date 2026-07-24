import 'package:minigames_core/minigames_core.dart';

/// Filler (GamePigeon-style color flood) on an 8×7 grid with 6 colors.
///
/// Each player owns a growing monochromatic blob: Player 1 (`playerIds[0]`)
/// starts at the bottom-left cell, Player 2 (`playerIds[1]`) at the top-right.
/// On your turn you pick one of the 6 colors — never your own current color
/// and never the opponent's — your whole territory repaints to that color and
/// absorbs every orthogonally-connected unowned cell of that color
/// (cascading flood fill). Score = cells owned. The game ends as soon as one
/// player holds a majority (29+ of 56) or when every cell is owned;
/// a full 28–28 board is a draw.
///
/// Board generation (seeded, deterministic): no two orthogonally-adjacent
/// cells share a color anywhere on the board — every blob starts as a single
/// cell (this is the classic Filler constraint and covers the GP requirements:
/// start corners differ from all their neighbors, so turn one always has real
/// choices). Additionally the two start corners are forced to differ from
/// each other so both players begin with distinct colors.
class FillerState {
  static const int cols = 8;
  static const int rows = 7;
  static const int cellCount = cols * rows; // 56
  static const int colorCount = 6;

  /// Majority threshold: opponent can no longer catch up.
  static const int majority = cellCount ~/ 2 + 1; // 29

  /// Player 1's start cell (bottom-left).
  static const int p1Start = (rows - 1) * cols; // 48

  /// Player 2's start cell (top-right).
  static const int p2Start = cols - 1; // 7

  /// Color index (0..5) per cell, row-major from the top-left.
  final List<int> cells;

  /// Owner per cell: -1 unowned, else player index (0 or 1).
  final List<int> owners;

  final List<String> playerIds;

  /// Index of the player to move (0 or 1).
  final int turnIndex;

  const FillerState({
    required this.cells,
    required this.owners,
    required this.playerIds,
    required this.turnIndex,
  });

  String get currentPlayerId => playerIds[turnIndex];

  static int indexOf(int row, int col) => row * cols + col;
  static int rowOf(int index) => index ~/ cols;
  static int colOf(int index) => index % cols;

  /// Orthogonal neighbors of [index] (2–4 cells).
  static List<int> neighborsOf(int index) {
    final r = rowOf(index);
    final c = colOf(index);
    return [
      if (r > 0) index - cols,
      if (r < rows - 1) index + cols,
      if (c > 0) index - 1,
      if (c < cols - 1) index + 1,
    ];
  }

  /// Cells owned by player [p] (0 or 1).
  int scoreOfIndex(int p) {
    var n = 0;
    for (final o in owners) {
      if (o == p) n++;
    }
    return n;
  }

  int scoreOf(String playerId) => scoreOfIndex(playerIds.indexOf(playerId));

  /// Current territory color of player [p]. The start corner is always part
  /// of a player's territory, and a territory is monochromatic, so the corner
  /// cell's color is the territory color.
  int colorOfIndex(int p) => cells[p == 0 ? p1Start : p2Start];

  int get unownedCount {
    var n = 0;
    for (final o in owners) {
      if (o == -1) n++;
    }
    return n;
  }
}

class FillerMove {
  /// Chosen color index (0..5).
  final int color;

  const FillerMove(this.color);
}

class FillerGame extends TurnGame<FillerState, FillerMove> {
  const FillerGame();

  @override
  String get id => 'filler';

  // Deterministic 32-bit LCG so both clients build the identical board from
  // the seed on every platform (dart:math Random is not guaranteed stable).
  static int _next(int s) => (s * 1664525 + 1013904223) & 0x7fffffff;

  @override
  FillerState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2);
    var s = (seed ^ 0x2545F491) & 0x7fffffff;
    final cells = List<int>.filled(FillerState.cellCount, 0);

    // Greedy row-major fill: each cell avoids its left and upper neighbor's
    // color, guaranteeing no orthogonally-adjacent same-color pair.
    for (var i = 0; i < FillerState.cellCount; i++) {
      final banned = <int>{};
      if (FillerState.colOf(i) > 0) banned.add(cells[i - 1]);
      if (FillerState.rowOf(i) > 0) banned.add(cells[i - FillerState.cols]);
      final choices = [
        for (var c = 0; c < FillerState.colorCount; c++)
          if (!banned.contains(c)) c,
      ];
      s = _next(s);
      cells[i] = choices[(s >> 13) % choices.length];
    }

    // Force distinct start-corner colors (corners aren't adjacent, so the
    // greedy pass can't guarantee it). Re-pick the top-right corner while
    // still avoiding its own neighbors.
    if (cells[FillerState.p1Start] == cells[FillerState.p2Start]) {
      final banned = <int>{
        cells[FillerState.p1Start],
        for (final n in FillerState.neighborsOf(FillerState.p2Start)) cells[n],
      };
      final choices = [
        for (var c = 0; c < FillerState.colorCount; c++)
          if (!banned.contains(c)) c,
      ];
      s = _next(s);
      cells[FillerState.p2Start] = choices[(s >> 13) % choices.length];
    }

    final owners = List<int>.filled(FillerState.cellCount, -1);
    owners[FillerState.p1Start] = 0;
    owners[FillerState.p2Start] = 1;

    return FillerState(
      cells: cells,
      owners: owners,
      playerIds: List.of(playerIds),
      turnIndex: 0,
    );
  }

  @override
  String currentPlayer(FillerState state) => state.currentPlayerId;

  @override
  bool validateMove(FillerState state, FillerMove move, String playerId) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    final c = move.color;
    if (c < 0 || c >= FillerState.colorCount) return false;
    if (c == state.colorOfIndex(state.turnIndex)) return false;
    if (c == state.colorOfIndex(1 - state.turnIndex)) return false;
    return true;
  }

  @override
  FillerState applyMove(FillerState state, FillerMove move) {
    final p = state.turnIndex;
    final c = move.color;
    final cells = List<int>.of(state.cells);
    final owners = List<int>.of(state.owners);

    // Repaint the whole territory, then flood-absorb every unowned cell of
    // the chosen color orthogonally connected to it (cascading).
    final queue = <int>[];
    for (var i = 0; i < FillerState.cellCount; i++) {
      if (owners[i] == p) {
        cells[i] = c;
        queue.add(i);
      }
    }
    while (queue.isNotEmpty) {
      final cell = queue.removeLast();
      for (final n in FillerState.neighborsOf(cell)) {
        if (owners[n] == -1 && cells[n] == c) {
          owners[n] = p;
          queue.add(n);
        }
      }
    }

    return FillerState(
      cells: cells,
      owners: owners,
      playerIds: state.playerIds,
      turnIndex: 1 - p,
    );
  }

  @override
  GameOutcome? outcome(FillerState state) {
    final a = state.scoreOfIndex(0);
    final b = state.scoreOfIndex(1);
    // Majority is decisive — the opponent can never catch up, so end early
    // (GP declares the winner as soon as someone crosses half the board).
    if (a >= FillerState.majority) return GameOutcome.win(state.playerIds[0]);
    if (b >= FillerState.majority) return GameOutcome.win(state.playerIds[1]);
    if (a + b == FillerState.cellCount) {
      if (a > b) return GameOutcome.win(state.playerIds[0]);
      if (b > a) return GameOutcome.win(state.playerIds[1]);
      return const GameOutcome.draw();
    }
    return null;
  }

  @override
  Map<String, dynamic> encodeState(FillerState state) => {
        'cells': state.cells,
        'owners': state.owners,
        'playerIds': state.playerIds,
        'turn': state.turnIndex,
      };

  @override
  FillerState decodeState(Map<String, dynamic> json, int version) =>
      FillerState(
        cells: (json['cells'] as List).map((e) => e as int).toList(),
        owners: (json['owners'] as List).map((e) => e as int).toList(),
        playerIds:
            (json['playerIds'] as List).map((e) => e as String).toList(),
        turnIndex: json['turn'] as int,
      );

  @override
  Map<String, dynamic> encodeMove(FillerMove move) => {'color': move.color};

  @override
  FillerMove decodeMove(Map<String, dynamic> json) =>
      FillerMove(json['color'] as int);
}
