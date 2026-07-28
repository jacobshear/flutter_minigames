import 'package:flutter/foundation.dart';
import 'package:flutter_minigames/src/cards/cards.dart';

/// The two ways cards combine in rummy.
enum MeldKind {
  /// Three or four cards of the same rank.
  set,

  /// Three or more cards in sequence in one suit. **Aces are low**: A-2-3 is a
  /// run, Q-K-A is not.
  run,
}

/// A validated group of melded cards.
///
/// Construction goes through [Meld.trySet] / [Meld.tryRun] / [Meld.tryFrom],
/// which return null for anything illegal, so an invalid meld cannot exist.
@immutable
class Meld {
  final MeldKind kind;

  /// Sets: sorted by suit. Runs: sorted ascending, aces low.
  final List<PlayingCard> cards;

  const Meld._(this.kind, this.cards);

  /// A set of 3–4 same-rank cards, or null.
  static Meld? trySet(Iterable<PlayingCard> cards) {
    final list = List<PlayingCard>.of(cards);
    if (list.length < 3 || list.length > 4) return null;
    final rank = list.first.rank;
    if (list.any((c) => c.rank != rank)) return null;
    if (list.map((c) => c.suit).toSet().length != list.length) return null;
    list.sort();
    return Meld._(MeldKind.set, List.unmodifiable(list));
  }

  /// A run of 3+ consecutive same-suit cards (aces low), or null.
  static Meld? tryRun(Iterable<PlayingCard> cards) {
    final list = List<PlayingCard>.of(cards);
    if (list.length < 3) return null;
    final suit = list.first.suit;
    if (list.any((c) => c.suit != suit)) return null;
    list.sort(PlayingCard.byRankThenSuit);
    for (var i = 1; i < list.length; i++) {
      if (list[i].rank.ordinal != list[i - 1].rank.ordinal + 1) return null;
    }
    return Meld._(MeldKind.run, List.unmodifiable(list));
  }

  /// Whichever kind [cards] forms, or null if it forms neither.
  static Meld? tryFrom(Iterable<PlayingCard> cards) =>
      trySet(cards) ?? tryRun(cards);

  bool get isSet => kind == MeldKind.set;
  bool get isRun => kind == MeldKind.run;
  int get length => cards.length;

  /// The shared rank of a set. Meaningless for a run.
  Rank get rank => cards.first.rank;

  /// The shared suit of a run. Meaningless for a set.
  Suit get suit => cards.first.suit;

  /// Lowest ordinal in a run (aces low).
  int get lowOrdinal => cards.first.rank.ordinal;

  /// Highest ordinal in a run.
  int get highOrdinal => cards.last.rank.ordinal;

  /// Whether [card] can be laid off onto this meld: a fourth card of a set's
  /// rank, or a card extending either end of a run. Aces never wrap around
  /// the king.
  bool canExtendWith(PlayingCard card) {
    if (cards.contains(card)) return false;
    if (isSet) return cards.length < 4 && card.rank == rank;
    if (card.suit != suit) return false;
    final o = card.rank.ordinal;
    return o == lowOrdinal - 1 || o == highOrdinal + 1;
  }

  /// This meld with [card] added. Call [canExtendWith] first.
  Meld extend(PlayingCard card) {
    assert(canExtendWith(card), 'illegal lay-off of ${card.code} onto $this');
    final next = [...cards, card];
    return isSet ? trySet(next)! : tryRun(next)!;
  }

  /// Pip total of the melded cards — zero deadwood by definition, but useful
  /// when a UI wants to show what a meld is "worth".
  int get pipValue => CardDeck.pipTotal(cards);

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'cards': PlayingCard.encodeAll(cards),
      };

  static Meld fromJson(Map<String, dynamic> json) {
    final cards = PlayingCard.decodeAll(json['cards']);
    final kind = MeldKind.values.firstWhere((k) => k.name == json['kind']);
    final meld = kind == MeldKind.set ? trySet(cards) : tryRun(cards);
    if (meld == null) {
      throw FormatException('Not a valid ${json['kind']}: $cards');
    }
    return meld;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Meld && other.kind == kind && listEquals(other.cards, cards));

  @override
  int get hashCode => Object.hash(kind, Object.hashAll(cards));

  @override
  String toString() => '${kind.name}(${cards.map((c) => c.code).join(' ')})';
}

