import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/cards/cards.dart';

void main() {
  group('CardDeck', () {
    test('standard deck is 52 distinct cards in sorted order', () {
      final deck = CardDeck.standard();
      expect(deck.length, 52);
      expect(deck.toSet().length, 52);
      expect(deck.first, const PlayingCard(Rank.ace, Suit.clubs));
      expect(deck.last, const PlayingCard(Rank.king, Suit.spades));
      final sorted = List.of(deck)..sort();
      expect(deck, sorted);
    });

    test('shuffle keeps every card exactly once', () {
      for (final seed in [0, 1, 42, -7, 999983, 0x7FFFFFFF]) {
        final deck = CardDeck.shuffled(seed);
        expect(deck.length, 52, reason: 'seed $seed');
        expect(deck.toSet().length, 52, reason: 'seed $seed');
        final counts = <int, int>{};
        for (final c in deck) {
          counts[c.index] = (counts[c.index] ?? 0) + 1;
        }
        expect(counts.values.every((n) => n == 1), isTrue,
            reason: 'seed $seed');
      }
    });

    test('shuffle is deterministic per seed and differs across seeds', () {
      final a = CardDeck.shuffled(12345);
      final b = CardDeck.shuffled(12345);
      final c = CardDeck.shuffled(12346);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('shuffle is pinned — seed 1 deals this exact deck', () {
      // Guards the splitmix constants: changing them silently invalidates
      // every stored match, so the expected order is written down here.
      final codes = CardDeck.shuffled(1).map((c) => c.code).join(' ');
      expect(
        codes,
        _seed1Order,
        reason: 'CardRandom constants changed — stored deals would break',
      );
    });

    test('shuffle actually mixes (not near-identity)', () {
      final deck = CardDeck.shuffled(7);
      var fixedPoints = 0;
      for (var i = 0; i < 52; i++) {
        if (deck[i].index == i) fixedPoints++;
      }
      expect(fixedPoints, lessThan(6));
    });

    test('deal takes off the top round-robin and leaves the stock', () {
      final deck = CardDeck.standard();
      final deal = CardDeck.deal(deck, players: 2, perPlayer: 10);
      expect(deal.hands.length, 2);
      expect(deal.hands[0].length, 10);
      expect(deal.hands[1].length, 10);
      expect(deal.stock.length, 32);
      // Top of a sorted deck is K♠; the first card goes to player 0.
      expect(deal.hands[0].first, const PlayingCard(Rank.king, Suit.spades));
      expect(deal.hands[1].first, const PlayingCard(Rank.queen, Suit.spades));
      // Nothing is lost or duplicated.
      final all = {...deal.hands[0], ...deal.hands[1], ...deal.stock};
      expect(all.length, 52);
      // The source deck is untouched.
      expect(deck.length, 52);
    });

    test('deal in blocks is contiguous', () {
      final deal = CardDeck.deal(
        CardDeck.standard(),
        players: 2,
        perPlayer: 3,
        roundRobin: false,
      );
      expect(
        deal.hands[0].map((c) => c.code).toList(),
        ['KS', 'QS', 'JS'],
      );
      expect(
        deal.hands[1].map((c) => c.code).toList(),
        ['TS', '9S', '8S'],
      );
    });

    test('deal rejects impossible requests', () {
      expect(
        () => CardDeck.deal(CardDeck.standard(), players: 6, perPlayer: 10),
        throwsArgumentError,
      );
      expect(
        () => CardDeck.deal(CardDeck.standard(), players: 0, perPlayer: 1),
        throwsRangeError,
      );
    });

    test('pipTotal counts aces low and faces as ten', () {
      expect(CardDeck.pipTotal(PlayingCard.parseAll('AS KH 7D')), 18);
      expect(CardDeck.pipTotal(const []), 0);
    });
  });

  group('CardRandom', () {
    test('same seed, same stream', () {
      final a = CardRandom(99);
      final b = CardRandom(99);
      for (var i = 0; i < 200; i++) {
        expect(a.nextUint32(), b.nextUint32());
      }
    });

    test('stays inside 32 bits', () {
      final r = CardRandom(5);
      for (var i = 0; i < 500; i++) {
        final v = r.nextUint32();
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThanOrEqualTo(0xFFFFFFFF));
      }
    });

    test('nextInt is in range and roughly uniform', () {
      final r = CardRandom(2024);
      final buckets = List<int>.filled(6, 0);
      for (var i = 0; i < 60000; i++) {
        final v = r.nextInt(6);
        expect(v, inInclusiveRange(0, 5));
        buckets[v]++;
      }
      for (final n in buckets) {
        // 10000 expected; a 15% band is far outside plausible noise.
        expect(n, inInclusiveRange(8500, 11500));
      }
    });

    test('derived streams differ but replay from the same seed', () {
      final a = CardRandom.derived(4242, 1).shuffled(CardDeck.standard());
      final b = CardRandom.derived(4242, 1).shuffled(CardDeck.standard());
      final c = CardRandom.derived(4242, 2).shuffled(CardDeck.standard());
      expect(a, b);
      expect(a, isNot(c));
      expect(a.toSet().length, 52);
    });

    test('nextInt rejects non-positive bounds', () {
      expect(() => CardRandom(1).nextInt(0), throwsRangeError);
    });

    test('shuffle reaches every permutation of a small list', () {
      final seen = <String>{};
      for (var seed = 0; seed < 400; seed++) {
        final list = [1, 2, 3];
        CardRandom(seed).shuffle(list);
        seen.add(list.join());
      }
      expect(seen.length, 6);
    });
  });
}

/// The deck `CardRandom(1)` produces. Regenerate only on a deliberate change
/// to the PRNG, and know that it invalidates saved matches.
const String _seed1Order =
    'AS 7S 5C JD 3S AH 7D JC JH 2D KS 5S 3C 6H TH 2S KD 4S 8C 9H 6D 4D 6C 8D '
    '2H 7H QD 7C 9C TC 4H QC AD KC QH 9D 2C JS QS TD 5D 4C 8S 3D 6S TS KH AC '
    '9S 8H 3H 5H';
