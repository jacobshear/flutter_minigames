import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/mini_golf/mini_golf.dart';

/// The complaint that drove this rewrite: "these minigolf holes are still
/// ridiculously similar to each other". These tests are the guard against it
/// coming back.
void main() {
  group('determinism', () {
    test('same seed reproduces an identical hole', () {
      for (final seed in [0, 7, 1234, -3]) {
        final a = MiniGolfCourse.forSeed(seed);
        final b = MiniGolfCourse.forSeed(seed);
        expect(a.fingerprint, b.fingerprint);
        expect(a.par, b.par);
        expect(a.routeLength, b.routeLength);
      }
    });

    test('same base seed reproduces an identical course', () {
      for (var h = 0; h < 9; h++) {
        final a = MiniGolfCourse.forHole(42, h);
        final b = MiniGolfCourse.forHole(42, h);
        expect(a.fingerprint, b.fingerprint);
        expect(a.archetype, b.archetype);
      }
    });

    test('different base seeds give different courses', () {
      final a = [for (var h = 0; h < 9; h++) MiniGolfCourse.forHole(1, h)];
      final b = [for (var h = 0; h < 9; h++) MiniGolfCourse.forHole(2, h)];
      final same = List.generate(9, (i) => a[i].fingerprint == b[i].fingerprint)
          .where((x) => x)
          .length;
      expect(same, 0);
    });
  });

  group('variety', () {
    test('no two consecutive holes share a fingerprint', () {
      for (var base = 0; base < 60; base++) {
        final course = [
          for (var h = 0; h < 9; h++) MiniGolfCourse.forHole(base, h),
        ];
        for (var h = 1; h < course.length; h++) {
          expect(
            course[h].fingerprint,
            isNot(course[h - 1].fingerprint),
            reason: 'base $base: hole ${h + 1} duplicates hole $h',
          );
          expect(
            course[h].archetype,
            isNot(course[h - 1].archetype),
            reason: 'base $base: hole ${h + 1} repeats the previous shape',
          );
        }
      }
    });

    test('every hole in a course has a unique fingerprint', () {
      for (var base = 0; base < 40; base++) {
        final prints = <String>{
          for (var h = 0; h < 9; h++)
            MiniGolfCourse.forHole(base, h).fingerprint,
        };
        expect(prints.length, 9, reason: 'base $base repeats a layout');
      }
    });

    test('a 9-hole course uses every archetype', () {
      for (var base = 0; base < 40; base++) {
        final used = <MiniGolfArchetype>{
          for (var h = 0; h < 9; h++) MiniGolfCourse.forHole(base, h).archetype,
        };
        expect(
          used.length,
          MiniGolfArchetype.values.length,
          reason: 'base $base only used ${used.map((a) => a.name)}',
        );
      }
    });

    test('archetype running order actually varies between courses', () {
      final orders = <String>{
        for (var base = 0; base < 30; base++)
          MiniGolfCourse.archetypeOrder(base).map((a) => a.index).join(),
      };
      expect(orders.length, greaterThan(20),
          reason: 'the deal is barely shuffling');
    });

    test('a short course still walks distinct shapes', () {
      for (var base = 0; base < 20; base++) {
        for (final n in [3, 6]) {
          final used = <MiniGolfArchetype>{
            for (var h = 0; h < n; h++)
              MiniGolfCourse.forHole(base, h).archetype,
          };
          expect(used.length, n);
        }
      }
    });

    test('outlines differ in shape, not just in numbers', () {
      // Vertex counts and lateral/length ratios should spread across a course —
      // eight variants of one rectangle would pass a fingerprint test but fail
      // this one.
      final ratios = <double>[];
      final vertexCounts = <int>{};
      for (var h = 0; h < 9; h++) {
        final c = MiniGolfCourse.forHole(11, h);
        ratios.add(c.width / c.length);
        vertexCounts.add(c.outline.length);
      }
      ratios.sort();
      expect(ratios.last / ratios.first, greaterThan(1.6));
      expect(vertexCounts.length, greaterThan(2));
    });
  });

  group('length', () {
    test('every hole is longer than a single putt can reach', () {
      for (var base = 0; base < 30; base++) {
        for (var h = 0; h < 9; h++) {
          final c = MiniGolfCourse.forHole(base, h);
          expect(
            c.routeLength,
            greaterThan(MiniGolfCourse.maxPuttReach),
            reason: '${c.archetype.name} is a one-putt hole',
          );
        }
      }
    });

    test('length varies substantially across a course', () {
      for (var base = 0; base < 30; base++) {
        final routes = [
          for (var h = 0; h < 9; h++)
            MiniGolfCourse.forHole(base, h).routeLength,
        ]..sort();
        expect(routes.last / routes.first, greaterThan(1.5),
            reason: 'base $base: every hole is the same length');
      }
    });

    test('par spreads across a course and covers short and long holes', () {
      final seen = <int>{};
      for (var base = 0; base < 30; base++) {
        final pars = [
          for (var h = 0; h < 9; h++) MiniGolfCourse.forHole(base, h).par
        ];
        expect(pars.toSet().length, greaterThanOrEqualTo(2),
            reason: 'base $base plays one flat par');
        seen.addAll(pars);
      }
      expect(seen.contains(2), isTrue, reason: 'no short par-2 anywhere');
      expect(seen.contains(4), isTrue, reason: 'no long par-4 anywhere');
      for (final p in seen) {
        expect(p, inInclusiveRange(2, 5));
      }
    });

    test('par tracks route length', () {
      // Longer route ⇒ never a lower par, within an archetype.
      for (final a in MiniGolfArchetype.values) {
        final samples = <({double route, int par})>[];
        for (var seed = 0; seed < 60; seed++) {
          final c = _forArchetype(a, seed);
          samples.add((route: c.routeLength, par: c.par));
        }
        samples.sort((x, y) => x.route.compareTo(y.route));
        expect(samples.first.par, lessThanOrEqualTo(samples.last.par),
            reason: a.name);
      }
    });
  });

  group('playability', () {
    test('tee and cup are on the green and clear of solids', () {
      for (var seed = 0; seed < 400; seed++) {
        final c = MiniGolfCourse.forSeed(seed);
        expect(c.containsWorld(c.tee), isTrue,
            reason: 'tee off green: ${c.archetype.name} seed $seed');
        expect(c.containsWorld(c.cup), isTrue,
            reason: 'cup off green: ${c.archetype.name} seed $seed');
        for (final o in c.obstacles) {
          expect(_clearOf(o, c.tee, MiniGolfCourse.ballRadius * 1.5), isTrue,
              reason: 'tee inside a solid: ${c.archetype.name} seed $seed');
          expect(_clearOf(o, c.cup, MiniGolfCourse.cupRadius * 1.2), isTrue,
              reason: 'cup inside a solid: ${c.archetype.name} seed $seed');
        }
      }
    });

    test('every obstacle leaves a lane of at least 2.5 ball diameters', () {
      // The bug this guards: an obstacle spanning the fairway, leaving gaps
      // barely wider than the ball — unplayable except dead-on.
      var checked = 0;
      for (var seed = 0; seed < 400; seed++) {
        final c = MiniGolfCourse.forSeed(seed);
        for (final o in c.obstacles) {
          checked++;
          expect(
            o.laneGap,
            greaterThanOrEqualTo(MiniGolfCourse.minObstacleGap),
            reason: '${c.archetype.name} seed $seed leaves ${o.laneGap}',
          );
        }
      }
      expect(checked, greaterThan(600), reason: 'not enough obstacles sampled');
    });

    test('the guarantee holds for every archetype independently', () {
      for (final a in MiniGolfArchetype.values) {
        var obstacles = 0;
        for (var seed = 0; seed < 120; seed++) {
          final c = _forArchetype(a, seed);
          expect(c.minFairwayWidth,
              greaterThanOrEqualTo(MiniGolfCourse.minFairwayFloor),
              reason: '${a.name} seed $seed narrows to ${c.minFairwayWidth}');
          for (final o in c.obstacles) {
            obstacles++;
            expect(
                o.laneGap, greaterThanOrEqualTo(MiniGolfCourse.minObstacleGap),
                reason: '${a.name} seed $seed');
          }
        }
        expect(obstacles, greaterThan(0), reason: '${a.name} has no obstacles');
      }
    });

    test('the ball can physically roll from tee to cup on every archetype', () {
      // The real guarantee, measured rather than claimed: flood-fill the ball's
      // configuration space (points at least one ball radius clear of every rail
      // and solid) and check the cup is reachable from the tee.
      for (final a in MiniGolfArchetype.values) {
        for (var seed = 0; seed < 8; seed++) {
          final c = _forArchetype(a, seed * 37 + 5);
          expect(_reachable(c), isTrue,
              reason: '${a.name} seed ${seed * 37 + 5} is unplayable');
        }
      }
    });
  });

  group('geometry', () {
    test('outlines are simple closed polygons wound counter-clockwise', () {
      for (var seed = 0; seed < 200; seed++) {
        final c = MiniGolfCourse.forSeed(seed);
        expect(c.outline.length, greaterThanOrEqualTo(4));
        expect(_signedArea(c.outline), greaterThan(0),
            reason: '${c.archetype.name} seed $seed is wound backwards');
      }
    });

    test('the hole runs down-range with the tee near and the cup far', () {
      for (var seed = 0; seed < 200; seed++) {
        final c = MiniGolfCourse.forSeed(seed);
        expect(c.cup.dy, greaterThan(c.tee.dy + 4),
            reason: '${c.archetype.name} seed $seed barely travels');
        expect(c.length, greaterThan(6));
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Finds a seed that generates [a] — the archetype is part of the draw in
/// [MiniGolfCourse.forSeed], so this walks forward until it lands on one.
MiniGolfCourse _forArchetype(MiniGolfArchetype a, int from) {
  for (var s = from; s < from + 400; s++) {
    final c = MiniGolfCourse.forSeed(s);
    if (c.archetype == a) return c;
  }
  fail('no seed near $from generates ${a.name}');
}

bool _clearOf(MiniGolfObstacle o, Offset p, double margin) {
  if (o.round) {
    return (p - Offset(o.centerX, o.centerZ)).distance > o.radius + margin;
  }
  final cx = p.dx.clamp(o.left, o.right);
  final cz = p.dy.clamp(o.near, o.far);
  return (p - Offset(cx, cz)).distance > margin;
}

double _signedArea(List<Offset> poly) {
  var area = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    area += a.dx * b.dy - b.dx * a.dy;
  }
  return area / 2;
}

/// Distance from [p] to the polygon boundary (unsigned).
double _distanceToOutline(List<Offset> poly, Offset p) {
  var best = double.infinity;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    final t = l2 < 1e-12
        ? 0.0
        : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
    best = math.min(best, (p - (a + ab * t)).distance);
  }
  return best;
}

/// Can the ball's centre legally occupy [p]?
bool _free(MiniGolfCourse c, Offset p) {
  const r = MiniGolfCourse.ballRadius;
  if (!c.containsWorld(p)) return false;
  if (_distanceToOutline(c.outline, p) < r) return false;
  for (final o in c.obstacles) {
    if (!_clearOf(o, p, r)) return false;
  }
  return true;
}

/// Flood-fills the free configuration space from the tee and reports whether
/// the cup is in the same connected component.
bool _reachable(MiniGolfCourse c) {
  const step = 0.06;
  final b = c.bounds;
  final cols = ((b.maxX - b.minX) / step).ceil() + 1;
  final rows = ((b.maxZ - b.minZ) / step).ceil() + 1;
  Offset at(int col, int row) =>
      Offset(b.minX + col * step, b.minZ + row * step);
  int idx(int col, int row) => row * cols + col;

  ({int col, int row}) nearestFree(Offset target) {
    var best = (col: -1, row: -1);
    var bestD = double.infinity;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final p = at(col, row);
        final d = (p - target).distance;
        if (d >= bestD) continue;
        if (!_free(c, p)) continue;
        bestD = d;
        best = (col: col, row: row);
      }
    }
    return best;
  }

  final start = nearestFree(c.tee);
  final goal = nearestFree(c.cup);
  if (start.col < 0 || goal.col < 0) return false;

  final seen = List<bool>.filled(cols * rows, false);
  final queue = Queue<({int col, int row})>()..add(start);
  seen[idx(start.col, start.row)] = true;
  const deltas = [(1, 0), (-1, 0), (0, 1), (0, -1)];
  while (queue.isNotEmpty) {
    final cur = queue.removeFirst();
    if (cur.col == goal.col && cur.row == goal.row) return true;
    for (final (dc, dr) in deltas) {
      final col = cur.col + dc;
      final row = cur.row + dr;
      if (col < 0 || row < 0 || col >= cols || row >= rows) continue;
      if (seen[idx(col, row)]) continue;
      seen[idx(col, row)] = true;
      if (!_free(c, at(col, row))) continue;
      queue.add((col: col, row: row));
    }
  }
  return false;
}
