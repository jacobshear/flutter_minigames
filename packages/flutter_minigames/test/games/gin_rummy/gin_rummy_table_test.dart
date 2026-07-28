import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/gin_rummy/gin_rummy.dart';
import 'package:flutter_minigames/src/cards/cards.dart';
import 'package:flutter_minigames/src/core/core.dart';

/// A real phone, because the layout is the thing under test.
const _phone = Size(402, 798);

/// The box the demo shell hands the table on that phone.
const _tablePad = EdgeInsets.fromLTRB(14, 105, 14, 72);

const _flightKey = ValueKey('gin-rummy-flight');

List<PlayingCard> _c(String codes) => PlayingCard.parseAll(codes);

List<PlayingCard> _fill(Iterable<PlayingCard> used, int count) {
  final taken = used.toSet();
  final out = <PlayingCard>[];
  for (var i = 51; i >= 0 && out.length < count; i--) {
    final card = PlayingCard.fromIndex(i);
    if (!taken.contains(card)) out.add(card);
  }
  return out;
}

/// A game whose deal is a fixed position, so a layout test is reproducible.
class _Rigged extends GinRummyGame {
  final GinRummyState Function(List<String> ids) build;

  const _Rigged(this.build, {super.rules});

  @override
  GinRummyState initialState({
    required int seed,
    required List<String> playerIds,
  }) =>
      build(playerIds);
}

/// Mid-hand, about to draw: two melds and some loose cards in both sizes.
GinRummyState _mid(List<String> ids, GinRummyRules rules) {
  final h0 = _c(rules.handSize == 7
      ? '5H 6H 7H 9D 9C 9H KS'
      : '5H 6H 7H 9D 9C 9H KS 2C 4D TS');
  final h1 = _fill(h0, rules.handSize);
  final discard = _c('QS');
  return GinRummyState(
    playerIds: ids,
    hands: [h0, h1],
    stock: _fill([...h0, ...h1, ...discard], 24),
    discard: discard,
    currentIndex: 0,
    dealerIndex: 1,
    phase: GinRummyPhase.draw,
    openingPasses: 1,
    blockedDiscard: null,
    scores: const [24, 31],
    handsWon: const [1, 2],
    handNumber: 3,
    seed: 7,
  );
}

Future<MatchController<GinRummyState, GinRummyMove>> _controller(
  WidgetTester tester,
  GinRummyGame game,
) async {
  final transport = LocalTransport();
  addTearDown(transport.dispose);
  final controller = await MatchController.create<GinRummyState, GinRummyMove>(
    game: game,
    transport: transport,
    matchId: 'table-test',
    playerIds: const ['p1', 'p2'],
    localPlayerId: 'p1',
    hotSeat: true,
    seed: 1,
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _shell(MatchController<GinRummyState, GinRummyMove> c) => MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: _tablePad,
          child: GinRummyTable(controller: c),
        ),
      ),
    );

