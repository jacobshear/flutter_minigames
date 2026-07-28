/// GamePigeon-style Crazy 8s for two players.
///
/// Rules implemented (GP fidelity, deviations documented):
///  * 52-card deck, 8 cards dealt to each player, one card flipped to start
///    the discard pile.
///  * On your turn play a card matching the top card's suit or rank, or any 8.
///  * Playing an 8 declares a suit; the next play must match that suit (or be
///    another 8).
///  * If the flipped starter is an 8 it is a **free-suit start**: any card may
///    be played on it (no declared suit).
///  * You may draw from the stock at any point on your turn (even with a
///    playable card in hand — "choose not to play"); drawing does not end the
///    turn.
///  * When the stock empties, the discard pile minus its top card is
///    reshuffled into the stock. The reshuffle order derives deterministically
///    from the match seed plus a reshuffle counter, so replays stay
///    consistent. Because the check runs after every move, the stock is only
///    ever empty when the discard holds a single card (nothing to reshuffle).
///  * Passing is only legal when the stock is empty AND you hold no playable
///    card. Two consecutive passes end the game: lowest pip count wins
///    (8s = 50, J/Q/K = 10, ace = 1, numbers = face value); equal counts are
///    a draw.
///  * First player to empty their hand wins.
library;

import 'package:flutter_minigames/src/core/core.dart';

/// Card helpers. A card is an int 0..51: `suit = card ~/ 13`,
/// `rank = card % 13` (0 = ace … 7 = eight … 12 = king).
abstract final class CrazyEightsCards {
  static const int spades = 0;
  static const int hearts = 1;
  static const int diamonds = 2;
  static const int clubs = 3;

  static const int deckSize = 52;

  /// Suit index 0..3 for [card].
  static int suitOf(int card) => card ~/ 13;

  /// Rank index 0..12 (0 = ace, 7 = eight, 12 = king) for [card].
  static int rankOf(int card) => card % 13;

  /// Whether [card] is an 8 (the wild rank).
  static bool isEight(int card) => rankOf(card) == 7;

  /// Endgame pip value: 8s 50, J/Q/K 10, ace 1, numbers face value.
  static int pipValue(int card) {
    final rank = rankOf(card);
    if (rank == 7) return 50;
    if (rank >= 10) return 10;
    return rank + 1;
  }

  /// Total pip count of [hand].
  static int pipTotal(Iterable<int> hand) =>
      hand.fold(0, (sum, c) => sum + pipValue(c));

  static const List<String> rankLabels = [
    'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K',
  ];
  static const List<String> suitLabels = ['♠', '♥', '♦', '♣'];

  /// Debug label like `8♥`.
  static String label(int card) =>
      '${rankLabels[rankOf(card)]}${suitLabels[suitOf(card)]}';
}

/// Tiny xorshift32 PRNG so shuffles are deterministic on every platform
/// (dart:math's Random is implementation-defined). 32-bit masked so web is
/// identical to VM.
class _Prng {
  int _s;

  _Prng(int seed) : _s = (seed ^ 0x9E3779B9) & 0xFFFFFFFF {
    if (_s == 0) _s = 0x1F123BB5;
  }

  int _next() {
    var x = _s;
    x = (x ^ (x << 13)) & 0xFFFFFFFF;
    x = (x ^ (x >> 17)) & 0xFFFFFFFF;
    x = (x ^ (x << 5)) & 0xFFFFFFFF;
    _s = x;
    return x;
  }

  int nextInt(int max) => _next() % max;

  /// In-place Fisher–Yates.
  void shuffle(List<int> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }
}

/// What the previous move was, for UI animation cues.
enum CrazyEightsAction { deal, play, draw, pass }

/// Immutable Crazy 8s state. Lists are never mutated after construction.
class CrazyEightsState {
  final List<String> playerIds;

  /// `hands[seat]` — each player's cards.
  final List<List<int>> hands;

  /// Draw pile; **last element is the top** (next card drawn).
  final List<int> stock;

  /// Discard pile; **last element is the face-up top card**.
  final List<int> discard;

  /// Seat index (0/1) whose turn it is.
  final int currentIndex;

  /// Active declared suit after an 8 was played, else null. A null suit with
  /// an 8 on top means the free-suit start (flipped starter).
  final int? declaredSuit;

  /// Consecutive pass moves (2 ends the game on pip count).
  final int passes;

  /// How many deterministic reshuffles have happened.
  final int reshuffles;

  /// Match seed — kept in state so reshuffles replay identically after
  /// decode.
  final int seed;

  /// The previous move, for UI animation.
  final CrazyEightsAction lastAction;

  /// Card involved in [lastAction] (played or drawn), if any.
  final int? lastCard;

  /// Seat that performed [lastAction], if any.
  final int? lastActor;

  const CrazyEightsState({
    required this.playerIds,
    required this.hands,
    required this.stock,
    required this.discard,
    required this.currentIndex,
    required this.declaredSuit,
    required this.passes,
    required this.reshuffles,
    required this.seed,
    this.lastAction = CrazyEightsAction.deal,
    this.lastCard,
    this.lastActor,
  });

