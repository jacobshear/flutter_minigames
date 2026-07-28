import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show Offset;

/// The distinct shapes a hole can take.
///
/// Variety is the whole point of this enum. The previous generator had *one*
/// shape (an L-shaped dogleg) with jittered numbers, so every hole in a course
/// looked like its neighbour with the furniture moved. Each archetype here has
/// its own outline construction, its own obstacle character and its own length
/// band, and [MiniGolfCourse.forHole] deals them out as a seeded permutation so
/// a 9-hole course walks through all eight before it can repeat one.
enum MiniGolfArchetype {
  /// Long, dead straight, and tapering: wide at the tee, a hair over a ball's
  /// width at the cup, with a gate of two blocks pinching the middle.
  straightNarrowing,

  /// One hard bend to the left, with a fat blocker parked in the second arm.
  doglegLeft,

  /// The mirror image: one hard bend to the right.
  doglegRight,

  /// Two opposing bends — the longest hole on the course, with a chicane post
  /// on each apex.
  sBend,

  /// Short, wide and open: a bowl with a big round island sitting between the
  /// tee and the cup. The short par-2.
  islandGreen,

  /// The fairway bulges and a long island splits it into two routes: a tight
  /// lane that lines up with the cup, and a roomy lane that costs you a putt.
  splitFork,

  /// Wide bowl, a narrow waist you have to thread, then another wide bowl with
  /// the cup tucked off-centre.
  hourglass,

  /// A narrow chute with baffles jutting alternately from each rail — a
  /// serpentine you either weave or bank off the walls.
  railChicane,
}

/// Human-readable name, for the hole chip.
extension MiniGolfArchetypeLabel on MiniGolfArchetype {
  String get label => switch (this) {
        MiniGolfArchetype.straightNarrowing => 'Narrows',
        MiniGolfArchetype.doglegLeft => 'Dogleg left',
        MiniGolfArchetype.doglegRight => 'Dogleg right',
        MiniGolfArchetype.sBend => 'S-bend',
        MiniGolfArchetype.islandGreen => 'Island',
        MiniGolfArchetype.splitFork => 'Split fork',
        MiniGolfArchetype.hourglass => 'Hourglass',
        MiniGolfArchetype.railChicane => 'Chicane',
      };
}

/// A solid the ball bounces off, standing on the green.
///
/// Either an axis-aligned block or a round post inscribed in that box. Both
/// carry [laneGap] — the widest passable clearance beside them — which is the
/// number the passability guarantee is asserted against.
class MiniGolfObstacle {
  /// World-space x range (lateral).
  final double left;
  final double right;

  /// World-space z range (down-range). [near] < [far].
  final double near;
  final double far;

  /// True for a round post/island inscribed in the box; false for a block.
  final bool round;

  /// The widest clearance the ball can roll through beside this solid, in world
  /// units. Never below [MiniGolfCourse.minObstacleGap].
  final double laneGap;

  /// Drawn height above the green.
  final double height;

  const MiniGolfObstacle({
    required this.left,
    required this.right,
    required this.near,
    required this.far,
    required this.laneGap,
    this.round = false,
    this.height = 0.34,
  });

  double get centerX => (left + right) / 2;
  double get centerZ => (near + far) / 2;
  double get halfWidth => (right - left) / 2;
  double get halfDepth => (far - near) / 2;

  /// Radius when [round].
  double get radius => math.min(halfWidth, halfDepth);

  @override
  String toString() => 'Obstacle(${round ? 'post' : 'block'} '
      '${centerX.toStringAsFixed(2)},${centerZ.toStringAsFixed(2)} '
      'lane ${laneGap.toStringAsFixed(2)})';
}

/// One deterministic mini-golf hole, in **world units**.
///
/// ## Coordinates
///
/// The green lies on the ground plane `y == 0` of the [minigames_3d] world:
/// * `x` is lateral (right positive), roughly centred on 0;
/// * `z` is down-range — the tee sits near `z == 0` and the cup down at
///   `z == length`, so the camera behind the tee looks straight down the hole.
///
/// Geometry is stored as [Offset] pairs of `(x, z)`, *not* screen points. The
/// normalized `(nx, ny)` pair the [TurnGame] state serializes is derived from
/// this via [normalize] / [denormalize]: `nx` runs 0→1 left→right across the
/// bounding box and `ny` runs 0→1 far→near, matching the old top-down
/// convention so the move schema is unchanged.
///
/// ## Why this is pure
///
/// Both players must rebuild an identical course from the match seed alone, so
/// generation is a pure function of an integer — no `Random()`, no
/// `DateTime` — via [_seededUnit]. Same seed ⇒ identical outline, obstacles,
/// tee, cup and par.
class MiniGolfCourse {
  // -- shared physical constants ---------------------------------------------

