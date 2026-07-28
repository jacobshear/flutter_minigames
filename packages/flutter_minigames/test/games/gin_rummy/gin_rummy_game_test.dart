import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/gin_rummy/gin_rummy.dart';
import 'package:flutter_minigames/src/cards/cards.dart';
import 'package:flutter_minigames/src/core/core.dart';

/// The hand-built scenarios below are ten-card positions, so they run against
/// the ten-card rule set explicitly — the app's default is now seven. The
/// seven-card deal, its constants and the "nothing assumed ten" checks live in
/// the last three groups, against [game].
const tenCard = GinRummyGame(rules: GinRummyRules.classic);

/// The rule set the app actually deals: seven cards.
const game = GinRummyGame();
const players = ['p1', 'p2'];

List<PlayingCard> cards(String codes) => PlayingCard.parseAll(codes);

/// Cards not already in play, so a hand-built state stays a legal deck.
List<PlayingCard> fillStock(Iterable<PlayingCard> used, int count) {
  final taken = used.toSet();
  final out = <PlayingCard>[];
  for (var i = 0; i < 52 && out.length < count; i++) {
    final c = PlayingCard.fromIndex(i);
    if (!taken.contains(c)) out.add(c);
  }
  return out;
}

/// Builds an arbitrary mid-hand state. The engine is a pure reducer, so a test
/// can drop it straight into the position it wants to check.
GinRummyState state({
  required String hand0,
  required String hand1,
  String discard = 'KS',
  int stockSize = 20,
  int current = 0,
  int dealer = 1,
  GinRummyPhase phase = GinRummyPhase.discard,
  int passes = 0,
  PlayingCard? blocked,
  List<int> scores = const [0, 0],
  List<int> handsWon = const [0, 0],
  int handNumber = 0,
  GinRummyKnock? knock,
}) {
  final h0 = cards(hand0);
  final h1 = cards(hand1);
  final d = cards(discard);
  return GinRummyState(
    playerIds: players,
    hands: [h0, h1],
    stock: fillStock([...h0, ...h1, ...d], stockSize),
    discard: d,
    currentIndex: current,
    dealerIndex: dealer,
    phase: phase,
    openingPasses: passes,
    blockedDiscard: blocked,
    scores: scores,
    handsWon: handsWon,
    handNumber: handNumber,
    seed: 7,
    knock: knock,
  );
}

