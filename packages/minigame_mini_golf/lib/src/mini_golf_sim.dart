import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:minigames_3d/minigames_3d.dart';

import 'mini_golf_course.dart';
import 'mini_golf_world.dart';

/// Things that happen during a putt, worth a sound or a haptic.
enum PuttEventKind {
  /// The ball was struck.
  launch,

  /// The ball banked off a boundary rail.
  rail,

  /// The ball hit a block or post.
  obstacle,

  /// The ball crossed the cup too fast and horseshoed out.
  lipOut,

  /// The ball caught the lip and started to fall.
  drop,

  /// The ball is in the hole.
  sink,

  /// The ball came to rest on the green.
  rest,

  /// The ball ended up off the green.
  outOfBounds,
}

/// A [PuttEventKind] tied to the path sample it happened at, so playback can
/// fire it at exactly the moment the simulation did.
class PuttEvent {
  final int sample;
  final PuttEventKind kind;

  const PuttEvent(this.sample, this.kind);

  @override
  String toString() => '${kind.name}@$sample';
}

/// One recorded frame of the roll.
class PuttSample {
  /// Ball centre in world space.
  final Vec3 position;

  /// Accumulated roll angle, radians.
  final double spin;

  const PuttSample(this.position, this.spin);
}

/// The whole putt, simulated to rest.
class PuttResult {
  /// Recorded roll, launch → settle, at [sampleHz].
  final List<PuttSample> path;

  /// Simulation events with the sample index they occurred on.
  final List<PuttEvent> events;

  /// Where the ball ended up, world `(x, z)`.
  final Offset settled;

  /// The ball dropped in the cup.
  final bool sunk;

  /// The ball finished off the green.
  final bool outOfBounds;

  /// Simulated duration, seconds.
  final double duration;

  const PuttResult({
    required this.path,
    required this.events,
    required this.settled,
    required this.sunk,
    required this.outOfBounds,
    required this.duration,
  });

  /// Playback rate of [path].
  static const double sampleHz = 60;

  /// Distance the ball actually travelled along its path.
  double get rollDistance {
    var d = 0.0;
    for (var i = 1; i < path.length; i++) {
      final a = path[i - 1].position;
      final b = path[i].position;
      d += math.sqrt(
        (b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z),
      );
    }
    return d;
  }

  /// Straight-line displacement from launch to settle.
  double get displacement {
    if (path.isEmpty) return 0;
    final a = path.first.position;
    return math.sqrt(
      (settled.dx - a.x) * (settled.dx - a.x) +
          (settled.dy - a.z) * (settled.dy - a.z),
    );
  }

  bool has(PuttEventKind kind) => events.any((e) => e.kind == kind);

  /// The sample nearest [t] seconds into the roll.
  PuttSample sampleAt(double t) {
    if (path.isEmpty) {
      return const PuttSample(Vec3.zero, 0);
    }
    final i = (t * sampleHz).round().clamp(0, path.length - 1);
    return path[i];
  }
}

/// The putt simulator: a rolling ball on a walled green.
///
/// ## Why this is not a throw
///
/// [minigames_3d] was built for balls in flight, but a putt is a ball *on* the
/// ground: it stays at `y == ballRadius`, gravity does nothing, and it stops
/// because the green scrubs it, not because it lands. So this uses [Projectile]
/// for the fixed-step integration and its [Projectile.bounce] reflection, runs
/// with `gravity: 0`, and adds a constant rolling friction on top of the linear
/// drag — the mix is what gives a putt its "decays fast, then trickles" feel
/// instead of the pure exponential a drag-only model produces.
///
/// Gravity is switched on by hand for exactly one situation: the ball catches
/// the cup lip and drops. The capture test is then a genuine
/// [Surfaces.passesDownThroughDisc] against the cup mouth — descending, so a
/// ball that crosses the hole too fast simply lips out and rolls on.
///
/// The whole putt is simulated at release and returned as a recorded path. The
/// board plays that path back on a ticker, which keeps rendering a pure
/// function of a frame index, makes a mid-putt frame trivially snapshot-able,
/// and means the outcome the reducer receives is the outcome that was drawn.
class MiniGolfPutt {
  const MiniGolfPutt._();