  /// Ball radius in world units. Single source of truth for the simulation, the
  /// renderer and the obstacle-passability guarantee.
  static const double ballRadius = 0.12;

  /// Ball diameter in world units.
  static const double ballDiameter = 2 * ballRadius; // 0.24

  /// The minimum passable clearance beside any obstacle: 2.5 ball diameters.
  /// No generated hole ever violates this — asserted across seeds and
  /// archetypes in the tests.
  static const double minObstacleGap = 2.5 * ballDiameter; // 0.60

  /// The narrowest the fairway itself is ever allowed to get: 4 ball diameters.
  /// The waist of an hourglass and the far end of a taper are terrain, not
  /// obstacles, so they get their own floor.
  static const double minFairwayFloor = 4 * ballDiameter; // 0.96

  /// Cup mouth radius. Roughly a real cup: a shade over two ball diameters.
  static const double cupRadius = 0.26;

  /// Height and thickness of the raised rails around the green.
  static const double railHeight = 0.30;
  static const double railThickness = 0.20;

  /// How far the hardest putt rolls on the flat, in world units. Par is derived
  /// from this, and the simulator asserts its own reach matches it.
  static const double maxPuttReach = 7.6;

  // -- the hole ---------------------------------------------------------------

  /// Which shape family this hole is.
  final MiniGolfArchetype archetype;

  /// The seed this hole was generated from.
  final int seed;

  /// Outer boundary of the green as world `(x, z)` vertices, wound
  /// counter-clockwise (positive signed area) so edge normals are consistent.
  final List<Offset> outline;

  /// Solids standing on the green.
  final List<MiniGolfObstacle> obstacles;

  /// Tee (ball start), world `(x, z)`.
  final Offset tee;

  /// Cup centre, world `(x, z)`.
  final Offset cup;

  /// Approximate distance a ball must travel tee → cup along a playable route.
  /// This — not the straight-line distance — is what [par] is derived from.
  final double routeLength;

  /// The narrowest the fairway gets, in world units. Never below
  /// [minFairwayFloor].
  final double minFairwayWidth;

  /// Expected strokes for a good round: derived per hole from [routeLength] and
  /// the archetype's difficulty bias, not a single global constant.
  final int par;

  const MiniGolfCourse({
    required this.archetype,
    required this.seed,
    required this.outline,
    required this.obstacles,
    required this.tee,
    required this.cup,
    required this.routeLength,
    required this.minFairwayWidth,
    required this.par,
  });

  // -- generation -------------------------------------------------------------

  /// Every archetype, in declaration order.
  static const List<MiniGolfArchetype> archetypes = MiniGolfArchetype.values;

  /// The hole at [holeIndex] of a match built on [baseSeed].
  ///
  /// Archetypes are dealt from a seeded **permutation** rather than drawn
  /// independently: hole `i` gets `perm[i % perm.length]`. Two consequences the
  /// tests lean on — a 9-hole course uses all eight archetypes, and no two
  /// consecutive holes can share one (the permutation has no repeats, and the
  /// wrap lands `perm[0]` after `perm[last]`).
  factory MiniGolfCourse.forHole(int baseSeed, int holeIndex) {
    final perm = archetypeOrder(baseSeed);
    final archetype = perm[holeIndex % perm.length];
    return _generate(holeSeed(baseSeed, holeIndex), archetype);
  }

  /// A standalone hole for [seed], archetype included in the draw. Used for
  /// broad property sampling (passability across hundreds of seeds).
  factory MiniGolfCourse.forSeed(int seed) {
    final pick = (_seededUnit(seed, 91) * archetypes.length)
        .floor()
        .clamp(0, archetypes.length - 1);
    return _generate(seed, archetypes[pick]);
  }