  String get currentPlayerId => playerIds[currentIndex];

  /// Top of the discard pile.
  int get topCard => discard.last;

  /// The suit a non-8 play must match right now, or null when any card goes
  /// (free-suit start).
  int? get activeSuit {
    if (declaredSuit != null) return declaredSuit;
    if (CrazyEightsCards.isEight(topCard)) return null; // free-suit start
    return CrazyEightsCards.suitOf(topCard);
  }

  int seatOf(String playerId) => playerIds.indexOf(playerId);
}

enum CrazyEightsMoveType { play, draw, pass }

class CrazyEightsMove {
  final CrazyEightsMoveType type;

  /// The card played (playCard only).
  final int? card;

  /// Declared suit 0..3 — required iff [card] is an 8.
  final int? declaredSuit;

  const CrazyEightsMove.play(int this.card, {this.declaredSuit})
      : type = CrazyEightsMoveType.play;

  const CrazyEightsMove.draw()
      : type = CrazyEightsMoveType.draw,
        card = null,
        declaredSuit = null;

  const CrazyEightsMove.pass()
      : type = CrazyEightsMoveType.pass,
        card = null,
        declaredSuit = null;
}

class CrazyEightsGame extends TurnGame<CrazyEightsState, CrazyEightsMove> {
  const CrazyEightsGame();

  /// Cards dealt to each player (GP deals 8 in Crazy 8s).
  static const int handSize = 8;

  @override
  String get id => 'crazy_eights';