  /// Fixed integration step.
  static const double fixedDt = 1 / 120;

  /// Launch speed at zero and full power, world units/s. Full power rolls
  /// [MiniGolfCourse.maxPuttReach] on the flat.
  static const double minSpeed = 1.5;
  static const double maxSpeed = 7.9;

  /// Linear drag (fraction of speed bled per second).
  static const double rollDrag = 0.55;

  /// Constant rolling deceleration, world units/s².
  static const double rollFriction = 1.5;

  /// Speed below which the ball is treated as stopped.
  static const double restSpeed = 0.22;

  /// Consecutive steps under [restSpeed] before the putt is declared settled.
  static const int settleSteps = 10;

  /// Bounce energy kept off the boundary rails and off interior solids.
  static const double railRestitution = 0.74;
  static const double obstacleRestitution = 0.62;

  /// Tangential scrub applied on a bounce.
  static const double bounceFriction = 0.10;

  /// A ball crossing the cup faster than this horseshoes out instead of
  /// dropping.
  static const double lipOutSpeed = 2.3;

  /// Downward speed the lip imparts once the ball is captured.
  static const double dropSpeed = 0.55;

  /// Gravity during the drop.
  static const double dropGravity = 9.8;

  /// Hard step cap so a pathological putt still terminates.
  static const int maxSteps = 3600;

  /// Every Nth integration step is recorded — 120 Hz physics, 60 Hz playback.
  static const int _sampleEvery = 2;

  /// Launch speed for a 0..1 [power].
  static double speedFor(double power) =>
      minSpeed + (maxSpeed - minSpeed) * power.clamp(0.0, 1.0);