  /// The distinct layout seed for hole [holeIndex] of a match on [baseSeed].
  /// Spread far apart so adjacent holes avalanche to unrelated parameters.
  static int holeSeed(int baseSeed, int holeIndex) =>
      baseSeed * 9973 + holeIndex * 131 + 17;

  /// The archetype running order for a match on [baseSeed] — a seeded
  /// Fisher-Yates shuffle of [archetypes].
  static List<MiniGolfArchetype> archetypeOrder(int baseSeed) {
    final list = List<MiniGolfArchetype>.of(archetypes);
    for (var i = list.length - 1; i > 0; i--) {
      final j = (_seededUnit(baseSeed, 300 + i) * (i + 1)).floor().clamp(0, i);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
    return list;
  }

  /// Generation is cheap but a scorecard asks for all nine holes' par on every
  /// rebuild, so results are memoized. Deterministic, so caching changes
  /// nothing observable.
  static final LinkedHashMap<int, MiniGolfCourse> _cache = LinkedHashMap();
  static const int _cacheCap = 192;

  static MiniGolfCourse _generate(int seed, MiniGolfArchetype archetype) {
    final key = seed * 31 + archetype.index;
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    final built = _build(seed, archetype);
    _cache[key] = built;
    if (_cache.length > _cacheCap) _cache.remove(_cache.keys.first);
    return built;
  }

  static MiniGolfCourse _build(int seed, MiniGolfArchetype archetype) {
    final layout = switch (archetype) {
      MiniGolfArchetype.straightNarrowing => _straightNarrowing(seed),
      MiniGolfArchetype.doglegLeft => _dogleg(seed, -1),
      MiniGolfArchetype.doglegRight => _dogleg(seed, 1),
      MiniGolfArchetype.sBend => _sBend(seed),
      MiniGolfArchetype.islandGreen => _islandGreen(seed),
      MiniGolfArchetype.splitFork => _splitFork(seed),
      MiniGolfArchetype.hourglass => _hourglass(seed),
      MiniGolfArchetype.railChicane => _railChicane(seed),
    };
    return MiniGolfCourse(
      archetype: archetype,
      seed: seed,
      outline: _ensureCcw(layout.outline),
      obstacles: layout.obstacles,
      tee: layout.tee,
      cup: layout.cup,
      routeLength: layout.route,
      minFairwayWidth: layout.minFairwayWidth,
      par: _parFor(layout.route, _parBias(archetype)),
    );
  }

  /// Difficulty surcharge: routes that force a detour or a bank play a stroke
  /// longer than their raw length suggests.
  static int _parBias(MiniGolfArchetype a) => switch (a) {
        MiniGolfArchetype.splitFork => 1,
        MiniGolfArchetype.railChicane => 1,
        _ => 0,
      };

  /// Par from route length. A good putt — on line, at a pace that leaves the
  /// next one makeable — covers a bit under 60% of [maxPuttReach], so expected
  /// strokes ≈ route / (0.58 · reach); rounded, biased, clamped.
  static int _parFor(double route, int bias) {
    const good = maxPuttReach * 0.58; // ≈ 4.4 units per solid putt
    return ((route / good).round() + bias).clamp(2, 5);
  }

  // -- derived geometry -------------------------------------------------------

  /// Axis-aligned bounds of the green, world units.
  ({double minX, double maxX, double minZ, double maxZ}) get bounds {
    var minX = double.infinity, maxX = -double.infinity;
    var minZ = double.infinity, maxZ = -double.infinity;
    for (final p in outline) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minZ = math.min(minZ, p.dy);
      maxZ = math.max(maxZ, p.dy);
    }
    return (minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ);
  }

  /// Down-range extent of the hole (its "length" on the scorecard).
  double get length => bounds.maxZ - bounds.minZ;

  /// Lateral extent of the hole.
  double get width => bounds.maxX - bounds.minX;

  /// The widest passable clearance beside the tightest obstacle, or null when
  /// the hole has none. Always ≥ [minObstacleGap] when present.
  double? get tightestLane {
    if (obstacles.isEmpty) return null;
    var m = double.infinity;
    for (final o in obstacles) {
      m = math.min(m, o.laneGap);
    }
    return m;
  }

