/// Two-player Go Fish as a pure [TurnGame].
///
/// ## The rules implemented (and why)
///
/// Go Fish is a folk game, so the published rule sets disagree. This is the
/// Pagat two-hander, which is also what most printed rule cards say:
///
///  * **Deal** — 7 cards each from a standard 52. Everything left is the
///    **pond** (the stock); its **last element is the top**, matching the
///    `minigames_cards` convention.
///  * **The ask** — on your turn you name a rank and the opponent answers. You
///    may only name a rank you **already hold at least one of**. This is the
///    rule casual implementations skip, and skipping it turns the game into
///    blind guessing, so it is enforced in [GoFishGame.validateMove] as well
///    as in the UI (which only offers ranks you hold).
///  * **A hit** — if the opponent holds that rank they hand over **all** of it
///    and you **go again**.
///  * **Go fish** — otherwise you draw the top card of the pond. Pagat's
///    variant: if the card you drew is exactly the rank you asked for, you show
///    it and **go again**; otherwise you keep it and the turn passes. That
///    variant is implemented here because it rewards the one decision the game
///    has (which of your ranks to ask for) and it makes the draw worth watching
///    instead of a dead beat.
///  * **Books** — the moment you hold all four of a rank it is laid down as a
///    **book** worth 1 point. Extraction happens inside the reducer right after
///    the transfer or draw, so a rank can never be booked twice and a book is
///    never something the player has to remember to claim.
///  * **Empty hand** — a player whose hand empties while the pond still has
///    cards immediately draws one, so they can keep asking. (Both seats are
///    topped up, the mover first, so the order is deterministic.) An empty
///    hand is *not* an early win: Go Fish is scored on books, and going out
///    early only means you stop having cards to ask with.
///  * **Empty pond** — a "go fish" with an empty pond simply draws nothing and
///    the turn passes. Play continues as long as any book is still reachable.
///  * **The end** — the game ends when all 13 books are made, or, once the pond
///    is empty, as soon as the two hands share no rank. That second condition
///    is exact rather than a heuristic: with no pond, cards only move on a hit,
///    a hit needs a shared rank, and no shared rank means no state can ever
///    change again. It subsumes "somebody ran out of cards" without needing a
///    separate stalemate counter. Most books wins; equal books is a draw.
///
/// Consequences worth knowing: because an empty hand refills whenever the pond
/// has cards, and because a live game with an empty pond always leaves the
/// mover holding a shared rank, **there is always at least one legal ask while
/// the game is open**. Go Fish never needs a pass move.
library;

import 'package:flutter_minigames/src/cards/cards.dart';
import 'package:flutter_minigames/src/core/core.dart';

/// Cards dealt to each player in the two-handed game.
const int kGoFishHandSize = 7;

/// Books in a full deck — the game ends when all of them are made.
const int kGoFishBookCount = 13;

/// What the last move did, for the UI's benefit. Never read by the rules.
enum GoFishAction {
  /// The opening deal.
  deal,

  /// The ask hit: the opponent handed cards over and the asker goes again.
  caught,

  /// Go fish — the drawn card was not the rank asked for; the turn passed.
  fished,

  /// Go fish — but the drawn card *was* the rank asked for, so the asker
  /// goes again.
  fishedHit,

  /// Go fish with an empty pond: nothing was drawn and the turn passed.
  fishedDry,
}

/// A read-only description of the move that produced the current state.
///
/// The table animates off this — the transfer beat, the "they had three
/// sevens" pill, the book flying down — so it carries the cards involved, not
/// just a verb.
class GoFishEvent {
  final GoFishAction action;

  /// Seat that asked (null only for [GoFishAction.deal]).
  final int? actor;

  /// The rank that was asked for.
  final Rank? rank;

  /// Cards the opponent handed over on a hit. Empty otherwise.
  final List<PlayingCard> taken;

  /// Card drawn from the pond on a go fish, if there was one.
  final PlayingCard? drawn;

  /// Books [actor] completed as a result of this move, in completion order.
  final List<Rank> books;

  /// Seats that were topped up from the pond because their hand had emptied.
  final List<int> refilled;

  const GoFishEvent({
    required this.action,
    this.actor,
    this.rank,
    this.taken = const [],
    this.drawn,
    this.books = const [],
    this.refilled = const [],
  });

  /// The asker kept the turn (a hit, or a go-fish that drew the asked rank).
  bool get keepsTurn =>
      action == GoFishAction.caught || action == GoFishAction.fishedHit;

