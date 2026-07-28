import 'package:flutter_minigames/src/core/core.dart';

/// Immutable tic-tac-toe state: 9 cells, each `null` (empty) or the id of the
/// player who marked it. Player order is `[X, O]`; whose turn it is is derived
/// from how many cells are filled, so it never needs to be stored separately.
class TicTacToeState {
  /// Row-major cells, length 9. `null` = empty, otherwise a player id.
  final List<String?> cells;

  /// Players in mark order: index 0 is X, index 1 is O.
  final List<String> playerIds;

  const TicTacToeState({required this.cells, required this.playerIds});

  int get filledCount => cells.where((c) => c != null).length;

  /// Id of the player to move next.
  String get currentPlayerId => playerIds[filledCount % 2];

  /// The mark ('X' / 'O') for a player id, or empty string if unknown.
  String markFor(String? playerId) {
    if (playerId == null) return '';
    final i = playerIds.indexOf(playerId);
    return i == 0 ? 'X' : (i == 1 ? 'O' : '');
  }

  /// Mark shown in [cell], or empty string.
  String markAt(int cell) => markFor(cells[cell]);

  TicTacToeState place(int cell, String playerId) {
    final next = List<String?>.of(cells);
    next[cell] = playerId;
    return TicTacToeState(cells: next, playerIds: playerIds);
  }
}

/// A move: the cell (0..8) a player wants to claim.
class TicTacToeMove {
  final int cell;
  const TicTacToeMove(this.cell);
}

/// Tic-tac-toe as a [TurnGame]. Pure logic — no Flutter import here.
class TicTacToeGame extends TurnGame<TicTacToeState, TicTacToeMove> {
  const TicTacToeGame();

  static const List<List<int>> winningLines = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8], // rows
    [0, 3, 6], [1, 4, 7], [2, 5, 8], // cols
    [0, 4, 8], [2, 4, 6], // diagonals
  ];

  @override
  String get id => 'tic_tac_toe';

  @override
  TicTacToeState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2, 'tic-tac-toe is exactly 2 players');
    return TicTacToeState(
      cells: List<String?>.filled(9, null),
      playerIds: List.of(playerIds),
    );
  }

  @override
  String currentPlayer(TicTacToeState state) => state.currentPlayerId;

  @override
  bool validateMove(
    TicTacToeState state,
    TicTacToeMove move,
    String playerId,
  ) {
    if (outcome(state) != null) return false;
    if (move.cell < 0 || move.cell >= 9) return false;
    if (state.cells[move.cell] != null) return false;
    return state.currentPlayerId == playerId;
  }

  @override
  TicTacToeState applyMove(TicTacToeState state, TicTacToeMove move) =>
      state.place(move.cell, state.currentPlayerId);

  @override
  GameOutcome? outcome(TicTacToeState state) {
    for (final line in winningLines) {
      final a = state.cells[line[0]];
      if (a != null && a == state.cells[line[1]] && a == state.cells[line[2]]) {
        return GameOutcome.win(a);
      }
    }
    if (state.cells.every((c) => c != null)) return const GameOutcome.draw();
    return null;
  }

  @override
  Map<String, dynamic> encodeState(TicTacToeState state) => {
        'cells': state.cells,
        'playerIds': state.playerIds,
      };

  @override
  TicTacToeState decodeState(Map<String, dynamic> json, int version) =>
      TicTacToeState(
        cells: (json['cells'] as List).map((e) => e as String?).toList(),
        playerIds: (json['playerIds'] as List).map((e) => e as String).toList(),
      );

  @override
  Map<String, dynamic> encodeMove(TicTacToeMove move) => {'cell': move.cell};

  @override
  TicTacToeMove decodeMove(Map<String, dynamic> json) =>
      TicTacToeMove(json['cell'] as int);
}
