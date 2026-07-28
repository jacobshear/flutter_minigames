import 'dart:math' as math;
import 'dart:ui' show Offset;

/// How marbles nestle in a pit.
///
/// The old layout was a single flat golden-angle scatter with push-apart — it
/// read as coins dropped on a table, because every stone shared one plane, one
/// size and one shadow. Real stones in a scooped pit form a *pile*: a floor
/// course fills first, later stones ride up into the hollows between them, and
/// the whole thing recedes into the far wall of the scoop.
///
/// This produces that: layered courses, per-stone depth (back = higher on
/// screen, smaller), and the contact points between touching stones so the
/// painter can pool ambient occlusion in the crevices — which does more for the
/// pile reading as solid than any single marble's shading does.
///
/// Pure and deterministic: the same `(count, well, seed)` always gives the same
/// pile, which is what lets the sow animation aim a ballistic drop at the exact
/// slot the stone will end up in.

/// One marble's place in the pile.
class PileSlot {
  /// Screen-space centre, already lifted for its course.
  final Offset centre;

  /// Radius multiplier: back-of-pit stones are further from the eye, stacked
  /// stones are nearer.
  final double scale;

  /// 0 = far wall of the scoop, 1 = near lip. Paint order and shadow depth.
  final double nearness;

  /// Which course: 0 = on the scoop floor.
  final int course;

  /// How buried this stone is (0 = proud, 1 = wedged). Drives its own AO wash.
  final double occlusion;

  /// Direction the crowding comes from, in unit screen space.
  final Offset occlusionFrom;

  const PileSlot({
    required this.centre,
    required this.scale,
    required this.nearness,
    required this.course,
    required this.occlusion,
    required this.occlusionFrom,
  });
}

/// Where two stones touch — the crevice AO goes here.
class PileContact {
  final Offset at;
  final double radius;
  final double strength;

  const PileContact({
    required this.at,
    required this.radius,
    required this.strength,
  });
}

class PileLayout {
  /// Slots in **deposit order** — index `n` is the nth stone put in this pit,
  /// so a flying stone can aim at `slots[nestIndex]`.
  final List<PileSlot> slots;

  /// Indices into [slots] in back-to-front paint order.
  final List<int> order;

  final List<PileContact> contacts;

  const PileLayout({
    required this.slots,
    required this.order,
    required this.contacts,
  });
}

/// Deterministic hash in `[0, 1)`.
double _hash(int a, int b) {
  var n = (a * 374761393) ^ (b * 668265263);
  n = (n ^ (n >> 13)) * 1274126177;
  n = n ^ (n >> 16);
  return (n & 0x3fffffff) / 0x3fffffff;
}

/// How many stones a course holds.
///
/// Not a strict circle-packing count: the scoop is a bowl seen from above, so
/// stones sitting on its sloped sides overlap in projection. A strict
/// non-overlapping bound puts far too few on the floor and shoves the rest into
/// a tower that climbs out of the pit — which is precisely what a real pit
/// never does.
int _capacity(double rx, double ry, double marbleR, {required bool floor}) {
  if (marbleR <= 0) return 1;
  final density = floor ? 1.15 : 0.95;
  return math.max(2, (density * rx * ry / (marbleR * marbleR)).floor());
}

/// Spread [n] points inside an ellipse and relax them apart.
List<Offset> _course({
  required int n,
  required Offset centre,
  required double rx,
  required double ry,
  required double marbleR,
  required int seed,
}) {
  if (n <= 0) return const [];
  if (n == 1) return [centre];

  // Stones on the sloped wall overhang the flat nest ellipse, so the usable
  // radius keeps only ~0.7 of a marble back from the rim.
  final maxRx = math.max(marbleR * 0.05, rx - marbleR * 0.72);
  final maxRy = math.max(marbleR * 0.05, ry - marbleR * 0.72);
  final out = <Offset>[];
  for (var i = 0; i < n; i++) {
    final ang = i * 2.399963 + seed * 0.37;
    final frac = math.sqrt((i + 0.38) / n);
    final jx = (_hash(seed, i) - 0.5) * marbleR * 0.30;
    final jy = (_hash(seed + 91, i) - 0.5) * marbleR * 0.30;
    out.add(centre +
        Offset(
          math.cos(ang) * maxRx * frac + jx,
          math.sin(ang) * maxRy * frac + jy,
        ));
  }

  // Below a full diameter: neighbouring stones in a bowl are at different
  // depths, so they legitimately overlap in a top-down projection.
  final minDist = marbleR * 1.70;
  for (var iter = 0; iter < 16; iter++) {
    for (var i = 0; i < out.length; i++) {
      for (var j = i + 1; j < out.length; j++) {
        var d = out[j] - out[i];
        var dist = d.distance;
        if (dist < 1e-5) {
          d = Offset(minDist * 0.5, minDist * 0.13);
          dist = d.distance;
        }
        if (dist < minDist) {
          final push = d / dist * (minDist - dist) * 0.5;
          out[i] = out[i] - push;
          out[j] = out[j] + push;
        }
      }
      final v = out[i] - centre;
      final q = Offset(v.dx / maxRx, v.dy / maxRy);
      if (q.distance > 1 && q.distance > 1e-5) {
        out[i] = centre +
            Offset(q.dx / q.distance * maxRx, q.dy / q.distance * maxRy);
      }
    }
  }
  return out;
}

final Map<String, PileLayout> _cache = {};