  /// Simulate a putt from [from] (world `(x, z)`) heading in unit [direction]
  /// at 0..1 [power]. Deterministic and headless.
  static PuttResult simulate({
    required MiniGolfCourse course,
    required Offset from,
    required Offset direction,
    required double power,
  }) {
    final rails = _railsOf(course);
    final r = MiniGolfCourse.ballRadius;
    final speed = speedFor(power);
    final dir = direction.distance < 1e-9
        ? const Offset(0, 1)
        : direction / direction.distance;

    final ball = Projectile(
      position: Vec3(from.dx, MiniGolfWorld.ballY, from.dy),
      velocity: Vec3(dir.dx * speed, 0, dir.dy * speed),
      config: const ThrowConfig(
        gravity: 0,
        drag: rollDrag,
        restSpeed: restSpeed,
        fixedDt: fixedDt,
        maxSteps: maxSteps,
      ),
    );

    final path = <PuttSample>[PuttSample(ball.position, 0)];
    final events = <PuttEvent>[const PuttEvent(0, PuttEventKind.launch)];
    var spin = 0.0;
    var still = 0;
    var dropping = false;
    var lipCooldown = false;
    var sunk = false;
    var escaped = false;
    var steps = 0;

    final bounds = course.bounds;
    final cup = Vec3(course.cup.dx, MiniGolfWorld.groundY, course.cup.dy);

    void record() {
      path.add(PuttSample(ball.position, spin));
    }

    void mark(PuttEventKind kind) {
      events.add(PuttEvent(path.length - 1, kind));
    }

    while (steps < maxSteps) {
      steps++;

      if (dropping) {
        // Gravity, by hand — the config is a rolling config.
        ball.velocity = Vec3(
          ball.velocity.x,
          ball.velocity.y - dropGravity * fixedDt,
          ball.velocity.z,
        );
      } else {
        // Constant rolling friction on top of the config's linear drag.
        final v = ball.velocity;
        final s = math.sqrt(v.x * v.x + v.z * v.z);
        if (s > 1e-9) {
          final drop = math.min(s, rollFriction * fixedDt);
          final k = (s - drop) / s;
          ball.velocity = Vec3(v.x * k, 0, v.z * k);
        } else {
          ball.velocity = Vec3(0, 0, 0);
        }
      }

      final before = ball.step();
      final after = ball.position;

      if (dropping) {
        if (Surfaces.passesDownThroughDisc(
          before,
          after,
          cup,
          MiniGolfCourse.cupRadius,
        )) {
          sunk = true;
          // Park it in the bottom of the cup for the final frame.
          ball.position = Vec3(cup.x, -r * 1.6, cup.z);
          ball.velocity = Vec3.zero;
          record();
          mark(PuttEventKind.sink);
          break;
        }
        if (after.y < -0.8) {
          // Fell past the cup without crossing the mouth: treat as settled at
          // the lip. Defensive; the mouth test above catches the real case.
          ball.position = Vec3(after.x, MiniGolfWorld.ballY, after.z);
          ball.velocity = Vec3.zero;
          break;
        }
        if (steps % _sampleEvery == 0) record();
        continue;
      }

      // Keep the roll pinned to the green.
      ball.position = Vec3(ball.position.x, MiniGolfWorld.ballY, ball.position.z);

      // --- cup ---------------------------------------------------------------
      final here = Offset(ball.position.x, ball.position.z);
      final wasThere = Offset(before.x, before.z);
      final toCup = _segmentPointDistance(wasThere, here, course.cup);
      final horizontal = math.sqrt(
        ball.velocity.x * ball.velocity.x + ball.velocity.z * ball.velocity.z,
      );
      if (!lipCooldown && toCup <= MiniGolfCourse.cupRadius - r * 0.35) {
        if (horizontal <= lipOutSpeed) {
          dropping = true;
          // The lip catches it: most of the pace goes, and it starts falling.
          ball.position = Vec3(course.cup.dx, MiniGolfWorld.ballY, course.cup.dy);
          ball.velocity = Vec3(
            ball.velocity.x * 0.35,
            -dropSpeed,
            ball.velocity.z * 0.35,
          );
          record();
          mark(PuttEventKind.drop);
          continue;
        }
        // Too quick: it rattles round the rim and carries on, a shade slower.
        lipCooldown = true;
        ball.velocity = Vec3(
          ball.velocity.x * 0.86,
          0,
          ball.velocity.z * 0.86,
        );
        if (steps % _sampleEvery == 0) record();
        mark(PuttEventKind.lipOut);
        continue;
      }
      if (lipCooldown &&
          (here - course.cup).distance > MiniGolfCourse.cupRadius + r * 2) {
        lipCooldown = false;
      }

      // --- solids ------------------------------------------------------------
      final hit = _resolveContacts(ball, rails, course.obstacles, r);
      if (hit != null && horizontal > 0.35) mark(hit);

      // --- escape guard ------------------------------------------------------
      final p = ball.position;
      if (p.x < bounds.minX - 2 ||
          p.x > bounds.maxX + 2 ||
          p.z < bounds.minZ - 2 ||
          p.z > bounds.maxZ + 2) {
        escaped = true;
        record();
        break;
      }

      // --- settle ------------------------------------------------------------
      final sp = math.sqrt(
        ball.velocity.x * ball.velocity.x + ball.velocity.z * ball.velocity.z,
      );
      spin += (sp / r) * fixedDt;
      if (sp < restSpeed) {
        still++;
        if (still >= settleSteps) {
          ball.velocity = Vec3.zero;
          record();
          break;
        }
      } else {
        still = 0;
      }

      if (steps % _sampleEvery == 0) record();
    }

    final end = Offset(ball.position.x, ball.position.z);
    final oob = !sunk && (escaped || !course.containsWorld(end));
    if (!sunk) {
      mark(oob ? PuttEventKind.outOfBounds : PuttEventKind.rest);
    }

    return PuttResult(
      path: path,
      events: events,
      settled: sunk ? course.cup : end,
      sunk: sunk,
      outOfBounds: oob,
      duration: steps * fixedDt,
    );
  }

  // -- collision --------------------------------------------------------------

