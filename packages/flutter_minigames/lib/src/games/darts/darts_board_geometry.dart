import 'dart:math' as math;

/// Where a single dart landed on the board, as a sector + multiplier.
///
/// The bulls are modelled as sector **25**: outer bull is `25 × 1`, the
/// bullseye is `25 × 2`. That is the standard darts convention and it is what
/// makes the bullseye legal as a double-out finish without a special case.
///
/// A dart outside the double ring is [DartHit.miss] — sector 0, multiplier 0.
class DartHit {
  /// 1..20 for a numbered sector, 25 for either bull, 0 for a miss.
  final int sector;

  /// 1 single, 2 double, 3 treble. 0 for a miss. Bullseye is `sector 25 × 2`.
  final int multiplier;

  const DartHit(this.sector, this.multiplier);

  /// A dart that landed off the scoring area.
  static const miss = DartHit(0, 0);

  /// Points this dart scores.
  int get value => sector * multiplier;

  /// Whether this dart counts as a double for double-out purposes. The
  /// bullseye (25 × 2) qualifies; the outer bull (25 × 1) does not.
  bool get isDouble => multiplier == 2 && sector > 0;

  bool get isMiss => sector == 0 || multiplier == 0;

  /// Short scoreboard label: `T20`, `D16`, `20`, `BULL`, `25`, `MISS`.
  String get label {
    if (isMiss) return 'MISS';
    if (sector == 25) return multiplier == 2 ? 'BULL' : '25';
    return switch (multiplier) {
      3 => 'T$sector',
      2 => 'D$sector',
      _ => '$sector',
    };
  }

  /// Announcement used for the transient pill ("Treble 20!").
  String get announcement {
    if (isMiss) return 'Miss';
    if (sector == 25) return multiplier == 2 ? 'Bullseye!' : 'Outer bull';
    return switch (multiplier) {
      3 => 'Treble $sector!',
      2 => 'Double $sector!',
      _ => 'Single $sector',
    };
  }

  Map<String, dynamic> toJson() => {'sector': sector, 'multiplier': multiplier};

  static DartHit fromJson(Map<String, dynamic> json) => DartHit(
        (json['sector'] as num).toInt(),
        (json['multiplier'] as num).toInt(),
      );

  /// Whether this is a shape the rules can accept (guards decoded moves).
  bool get isWellFormed {
    if (sector == 0) return multiplier == 0;
    if (sector == 25) return multiplier == 1 || multiplier == 2;
    if (sector < 1 || sector > 20) return false;
    return multiplier >= 1 && multiplier <= 3;
  }

  @override
  bool operator ==(Object other) =>
      other is DartHit &&
      other.sector == sector &&
      other.multiplier == multiplier;

  @override
  int get hashCode => Object.hash(sector, multiplier);

  @override
  String toString() => 'DartHit($label)';
}

/// Regulation dartboard geometry: a point on the board face → sector and
/// multiplier.
///
/// This is the heart of the game and deliberately lives in the pure layer with
/// no Flutter, no camera and no physics — the renderer and the simulation both
/// call the same function, and it is exhaustively unit-tested.
///
/// ## Coordinates
///
/// [hitAt] takes a point **on the board face**, measured from the bullseye:
/// `x` right, `y` up, in the same unit as [radius]. `radius` is the outer edge
/// of the double ring (the scoring boundary), so the ring bands scale with the
/// board — the ratios below are regulation, the absolute size is the caller's.
///
/// ## Ring radii (BDO/WDF regulation, millimetres from centre)
///
/// | ring | radius |
/// |---|---|
/// | inner bull (bullseye, 50) | 6.35 |
/// | outer bull (25) | 15.9 |
/// | treble ring | 99 → 107 |
/// | double ring | 162 → 170 |
///
/// ## Sectors
///
/// Twenty 18° sectors, **20 centred at the top**, running clockwise:
/// 20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5.
///
/// Each sector owns the half-open angular span `[c − 9°, c + 9°)`, so a dart
/// either side of a wire always resolves to the bed it is actually in. A dart
/// landing on the wire *to the last bit of a double* is a measure-zero tie the
/// float arithmetic settles either way; the tests pin the beds, not the tie.
abstract final class DartsBoardGeometry {
  /// Outer edge of the double ring, in millimetres — the reference radius.
  static const double outerDoubleMm = 170.0;
  static const double innerDoubleMm = 162.0;
  static const double outerTrebleMm = 107.0;
  static const double innerTrebleMm = 99.0;
  static const double outerBullMm = 15.9;
  static const double innerBullMm = 6.35;

  /// Ring radii as a fraction of the board's scoring radius.
  static const double innerBullRatio = innerBullMm / outerDoubleMm;
  static const double outerBullRatio = outerBullMm / outerDoubleMm;
  static const double innerTrebleRatio = innerTrebleMm / outerDoubleMm;
  static const double outerTrebleRatio = outerTrebleMm / outerDoubleMm;
  static const double innerDoubleRatio = innerDoubleMm / outerDoubleMm;

  /// Outer edge of the numbered wire ring / surround, as a ratio. Purely
  /// cosmetic — nothing out here scores.
  static const double numberRingRatio = 1.20;

  /// The regulation board scoring radius in metres (170 mm).
  static const double regulationRadius = outerDoubleMm / 1000.0;

  /// Sector values clockwise from the top (index 0 = the 20, centred at 12
  /// o'clock).
  static const List<int> sectorOrder = [
    20, 1, 18, 4, 13, 6, 10, 15, 2, 17, //
    3, 19, 7, 16, 8, 11, 14, 9, 12, 5,
  ];

  /// Angular width of one sector, radians (18°).
  static const double sectorSpan = 2 * math.pi / 20;

  /// Index into [sectorOrder] for a point at ([x], [y]) on the board face.
  ///
  /// Angle is measured **clockwise from 12 o'clock**, which is `atan2(x, y)`
  /// with x right and y up.
  static int sectorIndexAt(double x, double y) {
    if (x == 0 && y == 0) return 0;
    final clockwise = math.atan2(x, y);
    final raw = (clockwise / sectorSpan + 0.5).floor();
    return ((raw % 20) + 20) % 20;
  }

  /// The sector number a point falls in, ignoring rings (1..20).
  static int sectorValueAt(double x, double y) =>
      sectorOrder[sectorIndexAt(x, y)];

  /// Centre angle (clockwise from 12 o'clock, radians) of sector [index].
  static double sectorCentreAngle(int index) => index * sectorSpan;

  /// Score a dart that landed at ([x], [y]) on a board of scoring [radius].
  ///
  /// Boundaries are inclusive at the outer edge of each band: a dart exactly on
  /// `radius` is still a double, one hair beyond is a miss.
  static DartHit hitAt(double x, double y, {double radius = regulationRadius}) {
    if (radius <= 0) return DartHit.miss;
    final r = math.sqrt(x * x + y * y) / radius;
    if (r <= innerBullRatio) return const DartHit(25, 2);
    if (r <= outerBullRatio) return const DartHit(25, 1);
    if (r > 1.0) return DartHit.miss;
    final sector = sectorValueAt(x, y);
    if (r >= innerDoubleRatio) return DartHit(sector, 2);
    if (r >= innerTrebleRatio && r <= outerTrebleRatio) {
      return DartHit(sector, 3);
    }
    return DartHit(sector, 1);
  }
}
