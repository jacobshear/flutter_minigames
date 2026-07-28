import 'package:flutter_minigames/src/core/core.dart';

/// English draughts / American checkers on an 8×8 board.
///
/// Pieces sit on dark squares only. Men move/capture diagonally forward; kings
/// move/capture either direction (one square, no flying kings). Captures are
/// **optional** (casual mini-game rules). Multi-jumps are separate moves locked
/// to the same piece via [CheckersState.mustContinueFrom]. Crowning ends the
/// turn even if more captures would be available.
class CheckersState {
  static const int size = 8;
  static const int cellCount = size * size;

  /// Owner player id per cell, or `null` if empty.
  final List<String?> cells;

  /// Whether the piece at each cell is a king (ignored when empty).
  final List<bool> isKing;

  final List<String> playerIds;

  /// Whose turn (or mid multi-jump).
  final String currentPlayerId;

  /// When set, the current player must continue a multi-jump from this cell.
  final int? mustContinueFrom;

  /// Last move metadata for UI juice.
  final int? lastFrom;
  final int? lastTo;
  final int? lastCaptured;
  final bool lastBecameKing;

  const CheckersState({
    required this.cells,
    required this.isKing,
    required this.playerIds,
    required this.currentPlayerId,
    this.mustContinueFrom,
    this.lastFrom,
    this.lastTo,
    this.lastCaptured,
    this.lastBecameKing = false,
  });

  String get darkId => playerIds[0];
  String get lightId => playerIds[1];

  String opponentOf(String playerId) =>
      playerId == darkId ? lightId : darkId;

  /// Dark (p0) sits on the bottom and moves toward smaller row indices.
  int forwardDir(String playerId) => playerId == darkId ? -1 : 1;

  /// Last rank for crowning.
  int kingRow(String playerId) => playerId == darkId ? 0 : size - 1;

  int pieceCount(String playerId) =>
      cells.where((c) => c == playerId).length;

  static int index(int row, int col) => row * size + col;

  static (int row, int col) rc(int index) => (index ~/ size, index % size);

  /// Dark playable squares: (row + col) is odd with row 0 at top.
  static bool isDarkSquare(int row, int col) => (row + col).isOdd;

  static bool inBounds(int row, int col) =>
      row >= 0 && row < size && col >= 0 && col < size;
}

/// Slide or jump from [from] to [to] (both cell indices 0..63).
class CheckersMove {
  final int from;
  final int to;

  const CheckersMove({required this.from, required this.to});
}

class CheckersGame extends TurnGame<CheckersState, CheckersMove> {
  const CheckersGame();

  static const int size = CheckersState.size;

  @override
  String get id => 'checkers';

