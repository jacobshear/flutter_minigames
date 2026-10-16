import 'package:flutter/material.dart';
import 'package:flutter_minigames/src/games/anagrams/anagrams.dart';
import 'package:flutter_minigames/src/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dict = WordDictionary.fromWords(['cat', 'rose']);
  final game = AnagramsGame(dictionary: dict);

  const finished = AnagramsState(
    letters: 'catrose',
    playerIds: ['me', 'opp'],
    submissions: {
      'me': ['cat'],
      'opp': ['rose'],
    },
  );

  Widget results({bool? hostOwnsStatus}) {
    Widget view = AnagramsResultsView(
      game: game,
      state: finished,
      allWords: const ['rose', 'cat'],
    );
    if (hostOwnsStatus != null) {
      view = GameHostChrome(hostOwnsStatus: hostOwnsStatus, child: view);
    }
    return MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: view)),
    );
  }

  testWidgets('results draw their own winner banner without a host',
      (tester) async {
    await tester.pumpWidget(results());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('PLAYER 2 WINS'), findsOneWidget);
  });

  testWidgets('a host that owns status drops the banner, keeps the words',
      (tester) async {
    await tester.pumpWidget(results(hostOwnsStatus: true));
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('WINS'), findsNothing);
    expect(find.text('Found 2 of 2 words'), findsOneWidget);
    expect(find.text('ROSE'), findsWidgets);
  });

  testWidgets('tiles and controls are buttons with the same handlers',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnagramsRoundBoard(
          game: game,
          state: finished,
          playerLabel: 'Player 1',
          onRoundComplete: (_) {},
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));

    // Activating the first rack tile through semantics stages its letter.
    expect(find.bySemanticsLabel('C'), findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel('C'));
    await tester.pump();
    expect(
      find.bySemanticsLabel(RegExp(r'Your word: C\.')),
      findsOneWidget,
    );

    expect(find.bySemanticsLabel('Shuffle letters'), findsOneWidget);
    expect(find.bySemanticsLabel('Delete last letter'), findsOneWidget);
    expect(find.bySemanticsLabel('Enter'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the board label leaves the score and clock to the header',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnagramsRoundBoard(
          game: game,
          state: finished,
          playerLabel: 'Player 1',
          onRoundComplete: (_) {},
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));

    // The container names the word being built and the words found...
    expect(
      find.bySemanticsLabel(RegExp(r'^Anagrams\. 0 words found\.$')),
      findsOneWidget,
    );
    // ...and the score and the clock are read once, off the header's nodes.
    expect(find.bySemanticsLabel(RegExp(r'^Anagrams\..*Score')), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^Anagrams\..*left')), findsNothing);
    semantics.dispose();
  });
}
