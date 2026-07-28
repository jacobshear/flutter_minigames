/// Two-player Gin Rummy as a pure [TurnGame].
///
/// ## Rules implemented
///
/// Follows the standard rules as published by Bicycle and pagat.com, played at
/// the **seven-card** hand size ([GinRummyRules.sevenCard], the default — see
/// that class for why every derived number moved with it). The full ten-card
/// game is one constant away: [GinRummyRules.classic]. The deviations are
/// listed at the bottom and every one of them is deliberate.
///
///  * 52-card deck, **7 cards each**. The 15th card is turned up to start the
///    discard pile; the remaining 37 are the stock.
///  * **Opening upcard offer.** The non-dealer may take the upcard or pass. If
///    they pass, the dealer may take it. If both pass, the non-dealer must draw
///    from the stock. (The dealer of the first hand is seat 1, so seat 0 —
///    "Player 1" — always acts first.)
///  * **On your turn** draw the top of the stock or take the upcard, then
///    discard one card. You may not discard the card you just took from the
///    discard pile on that same turn.
///  * **Melds.** Sets are 3–4 of a rank; runs are 3+ in sequence in one suit.
///    **Aces are low** — A-2-3 is a run, Q-K-A is not.
///  * **Deadwood** is everything unmelded: aces 1, face cards 10, others pip
///    value. The split into melds is the true minimum (see
///    [GinRummyMelds.analyse]), never a greedy guess.
///  * **Knock** by discarding when the remaining 7 cards leave 7 or less
///    deadwood. **Gin** is a knock with zero deadwood.
///  * **Lay-offs.** After a knock (but never after gin) the defender may lay
///    unmelded cards onto the knocker's melds.
///  * **Scoring.** Gin: knocker scores the defender's deadwood + a 20 bonus.
///    Plain knock: knocker scores the difference in deadwood. **Undercut** —
///    defender's deadwood ≤ knocker's — the defender scores the difference plus
///    a 15 bonus.
///  * **Exhausted stock.** If a player discards without knocking and that
///    leaves two cards in the stock, the hand is cancelled: no score, same
///    dealer, redeal.
///  * **Match** to 90 points. At the end each player adds a 20-point box
///    bonus per hand won, and the player who reached the target adds a
///    90-point game bonus (180 if the loser never scored). Highest final
///    total wins. Every number above lives in [GinRummyRules] — pass
///    [GinRummyRules.modern] for the ten-card 25/25/25 variant, or a small
///    [GinRummyRules.targetScore] for a single-hand session.
///
/// ## Documented simplifications
///
///  * **Big gin** (an all-melded hand one card over the deal, worth a larger
///    bonus in some circles) is not implemented; such a hand simply goes gin on
///    the discard.
///  * The defender's melds are fixed at the knock to their own minimum-deadwood
///    partition, and lay-offs come out of that deadwood. A pathological hand
///    where a *worse* partition would enable more lay-offs is not searched.
///  * When the defender holds nothing that can be laid off, the lay-off phase
///    is skipped rather than presented as an empty prompt.
///  * The knocker's discard is face up (a real knock is face down). Nothing in
///    a hot-seat game reads the difference, and hiding it would only hide
///    information from the player who already saw it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_minigames/src/cards/cards.dart';
import 'package:flutter_minigames/src/core/core.dart';

import 'gin_rummy_meld.dart';

