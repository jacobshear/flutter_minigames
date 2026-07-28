import 'package:flutter_minigames/src/core/core.dart';

/// Dots and Boxes on an [n]×[n] grid of boxes ([n]+1 dots per side).
///
/// Claiming an edge that completes one or more boxes awards those boxes to the
/// mover **and keeps their turn**. Otherwise play passes. Game ends when every
/// box is claimed; higher box count wins (draw if tied).
class DotsAndBoxesState {
  /// Number of boxes along one side (default 3 → 4×4 dots, 24 edges, 9 boxes).
  final int n;

  /// Horizontal edges, row-major: row `r` (0..n), col `c` (0..n-1).
  /// Index = `r * n + c`. `null` = free, else claiming player id.
  final List<String?> hEdges;

  /// Vertical edges, row-major: row `r` (0..n-1), col `c` (0..n).
  /// Index = `r * (n + 1) + c`.
  final List<String?> vEdges;

  /// Box owners, row-major: row `r` (0..n-1), col `c` (0..n-1).
  /// Index = `r * n + c`.
  final List<String?> boxes;

  final List<String> playerIds;

  /// Whose turn it is. Stored explicitly — extra turns break simple alternation.
  final String currentPlayerId;

  /// Last claimed edge for UI animation (`true` = horizontal).
  final bool? lastWasHorizontal;
  final int? lastEdgeIndex;

  /// Box indices completed by the last move (for pop animations).
  final List<int> lastCompletedBoxes;

  /// Whether the last move awarded an extra turn.
  final bool lastKeptTurn;

  const DotsAndBoxesState({
    required this.n,
    required this.hEdges,
    required this.vEdges,
    required this.boxes,
    required this.playerIds,
    required this.currentPlayerId,
    this.lastWasHorizontal,
    this.lastEdgeIndex,
    this.lastCompletedBoxes = const [],
    this.lastKeptTurn = false,
  });

  int get hCount => (n + 1) * n;
  int get vCount => n * (n + 1);
  int get boxCount => n * n;

  int scoreFor(String playerId) =>
      boxes.where((b) => b == playerId).length;

  bool get allBoxesClaimed => boxes.every((b) => b != null);

  String? hAt(int row, int col) {
    if (row < 0 || row > n || col < 0 || col >= n) return null;
    return hEdges[row * n + col];
  }

  String? vAt(int row, int col) {
    if (row < 0 || row >= n || col < 0 || col > n) return null;
    return vEdges[row * (n + 1) + col];
  }

  String? boxAt(int row, int col) {
    if (row < 0 || row >= n || col < 0 || col >= n) return null;
    return boxes[row * n + col];
  }

  bool boxComplete(int row, int col, List<String?> h, List<String?> v) {
    final top = h[row * n + col];
    final bottom = h[(row + 1) * n + col];
    final left = v[row * (n + 1) + col];
    final right = v[row * (n + 1) + col + 1];
    return top != null && bottom != null && left != null && right != null;
  }
}

/// Claim one free edge.
class DotsAndBoxesMove {
  /// `true` → horizontal edge at [index]; `false` → vertical.
  final bool horizontal;
  final int index;

  const DotsAndBoxesMove({required this.horizontal, required this.index});

  const DotsAndBoxesMove.h(this.index) : horizontal = true;
  const DotsAndBoxesMove.v(this.index) : horizontal = false;
}

/// Dots and Boxes as a [TurnGame]. Pure logic — no Flutter import.
class DotsAndBoxesGame extends TurnGame<DotsAndBoxesState, DotsAndBoxesMove> {
  /// Boxes per side. 3 is the demo default (9 boxes — fast, always a winner).
  final int gridSize;

  const DotsAndBoxesGame({this.gridSize = 3});

  @override
  String get id => 'dots_and_boxes';

