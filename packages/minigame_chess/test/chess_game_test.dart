import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_chess/minigame_chess.dart';
import 'package:minigames_core/minigames_core.dart';

void main() {
  const game = ChessGame();
  ChessState fresh() =>
      game.initialState(seed: 0, playerIds: const ['white', 'black']);

  ChessState play(ChessState s, List<String> ucis) {
    for (final uci in ucis) {
      final m = ChessMove.parseUci(uci);
      expect(game.validateMove(s, m, s.currentPlayerId), isTrue,
          reason: '$uci should be legal');
      s = game.applyMove(s, m);
    }
    return s;
  }

  int perft(ChessState s, int depth) {
    if (depth == 0) return 1;
    var nodes = 0;
    for (final m in game.allLegalMoves(s)) {
      nodes += perft(game.applyMove(s, m), depth - 1);
    }
    return nodes;
  }

  group('ChessGame', () {
    test('opening state: standard position, white to move', () {
      final s = fresh();
      expect(s.whiteToMove, isTrue);
      expect(game.currentPlayer(s), 'white');
      final cells = s.boardCells();
      expect(cells[ChessState.cellOf(0, 4)], 'k');
      expect(cells[ChessState.cellOf(7, 4)], 'K');
      expect(cells[ChessState.cellOf(6, 0)], 'P');
      expect(game.outcome(s), isNull);
      expect(game.allLegalMoves(s).length, 20);
    });

    test('perft from the start position matches known node counts', () {
      final s = fresh();
      expect(perft(s, 1), 20);
      expect(perft(s, 2), 400);
      expect(perft(s, 3), 8902);
    });

    test('perft on Kiwipete (castling + ep + pins) matches', () {
      final s = game.fromFen(
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
        playerIds: const ['white', 'black'],
      );
      expect(perft(s, 1), 48);
      expect(perft(s, 2), 2039);
    });

    test('perft on promotion-heavy position matches', () {
      final s = game.fromFen(
        'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1',
        playerIds: const ['white', 'black'],
      );
      expect(perft(s, 1), 6);
      expect(perft(s, 2), 264);
    });

    test('fool\'s mate is a black win', () {
      final s = play(fresh(), ['f2f3', 'e7e5', 'g2g4', 'd8h4']);
      expect(game.isCheckmate(s), isTrue);
      expect(game.outcome(s), const GameOutcome.win('black'));
      // No moves accepted after game over.
      expect(
        game.validateMove(s, ChessMove.parseUci('a2a3'), 'white'),
        isFalse,
      );
    });

    test('en passant captures the bypassed pawn', () {
      final s = play(
          fresh(), ['e2e4', 'a7a6', 'e4e5', 'd7d5', 'e5d6']);
      final cells = s.boardCells();
      expect(cells[ChessState.cellFromAlgebraic('d6')], 'P');
      expect(cells[ChessState.cellFromAlgebraic('d5')], isNull);
    });

    test('kingside castling moves the rook too', () {
      final s = play(fresh(), [
        'e2e4', 'e7e5', 'g1f3', 'g8f6', 'f1c4', 'f8c5', 'e1g1',
      ]);
      final cells = s.boardCells();
      expect(cells[ChessState.cellFromAlgebraic('g1')], 'K');
      expect(cells[ChessState.cellFromAlgebraic('f1')], 'R');
      expect(cells[ChessState.cellFromAlgebraic('h1')], isNull);
    });

    test('promotion requires a piece and produces it', () {
      final s0 = game.fromFen('8/P7/8/8/8/8/k6K/8 w - - 0 1',
          playerIds: const ['white', 'black']);
      // Bare a7a8 (no promotion piece) is not a legal move.
      expect(
        game.validateMove(s0, ChessMove.parseUci('a7a8'), 'white'),
        isFalse,
      );
      final s = play(s0, ['a7a8q']);
      expect(s.boardCells()[ChessState.cellFromAlgebraic('a8')], 'Q');
      // All four promotion pieces are offered from a7.
      final promos = game
          .legalMovesFrom(s0, ChessState.cellFromAlgebraic('a7'))
          .map((m) => m.promotion)
          .toSet();
      expect(promos, {'q', 'r', 'b', 'n'});
    });

    test('stalemate and insufficient material are draws', () {
      final stalemate = game.fromFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1',
          playerIds: const ['white', 'black']);
      expect(game.isCheckmate(stalemate), isFalse);
      expect(game.outcome(stalemate), const GameOutcome.draw());

      final bareKings = game.fromFen('8/8/8/4k3/8/4K3/8/8 w - - 0 1',
          playerIds: const ['white', 'black']);
      expect(game.outcome(bareKings), const GameOutcome.draw());
    });

    test('threefold repetition draws, and survives encode/decode', () {
      var s = play(fresh(), [
        'g1f3', 'g8f6', 'f3g1', 'f6g8',
        'g1f3', 'g8f6', 'f3g1',
      ]);
      expect(game.outcome(s), isNull);
      // Round-trip mid-sequence: the history (not just the FEN) must travel.
      s = game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      s = play(s, ['f6g8']);
      expect(game.outcome(s), const GameOutcome.draw());
    });

    test('50-move rule draws', () {
      final s0 = game.fromFen('8/8/8/4k3/8/4K3/4R3/8 w - - 99 80',
          playerIds: const ['white', 'black']);
      expect(game.outcome(s0), isNull);
      final s = play(s0, ['e2e1']);
      expect(game.outcome(s), const GameOutcome.draw());
    });

    test('rejects out-of-turn and illegal moves', () {
      final s = fresh();
      expect(
        game.validateMove(s, ChessMove.parseUci('e7e5'), 'black'),
        isFalse,
      );
      expect(
        game.validateMove(s, ChessMove.parseUci('e2e5'), 'white'),
        isFalse,
      );
      expect(
        game.validateMove(s, ChessMove.parseUci('e2e4'), 'black'),
        isFalse,
      );
    });

    test('legalMovesFrom only reports the tapped piece', () {
      final s = fresh();
      final knight =
          game.legalMovesFrom(s, ChessState.cellFromAlgebraic('g1'));
      expect(knight.map((m) => m.uci).toSet(), {'g1f3', 'g1h3'});
      expect(
          game.legalMovesFrom(s, ChessState.cellFromAlgebraic('e8')), isEmpty);
    });

    test('move encode/decode round-trip keeps promotion', () {
      final m = game.decodeMove(game.encodeMove(
          ChessMove.parseUci('e7e8n')));
      expect(m.uci, 'e7e8n');
      expect(m.promotion, 'n');
    });
  });
}