/// Every number the rules argue about, in one place.
///
/// ## Why the defaults are the seven-card numbers
///
/// The app deals **seven**, not the classic ten: one readable row on a phone
/// and a hand that resolves in a couple of minutes. The hand size is not a free
/// knob though — the other constants have to move with it, and the direction
/// they move in is not the obvious one.
///
/// The numbers quoted below are measured, not estimated: a greedy bot (take the
/// upcard when it lowers your deadwood, shed the most expensive unmelded card,
/// knock the moment it is legal) played 40 seeded matches per rule set. The
/// scripted match in `gin_rummy_game_test.dart` is the same bot, so the
/// hands-per-match claim is a live assertion rather than a comment.
///
///  * **[knockThreshold] 10 → 7.** The one that actually matters. No card is
///    worth more than 10, so at a threshold of 10 a seven-card hand holding two
///    three-melds can *always* knock — the seventh card is irrelevant and the
///    knock stops being a decision. Measured, seven cards at threshold 10 plays
///    out statistically identically to the ten-card game (defender deadwood
///    18.7 vs 18.6, knocker 6.0 vs 6.2) while removing the choice entirely.
///    Seven is the classic scaled by hand size (10 × 7/10) and the same share
///    of a dealt hand's expected pip total (an average card is 85/13 ≈ 6.5, so
///    10/65 ≈ 7/46 ≈ 15%). What makes it work is landing strictly below 10:
///    with two melds down you knock on an ace through a seven and have to keep
///    playing on an eight or better.
///  * **[targetScore] 100 → 90, and the intuition for this one is wrong.**
///    Smaller hands look like they should score less, but a hand scores the
///    deadwood *difference*, and melds absorb cards in threes — so both sizes
///    leave a defender with roughly four unmelded cards at the knock, and
///    deadwood barely scales. Measured, a seven-card hand scores 14.3 points
///    against the ten-card game's 15.7: 91%, not the ~70% the card ratio
///    suggests. (Defender deadwood does fall, 18.6 → 14.8, but so does the
///    knocker's, 6.2 → 3.6, and the difference is what pays.) So the target
///    scales by the *measured* 0.91, not by 0.7: 100 × 0.91 ≈ 90. That lands a
///    match at 10.0 hands against the classic 10.35. Scaling by the card ratio
///    to 70 would have cut the match to 7.7 hands — a third shorter.
///  * **[ginBonus] 20 — measured, and deliberately not scaled.** Per occurrence
///    the classic bonus is already the right proportion at seven cards: a gin
///    hand pays defender deadwood + 20 ≈ 35 against a 14.3 average, or 2.4×,
///    where the ten-card game pays 18.6 + 20 ≈ 39 against 15.7, or 2.5×. What
///    changed is frequency — gin lands on 4–5% of hands instead of 2%, because
///    melding out of seven means finding a 3 + 4 rather than a 3 + 3 + 4. That
///    is the good half of the smaller hand and worth keeping: with undercuts
///    now rare (below), the reachable gin is the main reason not to knock the
///    instant you are legal. Scaling it down would leave nothing pulling
///    against the knock.
///  * **[undercutBonus] 10 → 15.** The undercut is the brake on knocking at the
///    threshold, and the tighter threshold blunted it: the defender now has to
///    reach 7 or less rather than 10 or less, and undercuts fell from 3% of
///    hands to 1%. Deterrence is frequency times payoff, so the payoff goes up
///    to partly compensate. 15 makes an undercut worth about one whole extra
///    hand (15 against the 14.3 average) rather than two thirds of one. Full
///    compensation would be 30, which is refused: one lucky defence deciding a
///    third of a 90-point match is too swingy for a game this short.
///  * **[boxBonus] 20 — unchanged.** Boxes are paid per hand won, and both the
///    hand count (10.0 vs 10.35) and the per-hand score (91%) stayed within a
///    tenth of classic, so the box's share of the final tally is already right.
///    Roughly five hands won × 20 ≈ 100 against a 90-point base, the same
///    balance classic strikes at 100 against 100.
///  * **[gameBonus] / [shutoutGameBonus] 100/200 → 90/180.** Classic sets the
///    game bonus equal to the target and the shutout at double; that identity
///    is the definition, so both follow [targetScore].
///  * **[stockFloor] 2 — unchanged, and it still makes sense.** It is a
///    deck-level rule ("the last two cards are dead"), not a hand-size one. The
///    stock did grow from 31 to 37, which only makes the exhausted-stock
///    cancellation rarer: zero cancelled hands in 40 seven-card matches against
///    one in 40 ten-card ones. The floor is now a genuine backstop rather than
///    an occasional ending, which is an improvement, not a drift.
///
/// [GinRummyRules.classic] keeps the full ten-card Bicycle game reachable, and
/// every constant above is a constructor argument, so a caller can dial any of
/// them independently.
@immutable
class GinRummyRules {
  /// Cards dealt to each player.
  final int handSize;

  /// Maximum deadwood you may knock with.
  final int knockThreshold;

  /// Bonus for going gin.
  final int ginBonus;

  /// Bonus for undercutting the knocker.
  final int undercutBonus;

  /// Bonus per hand won, added at the end of the match.
  final int boxBonus;

  /// Bonus for reaching [targetScore].
  final int gameBonus;

  /// [gameBonus] replacement when the loser scored nothing all match.
  final int shutoutGameBonus;

  /// Running total that ends the match.
  final int targetScore;

  /// The hand is cancelled when a non-knocking discard leaves this many cards
  /// in the stock.
  final int stockFloor;

  const GinRummyRules({
    this.handSize = 7,
    this.knockThreshold = 7,
    this.ginBonus = 20,
    this.undercutBonus = 15,
    this.boxBonus = 20,
    this.gameBonus = 90,
    this.shutoutGameBonus = 180,
    this.targetScore = 90,
    this.stockFloor = 2,
  });

  /// The seven-card game the app deals. Identical to the bare constructor;
  /// named so a call site can say which size it means.
  static const GinRummyRules sevenCard = GinRummyRules();

  /// The full ten-card Bicycle / pagat game, every constant at its published
  /// value. Still a supported deal — nothing in the engine or the table is
  /// written against seven.
  static const GinRummyRules classic = GinRummyRules(
    handSize: 10,
    knockThreshold: 10,
    ginBonus: 20,
    undercutBonus: 10,
    boxBonus: 20,
    gameBonus: 100,
    shutoutGameBonus: 200,
    targetScore: 100,
  );

  /// The common modern ten-card variant: 25 for gin, 25 for an undercut, 25 a
  /// box.
  static const GinRummyRules modern = GinRummyRules(
    handSize: 10,
    knockThreshold: 10,
    ginBonus: 25,
    undercutBonus: 25,
    boxBonus: 25,
    gameBonus: 100,
    shutoutGameBonus: 200,
    targetScore: 100,
  );

  /// One scored hand decides it — any score at all clears the target. Fits a
  /// short session without changing a single rule of play.
  static const GinRummyRules singleHand = GinRummyRules(targetScore: 1);
}

/// Where a hand is in its turn cycle.
enum GinRummyPhase {
  /// Opening offer of the turned-up card, non-dealer first.
  upcardOffer,

  /// The player to act must draw.
  draw,

  /// The player to act must discard (optionally knocking).
  discard,

  /// Someone knocked; the defender may lay cards onto their melds.
  layOff,

  /// The hand is scored and waiting for the next deal.
  handOver,

  /// Someone passed the target score.
  matchOver,
}

/// What the last applied move was, for UI cues and sound. Never drives rules.
enum GinRummyAction {
  deal,
  takeUpcard,
  passUpcard,
  drawStock,
  drawDiscard,
  discard,
  knock,
  gin,
  layOff,
  handScored,
  newHand,
}

/// The knock in progress: who knocked, with what, and what the defender has
/// left to lay off.
@immutable
class GinRummyKnock {
  final int knockerIndex;

  /// The knocker's melds — these grow as the defender lays off.
  final List<Meld> knockerMelds;

