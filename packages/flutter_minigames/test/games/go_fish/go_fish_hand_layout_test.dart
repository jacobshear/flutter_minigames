import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_minigames/src/cards/cards.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/go_fish/go_fish.dart';

/// Regression coverage for issue #6: a hand fragmented across six rank
/// groups used to be forced into one row, squeezing every card to ~40-49pt —
/// too narrow to read. The fix wraps onto a second row (whole trays only)
/// once a single row would fall below the readable floor, and keeps a
/// less-fragmented hand on one row.
void main() {
  Future<MatchController<GoFishState, GoFishMove>> controllerFor(
    GoFishState state,
  ) async {
    const game = GoFishGame();
    final transport = LocalTransport();
    final match = Match(
      id: 'hand-layout-${state.hashCode}',
      gameId: game.id,
      playerIds: state.playerIds,
      currentPlayerId: state.currentPlayerId,
      status: MatchStatus.open,
      turnCount: 0,
      state: game.encodeState(state),
      schemaVersion: game.stateSchemaVersion,
    );
    await transport.createMatch(match);
    final controller = MatchController<GoFishState, GoFishMove>(
      game: game,
      transport: transport,
      matchId: match.id,
      localPlayerId: state.playerIds[0],
      hotSeat: true,
    );
    await controller.connect();
    return controller;
  }

  /// Six ranks, one card each — the worst-case fragmented hand: every ask is
  /// a live decision and every tray is a singleton.
  GoFishState sixRankHand() {
    const hand = [
      PlayingCard(Rank.two, Suit.clubs),
      PlayingCard(Rank.four, Suit.diamonds),
      PlayingCard(Rank.six, Suit.hearts),
      PlayingCard(Rank.eight, Suit.spades),
      PlayingCard(Rank.ten, Suit.clubs),
      PlayingCard(Rank.queen, Suit.diamonds),
    ];
    const opponent = [
      PlayingCard(Rank.three, Suit.hearts),
      PlayingCard(Rank.five, Suit.spades),
      PlayingCard(Rank.seven, Suit.clubs),
      PlayingCard(Rank.nine, Suit.diamonds),
      PlayingCard(Rank.jack, Suit.hearts),
      PlayingCard(Rank.king, Suit.spades),
      PlayingCard(Rank.ace, Suit.clubs),
    ];
    const pond = [
      PlayingCard(Rank.ace, Suit.diamonds),
      PlayingCard(Rank.ace, Suit.hearts),
    ];
    return const GoFishState(
      playerIds: ['p1', 'p2'],
      hands: [hand, opponent],
      pond: pond,
      books: [[], []],
      currentIndex: 0,
      lastEvent: GoFishEvent(action: GoFishAction.deal),
    );
  }

  /// Three ranks, unevenly stacked — must not wrap.
  GoFishState threeRankHand() {
    const hand = [
      PlayingCard(Rank.two, Suit.clubs),
      PlayingCard(Rank.two, Suit.diamonds),
      PlayingCard(Rank.two, Suit.hearts),
      PlayingCard(Rank.seven, Suit.clubs),
      PlayingCard(Rank.seven, Suit.diamonds),
      PlayingCard(Rank.king, Suit.spades),
      PlayingCard(Rank.king, Suit.clubs),
    ];
    const opponent = [
      PlayingCard(Rank.three, Suit.hearts),
      PlayingCard(Rank.five, Suit.spades),
      PlayingCard(Rank.nine, Suit.diamonds),
      PlayingCard(Rank.jack, Suit.hearts),
      PlayingCard(Rank.four, Suit.spades),
      PlayingCard(Rank.six, Suit.clubs),
      PlayingCard(Rank.eight, Suit.diamonds),
    ];
    const pond = [
      PlayingCard(Rank.ace, Suit.diamonds),
      PlayingCard(Rank.ace, Suit.hearts),
    ];
    return const GoFishState(
      playerIds: ['p1', 'p2'],
      hands: [hand, opponent],
      pond: pond,
      books: [[], []],
      currentIndex: 0,
      lastEvent: GoFishEvent(action: GoFishAction.deal),
    );
  }

  Future<void> pumpTable(
    WidgetTester tester,
    GoFishState state,
    Size size,
  ) async {
    final controller = await controllerFor(state);
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: GoFishTable(
                controller: controller,
                style: const GoFishStyle(handoffCover: false),
              ),
            ),
          ),
        ),
      ),
    );
    // Let the entrance animation finish so every hand card is dealt.
    await tester.pump(const Duration(milliseconds: 900));
  }

  /// Face-up cards with a value are hand cards; face-down, valueless cards
  /// are the pond and the opponent's backs.
  Finder handCards() => find.byWidgetPredicate(
        (w) => w is CardView && w.card != null && w.faceUp,
      );

  Finder faceDownCards() => find.byWidgetPredicate(
        (w) => w is CardView && w.card == null && !w.faceUp,
      );

  const floor = 52.0;

  group('the hand wraps once a single row would go below the floor', () {
    testWidgets('a fragmented six-rank hand keeps every card at/above 52pt',
        (tester) async {
      await pumpTable(tester, sixRankHand(), const Size(402, 874));

      final cards = tester.widgetList<CardView>(handCards()).toList();
      expect(cards, hasLength(6), reason: 'one card per rank group');
      for (final card in cards) {
        expect(
          card.width,
          greaterThanOrEqualTo(floor - 0.01),
          reason: 'a hand card fell below the readable floor',
        );
      }
    });

    testWidgets('the fragmented hand actually wraps to two rows',
        (tester) async {
      await pumpTable(tester, sixRankHand(), const Size(402, 874));

      final tops =
          tester.getRectList(handCards()).map((r) => r.top.round()).toSet();
      expect(tops, hasLength(2),
          reason: 'six singleton trays in one row is exactly the bug');
    });

    testWidgets('a three-rank hand stays on one row', (tester) async {
      await pumpTable(tester, threeRankHand(), const Size(402, 874));

      final cards = tester.widgetList<CardView>(handCards()).toList();
      expect(cards, hasLength(7));
      final tops =
          tester.getRectList(handCards()).map((r) => r.top.round()).toSet();
      expect(tops, hasLength(1),
          reason: 'three groups comfortably fit a single row');
    });

    testWidgets('no hand card overlaps the pond/backs band', (tester) async {
      await pumpTable(tester, sixRankHand(), const Size(402, 874));

      final pondBottom = tester
          .getRectList(faceDownCards())
          .map((r) => r.bottom)
          .reduce((a, b) => a > b ? a : b);
      for (final rect in tester.getRectList(handCards())) {
        expect(
          rect.top,
          greaterThanOrEqualTo(pondBottom),
          reason: 'a hand card reached up into the pond/backs band',
        );
      }
    });
  });
}

extension on WidgetTester {
  /// The global paint rect of every element a finder matches.
  Iterable<Rect> getRectList(Finder finder) => finder.evaluate().map((e) {
        final box = e.renderObject! as RenderBox;
        return box.localToGlobal(Offset.zero) & box.size;
      });
}
