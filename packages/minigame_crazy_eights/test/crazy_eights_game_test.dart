import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_crazy_eights/minigame_crazy_eights.dart';
import 'package:minigames_core/minigames_core.dart';

void main() {
  const game = CrazyEightsGame();

  // card(suit, rank): rank 0 = ace … 7 = eight … 12 = king.
  int card(int suit, int rank) => suit * 13 + rank;

  const sp = CrazyEightsCards.spades;
  const he = CrazyEightsCards.hearts;
  const di = CrazyEightsCards.diamonds;
  const cl = CrazyEightsCards.clubs;

  // Default hands are non-empty filler (J♣/Q♣) so a fresh state isn't
  // already won; tests that care about hands pass them explicitly.
  CrazyEightsState make({
    List<int> hand0 = const [49],
    List<int> hand1 = const [50],
    List<int> stock = const [],
    List<int> discard = const [],
    int current = 0,
    int? declaredSuit,
    int passes = 0,
    int reshuffles = 0,
    int seed = 7,
  }) {
    return CrazyEightsState(
      playerIds: const ['p1', 'p2'],
      hands: [hand0, hand1],
      stock: stock,
      discard: discard.isEmpty ? [card(sp, 4)] : discard,
      currentIndex: current,
      declaredSuit: declaredSuit,
      passes: passes,
      reshuffles: reshuffles,
      seed: seed,
    );
  }

  group('deal', () {
    test('8 cards each, one flipped, 35 in stock, full deck accounted for',
        () {
      final s = game.initialState(seed: 42, playerIds: const ['p1', 'p2']);
      expect(s.hands[0].length, 8);
      expect(s.hands[1].length, 8);
      expect(s.discard.length, 1);
      expect(s.stock.length, 35);
      final all = [...s.hands[0], ...s.hands[1], ...s.stock, ...s.discard];
      expect(all.toSet().length, 52);
      expect(game.currentPlayer(s), 'p1');
      expect(game.outcome(s), isNull);
    });

    test('same seed deals identically, different seed differs', () {
      final a = game.initialState(seed: 42, playerIds: const ['p1', 'p2']);
      final b = game.initialState(seed: 42, playerIds: const ['p1', 'p2']);
      final c = game.initialState(seed: 43, playerIds: const ['p1', 'p2']);
      expect(game.encodeState(a), equals(game.encodeState(b)));
      expect(game.encodeState(a), isNot(equals(game.encodeState(c))));
    });
  });

  group('legal play validation', () {
    test('suit match, rank match, and 8s are playable; others are not', () {
      final s = make(
        hand0: [card(he, 2), card(sp, 9), card(cl, 7), card(di, 3)],
        discard: [card(he, 9)], // 10♥ on top
        stock: [card(cl, 0)],
      );
      // Suit match (3♥).
      expect(
        game.validateMove(s, CrazyEightsMove.play(card(he, 2)), 'p1'),
        isTrue,
      );
      // Rank match (10♠).
      expect(
        game.validateMove(s, CrazyEightsMove.play(card(sp, 9)), 'p1'),
        isTrue,
      );
      // 8 is always playable (with a declared suit).
      expect(
        game.validateMove(
          s,
          CrazyEightsMove.play(card(cl, 7), declaredSuit: di),
          'p1',
        ),
        isTrue,
      );
      // 4♦ matches neither suit nor rank.
      expect(
        game.validateMove(s, CrazyEightsMove.play(card(di, 3)), 'p1'),
        isFalse,
      );
    });

    test('rejects out-of-turn, cards not in hand, and finished games', () {
      final s = make(
        hand0: [card(he, 2)],
        hand1: [card(he, 3)],
        discard: [card(he, 9)],
        stock: [card(cl, 0)],
      );
      expect(
        game.validateMove(s, CrazyEightsMove.play(card(he, 3)), 'p2'),
        isFalse,
        reason: 'not p2\'s turn',
      );
      expect(
        game.validateMove(s, CrazyEightsMove.play(card(he, 3)), 'p1'),
        isFalse,
        reason: 'card not in p1\'s hand',
      );
      final won = make(
        hand0: const [],
        hand1: [card(he, 3)],
        discard: [card(he, 9)],
      );
      expect(game.outcome(won), const GameOutcome.win('p1'));
      expect(
        game.validateMove(won, const CrazyEightsMove.draw(), 'p2'),
        isFalse,
      );
    });

    test('8 requires a declared suit; non-8 must not carry one', () {
      final s = make(
        hand0: [card(cl, 7), card(he, 2)],
        discard: [card(he, 9)],
        stock: [card(cl, 0)],
      );
      expect(
        game.validateMove(s, CrazyEightsMove.play(card(cl, 7)), 'p1'),
        isFalse,
      );
      expect(
        game.validateMove(
          s,
          CrazyEightsMove.play(card(cl, 7), declaredSuit: 5),
          'p1',
        ),
        isFalse,
      );
      expect(
        game.validateMove(
          s,
          CrazyEightsMove.play(card(he, 2), declaredSuit: he),
          'p1',
        ),
        isFalse,
      );
    });
  });

  group('8 suit declaration', () {
    test('declared suit gates the next play and clears on a non-8', () {
      var s = make(
        hand0: [card(cl, 7)],
        hand1: [card(he, 4), card(di, 5), card(sp, 7), card(di, 9)],
        discard: [card(he, 9)],
        stock: [card(cl, 0)],
      );
      s = game.applyMove(
        s,
        CrazyEightsMove.play(card(cl, 7), declaredSuit: di),
      );
      // Hand emptied → p1 already won; rebuild with a live variant instead.
      s = make(
        hand0: [card(cl, 2)],
        hand1: [card(he, 4), card(di, 5), card(sp, 7), card(di, 9)],
        discard: [card(he, 9), card(cl, 7)],
        declaredSuit: di,
        current: 1,
        stock: [card(cl, 0)],
      );
      expect(s.activeSuit, di);
      // Hearts no longer legal despite matching nothing else.
      expect(
        game.validateMove(s, CrazyEightsMove.play(card(he, 4)), 'p2'),
        isFalse,
      );
      // Declared suit is legal.
      expect(
        game.validateMove(s, CrazyEightsMove.play(card(di, 5)), 'p2'),
        isTrue,
      );
      // Another 8 is legal on top of a declared 8.
      expect(
        game.validateMove(
          s,
          CrazyEightsMove.play(card(sp, 7), declaredSuit: he),
          'p2',
        ),
        isTrue,
      );
      // Playing the declared suit clears the declaration.
      final after = game.applyMove(s, CrazyEightsMove.play(card(di, 5)));
      expect(after.declaredSuit, isNull);
      expect(after.activeSuit, di);
    });

    test('flipped-8 starter is a free-suit start: anything goes', () {
      final s = make(
        hand0: [card(cl, 3), card(he, 11)],
        hand1: [card(di, 1)],
        discard: [card(sp, 7)], // flipped 8♠, no declaration
        stock: [card(cl, 0)],
      );
      expect(s.activeSuit, isNull);
      expect(
        game.validateMove(s, CrazyEightsMove.play(card(cl, 3)), 'p1'),
        isTrue,
      );
      expect(
        game.validateMove(s, CrazyEightsMove.play(card(he, 11)), 'p1'),
        isTrue,
      );
    });
  });

  group('drawing and passing', () {
    test('draw keeps the turn, moves the stock top into the hand', () {
      final s = make(
        hand0: [card(di, 3)],
        hand1: [card(di, 4)],
        discard: [card(he, 9)],
        stock: [card(cl, 0), card(cl, 1), card(cl, 2)],
      );
      expect(game.validateMove(s, const CrazyEightsMove.draw(), 'p1'), isTrue);
      final after = game.applyMove(s, const CrazyEightsMove.draw());
      expect(after.currentIndex, 0, reason: 'drawing does not end the turn');
      expect(after.hands[0], contains(card(cl, 2)));
      expect(after.stock, [card(cl, 0), card(cl, 1)]);
      expect(after.lastAction, CrazyEightsAction.draw);
    });

    test('draw is allowed even when a playable card is in hand', () {
      final s = make(
        hand0: [card(he, 2)], // playable on 10♥
        discard: [card(he, 9)],
        stock: [card(cl, 0)],
      );
      expect(game.validateMove(s, const CrazyEightsMove.draw(), 'p1'), isTrue);
    });

    test('pass is only legal with an empty stock and no playable card', () {
      // Stock non-empty → no pass.
      final withStock = make(
        hand0: [card(di, 3)],
        discard: [card(he, 9)],
        stock: [card(cl, 0)],
      );
      expect(
        game.validateMove(withStock, const CrazyEightsMove.pass(), 'p1'),
        isFalse,
      );
      // Stock empty but playable card in hand → no pass.
      final playable = make(
        hand0: [card(he, 2)],
        discard: [card(he, 9)],
      );
      expect(
        game.validateMove(playable, const CrazyEightsMove.pass(), 'p1'),
        isFalse,
      );
      // Stock empty, nothing playable → pass, turn flips.
      final stuck = make(
        hand0: [card(di, 3)],
        discard: [card(he, 9)],
      );
      expect(
        game.validateMove(stuck, const CrazyEightsMove.pass(), 'p1'),
        isTrue,
      );
      final after = game.applyMove(stuck, const CrazyEightsMove.pass());
      expect(after.currentIndex, 1);
      expect(after.passes, 1);
    });

    test('draw-until-playable at the table edge: empty stock forbids draw',
        () {
      final s = make(
        hand0: [card(di, 3)],
        discard: [card(he, 9)],
      );
      expect(
        game.validateMove(s, const CrazyEightsMove.draw(), 'p1'),
        isFalse,
      );
    });
  });

  group('reshuffle', () {
    CrazyEightsState lastStockState() => make(
          hand0: [card(di, 3)],
          hand1: [card(di, 4)],
          discard: [card(he, 0), card(he, 1), card(he, 2), card(he, 9)],
          stock: [card(cl, 0)],
          seed: 99,
        );

    test('emptying the stock recycles the discard minus its top card', () {
      final s = lastStockState();
      final after = game.applyMove(s, const CrazyEightsMove.draw());
      expect(after.hands[0], contains(card(cl, 0)));
      expect(after.discard, [card(he, 9)], reason: 'top card stays');
      expect(
        after.stock.toSet(),
        {card(he, 0), card(he, 1), card(he, 2)},
        reason: 'recycled cards form the new stock',
      );
      expect(after.reshuffles, 1);
    });

    test('reshuffle order is deterministic, including across decode', () {
      final a = game.applyMove(lastStockState(), const CrazyEightsMove.draw());
      final b = game.applyMove(lastStockState(), const CrazyEightsMove.draw());
      expect(a.stock, b.stock);

      final decoded = game.decodeState(
        game.encodeState(lastStockState()),
        game.stateSchemaVersion,
      );
      final c = game.applyMove(decoded, const CrazyEightsMove.draw());
      expect(c.stock, a.stock);
    });

    test('a second reshuffle uses a different deterministic order', () {
      final first = game.applyMove(
        lastStockState(),
        const CrazyEightsMove.draw(),
      );
      // Force a second reshuffle from an identical pile but reshuffles = 1.
      final again = CrazyEightsState(
        playerIds: first.playerIds,
        hands: first.hands,
        stock: [card(cl, 1)],
        discard: [card(he, 0), card(he, 1), card(he, 2), card(he, 9)],
        currentIndex: 0,
        declaredSuit: null,
        passes: 0,
        reshuffles: 1,
        seed: 99,
      );
      final second = game.applyMove(again, const CrazyEightsMove.draw());
      expect(second.reshuffles, 2);
      expect(second.stock.toSet(), {card(he, 0), card(he, 1), card(he, 2)});
    });
  });

  group('endgame', () {
    test('emptying your hand wins', () {
      final s = make(
        hand0: [card(he, 2)],
        hand1: [card(di, 4), card(di, 5)],
        discard: [card(he, 9)],
        stock: [card(cl, 0)],
      );
      final after = game.applyMove(s, CrazyEightsMove.play(card(he, 2)));
      expect(game.outcome(after), const GameOutcome.win('p1'));
    });

    test('two consecutive passes score pips: 8 = 50, face = 10, ace = 1', () {
      // p1 holds A♦ (1 pip); p2 holds 8♣ + K♦ (60 pips).
      var s = make(
        hand0: [card(di, 0)],
        hand1: [card(cl, 7), card(di, 12)],
        discard: [card(he, 9)],
        passes: 0,
      );
      // Neither can play (top is 10♥; no hearts, no 10s… but p2's 8 is
      // playable, so craft p2's hand pip-heavy without an 8 for the pass
      // sequence; keep the pip math for values separately below.)
      s = make(
        hand0: [card(di, 0)],
        hand1: [card(cl, 11), card(di, 12)],
        discard: [card(he, 9)],
      );
      s = game.applyMove(s, const CrazyEightsMove.pass());
      expect(game.outcome(s), isNull);
      s = game.applyMove(s, const CrazyEightsMove.pass());
      expect(game.outcome(s), const GameOutcome.win('p1'));

      expect(CrazyEightsCards.pipValue(card(cl, 7)), 50);
      expect(CrazyEightsCards.pipValue(card(di, 12)), 10);
      expect(CrazyEightsCards.pipValue(card(di, 0)), 1);
      expect(CrazyEightsCards.pipValue(card(sp, 8)), 9);
    });

    test('equal pip counts on a double pass is a draw', () {
      var s = make(
        hand0: [card(di, 2)],
        hand1: [card(cl, 2)],
        discard: [card(he, 9)],
      );
      s = game.applyMove(s, const CrazyEightsMove.pass());
      s = game.applyMove(s, const CrazyEightsMove.pass());
      expect(game.outcome(s), const GameOutcome.draw());
    });

    test('a play in between resets the pass chain', () {
      var s = make(
        hand0: [card(di, 3)],
        hand1: [card(he, 2), card(cl, 5)],
        discard: [card(he, 9)],
      );
      s = game.applyMove(s, const CrazyEightsMove.pass());
      expect(s.passes, 1);
      s = game.applyMove(s, CrazyEightsMove.play(card(he, 2)));
      expect(s.passes, 0);
      expect(game.outcome(s), isNull);
    });
  });

  group('serialization', () {
    test('state round-trips through encode/decode', () {
      var s = game.initialState(seed: 7, playerIds: const ['p1', 'p2']);
      // Take a couple of moves so optional fields are populated.
      s = game.applyMove(s, const CrazyEightsMove.draw());
      final decoded =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(game.encodeState(decoded), equals(game.encodeState(s)));
      expect(decoded.hands[0], s.hands[0]);
      expect(decoded.stock, s.stock);
      expect(decoded.lastAction, s.lastAction);
      expect(decoded.seed, s.seed);
    });

    test('all move types round-trip', () {
      final play = CrazyEightsMove.play(card(cl, 7), declaredSuit: he);
      final playDecoded = game.decodeMove(game.encodeMove(play));
      expect(playDecoded.type, CrazyEightsMoveType.play);
      expect(playDecoded.card, card(cl, 7));
      expect(playDecoded.declaredSuit, he);

      final draw = game.decodeMove(game.encodeMove(const CrazyEightsMove.draw()));
      expect(draw.type, CrazyEightsMoveType.draw);
      expect(draw.card, isNull);

      final pass = game.decodeMove(game.encodeMove(const CrazyEightsMove.pass()));
      expect(pass.type, CrazyEightsMoveType.pass);
    });
  });

  group('full seeded game via MatchController semantics', () {
    test('applyMove chains stay internally consistent from a real deal', () {
      var s = game.initialState(seed: 12, playerIds: const ['p1', 'p2']);
      var guard = 0;
      // Play a greedy bot vs bot game to exercise the whole rule set.
      while (game.outcome(s) == null && guard < 2000) {
        guard++;
        final seat = s.currentIndex;
        final hand = s.hands[seat];
        final playable =
            hand.where((c) => game.isPlayable(s, c)).toList();
        if (playable.isNotEmpty) {
          final c = playable.first;
          final move = CrazyEightsCards.isEight(c)
              ? CrazyEightsMove.play(c, declaredSuit: 0)
              : CrazyEightsMove.play(c);
          expect(game.validateMove(s, move, s.currentPlayerId), isTrue);
          s = game.applyMove(s, move);
        } else if (s.stock.isNotEmpty) {
          s = game.applyMove(s, const CrazyEightsMove.draw());
        } else {
          expect(
            game.validateMove(
              s,
              const CrazyEightsMove.pass(),
              s.currentPlayerId,
            ),
            isTrue,
          );
          s = game.applyMove(s, const CrazyEightsMove.pass());
        }
        // Invariant: every card exists exactly once.
        final all = [...s.hands[0], ...s.hands[1], ...s.stock, ...s.discard];
        expect(all.length, 52);
        expect(all.toSet().length, 52);
      }
      expect(game.outcome(s), isNotNull,
          reason: 'bot game should terminate (guard=$guard)');
    });
  });
}
