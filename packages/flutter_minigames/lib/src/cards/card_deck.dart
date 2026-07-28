import 'card_random.dart';
import 'playing_card.dart';

/// The result of a deal: one list per player plus whatever is left over.
typedef CardDeal = ({List<List<PlayingCard>> hands, List<PlayingCard> stock});

/// A standard 52-card deck, plus deterministic shuffling and dealing.
///
/// Nothing here is stateful — a "deck" is just a `List<PlayingCard>` whose
/// **last element is the top of the pile** (so drawing is `removeLast()`,
/// which is O(1)). Every card game in this repo uses that convention for
/// stocks and discard piles.
abstract final class CardDeck {
  /// Cards in a standard deck.
  static const int size = 52;

  /// A fresh deck in sorted order: clubs A→K, diamonds, hearts, spades.
  static List<PlayingCard> standard() =>
      List<PlayingCard>.generate(size, PlayingCard.fromIndex, growable: true);

  /// A deck shuffled deterministically from [seed]. The same seed always
  /// produces the same deck — see [CardRandom].
  static List<PlayingCard> shuffled(int seed) {
    final deck = standard();
    CardRandom(seed).shuffle(deck);
    return deck;
  }

  /// Shuffles [cards] in place from [seed]. Use for reshuffling a discard pile
  /// back into the stock mid-match (pass a [CardRandom.derived] stream index so
  /// the reshuffle replays with the match).
  static void shuffleInPlace(List<PlayingCard> cards, int seed) =>
      CardRandom(seed).shuffle(cards);

  /// Deals [perPlayer] cards to [players] hands off the **top** of [deck]
  /// (its end) and returns the hands plus the remaining stock.
  ///
  /// [roundRobin] deals one card at a time around the table (how cards are
  /// actually dealt); `false` deals each hand as a contiguous block. Both are
  /// deterministic; round-robin matches a physical deal, which matters when a
  /// game's rules talk about "the 21st card".
  ///
  /// [deck] is not modified.
  static CardDeal deal(
    List<PlayingCard> deck, {
    required int players,
    required int perPlayer,
    bool roundRobin = true,
  }) {
    if (players < 1) throw RangeError.range(players, 1, null, 'players');
    if (perPlayer < 0) throw RangeError.range(perPlayer, 0, null, 'perPlayer');
    final needed = players * perPlayer;
    if (needed > deck.length) {
      throw ArgumentError(
        'Deal needs $needed cards but the deck holds ${deck.length}',
      );
    }

    final hands = List<List<PlayingCard>>.generate(
      players,
      (_) => <PlayingCard>[],
    );
    // The top of the pile is the end of the list.
    var top = deck.length - 1;
    if (roundRobin) {
      for (var i = 0; i < needed; i++) {
        hands[i % players].add(deck[top--]);
      }
    } else {
      for (var p = 0; p < players; p++) {
        for (var i = 0; i < perPlayer; i++) {
          hands[p].add(deck[top--]);
        }
      }
    }
    return (hands: hands, stock: deck.sublist(0, top + 1));
  }

  /// Total [PlayingCard.pipValue] of [cards] — ace 1, face 10, else face
  /// value. The count rummy reaches for.
  static int pipTotal(Iterable<PlayingCard> cards) =>
      cards.fold(0, (sum, c) => sum + c.pipValue);

  /// A copy of [cards] sorted for display: by suit, then rank (aces low).
  static List<PlayingCard> sorted(
    Iterable<PlayingCard> cards, [
    Comparator<PlayingCard>? by,
  ]) =>
      List<PlayingCard>.of(cards)..sort(by ?? PlayingCard.bySuitThenRank);
}
