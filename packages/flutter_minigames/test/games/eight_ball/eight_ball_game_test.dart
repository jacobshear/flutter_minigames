import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/eight_ball/eight_ball.dart';
import 'package:flutter_minigames/src/core/core.dart';

void main() {
  const game = EightBallGame();

  EightBallState fresh() =>
      game.initialState(seed: 0, playerIds: const ['p1', 'p2']);

  // A shot outcome: carry every current ball, marking [pocket] (and the cue if
  // [cueScratch]) as pocketed. [firstHit] is the first ball the cue struck.
  EightBallMove shot(
    EightBallState s,
    String owner, {
    List<int> pocket = const [],
    int? firstHit,
    bool cueScratch = false,
  }) {
    return EightBallMove.shot(
      owner: owner,
      firstHitNumber: firstHit,
      positions: [
        for (final b in s.balls)
          BallPosition(
            number: b.number,
            nx: b.nx,
            ny: b.ny,
            pocketed: b.pocketed ||
                pocket.contains(b.number) ||
                (cueScratch && b.number == EightBallGame.cueNumber),
          ),
      ],
    );
  }

  // A state past the break with groups assigned (p1 solids, p2 stripes).
  EightBallState assigned({
    String current = 'p1',
    List<int> pocketedNumbers = const [],
    bool ballInHand = false,
  }) {
    final base = fresh();
    final balls = [
      for (final b in base.balls)
        b.copyWith(pocketed: pocketedNumbers.contains(b.number)),
    ];
    return base.copyWith(
      balls: balls,
      groups: {'p1': BallGroup.solids, 'p2': BallGroup.stripes},
      currentPlayerId: current,
      shotsTaken: 4,
      ballInHand: ballInHand,
    );
  }

  group('setup', () {
    test('opens with cue + 15 balls, p1 to break, open table', () {
      final s = fresh();
      expect(s.balls.length, 16);
      expect(s.balls.where((b) => b.pocketed), isEmpty);
      expect(game.currentPlayer(s), 'p1');
      expect(s.isOpenTable, isTrue);
      expect(s.shotsTaken, 0);
      expect(game.outcome(s), isNull);
      // The 8 is racked, cue is on the head end.
      expect(s.cue.ny, greaterThan(0.5));
    });

    test('groupOf classifies solids / stripes / neither', () {
      expect(EightBallGame.groupOf(1), BallGroup.solids);
      expect(EightBallGame.groupOf(7), BallGroup.solids);
      expect(EightBallGame.groupOf(9), BallGroup.stripes);
      expect(EightBallGame.groupOf(15), BallGroup.stripes);
      expect(EightBallGame.groupOf(8), isNull);
      expect(EightBallGame.groupOf(0), isNull);
    });
  });

  // The rack used to be laid out with a single "gap" constant reused for both
  // axes, which packed each row to ~59% of a ball diameter — every ball opened
  // visibly overlapping its neighbours until the break shook them apart. These
  // are the regression guards; they work in *world* units, the only frame where
  // "overlapping" means anything (nx and ny are on different scales).
  group('rack geometry', () {
    const d = EightBallGame.ballD; // 0.84 world units

    List<Ball> onTable(EightBallState s) => [
          for (final b in s.balls)
            if (!b.pocketed) b
        ];

    test('no two balls overlap in the opening layout', () {
      final balls = onTable(fresh());
      expect(balls.length, 16);
      for (var i = 0; i < balls.length; i++) {
        for (var j = i + 1; j < balls.length; j++) {
          final a = balls[i], b = balls[j];
          expect(
            EightBallGame.worldGap(a, b),
            greaterThanOrEqualTo(d),
            reason: 'balls ${a.number} and ${b.number} overlap '
                '(centres ${EightBallGame.worldGap(a, b).toStringAsFixed(4)} '
                'apart, need $d)',
          );
        }
      }
    });

    test('the rack is tight — every ball touches a neighbour', () {
      final rack = [
        for (final b in fresh().balls)
          if (!b.isCue) b
      ];
      expect(rack.length, 15);
      // 1% of a diameter: close enough to touching that no gap is visible.
      const eps = d * 0.01;
      for (final b in rack) {
        final nearest = rack
            .where((o) => o.number != b.number)
            .map((o) => EightBallGame.worldGap(b, o))
            .reduce(math.min);
        expect(
          nearest,
          lessThanOrEqualTo(d + eps),
          reason: 'ball ${b.number} floats ${nearest.toStringAsFixed(4)} from '
              'its nearest neighbour; a tight rack touches at $d',
        );
      }
    });

    test('rows are one diameter across and √3/2 diameters apart', () {
      final rack = [
        for (final b in fresh().balls)
          if (!b.isCue) b
      ];
      // Group by row (equal ny).
      final rows = <double, List<Ball>>{};
      for (final b in rack) {
        rows
            .putIfAbsent(
              rows.keys.firstWhere((k) => (k - b.ny).abs() < 1e-9,
                  orElse: () => b.ny),
              () => <Ball>[],
            )
            .add(b);
      }
      final nys = rows.keys.toList()..sort();
      expect(rows.length, 5);
      expect([for (final n in nys) rows[n]!.length], [5, 4, 3, 2, 1],
          reason: 'apex (1 ball) is nearest the breaker, i.e. largest ny');

      // Within a row: exactly one diameter, centre to centre.
      for (final row in rows.values) {
        row.sort((a, b) => a.nx.compareTo(b.nx));
        for (var i = 1; i < row.length; i++) {
          expect(
            (row[i].nx - row[i - 1].nx) * EightBallGame.tableW,
            closeTo(d, d * 0.01),
          );
        }
      }
      // Between rows: diameter × √3/2, perpendicular.
      for (var i = 1; i < nys.length; i++) {
        expect(
          (nys[i] - nys[i - 1]) * EightBallGame.tableL,
          closeTo(d * math.sqrt(3) / 2, d * 0.01),
        );
      }
    });

    test('the whole rack and the cue stay on the table', () {
      // addBounds walls the sim at the felt edge, so a centre must sit at least
      // one radius inside on both axes.
      final marginX = EightBallGame.ballR / EightBallGame.tableW;
      final marginY = EightBallGame.ballR / EightBallGame.tableL;
      for (final b in fresh().balls) {
        expect(b.nx, inInclusiveRange(marginX, 1 - marginX));
        expect(b.ny, inInclusiveRange(marginY, 1 - marginY));
      }
    });

    test('legal rack: apex on the foot spot, 8 centred in row 3, mixed corners',
        () {
      final s = fresh();
      final apex = s.ball(1);
      expect(apex.nx, closeTo(0.5, 1e-9));
      expect(apex.ny, closeTo(EightBallGame.rackApexNy, 1e-9));

      final eight = s.ball(8);
      expect(eight.nx, closeTo(0.5, 1e-9), reason: '8 is dead centre');
      expect(
        eight.ny,
        closeTo(EightBallGame.rackApexNy - 2 * EightBallGame.rackRowGap, 1e-9),
        reason: '8 sits in the third row',
      );

      // Back row = smallest ny; its outermost balls are one of each group.
      final back = [
        for (final b in s.balls)
          if (!b.isCue &&
              (b.ny - (EightBallGame.rackApexNy - 4 * EightBallGame.rackRowGap))
                      .abs() <
                  1e-9)
            b,
      ]..sort((a, b) => a.nx.compareTo(b.nx));
      expect(back.length, 5);
      expect(
        {back.first.group, back.last.group},
        {BallGroup.solids, BallGroup.stripes},
      );
    });

    test('cue breaks from behind the head string, apex-first', () {
      final s = fresh();
      expect(s.cue.nx, closeTo(0.5, 1e-9));
      expect(s.cue.ny, greaterThan(EightBallGame.headStringNy));
      // The apex is the closest object ball to the cue: the breaker sees the
      // point of the triangle, not the flat back row.
      final closest = [
        for (final b in s.balls)
          if (!b.isCue) b,
      ].reduce((a, b) =>
          EightBallGame.worldGap(s.cue, a) < EightBallGame.worldGap(s.cue, b)
              ? a
              : b);
      expect(closest.number, 1);
    });
  });

  group('group assignment on first pot', () {
    test('break never assigns even if a ball drops', () {
      var s = fresh();
      s = game.applyMove(s, shot(s, 'p1', pocket: [2], firstHit: 1));
      expect(s.isOpenTable, isTrue, reason: 'table stays open on the break');
      expect(s.shotsTaken, 1);
      // Potting on the break still keeps the shooter at the table.
      expect(s.currentPlayerId, 'p1');
    });

    test('first non-break pot assigns the potter their group', () {
      var s = fresh();
      // Break: dry, pass to p2.
      s = game.applyMove(s, shot(s, 'p1', firstHit: 1));
      expect(s.currentPlayerId, 'p2');
      // p2 sinks a stripe on the open table.
      s = game.applyMove(s, shot(s, 'p2', pocket: [11], firstHit: 11));
      expect(s.groups['p2'], BallGroup.stripes);
      expect(s.groups['p1'], BallGroup.solids);
      expect(s.currentPlayerId, 'p2', reason: 'made a ball, keeps the turn');
    });

    test('potting both groups on the open table keeps it open', () {
      var s = fresh();
      s = game.applyMove(s, shot(s, 'p1', firstHit: 1)); // dry break
      s = game.applyMove(s, shot(s, 'p2', pocket: [3, 11], firstHit: 3));
      expect(s.isOpenTable, isTrue);
      // Still made balls with no foul → continues.
      expect(s.currentPlayerId, 'p2');
    });
  });

  group('fouls', () {
    test('cue scratch is a foul → opponent ball in hand', () {
      var s = fresh();
      s = game.applyMove(s, shot(s, 'p1', firstHit: 1, cueScratch: true));
      expect(s.currentPlayerId, 'p2');
      expect(s.ballInHand, isTrue);
      expect(s.cue.pocketed, isTrue);
    });

    test('hitting no ball is a foul', () {
      var s = fresh();
      s = game.applyMove(s, shot(s, 'p1', firstHit: null));
      expect(s.ballInHand, isTrue);
      expect(s.currentPlayerId, 'p2');
    });

    test('striking the wrong group first is a foul', () {
      // p1 is solids; hitting a stripe (9) first fouls.
      final s = assigned(current: 'p1');
      final next = game.applyMove(s, shot(s, 'p1', firstHit: 9));
      expect(next.ballInHand, isTrue);
      expect(next.currentPlayerId, 'p2');
    });

    test('striking your own group first is legal', () {
      final s = assigned(current: 'p1');
      final next = game.applyMove(s, shot(s, 'p1', pocket: [3], firstHit: 3));
      expect(next.ballInHand, isFalse);
      expect(next.currentPlayerId, 'p1', reason: 'potted own, keeps turn');
    });
  });

  group('turn pass vs continue', () {
    test('a dry legal shot passes the turn (no ball in hand)', () {
      final s = assigned(current: 'p1');
      final next = game.applyMove(s, shot(s, 'p1', firstHit: 1));
      expect(next.currentPlayerId, 'p2');
      expect(next.ballInHand, isFalse);
    });

    test('sinking only an opponent ball passes the turn, no ball in hand', () {
      // p1 solids strikes own (legal) but only an opponent stripe drops.
      final s = assigned(current: 'p1');
      final next = game.applyMove(s, shot(s, 'p1', pocket: [10], firstHit: 1));
      expect(next.currentPlayerId, 'p2');
      expect(next.ballInHand, isFalse);
      expect(next.ball(10).pocketed, isTrue);
    });

    test('potting your own ball keeps the turn', () {
      final s = assigned(current: 'p1');
      final next = game.applyMove(s, shot(s, 'p1', pocket: [5], firstHit: 5));
      expect(next.currentPlayerId, 'p1');
    });
  });

  group('pocket → removed scoring from a move outcome', () {
    test('applyMove marks potted balls and decrements remaining', () {
      final s = assigned(current: 'p1');
      expect(s.remainingCountOf('p1'), 7);
      final next =
          game.applyMove(s, shot(s, 'p1', pocket: [1, 2], firstHit: 1));
      expect(next.ball(1).pocketed, isTrue);
      expect(next.ball(2).pocketed, isTrue);
      expect(next.remainingCountOf('p1'), 5);
    });
  });

  group('8-ball win vs early-8 loss', () {
    test('potting the 8 after clearing your group wins', () {
      final s = assigned(
        current: 'p1',
        pocketedNumbers: const [1, 2, 3, 4, 5, 6, 7],
      );
      expect(EightBallGame.groupCleared(s.balls, BallGroup.solids), isTrue);
      final next = game.applyMove(s, shot(s, 'p1', pocket: [8], firstHit: 8));
      expect(next.over, isTrue);
      expect(next.winnerId, 'p1');
      expect(game.outcome(next), const GameOutcome.win('p1'));
    });

    test('potting the 8 early loses (opponent wins)', () {
      final s = assigned(current: 'p1'); // no solids cleared yet
      final next = game.applyMove(s, shot(s, 'p1', pocket: [8], firstHit: 8));
      expect(next.over, isTrue);
      expect(next.winnerId, 'p2');
    });

    test('scratching while potting the 8 loses even after clearing', () {
      final s = assigned(
        current: 'p1',
        pocketedNumbers: const [1, 2, 3, 4, 5, 6, 7],
      );
      final next = game.applyMove(
        s,
        shot(s, 'p1', pocket: [8], firstHit: 8, cueScratch: true),
      );
      expect(next.over, isTrue);
      expect(next.winnerId, 'p2');
    });
  });

  group('ball-in-hand', () {
    test('placement repositions the cue and keeps the shooter', () {
      final s = assigned(
        current: 'p2',
        pocketedNumbers: const [],
        ballInHand: true,
      ).copyWith(
        balls: [
          for (final b in fresh().balls)
            b.isCue ? b.copyWith(pocketed: true) : b,
        ],
      );
      final move = EightBallMove.place(owner: 'p2', cueNx: 0.5, cueNy: 0.7);
      expect(game.validateMove(s, move, 'p2'), isTrue);
      final next = game.applyMove(s, move);
      expect(next.ballInHand, isFalse);
      expect(next.currentPlayerId, 'p2', reason: 'same player now shoots');
      expect(next.cue.pocketed, isFalse);
      expect(next.cue.nx, closeTo(0.5, 1e-9));
      expect(next.cue.ny, closeTo(0.7, 1e-9));
    });

    test('a shot is rejected while ball-in-hand is pending', () {
      final s = assigned(current: 'p2', ballInHand: true);
      expect(game.validateMove(s, shot(s, 'p2', firstHit: 9), 'p2'), isFalse);
    });

    test('placement rejected when out of bounds or not owed', () {
      final owed = assigned(current: 'p2', ballInHand: true);
      expect(
        game.validateMove(
            owed,
            const EightBallMove.place(owner: 'p2', cueNx: 1.4, cueNy: 0.5),
            'p2'),
        isFalse,
      );
      final notOwed = assigned(current: 'p2', ballInHand: false);
      expect(
        game.validateMove(
            notOwed,
            const EightBallMove.place(owner: 'p2', cueNx: 0.5, cueNy: 0.5),
            'p2'),
        isFalse,
      );
    });
  });

  group('validation', () {
    test('rejects out-of-turn and wrong-owner shots', () {
      final s = fresh();
      expect(game.validateMove(s, shot(s, 'p2', firstHit: 1), 'p2'), isFalse);
      expect(game.validateMove(s, shot(s, 'p2', firstHit: 1), 'p1'), isFalse);
    });

    test('rejects a shot missing an on-table ball', () {
      final s = fresh();
      final bad = EightBallMove.shot(
        owner: 'p1',
        firstHitNumber: 1,
        positions: [
          for (final b in s.balls)
            if (b.number != 5)
              BallPosition(number: b.number, nx: b.nx, ny: b.ny),
        ],
      );
      expect(game.validateMove(s, bad, 'p1'), isFalse);
    });

    test('accepts a well-formed break', () {
      final s = fresh();
      expect(game.validateMove(s, shot(s, 'p1', firstHit: 1), 'p1'), isTrue);
    });

    test('no move is legal once the game is over', () {
      final over = assigned(
        current: 'p1',
        pocketedNumbers: const [1, 2, 3, 4, 5, 6, 7],
      );
      final won =
          game.applyMove(over, shot(over, 'p1', pocket: [8], firstHit: 8));
      expect(
          game.validateMove(won, shot(won, 'p2', firstHit: 9), 'p2'), isFalse);
    });
  });

  group('serialization', () {
    test('state round-trips through JSON', () {
      var s = fresh();
      s = game.applyMove(s, shot(s, 'p1', firstHit: 1)); // dry break
      s = game.applyMove(
          s, shot(s, 'p2', pocket: [11], firstHit: 11)); // assign
      final decoded =
          game.decodeState(game.encodeState(s), game.stateSchemaVersion);
      expect(decoded.balls.length, s.balls.length);
      expect(decoded.currentPlayerId, s.currentPlayerId);
      expect(decoded.groups['p2'], BallGroup.stripes);
      expect(decoded.shotsTaken, s.shotsTaken);
      expect(decoded.ball(11).pocketed, isTrue);
    });

    test('shot move round-trips through JSON', () {
      final s = fresh();
      final move = shot(s, 'p1', pocket: [1], firstHit: 1);
      final decoded = game.decodeMove(game.encodeMove(move));
      expect(decoded.kind, MoveKind.shot);
      expect(decoded.owner, 'p1');
      expect(decoded.firstHitNumber, 1);
      expect(decoded.positions!.length, move.positions!.length);
      expect(
          decoded.positions!.firstWhere((p) => p.number == 1).pocketed, isTrue);
    });

    test('placement move round-trips through JSON', () {
      const move = EightBallMove.place(owner: 'p2', cueNx: 0.33, cueNy: 0.66);
      final decoded = game.decodeMove(game.encodeMove(move));
      expect(decoded.kind, MoveKind.place);
      expect(decoded.cueNx, closeTo(0.33, 1e-9));
      expect(decoded.cueNy, closeTo(0.66, 1e-9));
    });
  });
}
