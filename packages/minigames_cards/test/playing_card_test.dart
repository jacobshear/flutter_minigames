import 'package:flutter_test/flutter_test.dart';
import 'package:minigames_cards/minigames_cards.dart';

void main() {
  group('Rank', () {
    test('ordinals run ace-low 1..13', () {
      expect(Rank.ace.ordinal, 1);
      expect(Rank.ten.ordinal, 10);
      expect(Rank.king.ordinal, 13);
      expect(
        Rank.values.map((r) => r.ordinal),
        List.generate(13, (i) => i + 1),
      );
    });

    test('ace-high ordering promotes only the ace', () {
      expect(Rank.ace.aceHighOrdinal, 14);
      expect(Rank.king.aceHighOrdinal, 13);
      for (final r in Rank.values.where((r) => r != Rank.ace)) {
        expect(r.aceHighOrdinal, r.ordinal);
      }
    });

    test('pip value: ace 1, faces 10, others face value', () {
      expect(Rank.ace.pipValue, 1);
      expect(Rank.seven.pipValue, 7);
      expect(Rank.ten.pipValue, 10);
      expect(Rank.jack.pipValue, 10);
      expect(Rank.queen.pipValue, 10);
      expect(Rank.king.pipValue, 10);
    });

    test('blackjack value: ace 11, faces 10', () {
      expect(Rank.ace.blackjackValue, 11);
      expect(Rank.king.blackjackValue, 10);
      expect(Rank.nine.blackjackValue, 9);
    });

    test('fromOrdinal / fromCode round-trip', () {
      for (final r in Rank.values) {
        expect(Rank.fromOrdinal(r.ordinal), r);
        expect(Rank.fromCode(r.code), r);
        expect(Rank.fromCode(r.label), r);
      }
      expect(Rank.fromCode('10'), Rank.ten);
      expect(Rank.fromCode('t'), Rank.ten);
      expect(() => Rank.fromOrdinal(0), throwsRangeError);
      expect(() => Rank.fromCode('Z'), throwsFormatException);
    });
  });

  group('Suit', () {
    test('red/black split', () {
      expect(Suit.hearts.isRed, isTrue);
      expect(Suit.diamonds.isRed, isTrue);
      expect(Suit.clubs.isBlack, isTrue);
      expect(Suit.spades.isBlack, isTrue);
    });

    test('parses letters and symbols', () {
      expect(Suit.fromLetter('s'), Suit.spades);
      expect(Suit.fromLetter('♥'), Suit.hearts);
      expect(() => Suit.fromLetter('X'), throwsFormatException);
    });
  });

  group('PlayingCard', () {
    test('index is a bijection with 0..51', () {
      final seen = <int>{};
      for (var i = 0; i < 52; i++) {
        final c = PlayingCard.fromIndex(i);
        expect(c.index, i);
        expect(seen.add(i), isTrue);
      }
      expect(seen.length, 52);
      expect(() => PlayingCard.fromIndex(52), throwsRangeError);
    });

    test('equality and hashCode are value-based', () {
      const a = PlayingCard(Rank.queen, Suit.hearts);
      final b = PlayingCard.parse('QH');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect({a, b}.length, 1);
      expect(a == const PlayingCard(Rank.queen, Suit.spades), isFalse);
    });

    test('codes parse and print', () {
      expect(PlayingCard.parse('AS'), const PlayingCard(Rank.ace, Suit.spades));
      expect(PlayingCard.parse('10d'), const PlayingCard(Rank.ten, Suit.diamonds));
      expect(PlayingCard.parse('TD').code, 'TD');
      expect(const PlayingCard(Rank.king, Suit.clubs).label, 'K♣');
      expect(() => PlayingCard.parse('A'), throwsFormatException);
    });

    test('parseAll reads a hand', () {
      final hand = PlayingCard.parseAll('AS 2S,3S  KH');
      expect(hand.length, 4);
      expect(hand.first, const PlayingCard(Rank.ace, Suit.spades));
      expect(hand.last, const PlayingCard(Rank.king, Suit.hearts));
    });

    test('JSON round-trips through the integer index', () {
      for (var i = 0; i < 52; i++) {
        final c = PlayingCard.fromIndex(i);
        expect(PlayingCard.fromJson(c.toJson()), c);
        expect(PlayingCard.fromJson(c.code), c);
      }
      final hand = PlayingCard.parseAll('AS TD 7C');
      expect(PlayingCard.decodeAll(PlayingCard.encodeAll(hand)), hand);
      expect(() => PlayingCard.fromJson(1.5), throwsFormatException);
    });

    test('sorting: suit-major by default, rank comparators available', () {
      final hand = PlayingCard.parseAll('KH 2S AS 5H AC');
      final bySuit = List.of(hand)..sort();
      expect(bySuit.map((c) => c.code).toList(), ['AC', '5H', 'KH', 'AS', '2S']);

      final byRank = List.of(hand)..sort(PlayingCard.byRankThenSuit);
      expect(byRank.map((c) => c.code).toList(), ['AC', 'AS', '2S', '5H', 'KH']);

      final aceHigh = List.of(hand)..sort(PlayingCard.byRankAceHigh);
      expect(aceHigh.map((c) => c.code).toList(), ['2S', '5H', 'KH', 'AC', 'AS']);
    });

    test('card values delegate to rank', () {
      expect(PlayingCard.parse('KH').pipValue, 10);
      expect(PlayingCard.parse('AS').blackjackValue, 11);
      expect(PlayingCard.parse('AS').isBlack, isTrue);
      expect(PlayingCard.parse('AD').isRed, isTrue);
    });
  });
}