  Map<String, dynamic> toJson() => {
        'action': action.name,
        if (actor != null) 'actor': actor,
        if (rank != null) 'rank': rank!.ordinal,
        if (taken.isNotEmpty) 'taken': PlayingCard.encodeAll(taken),
        if (drawn != null) 'drawn': drawn!.index,
        if (books.isNotEmpty) 'books': [for (final r in books) r.ordinal],
        if (refilled.isNotEmpty) 'refilled': refilled,
      };

  static GoFishEvent fromJson(Map<String, dynamic> json) => GoFishEvent(
        action: GoFishAction.values.byName(json['action'] as String),
        actor: json['actor'] as int?,
        rank: json['rank'] == null ? null : Rank.fromOrdinal(json['rank'] as int),
        taken: json['taken'] == null
            ? const []
            : List.unmodifiable(PlayingCard.decodeAll(json['taken'])),
        drawn: json['drawn'] == null
            ? null
            : PlayingCard.fromIndex(json['drawn'] as int),
        books: json['books'] == null
            ? const []
            : List.unmodifiable([
                for (final o in (json['books'] as List))
                  Rank.fromOrdinal(o as int),
              ]),
        refilled: json['refilled'] == null
            ? const []
            : List.unmodifiable(
                [for (final s in (json['refilled'] as List)) s as int],
              ),
      );
}

/// One rank's worth of a hand — the unit the table lays out and the player
/// taps to ask.
typedef GoFishGroup = ({Rank rank, List<PlayingCard> cards});

/// Immutable Go Fish state. Every list handed out is unmodifiable; the reducer
/// always builds new ones.
class GoFishState {
  /// Players in seat order. Seat 0 acts first.
  final List<String> playerIds;

  /// `hands[seat]` — the cards a player is holding (books already removed).
  final List<List<PlayingCard>> hands;

  /// The pond. **Last element is the top** — a draw is `removeLast()`.
  final List<PlayingCard> pond;

  /// `books[seat]` — ranks that seat has completed, in completion order.
  final List<List<Rank>> books;

  /// Seat whose turn it is.
  final int currentIndex;

  /// What the previous move did.
  final GoFishEvent lastEvent;

  const GoFishState({
    required this.playerIds,
    required this.hands,
    required this.pond,
    required this.books,
    required this.currentIndex,
    required this.lastEvent,
  });

  String get currentPlayerId => playerIds[currentIndex];

  int seatOf(String playerId) => playerIds.indexOf(playerId);

  /// Books made by both players so far.
  int get booksMade => books[0].length + books[1].length;

  /// Distinct ranks [seat] is holding, in ace-low order — exactly the ranks
  /// that seat may legally ask for.
  List<Rank> askableRanks(int seat) {
    final held = <Rank>{for (final c in hands[seat]) c.rank};
    return [
      for (final r in Rank.values)
        if (held.contains(r)) r,
    ];
  }

  /// Whether [seat] may ask for [rank] (holds at least one).
  bool holds(int seat, Rank rank) => hands[seat].any((c) => c.rank == rank);

  /// [seat]'s hand split into rank groups, ace-low, each group suit-sorted.
  /// Grouping is what makes the ask decision readable, so the reducer owns it
  /// rather than leaving every UI to reinvent it.
  List<GoFishGroup> groupedHand(int seat) {
    final byRank = <Rank, List<PlayingCard>>{};
    for (final c in hands[seat]) {
      (byRank[c.rank] ??= <PlayingCard>[]).add(c);
    }
    return [
      for (final r in Rank.values)
        if (byRank.containsKey(r))
          (
            rank: r,
            cards: List<PlayingCard>.unmodifiable(
              byRank[r]!..sort(PlayingCard.bySuitThenRank),
            ),
          ),
    ];
  }

  /// Ranks both hands hold. While the pond is empty this is the set of moves
  /// that can still change anything — empty means the game is over.
  Set<Rank> get sharedRanks {
    final a = {for (final c in hands[0]) c.rank};
    final b = {for (final c in hands[1]) c.rank};
    return a.intersection(b);
  }

  GoFishState copyWith({
    List<List<PlayingCard>>? hands,
    List<PlayingCard>? pond,
    List<List<Rank>>? books,
    int? currentIndex,
    GoFishEvent? lastEvent,
  }) =>
      GoFishState(
        playerIds: playerIds,
        hands: hands ?? this.hands,
        pond: pond ?? this.pond,
        books: books ?? this.books,
        currentIndex: currentIndex ?? this.currentIndex,
        lastEvent: lastEvent ?? this.lastEvent,
      );
}

/// The only move in Go Fish: name a rank.
///
/// Two-player, so the target is implicit — there is exactly one opponent.
class GoFishMove {
  final Rank rank;