void main() {
  group('deal', () {
    test('10 cards each, one upcard, the rest in the stock', () {
      final s = tenCard.initialState(seed: 42, playerIds: players);
      expect(s.hands[0].length, 10);
      expect(s.hands[1].length, 10);
      expect(s.discard.length, 1);
      expect(s.stock.length, 31);
      expect(s.phase, GinRummyPhase.upcardOffer);
      expect(tenCard.outcome(s), isNull);
    });

    test('every card is dealt exactly once', () {
      for (final seed in [0, 1, 77, 12345]) {
        final s = tenCard.initialState(seed: seed, playerIds: players);
        final all = [...s.hands[0], ...s.hands[1], ...s.stock, ...s.discard];
        expect(all.length, 52, reason: 'seed $seed');
        expect(all.toSet().length, 52, reason: 'seed $seed');
      }
    });

    test('seat 1 deals, so seat 0 acts first', () {
      final s = tenCard.initialState(seed: 3, playerIds: players);
      expect(s.dealerIndex, 1);
      expect(s.nonDealerIndex, 0);
      expect(s.currentIndex, 0);
      expect(tenCard.currentPlayer(s), 'p1');
    });

    test('the same seed always deals the same hands', () {
      final a = tenCard.initialState(seed: 999, playerIds: players);
      final b = tenCard.initialState(seed: 999, playerIds: players);
      final c = tenCard.initialState(seed: 1000, playerIds: players);
      expect(a.hands[0], b.hands[0]);
      expect(a.stock, b.stock);
      expect(a.hands[0], isNot(c.hands[0]));
    });
  });

  group('opening upcard offer', () {
    test('non-dealer may take the upcard and must then discard', () {
      final s = tenCard.initialState(seed: 5, playerIds: players);
      const move = GinRummyMove.takeUpcard();
      expect(tenCard.validateMove(s, move, 'p1'), isTrue);
      final next = tenCard.applyMove(s, move);
      expect(next.hands[0].length, 11);
      expect(next.discard, isEmpty);
      expect(next.phase, GinRummyPhase.discard);
      expect(next.blockedDiscard, s.upcard);
      expect(next.currentIndex, 0);
    });

    test('a refusal passes the offer to the dealer', () {
      final s = tenCard.initialState(seed: 5, playerIds: players);
      final next = tenCard.applyMove(s, const GinRummyMove.passUpcard());
      expect(next.phase, GinRummyPhase.upcardOffer);
      expect(next.currentIndex, 1);
      expect(next.openingPasses, 1);
      expect(next.hands[0].length, 10);
    });

    test('both refuse: the non-dealer must draw from the stock', () {
      var s = tenCard.initialState(seed: 5, playerIds: players);
      s = tenCard.applyMove(s, const GinRummyMove.passUpcard());
      s = tenCard.applyMove(s, const GinRummyMove.passUpcard());
      expect(s.phase, GinRummyPhase.draw);
      expect(s.currentIndex, 0);
      expect(s.mustDrawFromStock, isTrue);
      expect(tenCard.validateMove(s, const GinRummyMove.drawDiscard(), 'p1'),
          isFalse);
      expect(
          tenCard.validateMove(s, const GinRummyMove.drawStock(), 'p1'), isTrue);

      final drawn = tenCard.applyMove(s, const GinRummyMove.drawStock());
      expect(drawn.phase, GinRummyPhase.discard);
      expect(drawn.mustDrawFromStock, isFalse);
      expect(drawn.openingPasses, 0);
      expect(drawn.blockedDiscard, isNull);
    });

    test('draw/discard moves are illegal during the offer', () {
      final s = tenCard.initialState(seed: 5, playerIds: players);
      expect(tenCard.validateMove(s, const GinRummyMove.drawStock(), 'p1'), isFalse);
      expect(
        tenCard.validateMove(s, GinRummyMove.discard(s.hands[0].first), 'p1'),
        isFalse,
      );
    });
  });

  group('turn flow', () {
    test('drawing from the stock moves to the discard phase', () {
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS',
        hand1: 'AC 2C 3C 4C 5C 6C 7C 8C 9C JD',
        discard: 'QH',
        phase: GinRummyPhase.draw,
      );
      final next = tenCard.applyMove(s, const GinRummyMove.drawStock());
      expect(next.hands[0].length, 11);
      expect(next.stock.length, s.stock.length - 1);
      expect(next.phase, GinRummyPhase.discard);
      expect(next.lastAction, GinRummyAction.drawStock);
    });

    test('taking the discard blocks discarding that same card this turn', () {
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C KH KS',
        hand1: 'AC 2C 3C 4C 5C 6C 7C 8C TC JD',
        discard: 'QH',
        phase: GinRummyPhase.draw,
      );
      final took = tenCard.applyMove(s, const GinRummyMove.drawDiscard());
      expect(took.blockedDiscard, PlayingCard.parse('QH'));
      expect(
        tenCard.validateMove(took, GinRummyMove.discard(PlayingCard.parse('QH')),
            'p1'),
        isFalse,
      );
      expect(
        tenCard.validateMove(took, GinRummyMove.discard(PlayingCard.parse('KH')),
            'p1'),
        isTrue,
      );
    });

    test('discarding hands the turn to the opponent', () {
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD',
        hand1: 'AC 2C 3C 4C 5C 6C 7C 8C TC JD',
        phase: GinRummyPhase.discard,
      );
      final next =
          tenCard.applyMove(s, GinRummyMove.discard(PlayingCard.parse('QD')));
      expect(next.currentIndex, 1);
      expect(next.phase, GinRummyPhase.draw);
      expect(next.discard.last, PlayingCard.parse('QD'));
      expect(next.hands[0].length, 10);
      expect(next.blockedDiscard, isNull);
    });

    test('only the player to move may act', () {
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD',
        hand1: 'AC 2C 3C 4C 5C 6C 7C 8C TC JD',
      );
      expect(
        tenCard.validateMove(s, GinRummyMove.discard(PlayingCard.parse('QD')),
            'p2'),
        isFalse,
      );
    });

    test('you cannot discard a card you do not hold', () {
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD',
        hand1: 'AC 2C 3C 4C 5C 6C 7C 8C TC JD',
      );
      expect(
        tenCard.validateMove(s, GinRummyMove.discard(PlayingCard.parse('4H')),
            'p1'),
        isFalse,
      );
    });
  });

  group('knocking', () {
    test('illegal above the threshold, legal at or below it', () {
      // After discarding QD: melds AS-2S-3S, 5H-6H-7H, 9D-9C-9H; deadwood KS =
      // 10, which is exactly the threshold.
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD',
        hand1: 'AC 2C 3C 4C 5C 6C 7C 8C TC JD',
      );
      expect(tenCard.canKnockWith(s, 0, PlayingCard.parse('QD')), isTrue);
      expect(tenCard.deadwoodAfterDiscarding(s, 0, PlayingCard.parse('QD')), 10);

      // Discarding a melded card instead leaves KS + QD = 20.
      expect(tenCard.canKnockWith(s, 0, PlayingCard.parse('9H')), isFalse);
      expect(
        tenCard.validateMove(
          s,
          GinRummyMove.discard(PlayingCard.parse('9H'), knock: true),
          'p1',
        ),
        isFalse,
      );
      expect(
        tenCard.validateMove(
          s,
          GinRummyMove.discard(PlayingCard.parse('QD'), knock: true),
          'p1',
        ),
        isTrue,
      );
    });

    test('a knock with no possible lay-off scores straight away', () {
      // Knocker keeps KS (10 deadwood); the defender holds nothing that
      // extends either meld.
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD',
        hand1: 'TC JC QC 2D 4D 6D 8D TD KD KH',
      );
      final next = tenCard.applyMove(
        s,
        GinRummyMove.discard(PlayingCard.parse('QD'), knock: true),
      );
      expect(next.phase, GinRummyPhase.handOver);
      final r = next.result!;
      expect(r.cancelled, isFalse);
      expect(r.knockerIndex, 0);
      expect(r.knockerDeadwoodValue, 10);
      // Defender melds T-J-Q clubs; deadwood 2+4+6+8+10+10+10 = 50.
      expect(r.defenderDeadwoodValue, 50);
      expect(r.winnerIndex, 0);
      expect(r.points, 40);
      expect(next.scores[0], 40);
      expect(next.handsWon[0], 1);
    });

    test('gin scores the defender deadwood plus the bonus, no lay-offs', () {
      final s = state(
        hand0: 'AS 2S 3S 4S 5H 6H 7H 9D 9C 9H KS',
        hand1: '2H 4C 6C 8H TS JH QD KD 3D 5D',
      );
      final next = tenCard.applyMove(
        s,
        GinRummyMove.discard(PlayingCard.parse('KS'), knock: true),
      );
      expect(next.phase, GinRummyPhase.handOver);
      final r = next.result!;
      expect(r.gin, isTrue);
      expect(r.knockerDeadwoodValue, 0);
      expect(r.laidOff, isEmpty);
      expect(r.winnerIndex, 0);
      expect(r.points, r.defenderDeadwoodValue + 20);
      expect(next.lastAction, GinRummyAction.handScored);
    });

    test('the defender lays off onto the knocker melds', () {
      // Knocker melds 5H-6H-7H and 9D-9C-9H, deadwood 4C = 4.
      // Defender holds 8H (extends the heart run) and 9S (fourth nine).
      final s = state(
        hand0: '5H 6H 7H 9D 9C 9H 4C 2S 3S AS',
        hand1: '8H 9S KD QC JH TS 2D 4D 6D 7D',
        phase: GinRummyPhase.discard,
      );
      final knocked = tenCard.applyMove(
        s.copyWith(hands: [
          [...cards('5H 6H 7H 9D 9C 9H 4C 2S 3S AS'), PlayingCard.parse('KH')],
          cards('8H 9S KD QC JH TS 2D 4D 6D 7D'),
        ]),
        GinRummyMove.discard(PlayingCard.parse('KH'), knock: true),
      );
      expect(knocked.phase, GinRummyPhase.layOff);
      expect(knocked.currentIndex, 1);

      final knock = knocked.knock!;
      expect(knock.gin, isFalse);
      expect(knock.knockerDeadwoodValue, 4);
      expect(knock.hasLayOff, isTrue);

      final runIndex =
          knock.knockerMelds.indexWhere((m) => m.isRun && m.suit == Suit.hearts);
      const eight = GinRummyMove.layOff(PlayingCard(Rank.eight, Suit.hearts), 0);
      expect(
        tenCard.validateMove(
          knocked,
          GinRummyMove.layOff(PlayingCard.parse('8H'), runIndex),
          'p2',
        ),
        isTrue,
      );
      // Wrong meld for that card.
      expect(
        tenCard.validateMove(
          knocked,
          GinRummyMove.layOff(PlayingCard.parse('8H'), 1 - runIndex),
          'p2',
        ),
        isFalse,
      );
      // A card the defender does not hold.
      expect(
        tenCard.validateMove(
          knocked,
          GinRummyMove.layOff(PlayingCard.parse('4H'), runIndex),
          'p2',
        ),
        isFalse,
      );
      expect(eight.card, PlayingCard.parse('8H'));

      final before = knocked.knock!.defenderDeadwoodValue;
      final laid = tenCard.applyMove(
        knocked,
        GinRummyMove.layOff(PlayingCard.parse('8H'), runIndex),
      );
      expect(laid.knock!.defenderDeadwoodValue, before - 8);
      expect(laid.knock!.laidOff, [PlayingCard.parse('8H')]);
      expect(laid.knock!.knockerMelds[runIndex].length, 4);

      final done = tenCard.applyMove(laid, const GinRummyMove.finishLayoff());
      expect(done.phase, GinRummyPhase.handOver);
      expect(done.result!.laidOff.length, 1);
      expect(
        done.result!.points,
        done.result!.defenderDeadwoodValue - 4,
      );
      expect(done.result!.winnerIndex, 0);
    });

    test('undercut: defender matching or beating the knocker scores', () {
      // Knocker leaves 10 deadwood; defender's own deadwood is 3.
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD',
        hand1: 'AC 2C 3C 4D 5D 6D TH JH QH 2H',
      );
      final next = tenCard.applyMove(
        s,
        GinRummyMove.discard(PlayingCard.parse('QD'), knock: true),
      );
      final r = next.result!;
      expect(r.knockerDeadwoodValue, 10);
      expect(r.defenderDeadwoodValue, 2);
      expect(r.undercut, isTrue);
      expect(r.winnerIndex, 1);
      expect(r.points, 10 - 2 + 10);
      expect(next.scores[1], 18);
      expect(next.scores[0], 0);
    });

    test('an equal count still undercuts', () {
      final knock = GinRummyKnock(
        knockerIndex: 0,
        knockerMelds: const [],
        knockerDeadwood: cards('5H'),
        knockerDeadwoodValue: 5,
        gin: false,
        defenderMelds: const [],
        defenderDeadwood: cards('5S'),
        laidOff: const [],
      );
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS',
        hand1: 'AC 2C 3C 4D 5D 6D TH JH QH 5S',
        phase: GinRummyPhase.layOff,
        current: 1,
        knock: knock,
      );
      final done = tenCard.applyMove(s, const GinRummyMove.finishLayoff());
      expect(done.result!.undercut, isTrue);
      expect(done.result!.winnerIndex, 1);
      expect(done.result!.points, 0 + 10);
    });
  });

  group('exhausted stock', () {
    test('a non-knocking discard that leaves two cards cancels the hand', () {
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD',
        hand1: 'AC 2C 3C 4C 5C 6C 7C 8C TC JD',
        stockSize: 2,
      );
      final next =
          tenCard.applyMove(s, GinRummyMove.discard(PlayingCard.parse('QD')));
      expect(next.phase, GinRummyPhase.handOver);
      expect(next.result!.cancelled, isTrue);
      expect(next.result!.winnerIndex, isNull);
      expect(next.scores, [0, 0]);
      expect(next.handsWon, [0, 0]);
    });

    test('a knock at the floor still scores', () {
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD',
        hand1: 'TC JC QC 2D 4D 6D 8D TD KD KH',
        stockSize: 2,
      );
      final next = tenCard.applyMove(
        s,
        GinRummyMove.discard(PlayingCard.parse('QD'), knock: true),
      );
      expect(next.result!.cancelled, isFalse);
      expect(next.result!.winnerIndex, 0);
    });

    test('a cancelled hand is redealt by the same dealer', () {
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD',
        hand1: 'AC 2C 3C 4C 5C 6C 7C 8C TC JD',
        stockSize: 2,
        dealer: 1,
      );
      final over =
          tenCard.applyMove(s, GinRummyMove.discard(PlayingCard.parse('QD')));
      final dealt = tenCard.applyMove(over, const GinRummyMove.nextHand());
      expect(dealt.dealerIndex, 1);
      expect(dealt.handNumber, 1);
      expect(dealt.phase, GinRummyPhase.upcardOffer);
      expect(dealt.hands[0].length, 10);
      expect(dealt.scores, [0, 0]);
    });
  });

  group('match', () {
    test('the deal alternates after a scored hand', () {
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD',
        hand1: 'TC JC QC 2D 4D 6D 8D TD KD KH',
        dealer: 1,
      );
      final over = tenCard.applyMove(
        s,
        GinRummyMove.discard(PlayingCard.parse('QD'), knock: true),
      );
      expect(tenCard.validateMove(over, const GinRummyMove.nextHand(), 'p1') ||
          tenCard.validateMove(over, const GinRummyMove.nextHand(), 'p2'), isTrue);
      final dealt = tenCard.applyMove(over, const GinRummyMove.nextHand());
      expect(dealt.dealerIndex, 0);
      expect(dealt.currentIndex, 1);
      expect(dealt.handNumber, 1);
    });

    test('crossing the target ends the match with box and game bonuses', () {
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD',
        hand1: 'TC JC QC 2D 4D 6D 8D TD KD KH',
        scores: [70, 30],
        handsWon: [2, 1],
      );
      final over = tenCard.applyMove(
        s,
        GinRummyMove.discard(PlayingCard.parse('QD'), knock: true),
      );
      expect(over.phase, GinRummyPhase.matchOver);
      final m = over.matchResult!;
      expect(m.targetReacherIndex, 0);
      expect(m.baseScores, [110, 30]);
      expect(m.shutout, isFalse);
      expect(m.gameBonus, 100);
      expect(m.boxBonuses, [60, 20]); // 3 hands and 1 hand at 20
      expect(m.finalScores, [270, 50]);
      expect(m.winnerIndex, 0);
      expect(tenCard.outcome(over), const GameOutcome.win('p1'));
      expect(
        tenCard.validateMove(over, const GinRummyMove.nextHand(), 'p1'),
        isFalse,
      );
    });

    test('a shutout doubles the game bonus', () {
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD',
        hand1: 'TC JC QC 2D 4D 6D 8D TD KD KH',
        scores: [70, 0],
        handsWon: [2, 0],
      );
      final over = tenCard.applyMove(
        s,
        GinRummyMove.discard(PlayingCard.parse('QD'), knock: true),
      );
      expect(over.matchResult!.shutout, isTrue);
      expect(over.matchResult!.gameBonus, 200);
    });

    test('a short match ends on the first scored hand', () {
      const short = GinRummyGame(rules: GinRummyRules.singleHand);
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD',
        hand1: 'TC JC QC 2D 4D 6D 8D TD KD KH',
      );
      final over = short.applyMove(
        s,
        GinRummyMove.discard(PlayingCard.parse('QD'), knock: true),
      );
      expect(over.phase, GinRummyPhase.matchOver);
      expect(short.outcome(over), isNotNull);
    });

    test('the modern rule set uses 25-point bonuses', () {
      const modern = GinRummyGame(rules: GinRummyRules.modern);
      final s = state(
        hand0: 'AS 2S 3S 4S 5H 6H 7H 9D 9C 9H KS',
        hand1: '2H 4C 6C 8H TS JH QD KD 3D 5D',
      );
      final over = modern.applyMove(
        s,
        GinRummyMove.discard(PlayingCard.parse('KS'), knock: true),
      );
      final r = over.result!;
      expect(r.points, r.defenderDeadwoodValue + 25);
    });
  });

  group('serialization', () {
    test('a fresh state round-trips', () {
      final s = tenCard.initialState(seed: 31337, playerIds: players);
      final back = tenCard.decodeState(tenCard.encodeState(s), 1);
      expect(back.hands[0], s.hands[0]);
      expect(back.hands[1], s.hands[1]);
      expect(back.stock, s.stock);
      expect(back.discard, s.discard);
      expect(back.phase, s.phase);
      expect(back.dealerIndex, s.dealerIndex);
      expect(back.currentIndex, s.currentIndex);
      expect(back.seed, s.seed);
    });

    test('a state carrying a live knock round-trips', () {
      final s = state(
        hand0: '5H 6H 7H 9D 9C 9H 4C 2S 3S AS KH',
        hand1: '8H 9S KD QC JH TS 2D 4D 6D 7D',
      );
      final knocked = tenCard.applyMove(
        s,
        GinRummyMove.discard(PlayingCard.parse('KH'), knock: true),
      );
      expect(knocked.phase, GinRummyPhase.layOff);
      final back = tenCard.decodeState(tenCard.encodeState(knocked), 1);
      expect(back.knock!.knockerIndex, knocked.knock!.knockerIndex);
      expect(back.knock!.knockerMelds, knocked.knock!.knockerMelds);
      expect(back.knock!.defenderDeadwood, knocked.knock!.defenderDeadwood);
      expect(back.knock!.gin, isFalse);
      expect(back.blockedDiscard, knocked.blockedDiscard);
    });

    test('a finished match round-trips with both results', () {
      final s = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD',
        hand1: 'TC JC QC 2D 4D 6D 8D TD KD KH',
        scores: [95, 12],
        handsWon: [3, 1],
      );
      final over = tenCard.applyMove(
        s,
        GinRummyMove.discard(PlayingCard.parse('QD'), knock: true),
      );
      final back = tenCard.decodeState(tenCard.encodeState(over), 1);
      expect(back.phase, GinRummyPhase.matchOver);
      expect(back.result!.points, over.result!.points);
      expect(back.result!.knockerMelds, over.result!.knockerMelds);
      expect(back.matchResult!.finalScores, over.matchResult!.finalScores);
      expect(tenCard.outcome(back), tenCard.outcome(over));
    });

    test('every move kind round-trips', () {
      final moves = <GinRummyMove>[
        const GinRummyMove.takeUpcard(),
        const GinRummyMove.passUpcard(),
        const GinRummyMove.drawStock(),
        const GinRummyMove.drawDiscard(),
        GinRummyMove.discard(PlayingCard.parse('7H')),
        GinRummyMove.discard(PlayingCard.parse('7H'), knock: true),
        GinRummyMove.layOff(PlayingCard.parse('9C'), 2),
        const GinRummyMove.finishLayoff(),
        const GinRummyMove.nextHand(),
      ];
      for (final m in moves) {
        expect(tenCard.decodeMove(tenCard.encodeMove(m)), m, reason: '$m');
      }
      expect(
        () => tenCard.decodeMove({'type': 'nope'}),
        throwsFormatException,
      );
    });
  });

  group('through a MatchController', () {
    test('a hot-seat hand plays start to finish over LocalTransport', () async {
      final transport = LocalTransport();
      addTearDown(transport.dispose);
      final controller =
          await MatchController.create<GinRummyState, GinRummyMove>(
        game: tenCard,
        transport: transport,
        matchId: 'gin-test',
        playerIds: players,
        localPlayerId: 'p1',
        hotSeat: true,
        seed: 2468,
      );
      addTearDown(controller.dispose);

      expect(controller.state!.phase, GinRummyPhase.upcardOffer);
      expect(await controller.submitMove(const GinRummyMove.passUpcard()), isTrue);
      expect(await controller.submitMove(const GinRummyMove.passUpcard()), isTrue);
      expect(controller.state!.phase, GinRummyPhase.draw);

      // A move out of phase is rejected by the controller, not applied.
      expect(
        await controller.submitMove(const GinRummyMove.drawDiscard()),
        isFalse,
      );
      expect(await controller.submitMove(const GinRummyMove.drawStock()), isTrue);

      // Play a few honest turns: discard the highest deadwood card each time.
      for (var turn = 0; turn < 8; turn++) {
        final s = controller.state!;
        if (s.phase == GinRummyPhase.draw) {
          expect(await controller.submitMove(const GinRummyMove.drawStock()),
              isTrue);
        }
        final now = controller.state!;
        if (now.phase != GinRummyPhase.discard) break;
        final analysis = GinRummyMelds.analyse(now.hands[now.currentIndex]);
        final card = analysis.deadwood.isNotEmpty
            ? analysis.deadwood.first
            : now.hands[now.currentIndex].last;
        expect(await controller.submitMove(GinRummyMove.discard(card)), isTrue);
      }

      final end = controller.state!;
      expect(end.hands[0].length + end.hands[1].length, 20);
      final all = [...end.hands[0], ...end.hands[1], ...end.stock, ...end.discard];
      expect(all.toSet().length, 52);
      expect(controller.outcome, isNull);
    });
  });

  // ===========================================================================
  // Seven cards — the deal the app actually uses.
  // ===========================================================================

  group('seven-card deal', () {
    test('the bare GinRummyGame deals seven', () {
      final s = game.initialState(seed: 42, playerIds: players);
      expect(s.hands[0].length, 7);
      expect(s.hands[1].length, 7);
      expect(s.discard.length, 1);
      expect(s.stock.length, 37);
      expect(s.phase, GinRummyPhase.upcardOffer);
      final all = [...s.hands[0], ...s.hands[1], ...s.stock, ...s.discard];
      expect(all.length, 52);
      expect(all.toSet().length, 52);
    });

    test('the derived constants moved with the hand size', () {
      const r = GinRummyRules.sevenCard;
      expect(r.handSize, 7);
      expect(r.knockThreshold, 7);
      // Bonuses that measurement said to leave alone.
      expect(r.ginBonus, GinRummyRules.classic.ginBonus);
      expect(r.boxBonus, GinRummyRules.classic.boxBonus);
      // …and the two that had to move.
      expect(r.undercutBonus, 15);
      expect(r.gameBonus, 90);
      expect(r.shutoutGameBonus, 180);
      expect(r.targetScore, 90);
      // A deck-level rule, not a hand-size one: unchanged on purpose.
      expect(r.stockFloor, GinRummyRules.classic.stockFloor);
      // The whole point of scaling the threshold: it must sit strictly below
      // the value of the most expensive single card, or two melds plus any
      // seventh card would be an automatic knock.
      expect(r.knockThreshold, lessThan(10));
    });

    test('the seventh card decides the knock — 7 knocks, 8 does not', () {
      // Two melds (5H-6H-7H and the three nines) plus one loose card. At the
      // classic threshold of 10 both of these would knock, which is exactly
      // the decision the smaller threshold restores.
      final withSeven = state(
        hand0: '5H 6H 7H 9D 9C 9H 7S QD',
        hand1: 'AC 2C 3C 4D 6D 8D TH',
      );
      final withEight = state(
        hand0: '5H 6H 7H 9D 9C 9H 8S QD',
        hand1: 'AC 2C 3C 4D 6D 8D TH',
      );
      final qd = PlayingCard.parse('QD');

      expect(game.deadwoodAfterDiscarding(withSeven, 0, qd), 7);
      expect(game.canKnockWith(withSeven, 0, qd), isTrue);

      expect(game.deadwoodAfterDiscarding(withEight, 0, qd), 8);
      expect(game.canKnockWith(withEight, 0, qd), isFalse);
      expect(
        game.validateMove(withEight, GinRummyMove.discard(qd, knock: true),
            'p1'),
        isFalse,
      );
      // …and the same 8 is a legal knock under the ten-card threshold, so the
      // difference really is the constant and not the hand.
      expect(8, lessThanOrEqualTo(GinRummyRules.classic.knockThreshold));
    });

    test('canKnockWith rejects a hand that is not handSize + 1', () {
      // A ten-card position handed to the seven-card game: the length guard
      // has to be reading rules.handSize, not a literal.
      final tenCardHand = state(
        hand0: 'AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD',
        hand1: 'TC JC QC 2D 4D 6D 8D TD KD KH',
      );
      expect(
        game.canKnockWith(tenCardHand, 0, PlayingCard.parse('QD')),
        isFalse,
      );
      expect(
        tenCard.canKnockWith(tenCardHand, 0, PlayingCard.parse('QD')),
        isTrue,
      );
    });

    test('gin at seven cards pays the same bonus as the ten-card game', () {
      // 3 + 4 melds everything, which is what gin looks like at this size.
      final s = state(
        hand0: '9D 9C 9H 4S 5S 6S 7S KH',
        hand1: '2H 4C 6C 8H TS JH QD',
      );
      final over = game.applyMove(
        s,
        GinRummyMove.discard(PlayingCard.parse('KH'), knock: true),
      );
      final r = over.result!;
      expect(r.gin, isTrue);
      expect(r.knockerDeadwoodValue, 0);
      expect(r.points, r.defenderDeadwoodValue + 20);
    });

    test('a match ends at 90 with 20-point boxes and a 90-point game bonus',
        () {
      final s = state(
        hand0: '5H 6H 7H 9D 9C 9H 7S QD',
        hand1: 'KC KD KH QS JS TD 8C',
        scores: [84, 12],
        handsWon: [3, 1],
      );
      final over = game.applyMove(
        s,
        GinRummyMove.discard(PlayingCard.parse('QD'), knock: true),
      );
      expect(over.phase, GinRummyPhase.matchOver);
      final m = over.matchResult!;
      expect(m.targetReacherIndex, 0);
      expect(m.gameBonus, 90);
      expect(m.boxBonuses, [4 * 20, 1 * 20]);
      expect(m.winnerIndex, 0);
    });
  });

  group('a full seven-card match', () {
    test('plays to matchOver and never holds more than eight cards', () {
      for (final seed in [1, 8, 99, 4242]) {
        final log = _MatchLog();
        final end = _playMatch(game, seed, log);
        expect(end.phase, GinRummyPhase.matchOver, reason: 'seed $seed');
        expect(end.matchResult, isNotNull, reason: 'seed $seed');
        expect(game.outcome(end), isNotNull, reason: 'seed $seed');

        // The hand-size invariant: seven at rest, eight mid-turn, never ten.
        expect(log.handSizes, unorderedEquals(<int>{7, 8}),
            reason: 'seed $seed saw ${log.handSizes}');
        expect(log.maxStock, 37, reason: 'seed $seed');

        // Somebody crossed the target and the accounting adds up.
        final m = end.matchResult!;
        expect(m.baseScores[m.targetReacherIndex],
            greaterThanOrEqualTo(GinRummyRules.sevenCard.targetScore),
            reason: 'seed $seed');
        for (var i = 0; i < 2; i++) {
          expect(m.boxBonuses[i], end.handsWon[i] * 20, reason: 'seed $seed');
          expect(
            m.finalScores[i],
            m.baseScores[i] +
                m.boxBonuses[i] +
                (i == m.targetReacherIndex ? m.gameBonus : 0),
            reason: 'seed $seed',
          );
        }
      }
    });

    test('runs to a similar length as the ten-card match it was scaled from',
        () {
      // This is what targetScore 90 was picked to hold: the same greedy bot,
      // the same seeds, both hand sizes, and a match that runs about as long.
      // It is also the guard on the counter-intuitive part — per-hand scores
      // barely shrink at seven cards, so scaling the target by the card ratio
      // (to 70) would fail this by a mile.
      const seeds = [1, 8, 99, 4242, 777, 31337, 5, 12, 2024, 68, 404, 909];
      var seven = 0;
      var ten = 0;
      for (final seed in seeds) {
        seven += _playMatch(game, seed, _MatchLog()).handNumber + 1;
        ten += _playMatch(tenCard, seed, _MatchLog()).handNumber + 1;
      }
      final sevenAvg = seven / seeds.length;
      final tenAvg = ten / seeds.length;
      expect(
        sevenAvg,
        inInclusiveRange(tenAvg * 0.75, tenAvg * 1.30),
        reason: 'seven-card match runs $sevenAvg hands, ten-card $tenAvg',
      );
    });
  });

  group('nothing is written against ten cards', () {
    test('the solver finds the non-greedy partition at seven and at ten', () {
      // Same trap both sizes: the four 7s look best until the spade run needs
      // one of them. Greedy takes the set and strands 8S 9S.
      final atSeven = GinRummyMelds.analyse(cards('7S 7H 7D 7C 8S 9S KH'));
      expect(atSeven.melds.length, 2, reason: '$atSeven');
      expect(atSeven.deadwoodValue, 10, reason: '$atSeven');

      final atTen =
          GinRummyMelds.analyse(cards('7S 7H 7D 7C 8S 9S KH QD 4C 2H'));
      expect(atTen.melds.length, 2, reason: '$atTen');
      expect(atTen.deadwoodValue, 10 + 10 + 4 + 2, reason: '$atTen');

      // And the mid-turn sizes either side of both deals.
      expect(GinRummyMelds.analyse(cards('9D 9C 9H 4S 5S 6S 7S')).isGin, isTrue);
      expect(
        GinRummyMelds.analyse(cards('9D 9C 9H 4S 5S 6S 7S KH')).deadwoodValue,
        10,
      );
    });

    test('lay-offs behave identically at seven and at ten', () {
      // The knocker melds a heart run and three nines and keeps 4C; the
      // defender holds 8H (extends the run) and 9S (the fourth nine). The only
      // difference between the two runs is the padding either hand carries.
      final cases = <(GinRummyGame, String, String)>[
        (game, '5H 6H 7H 9D 9C 9H 4C KH', '8H 9S KD QC JH TS 2D'),
        (
          tenCard,
          '5H 6H 7H 9D 9C 9H 4C 2S 3S AS KH',
          '8H 9S KD QC JH TS 2D 4D 6D 7D',
        ),
      ];

      for (final (g, knocker, defender) in cases) {
        final label = 'handSize ${g.rules.handSize}';
        final s = state(hand0: knocker, hand1: defender);
        final knocked = g.applyMove(
          s,
          GinRummyMove.discard(PlayingCard.parse('KH'), knock: true),
        );
        expect(knocked.phase, GinRummyPhase.layOff, reason: label);

        final knock = knocked.knock!;
        expect(knock.gin, isFalse, reason: label);
        expect(knock.knockerDeadwoodValue, 4, reason: label);
        expect(knock.hasLayOff, isTrue, reason: label);

        final run = knock.knockerMelds
            .indexWhere((m) => m.isRun && m.suit == Suit.hearts);
        final set = knock.knockerMelds.indexWhere((m) => m.isSet);
        expect(run, isNot(-1), reason: label);
        expect(set, isNot(-1), reason: label);

        final before = knock.defenderDeadwoodValue;
        var laid = g.applyMove(
          knocked,
          GinRummyMove.layOff(PlayingCard.parse('8H'), run),
        );
        expect(laid.knock!.defenderDeadwoodValue, before - 8, reason: label);
        expect(laid.knock!.knockerMelds[run].length, 4, reason: label);

        laid = g.applyMove(
          laid,
          GinRummyMove.layOff(PlayingCard.parse('9S'), set),
        );
        expect(laid.knock!.defenderDeadwoodValue, before - 17, reason: label);
        expect(laid.knock!.knockerMelds[set].length, 4, reason: label);
        // A fifth nine does not exist, and the set is now full.
        expect(
          g.validateMove(
            laid,
            GinRummyMove.layOff(PlayingCard.parse('KD'), set),
            'p2',
          ),
          isFalse,
          reason: label,
        );

        final done = g.applyMove(laid, const GinRummyMove.finishLayoff());
        expect(done.result!.laidOff.length, 2, reason: label);
        expect(done.result!.points, before - 17 - 4, reason: label);
        expect(done.result!.winnerIndex, 0, reason: label);
      }
    });
  });
}

