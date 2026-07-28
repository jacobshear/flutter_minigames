import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_gin_rummy/minigame_gin_rummy.dart';
import 'package:minigames_cards/minigames_cards.dart';

List<PlayingCard> hand(String codes) => PlayingCard.parseAll(codes);

/// Meld as a comparable set of codes, so assertions do not depend on ordering.
Set<String> codesOf(Meld m) => m.cards.map((c) => c.code).toSet();

bool hasMeld(HandAnalysis a, String codes) {
  final want = hand(codes).map((c) => c.code).toSet();
  return a.melds.any((m) => codesOf(m).length == want.length &&
      codesOf(m).containsAll(want));
}

void main() {
  group('Meld validation', () {
    test('sets need 3-4 cards of one rank in distinct suits', () {
      expect(Meld.trySet(hand('7S 7H 7D')), isNotNull);
      expect(Meld.trySet(hand('7S 7H 7D 7C')), isNotNull);
      expect(Meld.trySet(hand('7S 7H')), isNull);
      expect(Meld.trySet(hand('7S 7H 8D')), isNull);
    });

    test('runs need 3+ consecutive cards in one suit', () {
      expect(Meld.tryRun(hand('4C 5C 6C')), isNotNull);
      expect(Meld.tryRun(hand('4C 5C 6C 7C 8C')), isNotNull);
      expect(Meld.tryRun(hand('4C 5C')), isNull);
      expect(Meld.tryRun(hand('4C 5C 7C')), isNull);
      expect(Meld.tryRun(hand('4C 5C 6H')), isNull);
    });

    test('aces are low: A-2-3 is a run, Q-K-A is not', () {
      expect(Meld.tryRun(hand('AS 2S 3S')), isNotNull);
      expect(Meld.tryRun(hand('QS KS AS')), isNull);
      expect(Meld.tryRun(hand('AS KS QS')), isNull);
    });

    test('runs sort ascending, sets sort by suit', () {
      expect(
        Meld.tryRun(hand('6C 4C 5C'))!.cards.map((c) => c.code).toList(),
        ['4C', '5C', '6C'],
      );
      expect(Meld.trySet(hand('7S 7C 7H'))!.cards.first.suit, Suit.clubs);
    });

    test('tryFrom picks whichever kind fits', () {
      expect(Meld.tryFrom(hand('7S 7H 7D'))!.kind, MeldKind.set);
      expect(Meld.tryFrom(hand('4C 5C 6C'))!.kind, MeldKind.run);
      expect(Meld.tryFrom(hand('4C 9H KS')), isNull);
    });

    test('equality is by kind and cards', () {
      expect(Meld.tryRun(hand('4C 5C 6C')), Meld.tryRun(hand('6C 5C 4C')));
      expect(
        Meld.tryRun(hand('4C 5C 6C')).hashCode,
        Meld.tryRun(hand('6C 5C 4C')).hashCode,
      );
      expect(Meld.tryRun(hand('4C 5C 6C')), isNot(Meld.tryRun(hand('5C 6C 7C'))));
    });

    test('JSON round-trips', () {
      for (final m in [
        Meld.trySet(hand('7S 7H 7D 7C'))!,
        Meld.tryRun(hand('AS 2S 3S'))!,
      ]) {
        expect(Meld.fromJson(m.toJson()), m);
      }
      expect(
        () => Meld.fromJson({'kind': 'run', 'cards': [0, 5, 9]}),
        throwsFormatException,
      );
    });
  });

  group('lay-offs', () {
    test('a 3-card set takes a fourth of its rank, a 4-card set takes none', () {
      final three = Meld.trySet(hand('7S 7H 7D'))!;
      expect(three.canExtendWith(PlayingCard.parse('7C')), isTrue);
      expect(three.canExtendWith(PlayingCard.parse('8C')), isFalse);
      expect(three.extend(PlayingCard.parse('7C')).length, 4);

      final four = Meld.trySet(hand('7S 7H 7D 7C'))!;
      expect(four.canExtendWith(PlayingCard.parse('7C')), isFalse);
    });

    test('a run extends at either end, in suit, never wrapping the ace', () {
      final run = Meld.tryRun(hand('4C 5C 6C'))!;
      expect(run.canExtendWith(PlayingCard.parse('3C')), isTrue);
      expect(run.canExtendWith(PlayingCard.parse('7C')), isTrue);
      expect(run.canExtendWith(PlayingCard.parse('8C')), isFalse);
      expect(run.canExtendWith(PlayingCard.parse('3H')), isFalse);

      final low = Meld.tryRun(hand('AC 2C 3C'))!;
      expect(low.canExtendWith(PlayingCard.parse('KC')), isFalse);
      expect(low.canExtendWith(PlayingCard.parse('4C')), isTrue);

      final high = Meld.tryRun(hand('JC QC KC'))!;
      expect(high.canExtendWith(PlayingCard.parse('AC')), isFalse);
      expect(high.canExtendWith(PlayingCard.parse('TC')), isTrue);
    });

    test('layOffTarget finds the first meld that accepts a card', () {
      final melds = [
        Meld.tryRun(hand('4C 5C 6C'))!,
        Meld.trySet(hand('9S 9H 9D'))!,
      ];
      expect(GinRummyMelds.layOffTarget(melds, PlayingCard.parse('7C')), 0);
      expect(GinRummyMelds.layOffTarget(melds, PlayingCard.parse('9C')), 1);
      expect(GinRummyMelds.layOffTarget(melds, PlayingCard.parse('KH')), -1);
    });
  });

  group('deadwood arithmetic', () {
    test('aces 1, faces 10, others pip value', () {
      expect(GinRummyMelds.deadwoodValue(hand('AS')), 1);
      expect(GinRummyMelds.deadwoodValue(hand('TD JH QC KS')), 40);
      expect(GinRummyMelds.deadwoodValue(hand('2S 3H 9D')), 14);
      expect(GinRummyMelds.deadwoodValue(const []), 0);
    });
  });

  group('meld solver', () {
    test('a hand with no melds is all deadwood', () {
      final a = GinRummyMelds.analyse(hand('AS 2C 3D 5H 7C 9S JD KH 4H 6D'));
      expect(a.melds, isEmpty);
      expect(a.deadwood.length, 10);
      expect(a.deadwoodValue, 1 + 2 + 3 + 5 + 7 + 9 + 10 + 10 + 4 + 6);
      expect(a.isGin, isFalse);
      expect(a.canKnock(threshold: 10), isFalse);
      expect(a.canKnock(threshold: 7), isFalse);
    });

    test('a pure gin hand melds everything', () {
      final a = GinRummyMelds.analyse(hand('AS 2S 3S 4S 5H 6H 7H 9D 9C 9H'));
      expect(a.deadwoodValue, 0);
      expect(a.deadwood, isEmpty);
      expect(a.isGin, isTrue);
      expect(a.melds.length, 3);
      expect(a.meldedCards.length, 10);
    });

    test('greedy fails here: the 4-set must break so a run can complete', () {
      // 7S is in both the four 7s and the spade run. Taking the whole set
      // strands 8S 9S (17 deadwood); breaking it melds all six cards.
      final a = GinRummyMelds.analyse(hand('7S 7H 7D 7C 8S 9S KH QD 4C 2H'));
      expect(hasMeld(a, '7H 7D 7C'), isTrue,
          reason: 'the set should drop 7S: $a');
      expect(hasMeld(a, '7S 8S 9S'), isTrue, reason: '$a');
      expect(a.deadwoodValue, 10 + 10 + 4 + 2);
    });

    test('greedy fails here: overlapping run and set, set removes more', () {
      // 4C belongs to either 2C-3C-4C (removes 9) or the three 4s (removes 12).
      final a = GinRummyMelds.analyse(hand('2C 3C 4C 4D 4H KS KH QS 9D 8S'));
      expect(hasMeld(a, '4C 4D 4H'), isTrue, reason: '$a');
      expect(hasMeld(a, '2C 3C 4C'), isFalse, reason: '$a');
      expect(a.deadwoodValue, 2 + 3 + 10 + 10 + 10 + 9 + 8);
    });

    test('a long run is not split when the whole thing is better', () {
      final a = GinRummyMelds.analyse(hand('4H 5H 6H 7H 8H KS KD KC 2C 9S'));
      expect(hasMeld(a, '4H 5H 6H 7H 8H'), isTrue, reason: '$a');
      expect(hasMeld(a, 'KS KD KC'), isTrue, reason: '$a');
      expect(a.deadwoodValue, 2 + 9);
    });

    test('two runs sharing a card keep the higher-value partition', () {
      // 6S can extend 4S-5S or start 6S-7S-8S; the hand holds all of them, so
      // the single 4S..8S run is correct and greedy sub-run picking is not.
      final a = GinRummyMelds.analyse(hand('4S 5S 6S 7S 8S AD 2D KH QC JS'));
      expect(a.melds.length, 1);
      expect(hasMeld(a, '4S 5S 6S 7S 8S'), isTrue, reason: '$a');
      expect(a.deadwoodValue, 1 + 2 + 10 + 10 + 10);
    });

    test('aces low at both ends of the hand', () {
      // A-2-3 melds; Q-K-A does not, so the ace of hearts stays deadwood.
      final a = GinRummyMelds.analyse(hand('AS 2S 3S QH KH AH 5D 6C 8S 9D'));
      expect(hasMeld(a, 'AS 2S 3S'), isTrue, reason: '$a');
      expect(a.melds.length, 1);
      expect(a.deadwood.map((c) => c.code), contains('AH'));
      expect(a.deadwoodValue, 10 + 10 + 1 + 5 + 6 + 8 + 9);
    });

    test('an 11-card hand (mid-turn, before discarding) solves too', () {
      final a = GinRummyMelds.analyse(hand('AS 2S 3S 5H 6H 7H 9D 9C 9H KS QD'));
      expect(a.deadwoodValue, 20);
      expect(a.melds.length, 3);
      // Equal pip values, so the tie-break is deck order: Q♦ before K♠.
      expect(a.deadwood.map((c) => c.code).toList(), ['QD', 'KS']);
    });

    test('deadwood is sorted most expensive first', () {
      final a = GinRummyMelds.analyse(hand('KS 2H 9D AS 4C 5S 8H JD 7C 3D'));
      final values = a.deadwood.map((c) => c.pipValue).toList();
      final descending = List.of(values)..sort((x, y) => y - x);
      expect(values, descending);
    });

    test('candidates include every 3-subset of a four and every sub-run', () {
      final c = GinRummyMelds.candidates(hand('7S 7H 7D 7C'));
      expect(c.length, 5); // the four, plus four threes
      final runs = GinRummyMelds.candidates(hand('4C 5C 6C 7C'));
      expect(runs.length, 3); // 456, 567, 4567
    });

    test('is deterministic — the same hand always analyses identically', () {
      const codes = 'TS TH TD 9S 8S 7S 3C 3D KH 2H';
      final first = GinRummyMelds.analyse(hand(codes));
      for (var i = 0; i < 20; i++) {
        final again = GinRummyMelds.analyse(hand(codes));
        expect(again.melds, first.melds);
        expect(again.deadwood, first.deadwood);
      }
      // …and does not depend on the order the cards arrive in.
      final shuffled = hand(codes).reversed.toList();
      final other = GinRummyMelds.analyse(shuffled);
      expect(other.deadwoodValue, first.deadwoodValue);
      expect(other.melds.toSet(), first.melds.toSet());
    });

    test('empty and tiny hands are handled', () {
      expect(GinRummyMelds.analyse(const []).deadwoodValue, 0);
      expect(GinRummyMelds.analyse(hand('AS KH')).deadwoodValue, 11);
    });

    test('brute force agrees with the solver on random hands', () {
      // Independent check: enumerate every subset partition the slow way for a
      // handful of seeded hands and confirm the memoised search matches.
      for (var seed = 0; seed < 40; seed++) {
        final deck = CardDeck.shuffled(seed);
        final h = deck.take(10).toList();
        final fast = GinRummyMelds.analyse(h);
        final slow = _bruteForceDeadwood(h);
        expect(fast.deadwoodValue, slow, reason: 'seed $seed: $h');
      }
    });
  });
}

/// Exhaustive reference implementation: try every subset of candidate melds
/// that is pairwise disjoint. Exponential and only used to check the fast path.
int _bruteForceDeadwood(List<PlayingCard> cards) {
  final candidates = GinRummyMelds.candidates(cards);
  final masks = <int>[];
  for (final meld in candidates) {
    var mask = 0;
    final used = <int>{};
    for (final c in meld.cards) {
      for (var i = 0; i < cards.length; i++) {
        if (!used.contains(i) && cards[i] == c) {
          used.add(i);
          mask |= 1 << i;
          break;
        }
      }
    }
    masks.add(mask);
  }
  final total = CardDeck.pipTotal(cards);
  var bestRemoved = 0;

  void walk(int index, int usedMask, int removed) {
    if (removed > bestRemoved) bestRemoved = removed;
    for (var i = index; i < masks.length; i++) {
      if (masks[i] & usedMask != 0) continue;
      var value = 0;
      for (var b = 0; b < cards.length; b++) {
        if (masks[i] & (1 << b) != 0) value += cards[b].pipValue;
      }
      walk(i + 1, usedMask | masks[i], removed + value);
    }
  }

  walk(0, 0, 0);
  return total - bestRemoved;
}
