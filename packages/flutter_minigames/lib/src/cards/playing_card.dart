import 'package:flutter/foundation.dart';

/// The four French suits, ordered the way a sorted deck is dealt out:
/// clubs, diamonds, hearts, spades (bridge order, ascending).
///
/// [Suit.index] is 0..3 and is the suit half of [PlayingCard.index].
enum Suit {
  clubs('C', '♣', false),
  diamonds('D', '♦', true),
  hearts('H', '♥', true),
  spades('S', '♠', false);

  const Suit(this.letter, this.symbol, this.isRed);

  /// Single ASCII letter used in card codes (`'AS'`, `'TD'`).
  final String letter;

  /// Unicode pip, for debug labels only — never for rendering (see
  /// `paintPlayingCard`, which draws pips as vector paths).
  final String symbol;

  /// Hearts and diamonds.
  final bool isRed;

  bool get isBlack => !isRed;

  /// Parses `'C'`/`'c'`/`'♣'` (and the other three) into a suit.
  static Suit fromLetter(String letter) {
    final l = letter.trim().toUpperCase();
    for (final s in Suit.values) {
      if (s.letter == l || s.symbol == l) return s;
    }
    throw FormatException('Not a suit: "$letter"');
  }
}

/// Card ranks in ace-low order, so `Rank.values.indexOf` is also the ace-low
/// sort position.
///
/// Games differ on what a rank is *worth*, so this enum carries the three
/// counts that keep recurring and nothing game-specific:
///  * [ordinal] — 1..13 with ace = 1 (sequence position, aces low)
///  * [pipValue] — ace 1, face cards 10, others [ordinal] (the rummy count)
///  * [blackjackValue] — ace 11, face cards 10, others [ordinal]
enum Rank {
  ace(1, 'A'),
  two(2, '2'),
  three(3, '3'),
  four(4, '4'),
  five(5, '5'),
  six(6, '6'),
  seven(7, '7'),
  eight(8, '8'),
  nine(9, '9'),
  ten(10, '10'),
  jack(11, 'J'),
  queen(12, 'Q'),
  king(13, 'K');

  const Rank(this.ordinal, this.label);

  /// Sequence position with **aces low**: A = 1 … K = 13.
  final int ordinal;

  /// Display label — `'A'`, `'2'` … `'10'`, `'J'`, `'Q'`, `'K'`.
  final String label;

  /// Sequence position with **aces high**: 2 = 2 … K = 13, A = 14.
  /// Use for games where A-K-Q is a run and A beats K.
  int get aceHighOrdinal => this == Rank.ace ? 14 : ordinal;

  /// Ace 1, face cards 10, numbers face value. The rummy count.
  int get pipValue => ordinal > 10 ? 10 : ordinal;

  /// Ace 11, face cards 10, numbers face value. Callers handle the soft-ace
  /// demotion to 1 themselves — that is a hand rule, not a card rule.
  int get blackjackValue => this == Rank.ace ? 11 : pipValue;

  /// Jack, queen or king.
  bool get isFace => ordinal >= 11;

  /// Compact one-character code (ten is `'T'`), used by [PlayingCard.code].
  String get code => this == Rank.ten ? 'T' : label;

  /// Rank from its ace-low [ordinal] (1..13).
  static Rank fromOrdinal(int ordinal) {
    if (ordinal < 1 || ordinal > 13) {
      throw RangeError.range(ordinal, 1, 13, 'ordinal');
    }
    return Rank.values[ordinal - 1];
  }

  /// Parses `'A'`, `'2'`…`'9'`, `'T'` or `'10'`, `'J'`, `'Q'`, `'K'`.
  static Rank fromCode(String code) {
    final c = code.trim().toUpperCase();
    if (c == '10' || c == 'T') return Rank.ten;
    for (final r in Rank.values) {
      if (r.code == c) return r;
    }
    throw FormatException('Not a rank: "$code"');
  }
}