Future<MatchController<GinRummyState, GinRummyMove>> _pumpTable(
  WidgetTester tester,
  GinRummyRules rules,
) async {
  await tester.binding.setSurfaceSize(_phone);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final game = _Rigged((ids) => _mid(ids, rules), rules: rules);
  final controller = await _controller(tester, game);
  await tester.pumpWidget(_shell(controller));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  group('hand layout', () {
    // The row width used to be computed as one continuous fan across every
    // tray, which is short by (cardW - step) per extra tray — at seven cards
    // and two melds that pushed the second tray off the right edge of the
    // table. Both sizes are checked so the fix cannot be tuned for one.
    for (final rules in [GinRummyRules.sevenCard, GinRummyRules.classic]) {
      testWidgets(
        'every card stays inside the table at handSize ${rules.handSize}',
        (tester) async {
          final controller = await _pumpTable(tester, rules);
          await controller.submitMove(const GinRummyMove.drawStock());
          await tester.pumpAndSettle();

          expect(controller.state!.hands[0].length, rules.handSize + 1);

          final table = tester.getRect(find.byType(GinRummyTable));
          final cards = find.byType(CardView);
          expect(cards, findsWidgets);
          for (var i = 0; i < tester.widgetList(cards).length; i++) {
            final rect = tester.getRect(cards.at(i));
            expect(
              rect.left,
              greaterThanOrEqualTo(table.left - 0.5),
              reason: 'card $i runs off the left edge: $rect vs $table',
            );
            expect(
              rect.right,
              lessThanOrEqualTo(table.right + 0.5),
              reason: 'card $i runs off the right edge: $rect vs $table',
            );
            expect(
              rect.bottom,
              lessThanOrEqualTo(table.bottom + 0.5),
              reason: 'card $i runs off the bottom edge: $rect vs $table',
            );
          }
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'the hand board reaches the bottom of the table at handSize '
        '${rules.handSize}',
        (tester) async {
          // The bottom block is anchored, so a short hand must not leave a
          // band of bare felt underneath it.
          await _pumpTable(tester, rules);
          final table = tester.getRect(find.byType(GinRummyTable));
          final cards = find.byType(CardView);
          var lowest = 0.0;
          for (var i = 0; i < tester.widgetList(cards).length; i++) {
            lowest = lowest > tester.getRect(cards.at(i)).bottom
                ? lowest
                : tester.getRect(cards.at(i)).bottom;
          }
          expect(
            table.bottom - lowest,
            lessThan(30),
            reason: 'the hand floats ${table.bottom - lowest} above the bottom',
          );
        },
      );
    }

    testWidgets('the deadwood count is on screen and follows the hand',
        (tester) async {
      final controller = await _pumpTable(tester, GinRummyRules.sevenCard);
      expect(find.text('DEADWOOD'), findsOneWidget);
      // 5H-6H-7H and the three nines meld; K♠ is the only deadwood.
      expect(find.text('10'), findsOneWidget);

      await controller.submitMove(const GinRummyMove.drawStock());
      await tester.pumpAndSettle();
      // The drawn card either melds or adds to the count; either way the badge
      // shows whatever the solver says, not a stale number.
      final drawn = controller.state!.lastCard!;
      final shown = GinRummyMelds.analyse(controller.state!.hands[0]);
      expect(find.text('${shown.deadwoodValue}'), findsOneWidget);
      expect(shown.deadwoodValue, lessThanOrEqualTo(10 + drawn.pipValue));
    });

    testWidgets('runs and sets are labelled differently in the hand',
        (tester) async {
      await _pumpTable(tester, GinRummyRules.sevenCard);
      expect(find.text('RUN'), findsOneWidget);
      expect(find.text('SET'), findsOneWidget);
      expect(find.text('LOOSE'), findsOneWidget);
    });
  });

  group('card motion', () {
    testWidgets('a draw travels instead of teleporting', (tester) async {
      final controller = await _pumpTable(tester, GinRummyRules.sevenCard);
      expect(find.byKey(_flightKey), findsNothing);

      await controller.submitMove(const GinRummyMove.drawStock());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      final table = tester.getRect(find.byType(GinRummyTable));
      final inAir = find.byKey(_flightKey);
      expect(inAir, findsOneWidget,
          reason: 'the drawn card should be in the air');
      final flying = tester.getRect(find.descendant(
        of: inAir,
        matching: find.byType(CardView),
      ));
      // Somewhere between the piles and the hand, not parked on either.
      expect(flying.center.dy, greaterThan(table.top));
      expect(flying.center.dy, lessThan(table.bottom));

      await tester.pumpAndSettle();
      expect(find.byKey(_flightKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a discard travels to the pile before the handoff cover drops',
        (tester) async {
      final controller = await _pumpTable(tester, GinRummyRules.sevenCard);
      await controller.submitMove(const GinRummyMove.drawStock());
      await tester.pumpAndSettle();

      await controller
          .submitMove(GinRummyMove.discard(PlayingCard.parse('KS')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      expect(find.byKey(_flightKey), findsOneWidget);
      // The cover is owed but must wait: it would otherwise hide the throw.
      expect(find.text('Tap to continue'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byKey(_flightKey), findsNothing);
      expect(find.text('Tap to continue'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposing mid-flight does not throw', (tester) async {
      // Every controller is built in initState; a `late final` field
      // initialiser would run during dispose() and blow up here.
      final controller = await _pumpTable(tester, GinRummyRules.sevenCard);
      await controller.submitMove(const GinRummyMove.drawStock());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('the knock reveal', () {
    testWidgets('animates in and shows both hands and the score',
        (tester) async {
      await tester.binding.setSurfaceSize(_phone);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const rules = GinRummyRules.sevenCard;
      final game = _Rigged((ids) => _mid(ids, rules), rules: rules);
      final controller = await _controller(tester, game);
      await tester.pumpWidget(_shell(controller));
      await tester.pumpAndSettle();

      // Drop a knockable position in and knock with it.
      final knockable = controller.state!.copyWith(
        hands: [_c('5H 6H 7H 9D 9C 9H 4C KH'), _c('8H 9S KD QC JH TS 2D')],
        phase: GinRummyPhase.discard,
      );
      expect(
        game.canKnockWith(knockable, 0, PlayingCard.parse('KH')),
        isTrue,
      );
      final scored = game.applyMove(
        game.applyMove(
          knockable,
          GinRummyMove.discard(PlayingCard.parse('KH'), knock: true),
        ),
        const GinRummyMove.finishLayoff(),
      );
      final match = controller.match!;
      await controller.transport.submitTurn(
        Match(
          id: match.id,
          gameId: match.gameId,
          playerIds: match.playerIds,
          currentPlayerId: game.currentPlayer(scored),
          status: MatchStatus.open,
          turnCount: match.turnCount + 1,
          state: game.encodeState(scored),
          schemaVersion: game.stateSchemaVersion,
        ),
      );

      // Partway through the reveal the panel exists but has not settled.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.textContaining('KNOCKS'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(find.textContaining('KNOCKS'), findsOneWidget);
      expect(find.text('Next hand'), findsOneWidget);
      // Both hands are accounted for, each with its own deadwood badge.
      expect(find.text('DEADWOOD'), findsNWidgets(2));
      expect(find.textContaining('Player 1'), findsWidgets);
      expect(find.textContaining('Player 2'), findsWidgets);

      final table = tester.getRect(find.byType(GinRummyTable));
      final button = tester.getRect(find.text('Next hand'));
      expect(
        table.bottom - button.bottom,
        lessThan(40),
        reason: 'the summary should fill the table, not clump at the top',
      );
    });
  });
}