/// What a scripted match saw along the way — the assertions that would catch a
/// hand-size assumption left behind somewhere in the reducer.
class _MatchLog {
  final Set<int> handSizes = <int>{};
  int maxStock = 0;
}

/// Plays [g] from the deal to [GinRummyPhase.matchOver] with a greedy bot:
/// take the upcard when it lowers your deadwood, shed the most expensive
/// unmelded card, knock the moment it is legal, lay off everything that fits.
GinRummyState _playMatch(GinRummyGame g, int seed, _MatchLog log) {
  var s = g.initialState(seed: seed, playerIds: players);
  for (var guard = 0; guard < 20000; guard++) {
    if (s.phase == GinRummyPhase.matchOver) return s;
    for (final h in s.hands) {
      log.handSizes.add(h.length);
    }
    if (s.stock.length > log.maxStock) log.maxStock = s.stock.length;
    s = g.applyMove(s, _botMove(g, s));
  }
  fail('match did not finish for seed $seed');
}

/// Deadwood the seat would be left with after its best discard.
int _bestAfterDiscard(List<PlayingCard> hand) {
  var best = 1 << 30;
  for (final c in hand) {
    final rest = List<PlayingCard>.of(hand)..remove(c);
    final v = GinRummyMelds.analyse(rest).deadwoodValue;
    if (v < best) best = v;
  }
  return best;
}