/// A hand split into melds plus what is left over.
@immutable
class HandAnalysis {
  /// The melds of the best (minimum-deadwood) partition.
  final List<Meld> melds;

  /// Unmelded cards, sorted high to low so a UI shows the expensive ones
  /// first — those are what a player wants to shed.
  final List<PlayingCard> deadwood;

  /// Pip total of [deadwood]: ace 1, face cards 10, others face value.
  final int deadwoodValue;

  const HandAnalysis({
    required this.melds,
    required this.deadwood,
    required this.deadwoodValue,
  });

  /// Zero deadwood — the whole hand is melded.
  bool get isGin => deadwoodValue == 0;

  /// Whether this hand could knock at [threshold].
  ///
  /// No default: the threshold moves with the hand size (7 at the seven-card
  /// deal, 10 at ten), so a caller that does not say which it means is a bug
  /// waiting to happen. Pass `GinRummyRules.knockThreshold`.
  bool canKnock({required int threshold}) => deadwoodValue <= threshold;

  /// Every melded card, in meld order.
  List<PlayingCard> get meldedCards => [for (final m in melds) ...m.cards];

  @override
  String toString() =>
      'HandAnalysis(melds: $melds, deadwood: ${deadwood.map((c) => c.code)}'
      ' = $deadwoodValue)';
}

/// The meld solver: an exact minimum-deadwood partition of a rummy hand.
///
/// Greedy meld-taking is wrong often enough to lose hands — a 4-card set can
/// be worth less than breaking it so one of its cards completes a run, and two
/// candidate runs can overlap on a single card. So this enumerates every
/// candidate meld and searches all partitions, memoised on the bitmask of
/// still-unassigned cards. Nothing here is written against a particular hand
/// size — the search is over `hand.length` bits, so the 7/8-card seven-card
/// deal and the 10/11-card classic one both cost at most 2^11 states with a
/// few dozen candidates: microseconds, and exact.
abstract final class GinRummyMelds {
  /// Pip total: ace 1, face cards 10, others face value.
  static int deadwoodValue(Iterable<PlayingCard> cards) =>
      CardDeck.pipTotal(cards);

  /// Every meld that could be formed from [hand], including every 3-card
  /// subset of a 4-of-a-kind and every sub-window of a longer run — the
  /// partial forms are exactly what makes overlapping cases solvable.
  static List<Meld> candidates(List<PlayingCard> hand) {
    final out = <Meld>[];

    // Sets.
    final byRank = <Rank, List<PlayingCard>>{};
    for (final c in hand) {
      (byRank[c.rank] ??= []).add(c);
    }
    for (final group in byRank.values) {
      if (group.length < 3) continue;
      if (group.length == 4) {
        final four = Meld.trySet(group);
        if (four != null) out.add(four);
        for (var skip = 0; skip < 4; skip++) {
          final three = [
            for (var i = 0; i < 4; i++)
              if (i != skip) group[i],
          ];
          final meld = Meld.trySet(three);
          if (meld != null) out.add(meld);
        }
      } else {
        final meld = Meld.trySet(group);
        if (meld != null) out.add(meld);
      }
    }

    // Runs.
    final bySuit = <Suit, List<PlayingCard>>{};
    for (final c in hand) {
      (bySuit[c.suit] ??= []).add(c);
    }
    for (final group in bySuit.values) {
      group.sort(PlayingCard.byRankThenSuit);
      var start = 0;
      for (var i = 1; i <= group.length; i++) {
        final broken = i == group.length ||
            group[i].rank.ordinal != group[i - 1].rank.ordinal + 1;
        if (!broken) continue;
        final span = i - start;
        // Every contiguous window of length >= 3 inside this maximal run.
        for (var len = 3; len <= span; len++) {
          for (var from = start; from + len <= i; from++) {
            final meld = Meld.tryRun(group.sublist(from, from + len));
            if (meld != null) out.add(meld);
          }
        }
        start = i;
      }
    }

    return out;
  }