  /// World `(x, z)` → normalized `(nx, ny)`; `ny` runs far→near so it matches
  /// the top-down convention the move schema was written against.
  Offset normalize(Offset world) {
    final b = bounds;
    final dx = math.max(1e-6, b.maxX - b.minX);
    final dz = math.max(1e-6, b.maxZ - b.minZ);
    return Offset(
      ((world.dx - b.minX) / dx).clamp(0.0, 1.0),
      ((b.maxZ - world.dy) / dz).clamp(0.0, 1.0),
    );
  }

  /// Normalized `(nx, ny)` → world `(x, z)`.
  Offset denormalize(double nx, double ny) {
    final b = bounds;
    return Offset(
      b.minX + nx * (b.maxX - b.minX),
      b.maxZ - ny * (b.maxZ - b.minZ),
    );
  }

  /// Tee in normalized coordinates.
  Offset get normalizedTee => normalize(tee);

  /// Cup in normalized coordinates.
  Offset get normalizedCup => normalize(cup);

  /// Whether a world point lies inside the green's outline. The obstacles are
  /// walls, not holes, so they are not subtracted.
  bool containsWorld(Offset p) {
    var inside = false;
    final n = outline.length;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final a = outline[i];
      final b = outline[j];
      final straddles = (a.dy > p.dy) != (b.dy > p.dy);
      if (!straddles) continue;
      final x = (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (p.dx < x) inside = !inside;
    }
    return inside;
  }

  /// Whether a normalized point lies on the green.
  bool contains(double nx, double ny) => containsWorld(denormalize(nx, ny));

  /// Whether the ball centre is over the cup mouth. Whether it *drops* also
  /// depends on speed — that call belongs to the simulator.
  bool isOverCup(Offset world) => (world - cup).distance <= cupRadius;

  /// A structural signature of the hole: archetype, quantized outline, tee, cup
  /// and obstacle count. Two holes sharing a fingerprint are the same layout to
  /// the eye — which is precisely what the variety tests assert never happens
  /// between neighbours.
  String get fingerprint {
    final b = StringBuffer()
      ..write(archetype.index)
      ..write('|');
    for (final p in outline) {
      b
        ..write(_q(p.dx))
        ..write(',')
        ..write(_q(p.dy))
        ..write(';');
    }
    b
      ..write('|')
      ..write(_q(tee.dx))
      ..write(',')
      ..write(_q(tee.dy))
      ..write('|')
      ..write(_q(cup.dx))
      ..write(',')
      ..write(_q(cup.dy))
      ..write('|')
      ..write(obstacles.length);
    return b.toString();
  }

  static String _q(double v) => (v * 10).round().toString();

  @override
  String toString() => 'MiniGolfCourse(${archetype.name} seed $seed, '
      'route ${routeLength.toStringAsFixed(1)}, par $par, '
      '${obstacles.length} obstacles)';
}

// ---------------------------------------------------------------------------
// Layout construction
// ---------------------------------------------------------------------------

class _Layout {
  final List<Offset> outline;
  final List<MiniGolfObstacle> obstacles;
  final Offset tee;
  final Offset cup;
  final double route;
  final double minFairwayWidth;

  const _Layout({
    required this.outline,
    required this.obstacles,
    required this.tee,
    required this.cup,
    required this.route,
    required this.minFairwayWidth,
  });
}

/// One station along a fairway centreline: where it is and how wide it is there.
typedef _Node = ({Offset p, double half});

/// Builds a closed fairway polygon by offsetting a centreline left and right.
///
/// Corners are mitred (the offset is divided by the cosine of the half-turn),
/// which is what keeps a dogleg's bend from pinching to a sliver the ball can't
/// fit through — the failure mode of a naive constant offset.
List<Offset> _corridor(List<_Node> spine) {
  final n = spine.length;
  final left = <Offset>[];
  final right = <Offset>[];
  for (var i = 0; i < n; i++) {
    final p = spine[i].p;
    final tin = i == 0 ? _dir(p, spine[1].p) : _dir(spine[i - 1].p, p);
    final tout = i == n - 1 ? _dir(spine[n - 2].p, p) : _dir(p, spine[i + 1].p);
    var bis = tin + tout;
    if (bis.distance < 1e-6) bis = tin;
    bis = bis / bis.distance;
    final nrm = Offset(-bis.dy, bis.dx);
    final tinN = Offset(-tin.dy, tin.dx);
    final cosHalf = (nrm.dx * tinN.dx + nrm.dy * tinN.dy).abs();
    final off = spine[i].half / math.max(0.4, cosHalf);
    left.add(p + nrm * off);
    right.add(p - nrm * off);
  }
  return [...left, ...right.reversed];
}

