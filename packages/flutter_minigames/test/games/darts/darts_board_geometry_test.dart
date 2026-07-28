import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/darts/darts.dart';

/// A point at [radiusRatio] of the scoring radius, [degreesClockwise] from the
/// top of the board.
({double x, double y}) at(double radiusRatio, double degreesClockwise) {
  final r = radiusRatio * DartsBoardGeometry.regulationRadius;
  final a = degreesClockwise * math.pi / 180;
  return (x: math.sin(a) * r, y: math.cos(a) * r);
}

DartHit score(double radiusRatio, double degreesClockwise) {
  final p = at(radiusRatio, degreesClockwise);
  return DartsBoardGeometry.hitAt(p.x, p.y);
}

void main() {
  group('bulls', () {
    test('dead centre is the bullseye, worth 50 and counts as a double', () {
      const hit = DartHit(25, 2);
      expect(DartsBoardGeometry.hitAt(0, 0), hit);
      expect(DartsBoardGeometry.hitAt(0, 0).value, 50);
      expect(DartsBoardGeometry.hitAt(0, 0).isDouble, isTrue);
      expect(DartsBoardGeometry.hitAt(0, 0).label, 'BULL');
    });

    test('the outer bull is 25 and is NOT a double', () {
      final hit = score(0.06, 137);
      expect(hit, const DartHit(25, 1));
      expect(hit.value, 25);
      expect(hit.isDouble, isFalse);
    });

    test('bull ring boundaries resolve to the inner band', () {
      // Exactly on the inner-bull wire is still the bullseye.
      expect(score(DartsBoardGeometry.innerBullRatio, 0),
          const DartHit(25, 2));
      // A hair outside it is the outer bull.
      expect(score(DartsBoardGeometry.innerBullRatio + 1e-6, 0),
          const DartHit(25, 1));
      // Exactly on the outer-bull wire is still 25.
      expect(score(DartsBoardGeometry.outerBullRatio, 0),
          const DartHit(25, 1));
      // A hair outside drops into the sector bed.
      expect(score(DartsBoardGeometry.outerBullRatio + 1e-6, 0),
          const DartHit(20, 1));
    });
  });

  group('sectors', () {
    test('the standard clockwise order is on the board', () {
      const expected = [
        20, 1, 18, 4, 13, 6, 10, 15, 2, 17, //
        3, 19, 7, 16, 8, 11, 14, 9, 12, 5,
      ];
      for (var i = 0; i < 20; i++) {
        // Sample the centre of each sector, mid-bed.
        expect(score(0.4, i * 18.0).sector, expected[i],
            reason: 'sector at ${i * 18}°');
      }
    });

    test('cardinal sectors are where a real board puts them', () {
      expect(score(0.4, 0).sector, 20); // top
      expect(score(0.4, 90).sector, 6); // right
      expect(score(0.4, 180).sector, 3); // bottom
      expect(score(0.4, 270).sector, 11); // left
    });

    test('sector wires split cleanly', () {
      // The 20/1 wire sits 9° clockwise of the top; the 5/20 wire 9° back.
      // A dart a thousandth of a degree either side lands in the right bed.
      expect(score(0.4, 9.001).sector, 1);
      expect(score(0.4, 8.999).sector, 20);
      expect(score(0.4, -8.999).sector, 20);
      expect(score(0.4, -9.001).sector, 5);
      // Every one of the twenty wires separates two different sectors.
      for (var i = 0; i < 20; i++) {
        final wire = i * 18.0 + 9;
        expect(score(0.4, wire - 0.001).sector,
            isNot(score(0.4, wire + 0.001).sector));
      }
    });

    test('angles wrap past a full turn', () {
      expect(score(0.4, 360).sector, 20);
      expect(score(0.4, 378).sector, 1);
    });
  });

  group('rings', () {
    test('single beds either side of the treble', () {
      expect(score(0.3, 0), const DartHit(20, 1));
      expect(score(0.8, 0), const DartHit(20, 1));
    });

    test('the treble ring trebles the sector', () {
      final hit = score(0.6, 0);
      expect(hit, const DartHit(20, 3));
      expect(hit.value, 60);
      expect(hit.label, 'T20');
    });

    test('the double ring doubles the sector', () {
      final hit = score(0.98, 0);
      expect(hit, const DartHit(20, 2));
      expect(hit.value, 40);
      expect(hit.isDouble, isTrue);
      expect(hit.label, 'D20');
    });

    test('treble band boundaries are inclusive', () {
      expect(score(DartsBoardGeometry.innerTrebleRatio, 90),
          const DartHit(6, 3));
      expect(score(DartsBoardGeometry.outerTrebleRatio, 90),
          const DartHit(6, 3));
      expect(score(DartsBoardGeometry.innerTrebleRatio - 1e-6, 90),
          const DartHit(6, 1));
      expect(score(DartsBoardGeometry.outerTrebleRatio + 1e-6, 90),
          const DartHit(6, 1));
    });

    test('double band boundaries are inclusive, and the edge is the edge', () {
      expect(score(DartsBoardGeometry.innerDoubleRatio, 180),
          const DartHit(3, 2));
      expect(score(DartsBoardGeometry.innerDoubleRatio - 1e-6, 180),
          const DartHit(3, 1));
      expect(score(1.0, 180), const DartHit(3, 2));
      expect(score(1.0 + 1e-6, 180), DartHit.miss);
    });

    test('outside the double ring scores nothing', () {
      final hit = score(1.15, 45);
      expect(hit, DartHit.miss);
      expect(hit.value, 0);
      expect(hit.isMiss, isTrue);
      expect(hit.label, 'MISS');
    });
  });

  test('scoring scales with the board radius', () {
    // The same *ratio* scores the same on a board of any size — this is what
    // lets the scene stage an oversized board without changing the rules.
    const big = 0.38;
    final p = at(0.6, 0);
    expect(DartsBoardGeometry.hitAt(p.x, p.y), const DartHit(20, 3));
    expect(
      DartsBoardGeometry.hitAt(
        p.x * big / DartsBoardGeometry.regulationRadius,
        p.y * big / DartsBoardGeometry.regulationRadius,
        radius: big,
      ),
      const DartHit(20, 3),
    );
  });

  test('DartHit json round-trips and validates shape', () {
    for (final hit in [
      const DartHit(20, 3),
      const DartHit(25, 2),
      const DartHit(1, 1),
      DartHit.miss,
    ]) {
      expect(DartHit.fromJson(hit.toJson()), hit);
      expect(hit.isWellFormed, isTrue);
    }
    expect(const DartHit(25, 3).isWellFormed, isFalse);
    expect(const DartHit(21, 1).isWellFormed, isFalse);
    expect(const DartHit(0, 2).isWellFormed, isFalse);
    expect(const DartHit(5, 4).isWellFormed, isFalse);
  });

  test('announcements read like a caller', () {
    expect(const DartHit(20, 3).announcement, 'Treble 20!');
    expect(const DartHit(16, 2).announcement, 'Double 16!');
    expect(const DartHit(5, 1).announcement, 'Single 5');
    expect(const DartHit(25, 2).announcement, 'Bullseye!');
    expect(const DartHit(25, 1).announcement, 'Outer bull');
    expect(DartHit.miss.announcement, 'Miss');
  });
}