GinRummyMove _botMove(GinRummyGame g, GinRummyState s) {
  final seat = s.currentIndex;
  final hand = s.hands[seat];

  switch (s.phase) {
    case GinRummyPhase.upcardOffer:
    case GinRummyPhase.draw:
      final up = s.upcard;
      final wantsUpcard = up != null &&
          !s.mustDrawFromStock &&
          _bestAfterDiscard([...hand, up]) <
              GinRummyMelds.analyse(hand).deadwoodValue;
      if (s.phase == GinRummyPhase.upcardOffer) {
        return wantsUpcard
            ? const GinRummyMove.takeUpcard()
            : const GinRummyMove.passUpcard();
      }
      return wantsUpcard
          ? const GinRummyMove.drawDiscard()
          : const GinRummyMove.drawStock();

    case GinRummyPhase.discard:
      PlayingCard? choice;
      var bestValue = 1 << 30;
      for (final c in hand) {
        if (c == s.blockedDiscard) continue;
        final rest = List<PlayingCard>.of(hand)..remove(c);
        // Lower deadwood first, then shed the more expensive card.
        final v = GinRummyMelds.analyse(rest).deadwoodValue * 100 - c.pipValue;
        if (v < bestValue) {
          bestValue = v;
          choice = c;
        }
      }
      final card = choice ?? hand.first;
      return GinRummyMove.discard(
        card,
        knock: g.canKnockWith(s, seat, card),
      );

    case GinRummyPhase.layOff:
      final knock = s.knock!;
      for (final c in knock.defenderDeadwood) {
        final target = GinRummyMelds.layOffTarget(knock.knockerMelds, c);
        if (target >= 0) return GinRummyMove.layOff(c, target);
      }
      return const GinRummyMove.finishLayoff();

    case GinRummyPhase.handOver:
      return const GinRummyMove.nextHand();

    case GinRummyPhase.matchOver:
      throw StateError('no move at matchOver');
  }
}