Offset _dir(Offset a, Offset b) {
  final d = b - a;
  final l = d.distance;
  return l < 1e-9 ? const Offset(0, 1) : d / l;
}

/// Heading [radians] off down-range as a unit `(x, z)` direction.
Offset _heading(double radians) => Offset(math.sin(radians), math.cos(radians));

/// Rewinds a polygon counter-clockwise (positive signed area) so the renderer
/// and the collision layer can derive outward normals the same way.
List<Offset> _ensureCcw(List<Offset> poly) {
  var area = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    area += a.dx * b.dy - b.dx * a.dy;
  }
  return area < 0 ? poly.reversed.toList() : poly;
}

/// A round blocker sized to leave exactly [bigGap] on the [side] of a corridor
/// of half-width [half] and a sliver of [smallGap] on the other. Returns the
/// post's radius and its offset from the centreline.
({double radius, double offset}) _blocker(
  double half,
  double bigGap,
  double smallGap,
  int side,
) {
  final r = (2 * half - smallGap - bigGap) / 2;
  return (radius: math.max(0.25, r), offset: side * (half - r - bigGap));
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _minHalf(List<_Node> spine) {
  var m = double.infinity;
  for (final n in spine) {
    m = math.min(m, n.half);
  }
  return m;
}

// --- straight, narrowing ----------------------------------------------------

_Layout _straightNarrowing(int seed) {
  final len = 12.6 + 3.0 * _seededUnit(seed, 1);
  final wTee = 1.75 + 0.35 * _seededUnit(seed, 2);
  final wCup = 0.62 + 0.16 * _seededUnit(seed, 3);
  const steps = 6;
  final spine = <_Node>[
    for (var i = 0; i <= steps; i++)
      (
        p: Offset(0, len * i / steps),
        half: _lerp(wTee, wCup, math.pow(i / steps, 1.25).toDouble()),
      ),
  ];

  // A gate of two blocks pinching the fairway a little past halfway.
  final gz = len * (0.52 + 0.08 * _seededUnit(seed, 4));
  final gateHalf = _lerp(wTee, wCup, math.pow(gz / len, 1.25).toDouble());
  final lane = 0.64 + 0.26 * _seededUnit(seed, 5);
  final slack = 2 * gateHalf - lane - 0.34;
  final laneCentre = (_seededUnit(seed, 6) - 0.5) * math.max(0.0, slack);
  final obstacles = <MiniGolfObstacle>[
    MiniGolfObstacle(
      left: -gateHalf - 0.4,
      right: laneCentre - lane / 2,
      near: gz - 0.24,
      far: gz + 0.24,
      laneGap: lane,
    ),
    MiniGolfObstacle(
      left: laneCentre + lane / 2,
      right: gateHalf + 0.4,
      near: gz - 0.24,
      far: gz + 0.24,
      laneGap: lane,
    ),
  ];

  return _Layout(
    outline: _corridor(spine),
    obstacles: obstacles,
    tee: Offset(0, 0.75),
    cup: Offset((_seededUnit(seed, 7) - 0.5) * wCup * 0.7, len - 0.95),
    route: len - 1.7,
    minFairwayWidth: 2 * _minHalf(spine),
  );
}

// --- dogleg ------------------------------------------------------------------

_Layout _dogleg(int seed, int side) {
  final arm1 = 6.4 + 2.2 * _seededUnit(seed, 1);
  final arm2 = 6.0 + 2.4 * _seededUnit(seed, 2);
  // 36°–54°. A sharper bend than this turns the hole almost sideways, and a
  // hole wider than it is long can't fill a portrait canvas at any camera.
  final bend = side * (0.63 + 0.31 * _seededUnit(seed, 3));
  final half = 1.28 + 0.30 * _seededUnit(seed, 4);
  final corner = Offset(0, arm1);
  final d = _heading(bend);

  final spine = <_Node>[
    (p: Offset.zero, half: half),
    (p: Offset(0, arm1 * 0.55), half: half),
    (p: corner, half: half),
    (p: corner + d * (arm2 * 0.5), half: half),
    (p: corner + d * arm2, half: half),
  ];

  // A fat post parked in the second arm, offset so one side stays comfortably
  // passable and the other is a sliver.
  final bigGap = 0.66 + 0.30 * _seededUnit(seed, 5);
  final blockSide = _seededUnit(seed, 6) < 0.5 ? -1 : 1;
  final b = _blocker(half, bigGap, 0.16, blockSide);
  final at = corner + d * (arm2 * (0.35 + 0.15 * _seededUnit(seed, 7)));
  final perp = Offset(-d.dy, d.dx);
  final centre = at + perp * b.offset;

  return _Layout(
    outline: _corridor(spine),
    obstacles: [
      MiniGolfObstacle(
        left: centre.dx - b.radius,
        right: centre.dx + b.radius,
        near: centre.dy - b.radius,
        far: centre.dy + b.radius,
        round: true,
        laneGap: bigGap,
        height: 0.38,
      ),
    ],
    tee: const Offset(0, 0.8),
    cup: corner + d * (arm2 - 0.9),
    route: arm1 + arm2 - 1.7,
    minFairwayWidth: 2 * half,
  );
}

// --- S-bend ------------------------------------------------------------------

_Layout _sBend(int seed) {
  final side = _seededUnit(seed, 1) < 0.5 ? -1 : 1;
  final a = side * (0.66 + 0.24 * _seededUnit(seed, 2));
  final b = -side * (0.66 + 0.24 * _seededUnit(seed, 3));
  final half = 1.18 + 0.24 * _seededUnit(seed, 4);
  final s1 = 4.2 + 1.0 * _seededUnit(seed, 5);
  final s2 = 4.4 + 1.2 * _seededUnit(seed, 6);
  final s3 = 4.4 + 1.2 * _seededUnit(seed, 7);
  final s4 = 4.0 + 1.2 * _seededUnit(seed, 8);

  final p0 = Offset.zero;
  final p1 = p0 + _heading(0) * s1;
  final p2 = p1 + _heading(a) * s2;
  final p3 = p2 + _heading(b) * s3;
  final p4 = p3 + _heading(0) * s4;

  final spine = <_Node>[
    (p: p0, half: half),
    (p: p1, half: half),
    (p: p2, half: half),
    (p: p3, half: half),
    (p: p4, half: half),
  ];

  // A chicane post inside each apex — small enough to weave past on either
  // side, so the S reads as a rhythm rather than two gates.
  final gapA = 0.70 + 0.24 * _seededUnit(seed, 9);
  final gapB = 0.70 + 0.24 * _seededUnit(seed, 10);
  final bA = _blocker(half, gapA, 0.30, a > 0 ? 1 : -1);
  final bB = _blocker(half, gapB, 0.30, b > 0 ? 1 : -1);
  final dA = _dir(p1, p2);
  final dB = _dir(p2, p3);
  final cA = p1 + dA * (s2 * 0.55) + Offset(-dA.dy, dA.dx) * bA.offset;
  final cB = p2 + dB * (s3 * 0.55) + Offset(-dB.dy, dB.dx) * bB.offset;

  return _Layout(
    outline: _corridor(spine),
    obstacles: [
      MiniGolfObstacle(
        left: cA.dx - bA.radius,
        right: cA.dx + bA.radius,
        near: cA.dy - bA.radius,
        far: cA.dy + bA.radius,
        round: true,
        laneGap: gapA,
        height: 0.36,
      ),
      MiniGolfObstacle(
        left: cB.dx - bB.radius,
        right: cB.dx + bB.radius,
        near: cB.dy - bB.radius,
        far: cB.dy + bB.radius,
        round: true,
        laneGap: gapB,
        height: 0.36,
      ),
    ],
    tee: const Offset(0, 0.8),
    cup: p3 + _heading(0) * (s4 - 0.95),
    route: s1 + s2 + s3 + s4 - 1.8,
    minFairwayWidth: 2 * half,
  );
}

// --- island green ------------------------------------------------------------

_Layout _islandGreen(int seed) {
  final len = 9.4 + 1.8 * _seededUnit(seed, 1);
  final halfW = 2.35 + 0.55 * _seededUnit(seed, 2);
  const c = 1.15; // corner chamfer

  final outline = <Offset>[
    Offset(-halfW + c, 0),
    Offset(halfW - c, 0),
    Offset(halfW, c),
    Offset(halfW, len - c),
    Offset(halfW - c, len),
    Offset(-halfW + c, len),
    Offset(-halfW, len - c),
    Offset(-halfW, c),
  ];

  // The island: a big round hazard between tee and cup, offset so the two ways
  // round it are asymmetric.
  final r = 1.10 + 0.34 * _seededUnit(seed, 3);
  final ix = (_seededUnit(seed, 4) - 0.5) * (halfW - r - 0.85) * 1.6;
  final iz = len * (0.46 + 0.08 * _seededUnit(seed, 5));
  final laneL = halfW + ix - r;
  final laneR = halfW - ix - r;

  // Two small satellites guarding the approach. Held back from the rails so
  // their lanes stay legal, clear of the island behind them, and clear of the
  // cup ahead so the tap-in is never blocked.
  final sx = 0.95 + 0.40 * _seededUnit(seed, 6);
  const sr = 0.30;
  final sz = math.min(
    math.max(len * 0.76, iz + r + sr + 0.45),
    len - 1.15 - sr - 0.55,
  );

  final cupX = (_seededUnit(seed, 7) - 0.5) * (halfW * 0.8);
  return _Layout(
    outline: outline,
    obstacles: [
      MiniGolfObstacle(
        left: ix - r,
        right: ix + r,
        near: iz - r,
        far: iz + r,
        round: true,
        laneGap: math.max(laneL, laneR),
        height: 0.44,
      ),
      MiniGolfObstacle(
        left: -sx - sr,
        right: -sx + sr,
        near: sz - sr,
        far: sz + sr,
        round: true,
        laneGap: halfW - sx - sr,
        height: 0.30,
      ),
      MiniGolfObstacle(
        left: sx - sr,
        right: sx + sr,
        near: sz - sr,
        far: sz + sr,
        round: true,
        laneGap: halfW - sx - sr,
        height: 0.30,
      ),
    ],
    tee: const Offset(0, 0.85),
    cup: Offset(cupX, len - 1.15),
    // Straight-line plus the swing around the island.
    route: len - 2.0 + 1.1,
    minFairwayWidth: 2 * halfW,
  );
}

// --- split fork --------------------------------------------------------------

_Layout _splitFork(int seed) {
  final len = 13.4 + 2.6 * _seededUnit(seed, 1);
  const neck = 1.16;
  final wide = 2.40 + 0.35 * _seededUnit(seed, 2);

  final spine = <_Node>[
    (p: const Offset(0, 0), half: neck),
    (p: Offset(0, len * 0.18), half: 1.55),
    (p: Offset(0, len * 0.28), half: wide),
    (p: Offset(0, len * 0.72), half: wide),
    (p: Offset(0, len * 0.82), half: 1.55),
    (p: Offset(0, len), half: neck),
  ];

  // The island that splits the fairway: a tight lane on one side (worth the
  // risk — it lines up with the cup) and a roomy one on the other.
  final tightSide = _seededUnit(seed, 3) < 0.5 ? -1 : 1;
  final tight = 0.66 + 0.16 * _seededUnit(seed, 4);
  final roomy = 1.25 + 0.30 * _seededUnit(seed, 5);
  final tightEdge = wide - tight; // island edge on the tight side
  final roomyEdge = wide - roomy;
  final left = tightSide < 0 ? -tightEdge : -roomyEdge;
  final right = tightSide < 0 ? roomyEdge : tightEdge;

  return _Layout(
    outline: _corridor(spine),
    obstacles: [
      MiniGolfObstacle(
        left: left,
        right: right,
        near: len * 0.33,
        far: len * 0.67,
        laneGap: math.max(tight, roomy),
        height: 0.36,
      ),
    ],
    tee: const Offset(0, 0.8),
    // Cup tucked toward the tight lane so the short route actually pays.
    cup: Offset(tightSide * neck * 0.45, len - 0.95),
    route: len - 1.75 + 1.4,
    minFairwayWidth: 2 * neck,
  );
}

// --- hourglass ---------------------------------------------------------------

_Layout _hourglass(int seed) {
  final len = 13.6 + 2.6 * _seededUnit(seed, 1);
  final bowl1 = 2.10 + 0.30 * _seededUnit(seed, 2);
  final bowl2 = 2.25 + 0.35 * _seededUnit(seed, 3);
  final waist = 0.62 + 0.14 * _seededUnit(seed, 4);

  final spine = <_Node>[
    (p: const Offset(0, 0), half: bowl1 * 0.72),
    (p: Offset(0, len * 0.16), half: bowl1),
    (p: Offset(0, len * 0.34), half: bowl1 * 0.86),
    (p: Offset(0, len * 0.50), half: waist),
    (p: Offset(0, len * 0.66), half: bowl2 * 0.86),
    (p: Offset(0, len * 0.84), half: bowl2),
    (p: Offset(0, len), half: bowl2 * 0.72),
  ];

  // One post standing in the mouth of the far bowl. Sized directly rather than
  // via _blocker: a bowl is wide, and solving for a blocked sliver there would
  // produce a boulder that swallows the cup.
  final r = 0.85 + 0.30 * _seededUnit(seed, 5);
  final side = _seededUnit(seed, 6) < 0.5 ? -1 : 1;
  final lane = 0.80 + 0.35 * _seededUnit(seed, 8);
  final offset = side * (bowl2 - r - lane);
  final farLane = 2 * bowl2 - 2 * r - lane;
  final pz = len * 0.66;

  final cupX = -side * bowl2 * (0.30 + 0.22 * _seededUnit(seed, 7));
  return _Layout(
    outline: _corridor(spine),
    obstacles: [
      MiniGolfObstacle(
        left: offset - r,
        right: offset + r,
        near: pz - r,
        far: pz + r,
        round: true,
        laneGap: math.max(lane, farLane),
        height: 0.40,
      ),
    ],
    tee: const Offset(0, 0.9),
    cup: Offset(cupX, len - 1.25),
    route: len - 2.15 + cupX.abs(),
    minFairwayWidth: 2 * waist,
  );
}

// --- rail chicane ------------------------------------------------------------

_Layout _railChicane(int seed) {
  final half = 1.16 + 0.20 * _seededUnit(seed, 1);
  final len = 12.4 + 3.0 * _seededUnit(seed, 2);
  final count = _seededUnit(seed, 3) < 0.5 ? 3 : 4;
  var side = _seededUnit(seed, 4) < 0.5 ? -1 : 1;

  final spine = <_Node>[
    (p: const Offset(0, 0), half: half),
    (p: Offset(0, len * 0.5), half: half),
    (p: Offset(0, len), half: half),
  ];

  final obstacles = <MiniGolfObstacle>[];
  for (var i = 0; i < count; i++) {
    final z = len * (0.20 + 0.60 * (count == 1 ? 0.5 : i / (count - 1)));
    final lane = 0.64 + 0.24 * _seededUnit(seed, 10 + i);
    // A baffle rooted in one rail, reaching across until only `lane` is left.
    final inner = side * (lane - half);
    final rooted = side * (half + 0.4);
    obstacles.add(
      MiniGolfObstacle(
        left: math.min(inner, rooted),
        right: math.max(inner, rooted),
        near: z - 0.22,
        far: z + 0.22,
        laneGap: lane,
        height: 0.32,
      ),
    );
    side = -side;
  }

  return _Layout(
    outline: _corridor(spine),
    obstacles: obstacles,
    tee: const Offset(0, 0.8),
    cup: Offset((_seededUnit(seed, 5) - 0.5) * half * 0.6, len - 1.0),
    // Weaving past each baffle adds real distance to the route.
    route: len - 1.8 + 0.8 * count,
    minFairwayWidth: 2 * half,
  );
}

// ---------------------------------------------------------------------------

/// A stable unit value in [0,1) from an integer [seed] and a [salt], with no
/// `Random`/`DateTime` — pure, so course layout is reproducible across clients.
double _seededUnit(int seed, int salt) {
  // splitmix64-style avalanche over a mix of the seed and salt. Masking to 63
  // bits keeps every intermediate non-negative (Dart ints are 64-bit signed).
  var x = (seed + 1) * 0x9E3779B97F4A7C15 + salt * 0xD1B54A32D192ED03;
  x &= 0x7fffffffffffffff;
  x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9;
  x &= 0x7fffffffffffffff;
  x = (x ^ (x >> 27)) * 0x94D049BB133111EB;
  x &= 0x7fffffffffffffff;
  x = x ^ (x >> 31);
  x &= 0x7fffffffffffffff;
  return (x % 1000000) / 1000000.0;
}