  final List<PlayingCard> knockerDeadwood;
  final int knockerDeadwoodValue;

  /// True when the knocker melded everything (no lay-offs allowed).
  final bool gin;

  final List<Meld> defenderMelds;

  /// Shrinks as the defender lays cards off.
  final List<PlayingCard> defenderDeadwood;

  /// Cards the defender has moved onto the knocker's melds.
  final List<PlayingCard> laidOff;

  const GinRummyKnock({
    required this.knockerIndex,
    required this.knockerMelds,
    required this.knockerDeadwood,
    required this.knockerDeadwoodValue,
    required this.gin,
    required this.defenderMelds,
    required this.defenderDeadwood,
    required this.laidOff,
  });

  int get defenderIndex => 1 - knockerIndex;

  int get defenderDeadwoodValue =>
      GinRummyMelds.deadwoodValue(defenderDeadwood);

  /// Whether any remaining deadwood card fits any of the knocker's melds.
  bool get hasLayOff =>
      !gin &&
      defenderDeadwood
          .any((c) => GinRummyMelds.layOffTarget(knockerMelds, c) >= 0);

  GinRummyKnock copyWith({
    List<Meld>? knockerMelds,
    List<PlayingCard>? defenderDeadwood,
    List<PlayingCard>? laidOff,
  }) =>
      GinRummyKnock(
        knockerIndex: knockerIndex,
        knockerMelds: knockerMelds ?? this.knockerMelds,
        knockerDeadwood: knockerDeadwood,
        knockerDeadwoodValue: knockerDeadwoodValue,
        gin: gin,
        defenderMelds: defenderMelds,
        defenderDeadwood: defenderDeadwood ?? this.defenderDeadwood,
        laidOff: laidOff ?? this.laidOff,
      );

  Map<String, dynamic> toJson() => {
        'knocker': knockerIndex,
        'knockerMelds': [for (final m in knockerMelds) m.toJson()],
        'knockerDeadwood': PlayingCard.encodeAll(knockerDeadwood),
        'knockerValue': knockerDeadwoodValue,
        'gin': gin,
        'defenderMelds': [for (final m in defenderMelds) m.toJson()],
        'defenderDeadwood': PlayingCard.encodeAll(defenderDeadwood),
        'laidOff': PlayingCard.encodeAll(laidOff),
      };

  static GinRummyKnock fromJson(Map<String, dynamic> json) => GinRummyKnock(
        knockerIndex: json['knocker'] as int,
        knockerMelds: _melds(json['knockerMelds']),
        knockerDeadwood: PlayingCard.decodeAll(json['knockerDeadwood']),
        knockerDeadwoodValue: json['knockerValue'] as int,
        gin: json['gin'] as bool,
        defenderMelds: _melds(json['defenderMelds']),
        defenderDeadwood: PlayingCard.decodeAll(json['defenderDeadwood']),
        laidOff: PlayingCard.decodeAll(json['laidOff']),
      );
}

List<Meld> _melds(Object? json) => [
      for (final m in (json as List))
        Meld.fromJson((m as Map).cast<String, dynamic>()),
    ];

/// The full accounting of one finished hand — everything a scoring summary
/// needs to show, so the UI never recomputes rules.
@immutable
class GinRummyHandResult {
  final int handNumber;

  /// True when the stock ran out: nobody scores, same dealer redeals.
  final bool cancelled;

  /// Seat that scored, or null when [cancelled].
  final int? winnerIndex;

  /// Points awarded to [winnerIndex].
  final int points;

  final bool gin;
  final bool undercut;

  final int knockerIndex;
  final int knockerDeadwoodValue;
  final int defenderDeadwoodValue;

  final List<Meld> knockerMelds;
  final List<PlayingCard> knockerDeadwood;
  final List<Meld> defenderMelds;
  final List<PlayingCard> defenderDeadwood;

  /// Defender cards absorbed into the knocker's melds.
  final List<PlayingCard> laidOff;

  const GinRummyHandResult({
    required this.handNumber,
    required this.cancelled,
    required this.winnerIndex,
    required this.points,
    required this.gin,
    required this.undercut,
    required this.knockerIndex,
    required this.knockerDeadwoodValue,
    required this.defenderDeadwoodValue,
    required this.knockerMelds,
    required this.knockerDeadwood,
    required this.defenderMelds,
    required this.defenderDeadwood,
    required this.laidOff,
  });

  int get defenderIndex => 1 - knockerIndex;

  Map<String, dynamic> toJson() => {
        'hand': handNumber,
        'cancelled': cancelled,
        if (winnerIndex != null) 'winner': winnerIndex,
        'points': points,
        'gin': gin,
        'undercut': undercut,
        'knocker': knockerIndex,
        'knockerValue': knockerDeadwoodValue,
        'defenderValue': defenderDeadwoodValue,
        'knockerMelds': [for (final m in knockerMelds) m.toJson()],
        'knockerDeadwood': PlayingCard.encodeAll(knockerDeadwood),
        'defenderMelds': [for (final m in defenderMelds) m.toJson()],
        'defenderDeadwood': PlayingCard.encodeAll(defenderDeadwood),
        'laidOff': PlayingCard.encodeAll(laidOff),
      };

  static GinRummyHandResult fromJson(Map<String, dynamic> json) =>
      GinRummyHandResult(
        handNumber: json['hand'] as int,
        cancelled: json['cancelled'] as bool,
        winnerIndex: json['winner'] as int?,
        points: json['points'] as int,
        gin: json['gin'] as bool,
        undercut: json['undercut'] as bool,
        knockerIndex: json['knocker'] as int,
        knockerDeadwoodValue: json['knockerValue'] as int,
        defenderDeadwoodValue: json['defenderValue'] as int,
        knockerMelds: _melds(json['knockerMelds']),
        knockerDeadwood: PlayingCard.decodeAll(json['knockerDeadwood']),
        defenderMelds: _melds(json['defenderMelds']),
        defenderDeadwood: PlayingCard.decodeAll(json['defenderDeadwood']),
        laidOff: PlayingCard.decodeAll(json['laidOff']),
      );
}

