import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/word_bites/word_bites.dart';
import 'package:flutter_minigames/src/ui/ui.dart';
import 'package:flutter_minigames/src/words/words.dart';

/// Every semantics label currently in the tree, in tree order.
List<String> _labels(WidgetTester tester) {
  final labels = <String>[];
  void walk(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  // ignore: deprecated_member_use
  walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return labels;
}

void main() {
  final dict = WordDictionary.fromWords(['the', 'rat']);
  final game = WordBitesGame(dictionary: dict);

  const pieces = [
    WordBitesPiece(id: 0, shape: WordBitesPieceShape.single, letters: 't'),
    WordBitesPiece(id: 1, shape: WordBitesPieceShape.single, letters: 'h'),
    WordBitesPiece(id: 2, shape: WordBitesPieceShape.single, letters: 'e'),
    WordBitesPiece(id: 3, shape: WordBitesPieceShape.horizontal, letters: 'ra'),
    WordBitesPiece(id: 4, shape: WordBitesPieceShape.vertical, letters: 'on'),
    WordBitesPiece(id: 5, shape: WordBitesPieceShape.single, letters: 'a'),
  ];

  /// The piece letters as the tiles draw them — none of these may show up as
  /// a node of its own behind the board's container label.
  const tileLetters = ['T', 'H', 'E', 'R', 'A', 'O', 'N'];

  testWidgets('the live board reads its pieces once', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(430, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WordBitesBoard(pieces: pieces, dictionary: dict),
        ),
      ),
    );
    await tester.pump();

    final labels = _labels(tester);
    final board = labels.where((l) => l.startsWith('Word bites. Board of'));
    expect(board, hasLength(1), reason: 'the board label appears once');
    expect(board.single.contains('\n'), isFalse, reason: board.single);
    for (final letter in tileLetters) {
      expect(labels.contains(letter), isFalse,
          reason: 'the tile "$letter" is not a separate node');
    }
    handle.dispose();
  });

  testWidgets('the replay board reads its pieces once', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(430, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var s = WordBitesState(
      playerIds: const ['opponent', 'viewer'],
      rows: 9,
      cols: 8,
      pieces: pieces,
      submissions: const [],
    );
    s = game.applyMove(
      s,
      WordBitesMove(
        words: [
          WordBitesPlay(
            word: 'the',
            placements: [
              WordBitesPlacement(pieceId: 0, row: 2, col: 1),
              WordBitesPlacement(pieceId: 1, row: 2, col: 2),
              WordBitesPlacement(pieceId: 2, row: 2, col: 3),
            ],
          ),
        ],
      ),
    );
    s = game.applyMove(s, const WordBitesMove(words: []));
    final controller = RoundReplayController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WordBitesRoundReplay(
            game: game,
            state: s,
            playerId: 'opponent',
            viewerId: 'viewer',
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pump();

    final labels = _labels(tester);
    final replay = labels.where((l) => l.startsWith('Word bites replay.'));
    expect(replay, hasLength(1), reason: 'the replay label appears once');
    expect(replay.single.contains('\n'), isFalse, reason: replay.single);
    for (final letter in tileLetters) {
      expect(labels.contains(letter), isFalse,
          reason: 'the tile "$letter" is not a separate node');
    }
    handle.dispose();
  });
}