  @override
  CheckersState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2, 'checkers is exactly 2 players');
    final dark = playerIds[0];
    final light = playerIds[1];
    final cells = List<String?>.filled(CheckersState.cellCount, null);
    final kings = List<bool>.filled(CheckersState.cellCount, false);

    // Light on top three ranks, dark on bottom three, dark squares only.
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < size; col++) {
        if (CheckersState.isDarkSquare(row, col)) {
          cells[CheckersState.index(row, col)] = light;
        }
      }
    }
    for (var row = 5; row < size; row++) {
      for (var col = 0; col < size; col++) {
        if (CheckersState.isDarkSquare(row, col)) {
          cells[CheckersState.index(row, col)] = dark;
        }
      }
    }

    return CheckersState(
      cells: cells,
      isKing: kings,
      playerIds: List.of(playerIds),
      currentPlayerId: dark,
    );
  }

  @override
  String currentPlayer(CheckersState state) => state.currentPlayerId;

  /// All legal moves for [playerId] (respects multi-jump lock; captures optional).
  List<CheckersMove> legalMoves(CheckersState state, String playerId) {
    // Mid multi-jump: only further captures from the locked piece.
    if (state.mustContinueFrom != null &&
        state.currentPlayerId == playerId) {
      return _capturesFrom(state, state.mustContinueFrom!, playerId);
    }

    final out = <CheckersMove>[];
    for (var i = 0; i < CheckersState.cellCount; i++) {
      if (state.cells[i] != playerId) continue;
      out.addAll(_capturesFrom(state, i, playerId));
      out.addAll(_quietsFrom(state, i, playerId));
    }
    return out;
  }

  List<(int, int)> _dirsFor(CheckersState state, String playerId, bool king) {
    if (king) {
      return const [(-1, -1), (-1, 1), (1, -1), (1, 1)];
    }
    final d = state.forwardDir(playerId);
    return [(d, -1), (d, 1)];
  }

  List<CheckersMove> _quietsFrom(
    CheckersState state,
    int from,
    String playerId,
  ) {
    final (row, col) = CheckersState.rc(from);
    final dirs = _dirsFor(state, playerId, state.isKing[from]);
    final out = <CheckersMove>[];
    for (final (dr, dc) in dirs) {
      final r = row + dr;
      final c = col + dc;
      if (!CheckersState.inBounds(r, c)) continue;
      final to = CheckersState.index(r, c);
      if (state.cells[to] == null) {
        out.add(CheckersMove(from: from, to: to));
      }
    }
    return out;
  }

  List<CheckersMove> _capturesFrom(
    CheckersState state,
    int from,
    String playerId,
  ) {
    final (row, col) = CheckersState.rc(from);
    final dirs = _dirsFor(state, playerId, state.isKing[from]);
    final opp = state.opponentOf(playerId);
    final out = <CheckersMove>[];
    for (final (dr, dc) in dirs) {
      final midR = row + dr;
      final midC = col + dc;
      final landR = row + dr * 2;
      final landC = col + dc * 2;
      if (!CheckersState.inBounds(midR, midC) ||
          !CheckersState.inBounds(landR, landC)) {
        continue;
      }
      final mid = CheckersState.index(midR, midC);
      final to = CheckersState.index(landR, landC);
      if (state.cells[mid] == opp && state.cells[to] == null) {
        out.add(CheckersMove(from: from, to: to));
      }
    }
    return out;
  }

  @override
  bool validateMove(
    CheckersState state,
    CheckersMove move,
    String playerId,
  ) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    if (move.from < 0 ||
        move.from >= CheckersState.cellCount ||
        move.to < 0 ||
        move.to >= CheckersState.cellCount) {
      return false;
    }
    return legalMoves(state, playerId).any(
      (m) => m.from == move.from && m.to == move.to,
    );
  }

  @override
  CheckersState applyMove(CheckersState state, CheckersMove move) {
    final player = state.currentPlayerId;
    final cells = List<String?>.of(state.cells);
    final kings = List<bool>.of(state.isKing);

    final (fr, fc) = CheckersState.rc(move.from);
    final (tr, tc) = CheckersState.rc(move.to);
    final isJump = (tr - fr).abs() == 2;

    int? captured;
    if (isJump) {
      final mid = CheckersState.index((fr + tr) ~/ 2, (fc + tc) ~/ 2);
      captured = mid;
      cells[mid] = null;
      kings[mid] = false;
    }

    final wasKing = kings[move.from];
    cells[move.to] = player;
    kings[move.to] = wasKing;
    cells[move.from] = null;
    kings[move.from] = false;

    var becameKing = false;
    if (!kings[move.to] && tr == state.kingRow(player)) {
      kings[move.to] = true;
      becameKing = true;
    }

    final midState = CheckersState(
      cells: cells,
      isKing: kings,
      playerIds: state.playerIds,
      currentPlayerId: player,
    );
    final moreJumps = !becameKing &&
        isJump &&
        _capturesFrom(midState, move.to, player).isNotEmpty;

    if (moreJumps) {
      return CheckersState(
        cells: cells,
        isKing: kings,
        playerIds: state.playerIds,
        currentPlayerId: player,
        mustContinueFrom: move.to,
        lastFrom: move.from,
        lastTo: move.to,
        lastCaptured: captured,
        lastBecameKing: becameKing,
      );
    }

    return CheckersState(
      cells: cells,
      isKing: kings,
      playerIds: state.playerIds,
      currentPlayerId: state.opponentOf(player),
      mustContinueFrom: null,
      lastFrom: move.from,
      lastTo: move.to,
      lastCaptured: captured,
      lastBecameKing: becameKing,
    );
  }

  @override
  GameOutcome? outcome(CheckersState state) {
    final a = state.darkId;
    final b = state.lightId;
    if (state.pieceCount(a) == 0) return GameOutcome.win(b);
    if (state.pieceCount(b) == 0) return GameOutcome.win(a);

    final cur = state.currentPlayerId;
    if (legalMoves(state, cur).isEmpty) {
      return GameOutcome.win(state.opponentOf(cur));
    }
    return null;
  }

  @override
  Map<String, dynamic> encodeState(CheckersState state) => {
        'cells': state.cells,
        'isKing': state.isKing,
        'playerIds': state.playerIds,
        'currentPlayerId': state.currentPlayerId,
        if (state.mustContinueFrom != null)
          'mustContinueFrom': state.mustContinueFrom,
        if (state.lastFrom != null) 'lastFrom': state.lastFrom,
        if (state.lastTo != null) 'lastTo': state.lastTo,
        if (state.lastCaptured != null) 'lastCaptured': state.lastCaptured,
        'lastBecameKing': state.lastBecameKing,
      };

  @override
  CheckersState decodeState(Map<String, dynamic> json, int version) =>
      CheckersState(
        cells: (json['cells'] as List).map((e) => e as String?).toList(),
        isKing: (json['isKing'] as List).map((e) => e as bool).toList(),
        playerIds:
            (json['playerIds'] as List).map((e) => e as String).toList(),
        currentPlayerId: json['currentPlayerId'] as String,
        mustContinueFrom: json['mustContinueFrom'] as int?,
        lastFrom: json['lastFrom'] as int?,
        lastTo: json['lastTo'] as int?,
        lastCaptured: json['lastCaptured'] as int?,
        lastBecameKing: json['lastBecameKing'] as bool? ?? false,
      );

  @override
  Map<String, dynamic> encodeMove(CheckersMove move) => {
        'from': move.from,
        'to': move.to,
      };

  @override
  CheckersMove decodeMove(Map<String, dynamic> json) => CheckersMove(
        from: json['from'] as int,
        to: json['to'] as int,
      );
}