  const GoFishMove.ask(this.rank);

  @override
  bool operator ==(Object other) => other is GoFishMove && other.rank == rank;

  @override
  int get hashCode => rank.hashCode;

  @override
  String toString() => 'GoFishMove.ask(${rank.label})';
}

/// Two-player Go Fish. Pure, seeded, transport-agnostic — see the library
/// doc comment above for the exact rule variant.
class GoFishGame extends TurnGame<GoFishState, GoFishMove> {
  const GoFishGame();

  @override
  String get id => 'go_fish';

  @override
  GoFishState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2, 'Go Fish here is two-handed');
    final deal = CardDeck.deal(
      CardDeck.shuffled(seed),
      players: 2,
      perPlayer: kGoFishHandSize,
    );
    final state = GoFishState(
      playerIds: List.unmodifiable(playerIds),
      hands: [
        List.unmodifiable(CardDeck.sorted(deal.hands[0])),
        List.unmodifiable(CardDeck.sorted(deal.hands[1])),
      ],
      pond: List.unmodifiable(deal.stock),
      books: const [[], []],
      currentIndex: 0,
      lastEvent: const GoFishEvent(action: GoFishAction.deal),
    );
    // A seven-card deal can already contain a book; lay it down before anyone
    // gets a turn rather than making the first ask do it.
    return _settle(state, actor: null, action: GoFishAction.deal);
  }

  @override
  String currentPlayer(GoFishState state) => state.currentPlayerId;

  @override
  bool validateMove(GoFishState state, GoFishMove move, String playerId) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    // The rule most implementations get wrong: you may only ask for a rank you
    // already hold.
    return state.holds(state.currentIndex, move.rank);
  }

  @override
  GoFishState applyMove(GoFishState state, GoFishMove move) {
    final seat = state.currentIndex;
    final opp = 1 - seat;
    final rank = move.rank;

    final taken = [
      for (final c in state.hands[opp])
        if (c.rank == rank) c,
    ];

    if (taken.isNotEmpty) {
      // A hit: every matching card comes over and the asker goes again.
      final hands = _replace(
        state.hands,
        seat: seat,
        cards: [...state.hands[seat], ...taken],
        otherSeat: opp,
        otherCards: [
          for (final c in state.hands[opp])
            if (c.rank != rank) c,
        ],
      );
      return _settle(
        state.copyWith(hands: hands, currentIndex: seat),
        actor: seat,
        action: GoFishAction.caught,
        rank: rank,
        taken: taken,
      );
    }

    if (state.pond.isEmpty) {
      // Go fish with a dry pond: nothing to draw, the turn just passes.
      return _settle(
        state.copyWith(currentIndex: opp),
        actor: seat,
        action: GoFishAction.fishedDry,
        rank: rank,
      );
    }

    final pond = List<PlayingCard>.of(state.pond);
    final drawn = pond.removeLast();
    final hit = drawn.rank == rank;
    final hands = _replace(
      state.hands,
      seat: seat,
      cards: [...state.hands[seat], drawn],
    );
    return _settle(
      state.copyWith(
        hands: hands,
        pond: pond,
        // Pagat variant: fishing up the exact rank you asked for keeps the turn.
        currentIndex: hit ? seat : opp,
      ),
      actor: seat,
      action: hit ? GoFishAction.fishedHit : GoFishAction.fished,
      rank: rank,
      drawn: drawn,
    );
  }

  /// Lay down any completed books, top up empty hands from the pond, and
  /// stamp the event. Everything that happens automatically between moves
  /// lives here so [applyMove] only has to describe the ask itself.
  GoFishState _settle(
    GoFishState next, {
    required int? actor,
    required GoFishAction action,
    Rank? rank,
    List<PlayingCard> taken = const [],
    PlayingCard? drawn,
  }) {
    var hands = [
      List<PlayingCard>.of(next.hands[0]),
      List<PlayingCard>.of(next.hands[1]),
    ];
    final books = [
      List<Rank>.of(next.books[0]),
      List<Rank>.of(next.books[1]),
    ];

    // Only the actor can complete a book — giving cards away never does — but
    // the opening deal has no actor, so sweep both.
    final madeByActor = <Rank>[];
    for (var seat = 0; seat < 2; seat++) {
      final made = _extractBooks(hands[seat]);
      if (made.isEmpty) continue;
      books[seat].addAll(made);
      if (seat == actor) madeByActor.addAll(made);
    }

    // A player with no cards cannot ask, so they draw one back as soon as the
    // pond can spare it. The mover goes first, which keeps it deterministic.
    final pond = List<PlayingCard>.of(next.pond);
    final refilled = <int>[];
    for (final seat in [next.currentIndex, 1 - next.currentIndex]) {
      if (hands[seat].isEmpty && pond.isNotEmpty) {
        hands[seat].add(pond.removeLast());
        refilled.add(seat);
      }
    }

    hands = [
      List<PlayingCard>.unmodifiable(CardDeck.sorted(hands[0])),
      List<PlayingCard>.unmodifiable(CardDeck.sorted(hands[1])),
    ];

    return GoFishState(
      playerIds: next.playerIds,
      hands: hands,
      pond: List.unmodifiable(pond),
      books: [
        List.unmodifiable(books[0]),
        List.unmodifiable(books[1]),
      ],
      currentIndex: next.currentIndex,
      lastEvent: GoFishEvent(
        action: action,
        actor: actor,
        rank: rank,
        taken: List.unmodifiable(taken),
        drawn: drawn,
        books: List.unmodifiable(madeByActor),
        refilled: List.unmodifiable(refilled),
      ),
    );
  }

  /// Removes every complete four-of-a-rank from [hand] (in place) and returns
  /// the ranks booked, ace-low so the order is deterministic.
  static List<Rank> _extractBooks(List<PlayingCard> hand) {
    final counts = <Rank, int>{};
    for (final c in hand) {
      counts[c.rank] = (counts[c.rank] ?? 0) + 1;
    }
    final made = [
      for (final r in Rank.values)
        if (counts[r] == 4) r,
    ];
    if (made.isNotEmpty) {
      hand.removeWhere((c) => made.contains(c.rank));
    }
    return made;
  }

  static List<List<PlayingCard>> _replace(
    List<List<PlayingCard>> hands, {
    required int seat,
    required List<PlayingCard> cards,
    int? otherSeat,
    List<PlayingCard>? otherCards,
  }) {
    final out = [List<PlayingCard>.of(hands[0]), List<PlayingCard>.of(hands[1])];
    out[seat] = cards;
    if (otherSeat != null && otherCards != null) out[otherSeat] = otherCards;
    return out;
  }

  /// Whether the position is dead: no pond, and nothing the two hands could
  /// still trade. See the library doc for why this is exact.
  bool isExhausted(GoFishState state) =>
      state.pond.isEmpty && state.sharedRanks.isEmpty;

  @override
  GameOutcome? outcome(GoFishState state) {
    if (state.booksMade < kGoFishBookCount && !isExhausted(state)) return null;
    final a = state.books[0].length;
    final b = state.books[1].length;
    if (a == b) return const GameOutcome.draw();
    return GameOutcome.win(state.playerIds[a > b ? 0 : 1]);
  }

  @override
  Map<String, dynamic> encodeState(GoFishState state) => {
        'playerIds': state.playerIds,
        'hands': [
          PlayingCard.encodeAll(state.hands[0]),
          PlayingCard.encodeAll(state.hands[1]),
        ],
        'pond': PlayingCard.encodeAll(state.pond),
        'books': [
          [for (final r in state.books[0]) r.ordinal],
          [for (final r in state.books[1]) r.ordinal],
        ],
        'current': state.currentIndex,
        'event': state.lastEvent.toJson(),
      };

  @override
  GoFishState decodeState(Map<String, dynamic> json, int version) {
    final hands = json['hands'] as List;
    final books = json['books'] as List;
    List<Rank> ranks(Object? v) => List.unmodifiable(
          [for (final o in (v as List)) Rank.fromOrdinal(o as int)],
        );
    return GoFishState(
      playerIds: List.unmodifiable(
        [for (final p in (json['playerIds'] as List)) p as String],
      ),
      hands: [
        List.unmodifiable(PlayingCard.decodeAll(hands[0])),
        List.unmodifiable(PlayingCard.decodeAll(hands[1])),
      ],
      pond: List.unmodifiable(PlayingCard.decodeAll(json['pond'])),
      books: [ranks(books[0]), ranks(books[1])],
      currentIndex: json['current'] as int,
      lastEvent: GoFishEvent.fromJson(
        Map<String, dynamic>.from(json['event'] as Map),
      ),
    );
  }

  @override
  Map<String, dynamic> encodeMove(GoFishMove move) => {
        'type': 'ask',
        'rank': move.rank.ordinal,
      };

  @override
  GoFishMove decodeMove(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type != null && type != 'ask') {
      throw ArgumentError('Unknown Go Fish move: $type');
    }
    return GoFishMove.ask(Rank.fromOrdinal(json['rank'] as int));
  }
}