/// End-of-match accounting: base scores, box bonuses, game bonus.
@immutable
class GinRummyMatchResult {
  /// Seat with the highest [finalScores], or null on the (vanishing) tie.
  final int? winnerIndex;

  /// The seat that first crossed [GinRummyRules.targetScore].
  final int targetReacherIndex;

  final List<int> baseScores;
  final List<int> boxBonuses;
  final int gameBonus;
  final bool shutout;
  final List<int> finalScores;

  const GinRummyMatchResult({
    required this.winnerIndex,
    required this.targetReacherIndex,
    required this.baseScores,
    required this.boxBonuses,
    required this.gameBonus,
    required this.shutout,
    required this.finalScores,
  });

  Map<String, dynamic> toJson() => {
        if (winnerIndex != null) 'winner': winnerIndex,
        'reacher': targetReacherIndex,
        'base': baseScores,
        'box': boxBonuses,
        'gameBonus': gameBonus,
        'shutout': shutout,
        'final': finalScores,
      };

  static GinRummyMatchResult fromJson(Map<String, dynamic> json) =>
      GinRummyMatchResult(
        winnerIndex: json['winner'] as int?,
        targetReacherIndex: json['reacher'] as int,
        baseScores: _ints(json['base']),
        boxBonuses: _ints(json['box']),
        gameBonus: json['gameBonus'] as int,
        shutout: json['shutout'] as bool,
        finalScores: _ints(json['final']),
      );
}

List<int> _ints(Object? json) => [for (final v in (json as List)) v as int];

/// Immutable Gin Rummy state. Nothing here is mutated after construction.
@immutable
class GinRummyState {
  final List<String> playerIds;

  /// `hands[seat]`, in the order the cards arrived.
  final List<List<PlayingCard>> hands;

  /// Draw pile — **last element is the top**.
  final List<PlayingCard> stock;

  /// Discard pile — **last element is the face-up top**. Empty for the moment
  /// between taking the upcard and discarding.
  final List<PlayingCard> discard;

  final int currentIndex;

  /// Seat that dealt this hand. The other seat acts first.
  final int dealerIndex;

  final GinRummyPhase phase;

  /// Refusals of the opening upcard: 0, 1, or 2. While it reads 2 the player
  /// to act must draw from the stock (they already refused the upcard).
  final int openingPasses;

  /// The card just taken off the discard pile, which may not be discarded on
  /// this same turn.
  final PlayingCard? blockedDiscard;

  /// Running match totals, before end-of-match bonuses.
  final List<int> scores;

  /// Hands each seat has won — the box bonus is paid on these.
  final List<int> handsWon;

  /// 0-based; increments on every deal including cancelled redeals.
  final int handNumber;

  /// Match seed. Kept in state so every deal replays after a decode.
  final int seed;

  /// Live during [GinRummyPhase.layOff].
  final GinRummyKnock? knock;

  /// Set from [GinRummyPhase.handOver] onwards.
  final GinRummyHandResult? result;

  /// Set at [GinRummyPhase.matchOver].
  final GinRummyMatchResult? matchResult;

  final GinRummyAction lastAction;
  final PlayingCard? lastCard;
  final int? lastActor;

  const GinRummyState({
    required this.playerIds,
    required this.hands,
    required this.stock,
    required this.discard,
    required this.currentIndex,
    required this.dealerIndex,
    required this.phase,
    required this.openingPasses,
    required this.blockedDiscard,
    required this.scores,
    required this.handsWon,
    required this.handNumber,
    required this.seed,
    this.knock,
    this.result,
    this.matchResult,
    this.lastAction = GinRummyAction.deal,
    this.lastCard,
    this.lastActor,
  });

  String get currentPlayerId => playerIds[currentIndex];

  int get opponentIndex => 1 - currentIndex;

  /// Seat that did not deal this hand — they act first.
  int get nonDealerIndex => 1 - dealerIndex;

  /// The face-up top of the discard pile, or null while it is empty.
  PlayingCard? get upcard => discard.isEmpty ? null : discard.last;

  /// True while the opening offer has been refused twice: the stock is the
  /// only legal draw.
  bool get mustDrawFromStock =>
      phase == GinRummyPhase.draw && openingPasses >= 2;

  int seatOf(String playerId) => playerIds.indexOf(playerId);

  /// Minimum-deadwood split of [seat]'s hand.
  HandAnalysis analysisFor(int seat) => GinRummyMelds.analyse(hands[seat]);

  /// [seat]'s deadwood count right now.
  int deadwoodFor(int seat) => analysisFor(seat).deadwoodValue;

