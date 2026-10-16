import 'dart:math' as math;

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

  group('the hand fits the table height', () {
    /// Seat 0 holds [hand]; the opponent holds seven cards and the pond two.
    /// With [withBooks] each seat has already made one book.
    GoFishState withHand(List<PlayingCard> hand, {bool withBooks = false}) {
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
      return GoFishState(
        playerIds: const ['p1', 'p2'],
        hands: [hand, opponent],
        pond: pond,
        books: withBooks
            ? const [
                [Rank.three],
                [Rank.four],
              ]
            : const [[], []],
        currentIndex: 0,
        lastEvent: const GoFishEvent(action: GoFishAction.deal),
      );
    }

    /// A 7-card hand in six rank groups: five singletons and a pair.
    GoFishState sevenInSixGroups({bool withBooks = false}) => withHand(const [
          PlayingCard(Rank.two, Suit.clubs),
          PlayingCard(Rank.four, Suit.diamonds),
          PlayingCard(Rank.six, Suit.hearts),
          PlayingCard(Rank.eight, Suit.spades),
          PlayingCard(Rank.ten, Suit.clubs),
          PlayingCard(Rank.queen, Suit.diamonds),
          PlayingCard(Rank.queen, Suit.hearts),
        ], withBooks: withBooks);

    /// 13 cards in six groups: 3, 3, 2, 2, 2, 1.
    GoFishState thirteenInSixGroups() => withHand(const [
          PlayingCard(Rank.two, Suit.clubs),
          PlayingCard(Rank.two, Suit.diamonds),
          PlayingCard(Rank.two, Suit.hearts),
          PlayingCard(Rank.five, Suit.clubs),
          PlayingCard(Rank.five, Suit.diamonds),
          PlayingCard(Rank.five, Suit.hearts),
          PlayingCard(Rank.seven, Suit.clubs),
          PlayingCard(Rank.seven, Suit.spades),
          PlayingCard(Rank.nine, Suit.clubs),
          PlayingCard(Rank.nine, Suit.hearts),
          PlayingCard(Rank.jack, Suit.diamonds),
          PlayingCard(Rank.jack, Suit.spades),
          PlayingCard(Rank.king, Suit.hearts),
        ]);

    /// 13 cards, one of every rank: the most fragmented hand there is.
    GoFishState thirteenSingletons() => withHand([
          for (var i = 0; i < Rank.values.length; i++)
            PlayingCard(Rank.values[i], Suit.values[i % 4]),
        ]);

    /// The table sizes a phone gives the board once the host's chrome is
    /// out of the way, from a short iPhone SE-class area up to a Pro Max.
    const sizes = [
      Size(343, 440),
      Size(343, 542),
      Size(361, 654),
      Size(408, 755),
    ];

    /// Hand trays reach this far below the cards; the table's last band ends
    /// 16pt above its bottom edge.
    const trayPad = 4.0;
    const bottomMargin = 16.0;

    void expectFits(WidgetTester tester, Size size, String why) {
      expect(tester.takeException(), isNull, reason: '$why: layout threw');
      final rects = tester.getRectList(handCards()).toList();
      expect(rects, isNotEmpty);

      final bottom = rects.map((r) => r.bottom).reduce(math.max) + trayPad;
      expect(bottom, lessThanOrEqualTo(size.height - bottomMargin + 0.5),
          reason: '$why: the hand runs ${bottom - size.height + bottomMargin}'
              'pt past the bottom margin');
      for (final r in rects) {
        expect(r.left, greaterThanOrEqualTo(0), reason: '$why: clipped left');
        expect(r.right, lessThanOrEqualTo(size.width + 0.01),
            reason: '$why: clipped right');
      }

      // Nothing the hand reaches up into: the ask button and the pond.
      final handTop = rects.map((r) => r.top).reduce(math.min) - 16;
      final ask = tester.getRect(find.text('Pick a rank to ask for'));
      expect(handTop, greaterThanOrEqualTo(ask.bottom),
          reason: '$why: the hand reaches into the ask button');
      final pondBottom = tester
          .getRectList(faceDownCards())
          .map((r) => r.bottom)
          .reduce(math.max);
      expect(handTop, greaterThanOrEqualTo(pondBottom),
          reason: '$why: the hand reaches into the pond');

      // Two rows never overlap each other.
      for (final a in rects) {
        for (final b in rects) {
          if ((a.top - b.top).abs() < 1) continue;
          expect(a.overlaps(b), isFalse, reason: '$why: rows overlap');
        }
      }
    }

    final hands = <String, GoFishState Function()>{
      '7 cards in 6 groups': sevenInSixGroups,
      '13 cards in 6 groups': thirteenInSixGroups,
      '13 singletons': thirteenSingletons,
    };

    for (final size in sizes) {
      for (final entry in hands.entries) {
        testWidgets('${entry.key} fits ${size.width}x${size.height}',
            (tester) async {
          await pumpTable(tester, entry.value(), size);
          expectFits(tester, size, '${entry.key} @ $size');
        });
      }
    }

    testWidgets('with a book on each side the 7-card hand still fits',
        (tester) async {
      const size = Size(343, 542);
      await pumpTable(tester, sevenInSixGroups(withBooks: true), size);
      expectFits(tester, size, '7 cards + books @ $size');
    });

    testWidgets('a tall table keeps the full-size hand cards', (tester) async {
      // The height pass must not touch a table that already has the room.
      await pumpTable(tester, sevenInSixGroups(), const Size(402, 874));
      for (final card in tester.widgetList<CardView>(handCards())) {
        expect(card.width, closeTo(66, 0.01));
      }
    });

    testWidgets('a hand that settles on one row hands the pond its size back',
        (tester) async {
      // 343x440: two rows cannot fit at any readable size, so the hand stays
      // on one row (width-bound, ~38pt). The pond and backs were squeezed to
      // find room for two rows; with one row there is room to spare, so they
      // return to their natural size.
      await pumpTable(tester, sevenInSixGroups(), const Size(343, 440));
      final tops =
          tester.getRectList(handCards()).map((r) => r.top.round()).toSet();
      expect(tops, hasLength(1));
      for (final card in tester.widgetList<CardView>(handCards())) {
        expect(card.width, closeTo(38.4, 0.1));
      }
      final pond = tester
          .widgetList<CardView>(faceDownCards())
          .map((c) => c.width)
          .reduce(math.max);
      expect(pond, closeTo(440 * 0.125, 0.01));
    });

    testWidgets('the hand gives up to the floor before the pond shrinks',
        (tester) async {
      // 343x542: the natural two rows (66pt) do not fit, so the hand comes
      // down to the readable floor and the pond gives the rest.
      await pumpTable(tester, sevenInSixGroups(), const Size(343, 542));
      for (final card in tester.widgetList<CardView>(handCards())) {
        expect(card.width, closeTo(52, 0.01));
      }
      final pond = tester
          .widgetList<CardView>(faceDownCards())
          .map((c) => c.width)
          .reduce(math.max);
      expect(pond, lessThan(542 * 0.125),
          reason: 'the pond should have given up some of its natural size');
      expect(pond, greaterThanOrEqualTo(46 - 0.01));
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
