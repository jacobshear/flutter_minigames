import 'playing_card.dart';

/// How a card is said aloud — for screen-reader labels, never for rendering.
///
/// The faces are drawn as vectors with no text (see [CardGlyphs]), so a
/// VoiceOver user has nothing to read unless the table labels each card
/// itself. These give every table the same spelling: "Queen of hearts",
/// "7 of clubs".
extension RankSpoken on Rank {
  /// "Ace", "2" … "10", "Jack", "Queen", "King".
  String get spoken => switch (this) {
        Rank.ace => 'Ace',
        Rank.jack => 'Jack',
        Rank.queen => 'Queen',
        Rank.king => 'King',
        _ => label,
      };

  /// Lower-case plural for asking and counting: "aces", "sevens", "sixes".
  String get spokenPlural => switch (this) {
        Rank.ace => 'aces',
        Rank.two => 'twos',
        Rank.three => 'threes',
        Rank.four => 'fours',
        Rank.five => 'fives',
        Rank.six => 'sixes',
        Rank.seven => 'sevens',
        Rank.eight => 'eights',
        Rank.nine => 'nines',
        Rank.ten => 'tens',
        Rank.jack => 'jacks',
        Rank.queen => 'queens',
        Rank.king => 'kings',
      };
}

extension SuitSpoken on Suit {
  /// Lower-case plural: "clubs", "diamonds", "hearts", "spades".
  String get spoken => name;
}

extension PlayingCardSpoken on PlayingCard {
  /// Sentence-case name: "Queen of hearts", "7 of clubs".
  String get spokenName => '${rank.spoken} of ${suit.spoken}';
}