  @override
  CrazyEightsState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2, 'Crazy 8s is 2-player');
    final deck = List<int>.generate(CrazyEightsCards.deckSize, (i) => i);
    _Prng(seed).shuffle(deck);

    final hands = [<int>[], <int>[]];
    for (var i = 0; i < handSize * 2; i++) {
      hands[i % 2].add(deck[i]);
    }
    final starter = deck[handSize * 2];
    final stock = deck.sublist(handSize * 2 + 1);

    return CrazyEightsState(
      playerIds: List.unmodifiable(playerIds),
      hands: [List.unmodifiable(hands[0]), List.unmodifiable(hands[1])],
      stock: List.unmodifiable(stock),
      // Flipped 8 = free-suit start (activeSuit stays null).
      discard: List.unmodifiable([starter]),
      currentIndex: 0,
      declaredSuit: null,
      passes: 0,
      reshuffles: 0,
      seed: seed,
    );
  }

  @override
  String currentPlayer(CrazyEightsState state) => state.currentPlayerId;

  /// Whether [card] may legally be played on the current discard top.
  bool isPlayable(CrazyEightsState state, int card) {
    if (CrazyEightsCards.isEight(card)) return true;
    final active = state.activeSuit;
    if (active == null) return true; // free-suit start
    return CrazyEightsCards.suitOf(card) == active ||
        CrazyEightsCards.rankOf(card) == CrazyEightsCards.rankOf(state.topCard);
  }

  /// Whether [seat] holds at least one playable card.
  bool hasPlayableCard(CrazyEightsState state, int seat) =>
      state.hands[seat].any((c) => isPlayable(state, c));

  /// Pass is legal only when the stock is empty and the current player has
  /// no playable card.
  bool mustPass(CrazyEightsState state) =>
      state.stock.isEmpty && !hasPlayableCard(state, state.currentIndex);

  @override
  bool validateMove(
    CrazyEightsState state,
    CrazyEightsMove move,
    String playerId,
  ) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    final seat = state.currentIndex;

    switch (move.type) {
      case CrazyEightsMoveType.play:
        final card = move.card;
        if (card == null || card < 0 || card >= CrazyEightsCards.deckSize) {
          return false;
        }
        if (!state.hands[seat].contains(card)) return false;
        if (CrazyEightsCards.isEight(card)) {
          final s = move.declaredSuit;
          if (s == null || s < 0 || s > 3) return false;
        } else {
          if (move.declaredSuit != null) return false;
        }
        return isPlayable(state, card);
      case CrazyEightsMoveType.draw:
        return state.stock.isNotEmpty;
      case CrazyEightsMoveType.pass:
        return mustPass(state);
    }
  }

  @override
  CrazyEightsState applyMove(CrazyEightsState state, CrazyEightsMove move) {
    final seat = state.currentIndex;
    switch (move.type) {
      case CrazyEightsMoveType.play:
        final card = move.card!;
        final hand = List<int>.of(state.hands[seat])..remove(card);
        final hands = [
          seat == 0 ? hand : state.hands[0],
          seat == 1 ? hand : state.hands[1],
        ];
        return _reshuffleIfNeeded(CrazyEightsState(
          playerIds: state.playerIds,
          hands: hands,
          stock: state.stock,
          discard: List.unmodifiable([...state.discard, card]),
          currentIndex: 1 - seat,
          declaredSuit:
              CrazyEightsCards.isEight(card) ? move.declaredSuit : null,
          passes: 0,
          reshuffles: state.reshuffles,
          seed: state.seed,
          lastAction: CrazyEightsAction.play,
          lastCard: card,
          lastActor: seat,
        ));
      case CrazyEightsMoveType.draw:
        final stock = List<int>.of(state.stock);
        final drawn = stock.removeLast();
        final hand = List<int>.of(state.hands[seat])..add(drawn);
        final hands = [
          seat == 0 ? hand : state.hands[0],
          seat == 1 ? hand : state.hands[1],
        ];
        return _reshuffleIfNeeded(CrazyEightsState(
          playerIds: state.playerIds,
          hands: hands,
          stock: stock,
          discard: state.discard,
          currentIndex: seat, // drawing does not end the turn
          declaredSuit: state.declaredSuit,
          passes: 0,
          reshuffles: state.reshuffles,
          seed: state.seed,
          lastAction: CrazyEightsAction.draw,
          lastCard: drawn,
          lastActor: seat,
        ));
      case CrazyEightsMoveType.pass:
        return CrazyEightsState(
          playerIds: state.playerIds,
          hands: state.hands,
          stock: state.stock,
          discard: state.discard,
          currentIndex: 1 - seat,
          declaredSuit: state.declaredSuit,
          passes: state.passes + 1,
          reshuffles: state.reshuffles,
          seed: state.seed,
          lastAction: CrazyEightsAction.pass,
          lastActor: seat,
        );
    }
  }

  /// GP reshuffle rule: when the stock empties, the discard minus its top
  /// card is shuffled back into the stock. Order derives from
  /// `seed + reshuffle counter` so any decoded replica reshuffles
  /// identically.
  CrazyEightsState _reshuffleIfNeeded(CrazyEightsState state) {
    if (state.stock.isNotEmpty || state.discard.length <= 1) return state;
    final top = state.discard.last;
    final recycled = state.discard.sublist(0, state.discard.length - 1);
    _Prng(state.seed * 31 + (state.reshuffles + 1) * 1000003)
        .shuffle(recycled);
    return CrazyEightsState(
      playerIds: state.playerIds,
      hands: state.hands,
      stock: List.unmodifiable(recycled),
      discard: List.unmodifiable([top]),
      currentIndex: state.currentIndex,
      declaredSuit: state.declaredSuit,
      passes: state.passes,
      reshuffles: state.reshuffles + 1,
      seed: state.seed,
      lastAction: state.lastAction,
      lastCard: state.lastCard,
      lastActor: state.lastActor,
    );
  }

  @override
  GameOutcome? outcome(CrazyEightsState state) {
    for (var seat = 0; seat < 2; seat++) {
      if (state.hands[seat].isEmpty) {
        return GameOutcome.win(state.playerIds[seat]);
      }
    }
    if (state.passes >= 2) {
      final p0 = CrazyEightsCards.pipTotal(state.hands[0]);
      final p1 = CrazyEightsCards.pipTotal(state.hands[1]);
      if (p0 == p1) return const GameOutcome.draw();
      return GameOutcome.win(state.playerIds[p0 < p1 ? 0 : 1]);
    }
    return null;
  }

  @override
  Map<String, dynamic> encodeState(CrazyEightsState state) => {
        'playerIds': state.playerIds,
        'hands': state.hands,
        'stock': state.stock,
        'discard': state.discard,
        'current': state.currentIndex,
        if (state.declaredSuit != null) 'declaredSuit': state.declaredSuit,
        'passes': state.passes,
        'reshuffles': state.reshuffles,
        'seed': state.seed,
        'lastAction': state.lastAction.name,
        if (state.lastCard != null) 'lastCard': state.lastCard,
        if (state.lastActor != null) 'lastActor': state.lastActor,
      };

  @override
  CrazyEightsState decodeState(Map<String, dynamic> json, int version) {
    List<int> ints(Object? v) =>
        List.unmodifiable((v as List).map((e) => e as int));
    final hands = (json['hands'] as List).map(ints).toList();
    return CrazyEightsState(
      playerIds: List.unmodifiable(
          (json['playerIds'] as List).map((e) => e as String)),
      hands: hands,
      stock: ints(json['stock']),
      discard: ints(json['discard']),
      currentIndex: json['current'] as int,
      declaredSuit: json['declaredSuit'] as int?,
      passes: json['passes'] as int,
      reshuffles: json['reshuffles'] as int,
      seed: json['seed'] as int,
      lastAction: CrazyEightsAction.values
          .firstWhere((a) => a.name == json['lastAction'] as String),
      lastCard: json['lastCard'] as int?,
      lastActor: json['lastActor'] as int?,
    );
  }

  @override
  Map<String, dynamic> encodeMove(CrazyEightsMove move) => {
        'type': move.type.name,
        if (move.card != null) 'card': move.card,
        if (move.declaredSuit != null) 'suit': move.declaredSuit,
      };

  @override
  CrazyEightsMove decodeMove(Map<String, dynamic> json) {
    switch (json['type'] as String) {
      case 'play':
        return CrazyEightsMove.play(
          json['card'] as int,
          declaredSuit: json['suit'] as int?,
        );
      case 'draw':
        return const CrazyEightsMove.draw();
      case 'pass':
        return const CrazyEightsMove.pass();
      default:
        throw ArgumentError('Unknown Crazy 8s move: ${json['type']}');
    }
  }
}