  GinRummyState copyWith({
    List<List<PlayingCard>>? hands,
    List<PlayingCard>? stock,
    List<PlayingCard>? discard,
    int? currentIndex,
    GinRummyPhase? phase,
    int? openingPasses,
    PlayingCard? blockedDiscard,
    bool clearBlockedDiscard = false,
    List<int>? scores,
    List<int>? handsWon,
    GinRummyKnock? knock,
    bool clearKnock = false,
    GinRummyHandResult? result,
    GinRummyMatchResult? matchResult,
    GinRummyAction? lastAction,
    PlayingCard? lastCard,
    int? lastActor,
  }) =>
      GinRummyState(
        playerIds: playerIds,
        hands: hands ?? this.hands,
        stock: stock ?? this.stock,
        discard: discard ?? this.discard,
        currentIndex: currentIndex ?? this.currentIndex,
        dealerIndex: dealerIndex,
        phase: phase ?? this.phase,
        openingPasses: openingPasses ?? this.openingPasses,
        blockedDiscard: clearBlockedDiscard
            ? null
            : (blockedDiscard ?? this.blockedDiscard),
        scores: scores ?? this.scores,
        handsWon: handsWon ?? this.handsWon,
        handNumber: handNumber,
        seed: seed,
        knock: clearKnock ? null : (knock ?? this.knock),
        result: result ?? this.result,
        matchResult: matchResult ?? this.matchResult,
        lastAction: lastAction ?? this.lastAction,
        lastCard: lastCard ?? this.lastCard,
        lastActor: lastActor ?? this.lastActor,
      );
}

enum GinRummyMoveType {
  takeUpcard,
  passUpcard,
  drawStock,
  drawDiscard,
  discard,
  layOff,
  finishLayoff,
  nextHand,
}

/// One player action.
@immutable
class GinRummyMove {
  final GinRummyMoveType type;

  /// The card discarded or laid off.
  final PlayingCard? card;

  /// Set on a discard that ends the hand.
  final bool knock;

  /// Index into the knocker's melds, for [GinRummyMoveType.layOff].
  final int? meldIndex;

  const GinRummyMove._(this.type,
      {this.card, this.knock = false, this.meldIndex});

  /// Opening offer: take the turned-up card.
  const GinRummyMove.takeUpcard() : this._(GinRummyMoveType.takeUpcard);

  /// Opening offer: refuse the turned-up card.
  const GinRummyMove.passUpcard() : this._(GinRummyMoveType.passUpcard);

  /// Draw the top of the stock.
  const GinRummyMove.drawStock() : this._(GinRummyMoveType.drawStock);

  /// Take the top of the discard pile.
  const GinRummyMove.drawDiscard() : this._(GinRummyMoveType.drawDiscard);

  /// Discard [card], optionally knocking (or going gin) as you do.
  const GinRummyMove.discard(PlayingCard card, {bool knock = false})
      : this._(GinRummyMoveType.discard, card: card, knock: knock);

  /// Lay [card] onto the knocker's meld at [meldIndex].
  const GinRummyMove.layOff(PlayingCard card, int meldIndex)
      : this._(GinRummyMoveType.layOff, card: card, meldIndex: meldIndex);

  /// Done laying off — score the hand.
  const GinRummyMove.finishLayoff() : this._(GinRummyMoveType.finishLayoff);

  /// Deal the next hand.
  const GinRummyMove.nextHand() : this._(GinRummyMoveType.nextHand);

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (card != null) 'card': card!.index,
        if (knock) 'knock': true,
        if (meldIndex != null) 'meld': meldIndex,
      };

  static GinRummyMove fromJson(Map<String, dynamic> json) {
    final type = GinRummyMoveType.values.firstWhere(
      (t) => t.name == json['type'] as String,
      orElse: () => throw FormatException('Unknown move: ${json['type']}'),
    );
    switch (type) {
      case GinRummyMoveType.takeUpcard:
        return const GinRummyMove.takeUpcard();
      case GinRummyMoveType.passUpcard:
        return const GinRummyMove.passUpcard();
      case GinRummyMoveType.drawStock:
        return const GinRummyMove.drawStock();
      case GinRummyMoveType.drawDiscard:
        return const GinRummyMove.drawDiscard();
      case GinRummyMoveType.discard:
        return GinRummyMove.discard(
          PlayingCard.fromIndex(json['card'] as int),
          knock: json['knock'] as bool? ?? false,
        );
      case GinRummyMoveType.layOff:
        return GinRummyMove.layOff(
          PlayingCard.fromIndex(json['card'] as int),
          json['meld'] as int,
        );
      case GinRummyMoveType.finishLayoff:
        return const GinRummyMove.finishLayoff();
      case GinRummyMoveType.nextHand:
        return const GinRummyMove.nextHand();
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GinRummyMove &&
          other.type == type &&
          other.card == card &&
          other.knock == knock &&
          other.meldIndex == meldIndex);

  @override
  int get hashCode => Object.hash(type, card, knock, meldIndex);

  @override
  String toString() => 'GinRummyMove.${type.name}('
      '${card?.code ?? ''}${knock ? ' knock' : ''}'
      '${meldIndex != null ? ' -> $meldIndex' : ''})';
}

/// The rules engine. Pure, serializable, no rendering, no clock.
class GinRummyGame extends TurnGame<GinRummyState, GinRummyMove> {
  final GinRummyRules rules;

  const GinRummyGame({this.rules = GinRummyRules.sevenCard});

  @override
  String get id => 'gin_rummy';

  // ---------------------------------------------------------------------------
  // Dealing
  // ---------------------------------------------------------------------------