/// One card of a standard 52-card deck: a [rank] and a [suit], nothing else.
///
/// Immutable, `const`-constructible, and identified by [index] (0..51) so
/// equality, hashing, sorting and JSON are all one integer comparison. No game
/// scoring lives here — see [Rank.pipValue] / [Rank.blackjackValue] for the
/// shared counts and put game rules in the game package.
@immutable
class PlayingCard implements Comparable<PlayingCard> {
  final Rank rank;
  final Suit suit;

  const PlayingCard(this.rank, this.suit);

  /// The card at [index] in `suit.index * 13 + rank.index` order (0..51).
  factory PlayingCard.fromIndex(int index) {
    if (index < 0 || index >= 52) {
      throw RangeError.range(index, 0, 51, 'index');
    }
    return PlayingCard(Rank.values[index % 13], Suit.values[index ~/ 13]);
  }

  /// Dense id 0..51. Suit-major, ace-low — the deck's natural sorted order.
  int get index => suit.index * 13 + rank.index;

  /// Ace 1, face 10, else face value.
  int get pipValue => rank.pipValue;

  /// Ace 11, face 10, else face value.
  int get blackjackValue => rank.blackjackValue;

  bool get isRed => suit.isRed;
  bool get isBlack => suit.isBlack;

  /// Two/three-character code: `'AS'`, `'TD'`, `'KH'`.
  String get code => '${rank.code}${suit.letter}';

  /// Human label with the Unicode pip: `'A♠'`. Debug/logging only.
  String get label => '${rank.label}${suit.symbol}';

  /// Parses `'AS'`, `'10D'`, `'td'`, `'K♥'`.
  static PlayingCard parse(String code) {
    final s = code.trim();
    if (s.length < 2) throw FormatException('Not a card: "$code"');
    return PlayingCard(
      Rank.fromCode(s.substring(0, s.length - 1)),
      Suit.fromLetter(s.substring(s.length - 1)),
    );
  }

  /// Parses a whitespace- or comma-separated list: `'AS 2S 3S'`.
  /// The compact way to write a hand in a test.
  static List<PlayingCard> parseAll(String codes) => codes
      .split(RegExp(r'[\s,]+'))
      .where((c) => c.isNotEmpty)
      .map(PlayingCard.parse)
      .toList();

  /// Wire form: the integer [index]. JSON-safe on every platform.
  int toJson() => index;

  /// Accepts either the integer [index] or a [code] string.
  static PlayingCard fromJson(Object json) {
    if (json is int) return PlayingCard.fromIndex(json);
    if (json is String) return PlayingCard.parse(json);
    throw FormatException('Not a card payload: $json');
  }

  /// Encodes a list of cards as a list of [index] ints.
  static List<int> encodeAll(Iterable<PlayingCard> cards) =>
      [for (final c in cards) c.index];

  /// Decodes a JSON list produced by [encodeAll] (ints or code strings).
  static List<PlayingCard> decodeAll(Object? json) => [
        for (final e in (json as List)) PlayingCard.fromJson(e as Object),
      ];

  /// Suit-major, ace-low — the cheap default (`index` comparison).
  @override
  int compareTo(PlayingCard other) => index - other.index;

  /// Suit first, then rank ascending with aces low. Same as [compareTo].
  static int bySuitThenRank(PlayingCard a, PlayingCard b) => a.index - b.index;

  /// Rank ascending with aces **low**, then suit.
  static int byRankThenSuit(PlayingCard a, PlayingCard b) {
    final d = a.rank.ordinal - b.rank.ordinal;
    return d != 0 ? d : a.suit.index - b.suit.index;
  }

  /// Rank ascending with aces **high**, then suit.
  static int byRankAceHigh(PlayingCard a, PlayingCard b) {
    final d = a.rank.aceHighOrdinal - b.rank.aceHighOrdinal;
    return d != 0 ? d : a.suit.index - b.suit.index;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayingCard && other.rank == rank && other.suit == suit);

  @override
  int get hashCode => index;

  @override
  String toString() => label;
}
