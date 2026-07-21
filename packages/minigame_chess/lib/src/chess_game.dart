import 'package:chess/chess.dart' as engine;
import 'package:minigames_core/minigames_core.dart';

/// Full-rules chess backed by the `chess` package (a Dart port of chess.js).
///
/// The engine is an implementation detail: state serializes as a start FEN
/// plus the move history in UCI form, and every operation replays that
/// history into a fresh engine. Replaying (rather than loading the current
/// FEN) is what keeps threefold repetition and the 50-move clock correct
/// after a state crosses the wire. Games are short; replay cost is trivial.
///
/// White is `playerIds[0]` and moves first.
class ChessState {
  /// Position the game started from (standard chess unless [ChessGame.fromFen]).
  final String startFen;

  /// Moves played so far, in UCI form (`e2e4`, `e7e8q`).
  final List<String> history;

  /// Current position — cached so the UI never needs an engine to render.
  final String fen;

  final List<String> playerIds;

  const ChessState({
    required this.startFen,
    required this.history,
    required this.fen,
    required this.playerIds,
  });

  String get whiteId => playerIds[0];
  String get blackId => playerIds[1];

  /// Side to move, straight from the FEN.
  bool get whiteToMove => fen.split(' ')[1] == 'w';

  String get currentPlayerId => whiteToMove ? whiteId : blackId;

  /// Board cell index of the last move's origin/destination, if any.
  int? get lastFrom =>
      history.isEmpty ? null : ChessMove.parseUci(history.last).from;
  int? get lastTo =>
      history.isEmpty ? null : ChessMove.parseUci(history.last).to;

  /// Row-major 64 cells (row 0 = rank 8, white home at rows 6–7). Each cell
  /// is a FEN piece char (`P`..`K` white, `p`..`k` black) or null.
  List<String?> boardCells() {
    final cells = List<String?>.filled(64, null);
    final placement = fen.split(' ')[0];
    var i = 0;
    for (final ch in placement.split('')) {
      if (ch == '/') continue;
      final digit = int.tryParse(ch);
      if (digit != null) {
        i += digit;
      } else {
        cells[i++] = ch;
      }
    }
    return cells;
  }

  static int cellOf(int row, int col) => row * 8 + col;

  /// `0 → a8`, `63 → h1`.
  static String algebraic(int cell) =>
      '${'abcdefgh'[cell % 8]}${8 - cell ~/ 8}';

  /// `a8 → 0`, `h1 → 63`.
  static int cellFromAlgebraic(String square) =>
      (8 - int.parse(square[1])) * 8 + (square.codeUnitAt(0) - 97);
}

class ChessMove {
  /// Board cells 0..63, row 0 = rank 8.
  final int from;
  final int to;

  /// Promotion piece (`q`, `r`, `b`, `n`) when a pawn reaches the last rank.
  final String? promotion;

  const ChessMove(this.from, this.to, {this.promotion});

  String get uci =>
      ChessState.algebraic(from) +
      ChessState.algebraic(to) +
      (promotion ?? '');

  static ChessMove parseUci(String uci) => ChessMove(
        ChessState.cellFromAlgebraic(uci.substring(0, 2)),
        ChessState.cellFromAlgebraic(uci.substring(2, 4)),
        promotion: uci.length > 4 ? uci[4] : null,
      );
}

class ChessGame extends TurnGame<ChessState, ChessMove> {
  const ChessGame();

  @override
  String get id => 'chess';

  @override
  ChessState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2);
    return ChessState(
      startFen: engine.Chess.DEFAULT_POSITION,
      history: const [],
      fen: engine.Chess.DEFAULT_POSITION,
      playerIds: List.of(playerIds),
    );
  }

  /// A state starting from an arbitrary position — tests and tooling.
  ChessState fromFen(String fen, {required List<String> playerIds}) =>
      ChessState(
        startFen: fen,
        history: const [],
        fen: fen,
        playerIds: List.of(playerIds),
      );

  @override
  String currentPlayer(ChessState state) => state.currentPlayerId;

  engine.Chess _engineFor(ChessState state) {
    final e = engine.Chess.fromFEN(state.startFen);
    for (final uci in state.history) {
      final applied = e.move(_engineMap(ChessMove.parseUci(uci)));
      assert(applied, 'corrupt history: $uci rejected');
    }
    return e;
  }

  Map<String, String> _engineMap(ChessMove move) => {
        'from': ChessState.algebraic(move.from),
        'to': ChessState.algebraic(move.to),
        if (move.promotion != null) 'promotion': move.promotion!,
      };

  ChessMove _fromEngine(engine.Move m) => ChessMove(
        ChessState.cellFromAlgebraic(m.fromAlgebraic),
        ChessState.cellFromAlgebraic(m.toAlgebraic),
        promotion: m.promotion?.name,
      );

  @override
  bool validateMove(ChessState state, ChessMove move, String playerId) {
    if (playerId != state.currentPlayerId) return false;
    if (outcome(state) != null) return false;
    return _engineFor(state).move(_engineMap(move));
  }

  @override
  ChessState applyMove(ChessState state, ChessMove move) {
    final e = _engineFor(state);
    final applied = e.move(_engineMap(move));
    assert(applied, 'applyMove called with illegal move ${move.uci}');
    return ChessState(
      startFen: state.startFen,
      history: [...state.history, move.uci],
      fen: e.fen,
      playerIds: state.playerIds,
    );
  }

  @override
  GameOutcome? outcome(ChessState state) {
    final e = _engineFor(state);
    if (e.in_checkmate) {
      // Side to move is mated; the other player won.
      return GameOutcome.win(
          state.whiteToMove ? state.blackId : state.whiteId);
    }
    if (e.in_draw) return const GameOutcome.draw();
    return null;
  }

  /// Every legal move in the position.
  List<ChessMove> allLegalMoves(ChessState state) =>
      _engineFor(state).generate_moves().map(_fromEngine).toList();

  /// Legal moves for the piece on [cell] (empty if none or not that side's
  /// turn). Promotions appear once per promotion piece.
  List<ChessMove> legalMovesFrom(ChessState state, int cell) =>
      _engineFor(state)
          .generate_moves({'square': ChessState.algebraic(cell)})
          .map(_fromEngine)
          .toList();

  /// Whether the side to move is currently in check.
  bool isInCheck(ChessState state) => _engineFor(state).in_check;

  /// Whether the game ended by checkmate (vs a draw) — for UI copy.
  bool isCheckmate(ChessState state) => _engineFor(state).in_checkmate;

  /// Whether the position is stalemate — for UI copy on draws.
  bool isStalemate(ChessState state) => _engineFor(state).in_stalemate;

  @override
  Map<String, dynamic> encodeState(ChessState state) => {
        'startFen': state.startFen,
        'history': state.history,
        'fen': state.fen,
        'playerIds': state.playerIds,
      };

  @override
  ChessState decodeState(Map<String, dynamic> json, int version) => ChessState(
        startFen: json['startFen'] as String,
        history:
            (json['history'] as List? ?? const []).map((e) => e as String).toList(),
        fen: json['fen'] as String,
        playerIds:
            (json['playerIds'] as List).map((e) => e as String).toList(),
      );

  @override
  Map<String, dynamic> encodeMove(ChessMove move) => {'uci': move.uci};

  @override
  ChessMove decodeMove(Map<String, dynamic> json) =>
      ChessMove.parseUci(json['uci'] as String);
}
