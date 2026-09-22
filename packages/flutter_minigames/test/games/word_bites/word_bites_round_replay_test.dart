import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/word_bites/word_bites.dart';
import 'package:flutter_minigames/src/ui/ui.dart';
import 'package:flutter_minigames/src/words/words.dart';

void main() {
  final dict = WordDictionary.fromWords(['the', 'rat']);
  final game = WordBitesGame(dictionary: dict);

  /// Shared piece set (mirrors word_bites_game_test.dart's fixture):
  ///   0 't' single, 1 'h' single, 2 'e' single,
  ///   3 'ra' horizontal domino, 4 'on' vertical domino, 5 'a' single.
  const pieces = [
    WordBitesPiece(id: 0, shape: WordBitesPieceShape.single, letters: 't'),
    WordBitesPiece(id: 1, shape: WordBitesPieceShape.single, letters: 'h'),
    WordBitesPiece(id: 2, shape: WordBitesPieceShape.single, letters: 'e'),
    WordBitesPiece(id: 3, shape: WordBitesPieceShape.horizontal, letters: 'ra'),
    WordBitesPiece(id: 4, shape: WordBitesPieceShape.vertical, letters: 'on'),
    WordBitesPiece(id: 5, shape: WordBitesPieceShape.single, letters: 'a'),
  ];

  WordBitesPlacement at(int id, int row, int col) =>
      WordBitesPlacement(pieceId: id, row: row, col: col);

  // "the" at row 2, cols 1-3; "rat" at row 4, cols 2 (domino) + 4 (single).
  final thePlay = WordBitesPlay(
    word: 'the',
    placements: [at(0, 2, 1), at(1, 2, 2), at(2, 2, 3)],
  );
  final ratPlay = WordBitesPlay(
    word: 'rat',
    placements: [at(3, 4, 2), at(0, 4, 4)],
  );

  WordBitesState stateWith(List<WordBitesPlay> plays, {String? viewerWord}) {
    var s = WordBitesState(
      playerIds: const ['opponent', 'viewer'],
      rows: 9,
      cols: 8,
      pieces: pieces,
      submissions: const [],
    );
    // opponent submits first.
    s = game.applyMove(s, WordBitesMove(words: plays));
    // viewer submits second, optionally having found one of the same words.
    s = game.applyMove(
      s,
      WordBitesMove(
        words: viewerWord == null
            ? const []
            : [if (viewerWord == 'the') thePlay else ratPlay],
      ),
    );
    return s;
  }

  Widget harness(WordBitesState state, RoundReplayController controller) {
    return MaterialApp(
      home: Scaffold(
        body: WordBitesRoundReplay(
          game: game,
          state: state,
          playerId: 'opponent',
          viewerId: 'viewer',
          controller: controller,
        ),
      ),
    );
  }

  testWidgets('plays through to completion and lands on the final score',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = stateWith([thePlay, ratPlay], viewerWord: 'the');
    final controller = RoundReplayController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(state, controller));
    await tester.pump();
    // Pacing formula: base(3)=0.35 for both words (len 3), rawTotal=0.70s
    // (under the 15s cap, unscaled) + 0.45s final hold = 1.15s. Overshoot it.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(controller.finished, isTrue);
    expect(
      state.scoreOf('opponent'),
      WordBitesGame.scoreForLength(3) * 2,
      reason: 'sanity: both 3-letter words score 100 each',
    );
    expect(find.text('${state.scoreOf('opponent')}'), findsOneWidget);
    expect(find.text('THE'), findsOneWidget);
    expect(find.text('RAT'), findsOneWidget);
  });

  testWidgets('skip jumps straight to the resolved final state',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = stateWith([thePlay, ratPlay], viewerWord: 'rat');
    final controller = RoundReplayController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(state, controller));
    await tester.pump();

    controller.skip();
    await tester.pump();

    expect(controller.finished, isTrue);
    expect(find.text('${state.scoreOf('opponent')}'), findsOneWidget);
    expect(find.text('THE'), findsOneWidget);
    expect(find.text('RAT'), findsOneWidget);
  });

  testWidgets('empty submission goes straight to a "No words" end state',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = stateWith(const []);
    final controller = RoundReplayController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(state, controller));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(controller.finished, isTrue);
    expect(find.text('No words'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });
}