  /// The minimum-deadwood partition of [hand].
  ///
  /// Ties are broken deterministically: fewest deadwood *cards* first (a hand
  /// with the same pip count but more cards melded is strictly better to knock
  /// with), then by the melds' own ordering, so the same hand always analyses
  /// to the same answer on every client.
  static HandAnalysis analyse(List<PlayingCard> hand) {
    if (hand.isEmpty) {
      return const HandAnalysis(melds: [], deadwood: [], deadwoodValue: 0);
    }
    if (hand.length > 30) {
      throw ArgumentError('Hand too large for exhaustive analysis');
    }

    final cards = List<PlayingCard>.of(hand);
    final candidateMelds = candidates(cards);

    // Bitmask per candidate over positions in `cards`. Positions, not card
    // identity, so a duplicated card (multi-deck games later) still works.
    final masks = <int>[];
    for (final meld in candidateMelds) {
      var mask = 0;
      final used = <int>{};
      var ok = true;
      for (final c in meld.cards) {
        var found = -1;
        for (var i = 0; i < cards.length; i++) {
          if (!used.contains(i) && cards[i] == c) {
            found = i;
            break;
          }
        }
        if (found < 0) {
          ok = false;
          break;
        }
        used.add(found);
        mask |= 1 << found;
      }
      masks.add(ok ? mask : 0);
    }

    final pip = [for (final c in cards) c.pipValue];
    final full = (1 << cards.length) - 1;
    final memo = <int, _Partition>{};

    _Partition best(int remaining) {
      if (remaining == 0) return const _Partition(0, 0, []);
      final cached = memo[remaining];
      if (cached != null) return cached;

      // Always decide the lowest remaining card: either it is deadwood, or it
      // belongs to one of the candidate melds that contains it. That makes the
      // recursion cover every partition exactly once.
      final i = _lowestBit(remaining);

      final sub = best(remaining & ~(1 << i));
      var result = _Partition(sub.value + pip[i], sub.count + 1, sub.melds);

      for (var m = 0; m < masks.length; m++) {
        final mask = masks[m];
        if (mask == 0 || mask & (1 << i) == 0) continue;
        if (mask & remaining != mask) continue;
        final rest = best(remaining & ~mask);
        final candidate = _Partition(
          rest.value,
          rest.count,
          [m, ...rest.melds],
        );
        if (candidate.isBetterThan(result)) result = candidate;
      }

      memo[remaining] = result;
      return result;
    }

    final solution = best(full);
    var usedMask = 0;
    for (final m in solution.melds) {
      usedMask |= masks[m];
    }
    final deadwood = <PlayingCard>[
      for (var i = 0; i < cards.length; i++)
        if (usedMask & (1 << i) == 0) cards[i],
    ]..sort((a, b) {
        final d = b.pipValue - a.pipValue;
        return d != 0 ? d : a.index - b.index;
      });

    final melds = [for (final m in solution.melds) candidateMelds[m]]
      ..sort(_meldOrder);

    return HandAnalysis(
      melds: List.unmodifiable(melds),
      deadwood: List.unmodifiable(deadwood),
      deadwoodValue: solution.value,
    );
  }

  /// Whether [card] can be laid off onto any of [melds]; returns the index of
  /// the first meld that accepts it, or -1.
  static int layOffTarget(List<Meld> melds, PlayingCard card) {
    for (var i = 0; i < melds.length; i++) {
      if (melds[i].canExtendWith(card)) return i;
    }
    return -1;
  }

  /// Runs before sets, then by the first card — a stable display order.
  static int _meldOrder(Meld a, Meld b) {
    final d = a.kind.index - b.kind.index;
    if (d != 0) return d;
    return a.cards.first.index - b.cards.first.index;
  }

  static int _lowestBit(int mask) {
    var i = 0;
    while (mask & (1 << i) == 0) {
      i++;
    }
    return i;
  }
}

/// One partition candidate during the search.
@immutable
class _Partition {
  /// Deadwood pip total.
  final int value;

  /// Number of deadwood cards (the tie-break).
  final int count;

  /// Indices into the candidate list, ascending.
  final List<int> melds;

  const _Partition(this.value, this.count, this.melds);

  bool isBetterThan(_Partition other) {
    if (value != other.value) return value < other.value;
    if (count != other.count) return count < other.count;
    // Deterministic final tie-break so every client agrees on the melds.
    for (var i = 0; i < melds.length && i < other.melds.length; i++) {
      if (melds[i] != other.melds[i]) return melds[i] < other.melds[i];
    }
    return melds.length < other.melds.length;
  }
}