/// Build (or recall) the pile for [count] stones in an elliptical well.
///
/// The scoop is modelled as a shallow bowl seen from slightly in front: its far
/// half is further from the eye, so stones there sit higher on screen and paint
/// smaller. Courses above the floor tuck into the hollows below them, ride up
/// by a bit less than a full diameter (stones nest, they do not stack like
/// coins) and come out fractionally larger for being nearer the eye.
PileLayout pileLayout({
  required int count,
  required Offset centre,
  required double wellRx,
  required double wellRy,
  required double marbleR,
  required int seed,
}) {
  if (count <= 0) {
    return const PileLayout(slots: [], order: [], contacts: []);
  }
  final key = '$count|${centre.dx.toStringAsFixed(2)}|'
      '${centre.dy.toStringAsFixed(2)}|${wellRx.toStringAsFixed(2)}|'
      '${wellRy.toStringAsFixed(2)}|${marbleR.toStringAsFixed(3)}|$seed';
  final hit = _cache[key];
  if (hit != null) return hit;

  // Split the count into courses, floor first. A lone stone perched on top of
  // a full course looks like a mistake, so pull one down from the course below
  // when that would happen.
  final counts = <int>[];
  var left = count;
  var cx = wellRx;
  var cy = wellRy;
  var guard = 0;
  while (left > 0 && guard++ < 6) {
    final cap = _capacity(cx, cy, marbleR, floor: counts.isEmpty);
    var take = math.min(left, cap);
    // A lone stone perched on a full course looks like a mistake; pull one up
    // from below so the top course is at least a pair.
    if (left - take == 1 && take > 2) take -= 1;
    counts.add(take);
    left -= take;
    cx *= 0.62;
    cy *= 0.62;
  }
  if (left > 0) counts[counts.length - 1] += left;

  // Bowl floor: the stones settle slightly below the well centre, and the
  // whole pile sinks a touch as it gets tall (the bowl is not flat-bottomed).
  final floor = centre + Offset(0, wellRy * 0.10);

  final slots = <PileSlot>[];
  var placed = 0;
  var shrinkX = wellRx;
  var shrinkY = wellRy;
  for (var course = 0; course < counts.length; course++) {
    final n = counts[course];
    final pts = _course(
      n: n,
      centre: floor,
      rx: shrinkX,
      ry: shrinkY,
      marbleR: marbleR,
      seed: seed + course * 31,
    );
    for (var i = 0; i < pts.length; i++) {
      final base = pts[i];
      // Depth across the bowl, from its far wall to its near lip.
      final nearness =
          (((base.dy - floor.dy) / math.max(wellRy, 1e-3)) * 0.5 + 0.5)
              .clamp(0.0, 1.0);
      // Perspective from the bowl's tilt plus the course lift.
      final scale = (0.905 + 0.135 * nearness) * (1 + 0.055 * course);
      // Stones nest into the hollows below them, so a course rides up well
      // under a diameter — and the pile stays inside the scoop rather than
      // towering out of it.
      final lift = marbleR * 0.95 * course * (0.92 + 0.08 * nearness);
      slots.add(
        PileSlot(
          centre: Offset(base.dx, base.dy - lift),
          scale: scale,
          nearness: nearness + course * 0.001,
          course: course,
          occlusion: 0,
          occlusionFrom: Offset.zero,
        ),
      );
      placed++;
    }
    shrinkX *= 0.62;
    shrinkY *= 0.62;
  }
  assert(placed == count);

  // Neighbour occlusion: for each stone, how crowded it is and from where.
  // The crevice between two touching stones is the darkest thing in a pile and
  // is what sells them as solid objects rather than overlapping cutouts.
  final contacts = <PileContact>[];
  final resolved = <PileSlot>[];
  for (var i = 0; i < slots.length; i++) {
    var crowd = 0.0;
    var acc = Offset.zero;
    for (var j = 0; j < slots.length; j++) {
      if (i == j) continue;
      final a = slots[i];
      final b = slots[j];
      final d = b.centre - a.centre;
      final touch = marbleR * (a.scale + b.scale);
      final gap = d.distance - touch;
      if (gap > touch * 0.28) continue;
      final w = (1 - gap / (touch * 0.28)).clamp(0.0, 1.0);
      // Only stones below/behind bury this one; a stone in front of it does
      // not occlude its own lit face.
      final below = b.course < a.course ? 1.0 : (b.course == a.course ? 0.55 : 0.15);
      crowd += w * below;
      if (d.distance > 1e-4) acc += (d / d.distance) * w * below;
      if (j > i) {
        contacts.add(
          PileContact(
            at: a.centre + d * 0.5,
            radius: marbleR * 0.86,
            strength: w,
          ),
        );
      }
    }
    final s = slots[i];
    resolved.add(
      PileSlot(
        centre: s.centre,
        scale: s.scale,
        nearness: s.nearness,
        course: s.course,
        occlusion: (crowd * 0.26).clamp(0.0, 0.80),
        // Bias the wash downward: however the neighbours are arranged, a stone
        // in a heap is darkest where it disappears into the heap.
        occlusionFrom: acc + Offset(0, 0.85 * crowd),
      ),
    );
  }

  final order = List<int>.generate(resolved.length, (i) => i)
    ..sort((a, b) {
      final c = resolved[a].nearness.compareTo(resolved[b].nearness);
      return c != 0 ? c : resolved[a].course.compareTo(resolved[b].course);
    });

  final made =
      PileLayout(slots: resolved, order: order, contacts: contacts);
  if (_cache.length > 240) _cache.clear();
  _cache[key] = made;
  return made;
}