  /// Resolves the ball against the boundary rails and interior solids, pushing
  /// it out of penetration and reflecting its velocity. Returns the kind of
  /// contact that actually reversed the ball, or null.
  static PuttEventKind? _resolveContacts(
    Projectile ball,
    List<_Rail> rails,
    List<MiniGolfObstacle> obstacles,
    double r,
  ) {
    PuttEventKind? kind;
    for (var pass = 0; pass < 4; pass++) {
      var touched = false;
      final here = Offset(ball.position.x, ball.position.z);

      for (final rail in rails) {
        final closest = _closestOnSegment(here, rail.a, rail.b);
        final d = here - closest;
        final dist = d.distance;
        if (dist >= r) continue;
        // Inside-out check: if the ball has slipped past the wall, push it back
        // along the rail's inward normal rather than radially (which would
        // shove it further out).
        final radial = dist > 1e-6 ? d / dist : rail.inward;
        final n = _dot(radial, rail.inward) > 0 ? radial : rail.inward;
        final push = r - _dot(d, n);
        ball.position = Vec3(
          ball.position.x + n.dx * push,
          ball.position.y,
          ball.position.z + n.dy * push,
        );
        final before = ball.velocity;
        ball.bounce(
          Vec3(n.dx, 0, n.dy),
          restitution: railRestitution,
          friction: bounceFriction,
        );
        if (before != ball.velocity) kind ??= PuttEventKind.rail;
        touched = true;
      }

      for (final o in obstacles) {
        final n = o.round
            ? _circleNormal(here, o, r)
            : _boxNormal(here, o, r);
        if (n == null) continue;
        ball.position = Vec3(
          ball.position.x + n.normal.dx * n.push,
          ball.position.y,
          ball.position.z + n.normal.dy * n.push,
        );
        final before = ball.velocity;
        ball.bounce(
          Vec3(n.normal.dx, 0, n.normal.dy),
          restitution: obstacleRestitution,
          friction: bounceFriction,
        );
        if (before != ball.velocity) kind = PuttEventKind.obstacle;
        touched = true;
      }

      if (!touched) break;
    }
    return kind;
  }

  static ({Offset normal, double push})? _circleNormal(
    Offset ball,
    MiniGolfObstacle o,
    double r,
  ) {
    final centre = Offset(o.centerX, o.centerZ);
    final d = ball - centre;
    final dist = d.distance;
    final reach = o.radius + r;
    if (dist >= reach) return null;
    final n = dist > 1e-6 ? d / dist : const Offset(0, -1);
    return (normal: n, push: reach - dist);
  }

  static ({Offset normal, double push})? _boxNormal(
    Offset ball,
    MiniGolfObstacle o,
    double r,
  ) {
    final cx = ball.dx.clamp(o.left, o.right);
    final cz = ball.dy.clamp(o.near, o.far);
    final d = ball - Offset(cx, cz);
    final dist = d.distance;
    if (dist > 1e-6) {
      if (dist >= r) return null;
      return (normal: d / dist, push: r - dist);
    }
    // Centre is inside the box: eject along the shallowest face.
    final dl = ball.dx - o.left;
    final dr = o.right - ball.dx;
    final dn = ball.dy - o.near;
    final df = o.far - ball.dy;
    final m = math.min(math.min(dl, dr), math.min(dn, df));
    if (m == dl) return (normal: const Offset(-1, 0), push: dl + r);
    if (m == dr) return (normal: const Offset(1, 0), push: dr + r);
    if (m == dn) return (normal: const Offset(0, -1), push: dn + r);
    return (normal: const Offset(0, 1), push: df + r);
  }

  /// Boundary edges with their inward normals. The outline is wound
  /// counter-clockwise, so the outward normal of `a → b` is `(dz, -dx)`.
  static List<_Rail> _railsOf(MiniGolfCourse course) {
    final out = <_Rail>[];
    final n = course.outline.length;
    for (var i = 0; i < n; i++) {
      final a = course.outline[i];
      final b = course.outline[(i + 1) % n];
      final d = b - a;
      final len = d.distance;
      if (len < 1e-9) continue;
      final outward = Offset(d.dy, -d.dx) / len;
      out.add(_Rail(a, b, -outward));
    }
    return out;
  }
}

class _Rail {
  final Offset a;
  final Offset b;

  /// Unit normal pointing into the green.
  final Offset inward;

  const _Rail(this.a, this.b, this.inward);
}

double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

Offset _closestOnSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (l2 < 1e-12) return a;
  final t = (_dot(p - a, ab) / l2).clamp(0.0, 1.0);
  return a + ab * t;
}

double _segmentPointDistance(Offset a, Offset b, Offset p) =>
    (p - _closestOnSegment(p, a, b)).distance;