  @override
  GinRummyState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2, 'Gin Rummy is 2-player');
    // Seat 1 deals the first hand, so seat 0 ("Player 1") always acts first.
    return _deal(
      playerIds: List.unmodifiable(playerIds),
      seed: seed,
      dealerIndex: 1,
      handNumber: 0,
      scores: const [0, 0],
      handsWon: const [0, 0],
    );
  }

  GinRummyState _deal({
    required List<String> playerIds,
    required int seed,
    required int dealerIndex,
    required int handNumber,
    required List<int> scores,
    required List<int> handsWon,
  }) {
    // A fresh sub-stream per hand: the whole match still replays from one seed,
    // and a cancelled hand redeals differently because handNumber moved on.
    final deck = CardDeck.shuffled(
      CardRandom.derived(seed, handNumber).nextUint32(),
    );
    final dealt = CardDeck.deal(
      deck,
      players: 2,
      perPlayer: rules.handSize,
      roundRobin: true,
    );
    final nonDealer = 1 - dealerIndex;
    final hands = <List<PlayingCard>>[[], []];
    // The dealer deals to the opponent first, exactly as at a table.
    hands[nonDealer] = List.unmodifiable(dealt.hands[0]);
    hands[dealerIndex] = List.unmodifiable(dealt.hands[1]);

    final stock = List<PlayingCard>.of(dealt.stock);
    final upcard = stock.removeLast();

    return GinRummyState(
      playerIds: playerIds,
      hands: hands,
      stock: List.unmodifiable(stock),
      discard: List.unmodifiable([upcard]),
      currentIndex: nonDealer,
      dealerIndex: dealerIndex,
      phase: GinRummyPhase.upcardOffer,
      openingPasses: 0,
      blockedDiscard: null,
      scores: List.unmodifiable(scores),
      handsWon: List.unmodifiable(handsWon),
      handNumber: handNumber,
      seed: seed,
      lastAction: GinRummyAction.deal,
    );
  }

  @override
  String currentPlayer(GinRummyState state) => state.currentPlayerId;

  // ---------------------------------------------------------------------------
  // Legality
  // ---------------------------------------------------------------------------

  /// Whether [seat] could knock by discarding [card] — the question the knock
  /// button asks.
  bool canKnockWith(GinRummyState state, int seat, PlayingCard card) {
    final rest = List<PlayingCard>.of(state.hands[seat])..remove(card);
    if (rest.length != rules.handSize) return false;
    return GinRummyMelds.analyse(rest).deadwoodValue <= rules.knockThreshold;
  }

  /// Deadwood [seat] would be left with after discarding [card].
  int deadwoodAfterDiscarding(
    GinRummyState state,
    int seat,
    PlayingCard card,
  ) {
    final rest = List<PlayingCard>.of(state.hands[seat])..remove(card);
    return GinRummyMelds.analyse(rest).deadwoodValue;
  }

  @override
  bool validateMove(GinRummyState state, GinRummyMove move, String playerId) {
    if (state.phase == GinRummyPhase.matchOver) return false;
    if (playerId != state.currentPlayerId) return false;
    final seat = state.currentIndex;

    switch (move.type) {
      case GinRummyMoveType.takeUpcard:
        return state.phase == GinRummyPhase.upcardOffer &&
            state.discard.isNotEmpty;

      case GinRummyMoveType.passUpcard:
        return state.phase == GinRummyPhase.upcardOffer;

      case GinRummyMoveType.drawStock:
        return state.phase == GinRummyPhase.draw && state.stock.isNotEmpty;

      case GinRummyMoveType.drawDiscard:
        return state.phase == GinRummyPhase.draw &&
            !state.mustDrawFromStock &&
            state.discard.isNotEmpty;

      case GinRummyMoveType.discard:
        if (state.phase != GinRummyPhase.discard) return false;
        final card = move.card;
        if (card == null) return false;
        if (!state.hands[seat].contains(card)) return false;
        if (card == state.blockedDiscard) return false;
        if (move.knock && !canKnockWith(state, seat, card)) return false;
        return true;

      case GinRummyMoveType.layOff:
        final knock = state.knock;
        if (state.phase != GinRummyPhase.layOff || knock == null) return false;
        if (seat != knock.defenderIndex) return false;
        final card = move.card;
        final index = move.meldIndex;
        if (card == null || index == null) return false;
        if (index < 0 || index >= knock.knockerMelds.length) return false;
        if (!knock.defenderDeadwood.contains(card)) return false;
        return knock.knockerMelds[index].canExtendWith(card);

      case GinRummyMoveType.finishLayoff:
        return state.phase == GinRummyPhase.layOff;

      case GinRummyMoveType.nextHand:
        return state.phase == GinRummyPhase.handOver &&
            state.matchResult == null;
    }
  }

  // ---------------------------------------------------------------------------
  // Transitions
  // ---------------------------------------------------------------------------

  @override
  GinRummyState applyMove(GinRummyState state, GinRummyMove move) {
    final seat = state.currentIndex;
    switch (move.type) {
      case GinRummyMoveType.takeUpcard:
        return _pickUpDiscard(state, seat, GinRummyAction.takeUpcard);

      case GinRummyMoveType.passUpcard:
        final passes = state.openingPasses + 1;
        return state.copyWith(
          // First refusal hands the offer to the dealer; the second starts
          // play, and the refuser must draw from the stock.
          currentIndex: passes == 1 ? state.dealerIndex : state.nonDealerIndex,
          phase: passes == 1 ? GinRummyPhase.upcardOffer : GinRummyPhase.draw,
          openingPasses: passes,
          lastAction: GinRummyAction.passUpcard,
          lastActor: seat,
        );

      case GinRummyMoveType.drawStock:
        final stock = List<PlayingCard>.of(state.stock);
        final drawn = stock.removeLast();
        return state.copyWith(
          hands: _handsWith(state, seat, [...state.hands[seat], drawn]),
          stock: List.unmodifiable(stock),
          phase: GinRummyPhase.discard,
          openingPasses: 0,
          clearBlockedDiscard: true,
          lastAction: GinRummyAction.drawStock,
          lastCard: drawn,
          lastActor: seat,
        );

      case GinRummyMoveType.drawDiscard:
        return _pickUpDiscard(state, seat, GinRummyAction.drawDiscard);

      case GinRummyMoveType.discard:
        return _discard(state, seat, move.card!, knocking: move.knock);

      case GinRummyMoveType.layOff:
        final knock = state.knock!;
        final index = move.meldIndex!;
        final card = move.card!;
        final melds = List<Meld>.of(knock.knockerMelds);
        melds[index] = melds[index].extend(card);
        return state.copyWith(
          knock: knock.copyWith(
            knockerMelds: List.unmodifiable(melds),
            defenderDeadwood: List.unmodifiable(
              List<PlayingCard>.of(knock.defenderDeadwood)..remove(card),
            ),
            laidOff: List.unmodifiable([...knock.laidOff, card]),
          ),
          lastAction: GinRummyAction.layOff,
          lastCard: card,
          lastActor: seat,
        );

      case GinRummyMoveType.finishLayoff:
        return _scoreKnock(state, state.knock!);

      case GinRummyMoveType.nextHand:
        final result = state.result!;
        return _deal(
          playerIds: state.playerIds,
          seed: state.seed,
          // A cancelled hand is redealt by the same dealer.
          dealerIndex:
              result.cancelled ? state.dealerIndex : 1 - state.dealerIndex,
          handNumber: state.handNumber + 1,
          scores: state.scores,
          handsWon: state.handsWon,
        ).copyWith(lastAction: GinRummyAction.newHand);
    }
  }

  /// Take the face-up card into [seat]'s hand; that card may not be discarded
  /// again this turn.
  GinRummyState _pickUpDiscard(
    GinRummyState state,
    int seat,
    GinRummyAction action,
  ) {
    final discard = List<PlayingCard>.of(state.discard);
    final taken = discard.removeLast();
    return state.copyWith(
      hands: _handsWith(state, seat, [...state.hands[seat], taken]),
      discard: List.unmodifiable(discard),
      phase: GinRummyPhase.discard,
      openingPasses: 0,
      blockedDiscard: taken,
      lastAction: action,
      lastCard: taken,
      lastActor: seat,
    );
  }

  GinRummyState _discard(
    GinRummyState state,
    int seat,
    PlayingCard card, {
    required bool knocking,
  }) {
    final hand = List<PlayingCard>.of(state.hands[seat])..remove(card);
    final discard = List<PlayingCard>.unmodifiable([...state.discard, card]);
    final next = state.copyWith(
      hands: _handsWith(state, seat, hand),
      discard: discard,
      clearBlockedDiscard: true,
      lastCard: card,
      lastActor: seat,
    );

    if (knocking) {
      final knocker = GinRummyMelds.analyse(hand);
      final defender = GinRummyMelds.analyse(state.hands[1 - seat]);
      final knock = GinRummyKnock(
        knockerIndex: seat,
        knockerMelds: knocker.melds,
        knockerDeadwood: knocker.deadwood,
        knockerDeadwoodValue: knocker.deadwoodValue,
        gin: knocker.isGin,
        defenderMelds: defender.melds,
        defenderDeadwood: defender.deadwood,
        laidOff: const [],
      );
      // Gin allows no lay-offs, and an empty lay-off prompt helps nobody.
      if (!knock.hasLayOff) {
        return _scoreKnock(
          next.copyWith(
            knock: knock,
            lastAction:
                knocker.isGin ? GinRummyAction.gin : GinRummyAction.knock,
          ),
          knock,
        );
      }
      return next.copyWith(
        currentIndex: knock.defenderIndex,
        phase: GinRummyPhase.layOff,
        knock: knock,
        lastAction: GinRummyAction.knock,
      );
    }

    // Stock exhausted: the hand is dead, nobody scores, same dealer redeals.
    if (next.stock.length <= rules.stockFloor) {
      final knocker = GinRummyMelds.analyse(hand);
      final defender = GinRummyMelds.analyse(state.hands[1 - seat]);
      final result = GinRummyHandResult(
        handNumber: state.handNumber,
        cancelled: true,
        winnerIndex: null,
        points: 0,
        gin: false,
        undercut: false,
        knockerIndex: seat,
        knockerDeadwoodValue: knocker.deadwoodValue,
        defenderDeadwoodValue: defender.deadwoodValue,
        knockerMelds: knocker.melds,
        knockerDeadwood: knocker.deadwood,
        defenderMelds: defender.melds,
        defenderDeadwood: defender.deadwood,
        laidOff: const [],
      );
      return next.copyWith(
        currentIndex: 1 - state.dealerIndex,
        phase: GinRummyPhase.handOver,
        result: result,
        lastAction: GinRummyAction.handScored,
      );
    }

    return next.copyWith(
      currentIndex: 1 - seat,
      phase: GinRummyPhase.draw,
      lastAction: GinRummyAction.discard,
    );
  }

  /// Turn a completed knock into points and, if the target is reached, into a
  /// finished match.
  GinRummyState _scoreKnock(GinRummyState state, GinRummyKnock knock) {
    final defenderValue = knock.defenderDeadwoodValue;
    final knockerValue = knock.knockerDeadwoodValue;

    final int winner;
    final int points;
    var undercut = false;
    if (knock.gin) {
      winner = knock.knockerIndex;
      points = defenderValue + rules.ginBonus;
    } else if (defenderValue > knockerValue) {
      winner = knock.knockerIndex;
      points = defenderValue - knockerValue;
    } else {
      // Equal counts undercut too — the defender only has to match.
      undercut = true;
      winner = knock.defenderIndex;
      points = knockerValue - defenderValue + rules.undercutBonus;
    }

    final scores = List<int>.of(state.scores)..[winner] += points;
    final handsWon = List<int>.of(state.handsWon)..[winner] += 1;

    final result = GinRummyHandResult(
      handNumber: state.handNumber,
      cancelled: false,
      winnerIndex: winner,
      points: points,
      gin: knock.gin,
      undercut: undercut,
      knockerIndex: knock.knockerIndex,
      knockerDeadwoodValue: knockerValue,
      defenderDeadwoodValue: defenderValue,
      knockerMelds: knock.knockerMelds,
      knockerDeadwood: knock.knockerDeadwood,
      defenderMelds: knock.defenderMelds,
      defenderDeadwood: knock.defenderDeadwood,
      laidOff: knock.laidOff,
    );

    final matchOver = scores[winner] >= rules.targetScore;
    final scored = state.copyWith(
      scores: List.unmodifiable(scores),
      handsWon: List.unmodifiable(handsWon),
      currentIndex: 1 - state.dealerIndex,
      phase: GinRummyPhase.handOver,
      knock: knock,
      result: result,
      lastAction: GinRummyAction.handScored,
    );
    if (!matchOver) return scored;

    return scored.copyWith(
      phase: GinRummyPhase.matchOver,
      matchResult: _settleMatch(scores, handsWon, winner),
    );
  }

  GinRummyMatchResult _settleMatch(
    List<int> scores,
    List<int> handsWon,
    int reacher,
  ) {
    final shutout = scores[1 - reacher] == 0;
    final gameBonus = shutout ? rules.shutoutGameBonus : rules.gameBonus;
    final box = [
      for (var i = 0; i < 2; i++) handsWon[i] * rules.boxBonus,
    ];
    final finals = [
      for (var i = 0; i < 2; i++)
        scores[i] + box[i] + (i == reacher ? gameBonus : 0),
    ];
    final winner =
        finals[0] == finals[1] ? null : (finals[0] > finals[1] ? 0 : 1);
    return GinRummyMatchResult(
      winnerIndex: winner,
      targetReacherIndex: reacher,
      baseScores: List.unmodifiable(scores),
      boxBonuses: List.unmodifiable(box),
      gameBonus: gameBonus,
      shutout: shutout,
      finalScores: List.unmodifiable(finals),
    );
  }

  List<List<PlayingCard>> _handsWith(
    GinRummyState state,
    int seat,
    List<PlayingCard> hand,
  ) =>
      [
        seat == 0 ? List.unmodifiable(hand) : state.hands[0],
        seat == 1 ? List.unmodifiable(hand) : state.hands[1],
      ];

  @override
  GameOutcome? outcome(GinRummyState state) {
    final match = state.matchResult;
    if (state.phase != GinRummyPhase.matchOver || match == null) return null;
    final winner = match.winnerIndex;
    if (winner == null) return const GameOutcome.draw();
    return GameOutcome.win(state.playerIds[winner]);
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> encodeState(GinRummyState state) => {
        'playerIds': state.playerIds,
        'hands': [for (final h in state.hands) PlayingCard.encodeAll(h)],
        'stock': PlayingCard.encodeAll(state.stock),
        'discard': PlayingCard.encodeAll(state.discard),
        'current': state.currentIndex,
        'dealer': state.dealerIndex,
        'phase': state.phase.name,
        'passes': state.openingPasses,
        if (state.blockedDiscard != null)
          'blocked': state.blockedDiscard!.index,
        'scores': state.scores,
        'handsWon': state.handsWon,
        'hand': state.handNumber,
        'seed': state.seed,
        if (state.knock != null) 'knock': state.knock!.toJson(),
        if (state.result != null) 'result': state.result!.toJson(),
        if (state.matchResult != null) 'match': state.matchResult!.toJson(),
        'lastAction': state.lastAction.name,
        if (state.lastCard != null) 'lastCard': state.lastCard!.index,
        if (state.lastActor != null) 'lastActor': state.lastActor,
      };

  @override
  GinRummyState decodeState(Map<String, dynamic> json, int version) {
    Map<String, dynamic>? map(Object? v) =>
        v == null ? null : (v as Map).cast<String, dynamic>();
    return GinRummyState(
      playerIds: List.unmodifiable(
        (json['playerIds'] as List).map((e) => e as String),
      ),
      hands: [
        for (final h in (json['hands'] as List))
          List.unmodifiable(PlayingCard.decodeAll(h)),
      ],
      stock: List.unmodifiable(PlayingCard.decodeAll(json['stock'])),
      discard: List.unmodifiable(PlayingCard.decodeAll(json['discard'])),
      currentIndex: json['current'] as int,
      dealerIndex: json['dealer'] as int,
      phase: GinRummyPhase.values
          .firstWhere((p) => p.name == json['phase'] as String),
      openingPasses: json['passes'] as int,
      blockedDiscard: json['blocked'] == null
          ? null
          : PlayingCard.fromIndex(json['blocked'] as int),
      scores: List.unmodifiable(_ints(json['scores'])),
      handsWon: List.unmodifiable(_ints(json['handsWon'])),
      handNumber: json['hand'] as int,
      seed: json['seed'] as int,
      knock: json['knock'] == null
          ? null
          : GinRummyKnock.fromJson(map(json['knock'])!),
      result: json['result'] == null
          ? null
          : GinRummyHandResult.fromJson(map(json['result'])!),
      matchResult: json['match'] == null
          ? null
          : GinRummyMatchResult.fromJson(map(json['match'])!),
      lastAction: GinRummyAction.values
          .firstWhere((a) => a.name == json['lastAction'] as String),
      lastCard: json['lastCard'] == null
          ? null
          : PlayingCard.fromIndex(json['lastCard'] as int),
      lastActor: json['lastActor'] as int?,
    );
  }

  @override
  Map<String, dynamic> encodeMove(GinRummyMove move) => move.toJson();

  @override
  GinRummyMove decodeMove(Map<String, dynamic> json) =>
      GinRummyMove.fromJson(json);
}