  @override
  DotsAndBoxesState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2, 'dots and boxes is exactly 2 players');
    assert(gridSize >= 1 && gridSize <= 8, 'gridSize out of range');
    final n = gridSize;
    return DotsAndBoxesState(
      n: n,
      hEdges: List<String?>.filled((n + 1) * n, null),
      vEdges: List<String?>.filled(n * (n + 1), null),
      boxes: List<String?>.filled(n * n, null),
      playerIds: List.of(playerIds),
      currentPlayerId: playerIds.first,
    );
  }

  @override
  String currentPlayer(DotsAndBoxesState state) => state.currentPlayerId;

  @override
  bool validateMove(
    DotsAndBoxesState state,
    DotsAndBoxesMove move,
    String playerId,
  ) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    if (move.horizontal) {
      if (move.index < 0 || move.index >= state.hCount) return false;
      return state.hEdges[move.index] == null;
    }
    if (move.index < 0 || move.index >= state.vCount) return false;
    return state.vEdges[move.index] == null;
  }

  @override
  DotsAndBoxesState applyMove(DotsAndBoxesState state, DotsAndBoxesMove move) {
    final player = state.currentPlayerId;
    final n = state.n;
    final h = List<String?>.of(state.hEdges);
    final v = List<String?>.of(state.vEdges);
    final boxes = List<String?>.of(state.boxes);

    if (move.horizontal) {
      h[move.index] = player;
    } else {
      v[move.index] = player;
    }

    // Which boxes touch this edge and are newly complete?
    final completed = <int>[];
    if (move.horizontal) {
      final row = move.index ~/ n;
      final col = move.index % n;
      // Box above (if any)
      if (row > 0) {
        final br = row - 1;
        final bi = br * n + col;
        if (boxes[bi] == null && state.boxComplete(br, col, h, v)) {
          boxes[bi] = player;
          completed.add(bi);
        }
      }
      // Box below (if any)
      if (row < n) {
        final br = row;
        final bi = br * n + col;
        if (boxes[bi] == null && state.boxComplete(br, col, h, v)) {
          boxes[bi] = player;
          completed.add(bi);
        }
      }
    } else {
      final row = move.index ~/ (n + 1);
      final col = move.index % (n + 1);
      // Box left
      if (col > 0) {
        final bc = col - 1;
        final bi = row * n + bc;
        if (boxes[bi] == null && state.boxComplete(row, bc, h, v)) {
          boxes[bi] = player;
          completed.add(bi);
        }
      }
      // Box right
      if (col < n) {
        final bc = col;
        final bi = row * n + bc;
        if (boxes[bi] == null && state.boxComplete(row, bc, h, v)) {
          boxes[bi] = player;
          completed.add(bi);
        }
      }
    }

    final kept = completed.isNotEmpty;
    final nextPlayer = kept
        ? player
        : state.playerIds.firstWhere((p) => p != player);

    return DotsAndBoxesState(
      n: n,
      hEdges: h,
      vEdges: v,
      boxes: boxes,
      playerIds: state.playerIds,
      currentPlayerId: nextPlayer,
      lastWasHorizontal: move.horizontal,
      lastEdgeIndex: move.index,
      lastCompletedBoxes: completed,
      lastKeptTurn: kept,
    );
  }

  @override
  GameOutcome? outcome(DotsAndBoxesState state) {
    if (!state.allBoxesClaimed) return null;
    final a = state.playerIds[0];
    final b = state.playerIds[1];
    final sa = state.scoreFor(a);
    final sb = state.scoreFor(b);
    if (sa > sb) return GameOutcome.win(a);
    if (sb > sa) return GameOutcome.win(b);
    return const GameOutcome.draw();
  }

  @override
  Map<String, dynamic> encodeState(DotsAndBoxesState state) => {
        'n': state.n,
        'hEdges': state.hEdges,
        'vEdges': state.vEdges,
        'boxes': state.boxes,
        'playerIds': state.playerIds,
        'currentPlayerId': state.currentPlayerId,
        if (state.lastWasHorizontal != null)
          'lastWasHorizontal': state.lastWasHorizontal,
        if (state.lastEdgeIndex != null) 'lastEdgeIndex': state.lastEdgeIndex,
        'lastCompletedBoxes': state.lastCompletedBoxes,
        'lastKeptTurn': state.lastKeptTurn,
      };

  @override
  DotsAndBoxesState decodeState(Map<String, dynamic> json, int version) =>
      DotsAndBoxesState(
        n: json['n'] as int,
        hEdges: (json['hEdges'] as List).map((e) => e as String?).toList(),
        vEdges: (json['vEdges'] as List).map((e) => e as String?).toList(),
        boxes: (json['boxes'] as List).map((e) => e as String?).toList(),
        playerIds:
            (json['playerIds'] as List).map((e) => e as String).toList(),
        currentPlayerId: json['currentPlayerId'] as String,
        lastWasHorizontal: json['lastWasHorizontal'] as bool?,
        lastEdgeIndex: json['lastEdgeIndex'] as int?,
        lastCompletedBoxes: (json['lastCompletedBoxes'] as List? ?? const [])
            .map((e) => e as int)
            .toList(),
        lastKeptTurn: json['lastKeptTurn'] as bool? ?? false,
      );

  @override
  Map<String, dynamic> encodeMove(DotsAndBoxesMove move) => {
        'horizontal': move.horizontal,
        'index': move.index,
      };

  @override
  DotsAndBoxesMove decodeMove(Map<String, dynamic> json) => DotsAndBoxesMove(
        horizontal: json['horizontal'] as bool,
        index: json['index'] as int,
      );
}
