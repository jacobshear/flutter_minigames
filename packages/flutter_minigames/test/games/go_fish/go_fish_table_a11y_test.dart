import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_minigames/src/cards/cards.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/go_fish/go_fish.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

/// The hand is painted trays with no text a screen reader can reach, and the
/// "{name} to ask" pill restates what a host's own header already says. These
/// pin the labels, that activating a tray picks the rank a tap would, and the
/// host seam.
void main() {
  const game = GoFishGame();

  /// Seat 0 holds 2-2-2, 7-7, K-K; the opponent holds seven singletons and
  /// the pond two cards.
  GoFishState state({
    int current = 0,
    List<List<PlayingCard>>? hands,
  }) =>
      GoFishState(
        playerIds: const ['p1', 'p2'],
        hands: hands ??
            const [
              [
                PlayingCard(Rank.two, Suit.clubs),
                PlayingCard(Rank.two, Suit.diamonds),
                PlayingCard(Rank.two, Suit.hearts),
                PlayingCard(Rank.seven, Suit.clubs),
                PlayingCard(Rank.seven, Suit.diamonds),
                PlayingCard(Rank.king, Suit.spades),
                PlayingCard(Rank.king, Suit.clubs),
              ],
              [
                PlayingCard(Rank.three, Suit.hearts),
                PlayingCard(Rank.five, Suit.spades),
                PlayingCard(Rank.nine, Suit.diamonds),
                PlayingCard(Rank.jack, Suit.hearts),
                PlayingCard(Rank.four, Suit.spades),
                PlayingCard(Rank.six, Suit.clubs),
                PlayingCard(Rank.eight, Suit.diamonds),
              ],
            ],
        pond: const [
          PlayingCard(Rank.ace, Suit.diamonds),
          PlayingCard(Rank.ace, Suit.hearts),
        ],
        books: const [[], []],
        currentIndex: current,
        lastEvent: const GoFishEvent(action: GoFishAction.deal),
      );

  Future<MatchController<GoFishState, GoFishMove>> pump(
    WidgetTester tester, {
    int current = 0,
    bool host = false,
    bool reduceMotion = false,
    List<List<PlayingCard>>? hands,
  }) async {
    final s = state(current: current, hands: hands);
    final transport = LocalTransport();
    final match = Match(
      id: 'gf-a11y-$current',
      gameId: game.id,
      playerIds: s.playerIds,
      currentPlayerId: s.currentPlayerId,
      status: MatchStatus.open,
      turnCount: 0,
      state: game.encodeState(s),
      schemaVersion: game.stateSchemaVersion,
    );
    await transport.createMatch(match);
    final controller = MatchController<GoFishState, GoFishMove>(
      game: game,
      transport: transport,
      matchId: match.id,
      localPlayerId: 'p1',
      // Hot seat keeps the local seat acting; a remote match with the other
      // seat to move is how "not my turn" is staged.
      hotSeat: current == 0,
    );
    await controller.connect();
    addTearDown(controller.dispose);

    const size = Size(361, 654);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Material(
          child: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: GameHostChrome(
                hostOwnsStatus: host,
                child: GoFishTable(
                  controller: controller,
                  style: const GoFishStyle(handoffCover: false),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));
    return controller;
  }

  group('semantics', () {
    testWidgets('trays, pond and the opponent are labelled', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(find.bySemanticsLabel('Twos, 3 cards. Ask for twos.'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Sevens, 2 cards. Ask for sevens.'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Kings, 2 cards. Ask for kings.'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Pond, 2 cards'), findsOneWidget);
      expect(find.bySemanticsLabel('Player 2 has 7 cards'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('activating a tray picks that rank, then the ask goes through',
        (tester) async {
      final handle = tester.ensureSemantics();
      final controller = await pump(tester);

      final tray = find.bySemanticsLabel('Sevens, 2 cards. Ask for sevens.');
      final node = tester.getSemantics(tray).getSemanticsData();
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isSelected, isNot(Tristate.isTrue));

      tester.semantics
          .tap(find.semantics.byLabel('Sevens, 2 cards. Ask for sevens.'));
      await tester.pump();
      expect(
        tester
            .getSemantics(
                find.bySemanticsLabel('Sevens, 2 cards. Ask for sevens.'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );

      // The action button now names the rank, aloud as well as on screen.
      final ask = find.bySemanticsLabel('Ask for sevens');
      expect(ask, findsOneWidget);
      expect(tester.getSemantics(ask).getSemanticsData().flagsCollection.isButton,
          isTrue);
      tester.semantics.tap(find.semantics.byLabel('Ask for sevens'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.state!.lastEvent.action, isNot(GoFishAction.deal),
          reason: 'the ask never reached the game');
      handle.dispose();
    });

    testWidgets('a tray does not offer to ask when it is not your turn',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, current: 1);
      expect(find.bySemanticsLabel('Sevens, 2 cards.'), findsOneWidget);
      expect(find.bySemanticsLabel('Sevens, 2 cards. Ask for sevens.'),
          findsNothing);
      handle.dispose();
    });
  });

  group('hostOwnsStatus', () {
    testWidgets('without a host the table says whose turn it is',
        (tester) async {
      await pump(tester, current: 1);
      expect(find.text('Player 2 to ask'), findsOneWidget);
    });

    testWidgets('with a host that pill is left to the host', (tester) async {
      await pump(tester, current: 1, host: true);
      expect(find.textContaining('to ask'), findsNothing);
    });

    testWidgets('with a host my own prompt to pick a rank stays',
        (tester) async {
      await pump(tester, host: true);
      expect(find.text('Pick a rank to ask for'), findsOneWidget);
    });
  });

  group('Reduce Motion', () {
    /// The books painter's pulse, read off the live widget tree.
    double bookPulse(WidgetTester tester) {
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .where((p) => p.runtimeType.toString() == '_BooksPainter');
      expect(painters, isNotEmpty);
      return painters.map((p) => (p as dynamic).pulse as double).reduce(
          (a, b) => a > b ? a : b);
    }

    /// P1 holds three sevens and asks for the fourth, which closes a book.
    Future<double> pulseAfterBook(WidgetTester tester,
        {required bool reduce}) async {
      final controller = await pump(
        tester,
        reduceMotion: reduce,
        hands: const [
          [
            PlayingCard(Rank.seven, Suit.clubs),
            PlayingCard(Rank.seven, Suit.diamonds),
            PlayingCard(Rank.seven, Suit.hearts),
            PlayingCard(Rank.two, Suit.clubs),
          ],
          [
            PlayingCard(Rank.seven, Suit.spades),
            PlayingCard(Rank.five, Suit.spades),
          ],
        ],
      );
      controller.submitMove(GoFishMove.ask(Rank.seven));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));
      return bookPulse(tester);
    }

    testWidgets('a closed book pulses normally', (tester) async {
      expect(await pulseAfterBook(tester, reduce: false), greaterThan(0));
    });

    testWidgets('and holds still under Reduce Motion', (tester) async {
      expect(await pulseAfterBook(tester, reduce: true), 0);
    });
  });
}
