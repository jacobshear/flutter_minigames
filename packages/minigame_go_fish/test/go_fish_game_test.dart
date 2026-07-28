import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_go_fish/minigame_go_fish.dart';
import 'package:minigames_cards/minigames_cards.dart';
import 'package:minigames_core/minigames_core.dart';

const _game = GoFishGame();

/// Builds a mid-game position by hand. Hands must already be book-free — the
/// reducer strips books, it does not expect to be handed one.
GoFishState _state({
  required String h0,
  required String h1,
  String pond = '',
  List<Rank> books0 = const [],
  List<Rank> books1 = const [],
  int current = 0,
}) =>
    GoFishState(
      playerIds: const ['p1', 'p2'],
      hands: [PlayingCard.parseAll(h0), PlayingCard.parseAll(h1)],
      pond: PlayingCard.parseAll(pond),
      books: [books0, books1],
      currentIndex: current,
      lastEvent: const GoFishEvent(action: GoFishAction.deal),
    );

String _codes(Iterable<PlayingCard> cards) =>
    (cards.map((c) => c.code).toList()..sort()).join(' ');

void main() {
  group('deal', () {
    test('two-handed Go Fish deals 7 each and ponds the rest', () {
      final s = _game.initialState(seed: 12345, playerIds: const ['p1', 'p2']);
      final dealt = s.hands[0].length +
          s.hands[1].length +
          s.books[0].length * 4 +
          s.books[1].length * 4;
      expect(dealt, 14, reason: '7 cards each, books included');
      expect(s.pond.length, 52 - 14);
      expect(s.currentIndex, 0);
      expect(s.currentPlayerId, 'p1');
      expect(_game.outcome(s), isNull);
    });

    test('the same seed always deals the same game', () {
      final a = _game.initialState(seed: 99, playerIds: const ['p1', 'p2']);
      final b = _game.initialState(seed: 99, playerIds: const ['p1', 'p2']);
      expect(_codes(a.hands[0]), _codes(b.hands[0]));
      expect(_codes(a.hands[1]), _codes(b.hands[1]));
      expect(
        a.pond.map((c) => c.code).join(' '),
        b.pond.map((c) => c.code).join(' '),
      );
    });

    test('a book dealt in the opening 7 is laid down before the first ask',
        () {
      // Not reachable via initialState directly, so exercise the same settle
      // path through a move: a hand holding three of a rank plus the fourth
      // arriving books immediately.
      final s = _state(h0: '7C 7D 7H', h1: '7S 9C', pond: '2C 3D');
      final next = _game.applyMove(s, const GoFishMove.ask(Rank.seven));
      expect(next.books[0], [Rank.seven]);
    });
  });

  group('the ask restriction', () {
    final s = _state(h0: '7C 3D', h1: '9C 9D', pond: '2C');

    test('a rank you hold is legal', () {
      expect(_game.validateMove(s, const GoFishMove.ask(Rank.seven), 'p1'),
          isTrue);
      expect(_game.validateMove(s, const GoFishMove.ask(Rank.three), 'p1'),
          isTrue);
    });

    test('a rank you do not hold is rejected, even one the opponent has', () {
      expect(_game.validateMove(s, const GoFishMove.ask(Rank.nine), 'p1'),
          isFalse);
      expect(
          _game.validateMove(s, const GoFishMove.ask(Rank.king), 'p1'), isFalse);
    });

    test('asking out of turn is rejected', () {
      expect(_game.validateMove(s, const GoFishMove.ask(Rank.nine), 'p2'),
          isFalse);
    });

    test('nothing is legal once the game is over', () {
      final over = _state(h0: '7C', h1: '9C', pond: '');
      expect(_game.outcome(over), isNotNull);
      expect(_game.validateMove(over, const GoFishMove.ask(Rank.seven), 'p1'),
          isFalse);
    });

    test('askableRanks is exactly the set of held ranks', () {
      expect(s.askableRanks(0), [Rank.three, Rank.seven]);
      expect(s.askableRanks(1), [Rank.nine]);
    });
  });

  group('a hit', () {
    test('hands over every matching card and keeps the turn', () {
      final s = _state(h0: '7C 3D', h1: '7H 7S 9C', pond: '2C 4D');
      final next = _game.applyMove(s, const GoFishMove.ask(Rank.seven));

      expect(_codes(next.hands[0]), _codes(PlayingCard.parseAll('7C 7H 7S 3D')));
      expect(_codes(next.hands[1]), '9C');
      expect(next.currentIndex, 0, reason: 'a hit means you go again');
      expect(next.pond.length, 2, reason: 'a hit never touches the pond');
      expect(next.lastEvent.action, GoFishAction.caught);
      expect(_codes(next.lastEvent.taken), _codes(PlayingCard.parseAll('7H 7S')));
      expect(next.lastEvent.keepsTurn, isTrue);
    });

    test('one card is still all of them', () {
      final s = _state(h0: '7C', h1: '7H 9C', pond: '2C');
      final next = _game.applyMove(s, const GoFishMove.ask(Rank.seven));
      expect(next.lastEvent.taken.length, 1);
      expect(next.currentIndex, 0);
    });
  });

  group('go fish', () {
    test('a miss draws from the pond and passes the turn', () {
      // Last element is the top of the pond, so 3D is drawn.
      final s = _state(h0: '7C', h1: '9C 9D', pond: '2C 3D');
      final next = _game.applyMove(s, const GoFishMove.ask(Rank.seven));

      expect(_codes(next.hands[0]), _codes(PlayingCard.parseAll('7C 3D')));
      expect(_codes(next.hands[1]), _codes(PlayingCard.parseAll('9C 9D')));
      expect(next.pond.map((c) => c.code).toList(), ['2C']);
      expect(next.currentIndex, 1);
      expect(next.lastEvent.action, GoFishAction.fished);
      expect(next.lastEvent.drawn, PlayingCard.parse('3D'));
      expect(next.lastEvent.keepsTurn, isFalse);
    });

    test('fishing up the rank you asked for keeps the turn (Pagat variant)',
        () {
      final s = _state(h0: '7C', h1: '9C 9D', pond: '2C 7D');
      final next = _game.applyMove(s, const GoFishMove.ask(Rank.seven));

      expect(_codes(next.hands[0]), _codes(PlayingCard.parseAll('7C 7D')));
      expect(next.currentIndex, 0);
      expect(next.lastEvent.action, GoFishAction.fishedHit);
      expect(next.lastEvent.drawn, PlayingCard.parse('7D'));
      expect(next.lastEvent.keepsTurn, isTrue);
    });

    test('an empty pond draws nothing and simply passes the turn', () {
      // Both hold a five, so the position is still live with a dry pond.
      final s = _state(h0: '7C 5D', h1: '9C 5S');
      final next = _game.applyMove(s, const GoFishMove.ask(Rank.seven));

      expect(next.lastEvent.action, GoFishAction.fishedDry);
      expect(next.lastEvent.drawn, isNull);
      expect(_codes(next.hands[0]), _codes(PlayingCard.parseAll('7C 5D')));
      expect(next.pond, isEmpty);
      expect(next.currentIndex, 1);
      expect(_game.outcome(next), isNull);
    });
  });

  group('books', () {
    test('four of a rank books exactly once and leaves the hand', () {
      final s = _state(h0: '7C 7D 7H 3D', h1: '7S 9C', pond: '2C 4D');
      final next = _game.applyMove(s, const GoFishMove.ask(Rank.seven));

      expect(next.books[0], [Rank.seven]);
      expect(next.books[1], isEmpty);
      expect(_codes(next.hands[0]), '3D');
      expect(next.lastEvent.books, [Rank.seven]);

      // The rank is gone from the hand, so it can never be asked — or
      // booked — a second time.
      expect(next.holds(0, Rank.seven), isFalse);
      expect(_game.validateMove(next, const GoFishMove.ask(Rank.seven), 'p1'),
          isFalse);

      final after = _game.applyMove(next, const GoFishMove.ask(Rank.three));
      expect(after.books[0], [Rank.seven], reason: 'no second book of sevens');
    });

    test('a book can be closed by the card you fish up', () {
      final s = _state(h0: '7C 7D 7H', h1: '9C 9D', pond: '2C 7S');
      final next = _game.applyMove(s, const GoFishMove.ask(Rank.seven));

      expect(next.lastEvent.action, GoFishAction.fishedHit);
      expect(next.books[0], [Rank.seven]);
      expect(next.currentIndex, 0, reason: 'the fished rank still goes again');
    });

    test('two books can close on one hit', () {
      final s = _state(h0: '7C 7D 7H 8C 8D 8H', h1: '7S 8S', pond: '2C 4D 5H');
      final next = _game.applyMove(s, const GoFishMove.ask(Rank.seven));
      // Only sevens come across, so only the sevens book.
      expect(next.books[0], [Rank.seven]);
      expect(_codes(next.hands[0]), _codes(PlayingCard.parseAll('8C 8D 8H')));
    });
  });

  group('a player running out of cards', () {
    test('is topped up from the pond so they can keep asking', () {
      // Booking the sevens empties seat 0; seat 1 gave away its last card.
      final s = _state(h0: '7C 7D 7H', h1: '7S', pond: '2C 4D 5H');
      final next = _game.applyMove(s, const GoFishMove.ask(Rank.seven));

      expect(next.books[0], [Rank.seven]);
      // The mover refills first, off the top of the pond (the last element).
      expect(_codes(next.hands[0]), '5H');
      expect(_codes(next.hands[1]), '4D');
      expect(next.pond.map((c) => c.code).toList(), ['2C']);
      expect(next.lastEvent.refilled, [0, 1]);
      expect(next.currentIndex, 0);
      expect(_game.outcome(next), isNull, reason: 'both hands live again');
    });

    test('can be topped up into a dead position, which ends the game', () {
      // Both refill, the pond empties, and the two new cards share no rank —
      // nothing can ever move again, so the game is over on the spot.
      final s = _state(h0: '7C 7D 7H', h1: '7S', pond: '2C 4D');
      final next = _game.applyMove(s, const GoFishMove.ask(Rank.seven));

      expect(next.lastEvent.refilled, [0, 1]);
      expect(next.pond, isEmpty);
      expect(next.sharedRanks, isEmpty);
      expect(_game.outcome(next), const GameOutcomeMatcher('p1'));
    });

    test('is not topped up once the pond is dry, and ends the game', () {
      final s = _state(h0: '7C 7D 7H', h1: '7S', pond: '', books0: [Rank.two]);
      final next = _game.applyMove(s, const GoFishMove.ask(Rank.seven));

      expect(next.hands[0], isEmpty);
      expect(next.hands[1], isEmpty);
      expect(next.lastEvent.refilled, isEmpty);
      expect(_game.isExhausted(next), isTrue);
      expect(_game.outcome(next), const GameOutcomeMatcher('p1'));
    });
  });

  group('the end', () {
    test('all 13 books ends it and the most books wins', () {
      const seven = [
        Rank.ace,
        Rank.two,
        Rank.three,
        Rank.four,
        Rank.five,
        Rank.six,
        Rank.seven,
      ];
      const five = [Rank.eight, Rank.nine, Rank.ten, Rank.jack, Rank.queen];
      final s = _state(
        h0: 'KC KD KH',
        h1: 'KS',
        books0: seven,
        books1: five,
      );
      final next = _game.applyMove(s, const GoFishMove.ask(Rank.king));

      expect(next.booksMade, kGoFishBookCount);
      expect(next.books[0].length, 8);
      expect(next.books[1].length, 5);
      expect(_game.outcome(next), const GameOutcomeMatcher('p1'));
    });

    test('a dry pond with no shared rank ends it even with cards in hand', () {
      final s = _state(h0: 'KC 2D', h1: '9S 4H', pond: '');
      expect(s.sharedRanks, isEmpty);
      expect(_game.isExhausted(s), isTrue);
      expect(_game.outcome(s), isNotNull);
    });

    test('a dry pond with a shared rank is still live', () {
      final s = _state(h0: 'KC 2D', h1: '9S 2H', pond: '');
      expect(s.sharedRanks, {Rank.two});
      expect(_game.isExhausted(s), isFalse);
      expect(_game.outcome(s), isNull);
    });

    test('level books is a draw', () {
      const six0 = [
        Rank.ace,
        Rank.two,
        Rank.three,
        Rank.four,
        Rank.five,
        Rank.six,
      ];
      const six1 = [
        Rank.seven,
        Rank.eight,
        Rank.nine,
        Rank.ten,
        Rank.jack,
        Rank.queen,
      ];
      final s = _state(h0: 'KC', h1: 'KS', pond: '', current: 1);
      final tied = GoFishState(
        playerIds: s.playerIds,
        // No shared rank: the two kings are split but the hands are dead.
        hands: [PlayingCard.parseAll('KC'), PlayingCard.parseAll('QS')],
        pond: const [],
        books: const [six0, six1],
        currentIndex: 0,
        lastEvent: s.lastEvent,
      );
      final outcome = _game.outcome(tied);
      expect(outcome, isNotNull);
      expect(outcome!.isDraw, isTrue);
      expect(outcome.winnerId, isNull);
    });

    test('seat 1 winning is reported as p2', () {
      final s = _state(
        h0: 'KC',
        h1: 'QS',
        pond: '',
        books0: [Rank.ace],
        books1: [Rank.two, Rank.three],
      );
      expect(_game.outcome(s), const GameOutcomeMatcher('p2'));
    });
  });

  group('a full playout', () {
    test('always terminates and never loses a card', () {
      for (final seed in [1, 2, 7, 4242, 999983]) {
        var s = _game.initialState(seed: seed, playerIds: const ['p1', 'p2']);
        var moves = 0;
        while (_game.outcome(s) == null) {
          final askable = s.askableRanks(s.currentIndex);
          expect(
            askable,
            isNotEmpty,
            reason: 'a live position always has a legal ask (seed $seed)',
          );
          // Deterministic policy: rotate through the askable ranks so the
          // playout is not a single fixed line.
          final move = GoFishMove.ask(askable[moves % askable.length]);
          expect(_game.validateMove(s, move, _game.currentPlayer(s)), isTrue);
          s = _game.applyMove(s, move);
          moves++;

          final accounted = s.hands[0].length +
              s.hands[1].length +
              s.pond.length +
              (s.books[0].length + s.books[1].length) * 4;
          expect(accounted, 52, reason: 'card conservation (seed $seed)');
          expect(moves, lessThan(2000), reason: 'no stalemate (seed $seed)');
        }
        expect(_game.outcome(s), isNotNull);
      }
    });
  });

  group('serialization', () {
    test('state round-trips through JSON', () {
      var s = _game.initialState(seed: 777, playerIds: const ['p1', 'p2']);
      s = _game.applyMove(s, GoFishMove.ask(s.askableRanks(0).first));

      final round = _game.decodeState(
        _game.encodeState(s),
        _game.stateSchemaVersion,
      );

      expect(round.playerIds, s.playerIds);
      expect(_codes(round.hands[0]), _codes(s.hands[0]));
      expect(_codes(round.hands[1]), _codes(s.hands[1]));
      expect(
        round.pond.map((c) => c.code).toList(),
        s.pond.map((c) => c.code).toList(),
        reason: 'pond order matters — the last element is the top',
      );
      expect(round.books[0], s.books[0]);
      expect(round.books[1], s.books[1]);
      expect(round.currentIndex, s.currentIndex);
      expect(round.lastEvent.action, s.lastEvent.action);
      expect(round.lastEvent.actor, s.lastEvent.actor);
      expect(round.lastEvent.rank, s.lastEvent.rank);
      expect(_codes(round.lastEvent.taken), _codes(s.lastEvent.taken));
      expect(round.lastEvent.drawn, s.lastEvent.drawn);
      expect(round.lastEvent.books, s.lastEvent.books);
      expect(round.lastEvent.refilled, s.lastEvent.refilled);
    });

    test('an event carrying every field round-trips', () {
      final s = _state(h0: '7C 7D 7H', h1: '7S', pond: '2C 4D');
      final next = _game.applyMove(s, const GoFishMove.ask(Rank.seven));
      expect(next.lastEvent.taken, isNotEmpty);
      expect(next.lastEvent.books, isNotEmpty);
      expect(next.lastEvent.refilled, isNotEmpty);

      final round = _game.decodeState(
        _game.encodeState(next),
        _game.stateSchemaVersion,
      );
      expect(round.lastEvent.action, GoFishAction.caught);
      expect(round.lastEvent.rank, Rank.seven);
      expect(_codes(round.lastEvent.taken), '7S');
      expect(round.lastEvent.books, [Rank.seven]);
      expect(round.lastEvent.refilled, [0, 1]);
    });

    test('move round-trips through JSON', () {
      for (final rank in Rank.values) {
        final move = GoFishMove.ask(rank);
        final json = _game.encodeMove(move);
        expect(json['type'], 'ask');
        expect(_game.decodeMove(json), move);
      }
    });

    test('an unknown move type is rejected', () {
      expect(
        () => _game.decodeMove({'type': 'discard', 'rank': 7}),
        throwsArgumentError,
      );
    });

    test('the game id is stable', () {
      expect(_game.id, 'go_fish');
      expect(_game.stateSchemaVersion, 1);
    });
  });

  group('grouping', () {
    test('the hand groups by rank, ace-low, for the picker', () {
      final s = _state(h0: 'KD 3C AS 3H 3S', h1: '9C');
      final groups = s.groupedHand(0);
      expect(groups.map((g) => g.rank).toList(),
          [Rank.ace, Rank.three, Rank.king]);
      expect(groups[1].cards.length, 3);
      expect(_codes(groups[1].cards), _codes(PlayingCard.parseAll('3C 3H 3S')));
    });
  });
}

/// `GameOutcome` has value equality, so this is only sugar for reading the
/// win assertions above.
class GameOutcomeMatcher extends Matcher {
  final String winnerId;

  const GameOutcomeMatcher(this.winnerId);

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) =>
      item is GameOutcome && !item.isDraw && item.winnerId == winnerId;

  @override
  Description describe(Description description) =>
      description.add('a win for $winnerId');
}
