import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/crazy_eights/crazy_eights.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

/// The table paints every card as a vector with no text, so without labels a
/// screen reader sees a blank board. These pin the labels, that activating a
/// node plays the same move a tap does, and the host / Reduce Motion seams.
void main() {
  const game = CrazyEightsGame();

  // card(suit, rank): rank 0 = ace … 7 = eight … 12 = king.
  int card(int suit, int rank) => suit * 13 + rank;
  const sp = CrazyEightsCards.spades;
  const he = CrazyEightsCards.hearts;
  const cl = CrazyEightsCards.clubs;

  CrazyEightsState make({
    required List<int> hand0,
    List<int> hand1 = const [1, 2, 3, 4, 5],
    List<int> stock = const [20, 21, 22, 23, 24, 25],
    int top = 17, // 5 of hearts
    int passes = 0,
    int? declaredSuit,
  }) =>
      CrazyEightsState(
        playerIds: const ['p1', 'p2'],
        hands: [hand0, hand1],
        stock: stock,
        discard: [top],
        currentIndex: 0,
        declaredSuit: declaredSuit,
        passes: passes,
        reshuffles: 0,
        seed: 7,
      );

  Future<MatchController<CrazyEightsState, CrazyEightsMove>> controllerFor(
    CrazyEightsState state,
  ) async {
    final transport = LocalTransport();
    final match = Match(
      id: 'ce-a11y-${state.hashCode}',
      gameId: game.id,
      playerIds: state.playerIds,
      currentPlayerId: state.currentPlayerId,
      status: MatchStatus.open,
      turnCount: 0,
      state: game.encodeState(state),
      schemaVersion: game.stateSchemaVersion,
    );
    await transport.createMatch(match);
    final controller = MatchController<CrazyEightsState, CrazyEightsMove>(
      game: game,
      transport: transport,
      matchId: match.id,
      localPlayerId: 'p1',
      hotSeat: true,
    );
    await controller.connect();
    return controller;
  }

  Future<MatchController<CrazyEightsState, CrazyEightsMove>> pump(
    WidgetTester tester,
    CrazyEightsState state, {
    bool hostOwnsStatus = false,
    bool reduceMotion = false,
    Size size = const Size(361, 560),
  }) async {
    final controller = await controllerFor(state);
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Material(
          child: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: GameHostChrome(
                hostOwnsStatus: hostOwnsStatus,
                child: CrazyEightsTable(
                  controller: controller,
                  style: const CrazyEightsStyle(handoffCover: false),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Finish the deal so every card is on the table.
    await tester.pump(const Duration(milliseconds: 1300));
    return controller;
  }

  group('semantics', () {
    testWidgets('hand cards, piles and the opponent are labelled',
        (tester) async {
      final handle = tester.ensureSemantics();
      // Q♥ matches the 5♥ on suit; 7♣ matches nothing.
      await pump(tester, make(hand0: [card(he, 11), card(cl, 6)]));

      expect(find.bySemanticsLabel('Queen of hearts, playable'),
          findsOneWidget);
      expect(find.bySemanticsLabel('7 of clubs'), findsOneWidget);
      expect(find.bySemanticsLabel('Draw pile, 6 cards'), findsOneWidget);
      expect(find.bySemanticsLabel('Discard pile, 5 of hearts on top'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Player 2 has 5 cards'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a card is a button whose activation plays it',
        (tester) async {
      final handle = tester.ensureSemantics();
      final controller =
          await pump(tester, make(hand0: [card(he, 11), card(cl, 6)]));

      final node = tester.getSemantics(
          find.bySemanticsLabel('Queen of hearts, playable'));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);

      tester.semantics.tap(find.semantics.byLabel('Queen of hearts, playable'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.state!.topCard, card(he, 11),
          reason: 'the semantic tap did not play the card');
      handle.dispose();
    });

    testWidgets('an unplayable card says no through the same handler',
        (tester) async {
      final handle = tester.ensureSemantics();
      final controller =
          await pump(tester, make(hand0: [card(he, 11), card(cl, 6)]));

      tester.semantics.tap(find.semantics.byLabel('7 of clubs'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.state!.topCard, 17, reason: 'an illegal card played');
      expect(find.text('That one will not go there'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the draw pile draws', (tester) async {
      final handle = tester.ensureSemantics();
      final controller =
          await pump(tester, make(hand0: [card(he, 11), card(cl, 6)]));

      tester.semantics.tap(find.semantics.byLabel('Draw pile, 6 cards'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.state!.hands[0], hasLength(3));
      expect(controller.state!.stock, hasLength(5));
      handle.dispose();
    });

    testWidgets('an empty stock is said to be empty', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        make(hand0: [card(he, 11), card(cl, 6)], stock: const []),
      );
      expect(find.bySemanticsLabel('Draw pile, empty'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the declared suit is part of the discard label',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        make(
          hand0: [card(cl, 6), card(cl, 2)],
          top: card(sp, 7),
          declaredSuit: CrazyEightsCards.clubs,
        ),
      );
      expect(find.bySemanticsLabel('Discard pile, 8 of spades on top, clubs called'),
          findsOneWidget);
      handle.dispose();
    });

    testWidgets('the suit picker names its four suits and plays the choice',
        (tester) async {
      final handle = tester.ensureSemantics();
      final controller = await pump(
        tester,
        make(hand0: [card(sp, 7), card(cl, 6)]),
      );

      tester.semantics.tap(find.semantics.byLabel('8 of spades, playable'));
      await tester.pump();
      for (final suit in ['Spades', 'Hearts', 'Diamonds', 'Clubs']) {
        expect(find.bySemanticsLabel(suit), findsOneWidget);
      }

      tester.semantics.tap(find.semantics.byLabel('Hearts'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.state!.topCard, card(sp, 7));
      expect(controller.state!.declaredSuit, CrazyEightsCards.hearts);
      handle.dispose();
    });

    testWidgets('the picker can be backed out of with the dismiss action',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, make(hand0: [card(sp, 7), card(cl, 6)]));

      tester.semantics.tap(find.semantics.byLabel('8 of spades, playable'));
      await tester.pump();
      expect(find.text('Choose a suit'), findsOneWidget);

      final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
      SemanticsNode? scrim;
      void visit(SemanticsNode n) {
        if (n.getSemanticsData().hasAction(SemanticsAction.dismiss)) scrim = n;
        n.visitChildren((c) {
          visit(c);
          return true;
        });
      }

      visit(owner.rootSemanticsNode!);
      expect(scrim, isNotNull, reason: 'nothing on the picker can be dismissed');
      owner.performAction(scrim!.id, SemanticsAction.dismiss);
      await tester.pump();
      expect(find.text('Choose a suit'), findsNothing);
      handle.dispose();
    });

    testWidgets('hand cards are read left to right', (tester) async {
      final handle = tester.ensureSemantics();
      final hand = [
        card(he, 1), // 2♥
        card(he, 11), // Q♥
        card(cl, 6), // 7♣
        card(sp, 3), // 4♠
        card(cl, 12), // K♣
        card(he, 9), // 10♥
      ];
      await pump(tester, make(hand0: hand));

      final order = <String>[];
      void walk(SemanticsNode n) {
        final l = n.label;
        if (hand.any((c) => l.startsWith(CrazyEightsCards.spokenName(c)))) {
          order.add(l.split(',').first);
        }
        n.visitChildren((c) {
          walk(c);
          return true;
        });
      }

      walk(tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
      expect(order, [
        for (final c in hand) CrazyEightsCards.spokenName(c),
      ]);
      handle.dispose();
    });
  });

  group('hostOwnsStatus', () {
    /// P1 plays their last card, which ends the game in their favour.
    Future<void> win(WidgetTester tester, {required bool host}) async {
      final controller = await pump(
        tester,
        make(hand0: [card(he, 11)]),
        hostOwnsStatus: host,
      );
      controller.submitMove(CrazyEightsMove.play(card(he, 11)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('without a host the table announces the winner',
        (tester) async {
      await win(tester, host: false);
      expect(find.text('Player 1 wins'), findsOneWidget);
    });

    testWidgets('with a host the winner line is left to the host',
        (tester) async {
      await win(tester, host: true);
      expect(find.text('Player 1 wins'), findsNothing);
      expect(find.textContaining('wins'), findsNothing);
    });

    testWidgets('a points decision still says why', (tester) async {
      // Stock empty, both stuck: P1 passes, then P2 passes — 2 passes ends it.
      final controller = await pump(
        tester,
        make(
          hand0: [card(cl, 6)],
          hand1: [card(cl, 12), card(cl, 11)],
          stock: const [],
        ),
        hostOwnsStatus: true,
      );
      controller.submitMove(const CrazyEightsMove.pass());
      await tester.pump(const Duration(milliseconds: 100));
      controller.submitMove(const CrazyEightsMove.pass());
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Fewer points'), findsOneWidget);
      expect(find.textContaining('wins'), findsNothing);
    });

    testWidgets('keeps the suit prompt', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        make(hand0: [card(sp, 7), card(cl, 6)]),
        hostOwnsStatus: true,
      );
      // The prompt is an in-board choice, not turn status.
      tester.semantics.tap(find.semantics.byLabel('8 of spades, playable'));
      await tester.pump();
      expect(find.text('Choose a suit'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('keeps the pile captions', (tester) async {
      await pump(
        tester,
        make(hand0: [card(he, 11)]),
        hostOwnsStatus: true,
      );
      expect(find.text('6 left'), findsOneWidget);
      expect(find.text('Hearts or 5'), findsOneWidget);
    });
  });

  group('Reduce Motion', () {
    Finder confetti() => find.byWidgetPredicate((w) =>
        w is CustomPaint &&
        w.painter.runtimeType.toString() == '_ConfettiPainter');

    Future<void> win(WidgetTester tester, {required bool reduce}) async {
      final controller = await pump(
        tester,
        make(hand0: [card(he, 11)]),
        reduceMotion: reduce,
      );
      controller.submitMove(CrazyEightsMove.play(card(he, 11)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400)); // card lands
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('a win throws confetti normally', (tester) async {
      await win(tester, reduce: false);
      expect(confetti(), findsOneWidget);
    });

    testWidgets('and none under Reduce Motion', (tester) async {
      await win(tester, reduce: true);
      expect(confetti(), findsNothing);
      expect(find.byType(CrazyEightsTable), findsOneWidget);
    });
  });
}
