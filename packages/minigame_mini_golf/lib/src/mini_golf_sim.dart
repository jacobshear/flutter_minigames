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

  /// The falling ball clattered off the inside of the cup.
  rattle,

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

  /// Where it happened, world `(x, z)` — the contact point for a rail or
  /// obstacle strike, so the board can put a scuff on the right spot.
  final Offset at;

  /// 0..1 severity: for a bounce, the speed into the surface measured against
  /// [MiniGolfPutt.hardHitSpeed]. A graze is near 0 and stays silent.
  final double strength;

  const PuttEvent(
    this.sample,
    this.kind, {
    this.at = Offset.zero,
    this.strength = 1,
  });

  @override
  String toString() => '${kind.name}@$sample';
}

/// One recorded frame of the roll.
class PuttSample {
  /// Ball centre in world space.
  final Vec3 position;

  /// Accumulated roll angle, radians. Kept as the scalar it always was; the
  /// full 3-D orientation is in [roll].
  final double spin;

  /// The ball's orientation at this frame, integrated from its motion.
  final BallRoll roll;

  const PuttSample(this.position, this.spin, [this.roll = BallRoll.identity]);
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
  ///
  /// Was 0.22, which cut the roll off while the ball was still visibly moving —
  /// a putt ended by snapping to a halt rather than dying. The last stretch of
  /// a real putt is its most watchable part, so the threshold drops to where
  /// the ball is genuinely crawling. It costs about a centimetre of reach (the
  /// tail is decelerating at [rollFriction], so the extra roll is tiny), well
  /// inside the band the reach test allows.
  static const double restSpeed = 0.13;

  /// Consecutive steps under [restSpeed] before the putt is declared settled.
  static const int settleSteps = 14;

  /// Extra braking applied over the last stretch, as a multiple of
  /// [rollFriction], ramped in as the ball approaches [crawlSpeed]. Grass grabs
  /// a nearly-stopped ball far harder than a rolling one, and without this the
  /// low threshold above just makes the ball creep for an age.
  static const double crawlBrake = 2.2;

  /// Speed under which [crawlBrake] starts to bite.
  static const double crawlSpeed = 0.55;

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

  /// How much pace a falling ball keeps when it clatters off the inside of the
  /// cup. This is the rattle — a ball that catches the lip off-centre bounces
  /// wall to wall on the way down instead of sliding cleanly out of sight.
  static const double cupWallRestitution = 0.42;

  /// How much pace it keeps landing on the bottom of the cup.
  static const double cupFloorRestitution = 0.30;

  /// Below this vertical speed a bounce in the cup is not worth a sound.
  static const double rattleSpeed = 0.55;

  /// The impact speed a bounce is measured against for [PuttEvent.strength].
  /// Roughly a full-power putt arriving square on a rail.
  static const double hardHitSpeed = 6.5;

  /// Below this speed into a surface, a contact is a nudge: no sound, no scuff.
  static const double quietHitSpeed = 0.45;

  /// How hard a lip-out throws the ball off line, as a fraction of its speed
  /// pushed along the outward radius of the cup. A ball that crosses the hole
  /// too fast has to *visibly* ride the rim and spin away — that moment is half
  /// the reason cups are fun to miss.
  static const double lipOutDeflect = 0.55;

  /// How far the rim drops a horseshoeing ball, as a fraction of its radius,
  /// and for how many steps. Deliberately short of the depth at which the
  /// painter treats a ball as being inside the cup — it dips into the mouth,
  /// it does not fall in.
  static const double lipOutDip = 0.45;
  static const int lipOutDipSteps = 26;

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
    final events = <PuttEvent>[
      PuttEvent(0, PuttEventKind.launch, at: from),
    ];
    var spin = 0.0;
    var roll = BallRoll.identity;
    var still = 0;
    var dropping = false;
    var lipCooldown = false;
    var lipDip = 0;
    var sunk = false;
    var escaped = false;
    var settledInCup = 0;
    var steps = 0;

    final bounds = course.bounds;
    final cup = Vec3(course.cup.dx, MiniGolfWorld.groundY, course.cup.dy);

    void record() {
      path.add(PuttSample(ball.position, spin, roll));
    }

    void mark(PuttEventKind kind, {Offset? at, double strength = 1}) {
      events.add(PuttEvent(
        path.length - 1,
        kind,
        at: at ?? Offset(ball.position.x, ball.position.z),
        strength: strength.clamp(0.0, 1.0),
      ));
    }

    /// 0..1 severity of a contact arriving at [speed].
    double severity(double speed) =>
        ((speed - quietHitSpeed) / hardHitSpeed).clamp(0.0, 1.0);

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
        // Constant rolling friction on top of the config's linear drag, plus
        // extra grab over the last stretch so the ball dies into rest instead
        // of creeping to a threshold and being switched off.
        final v = ball.velocity;
        final s = math.sqrt(v.x * v.x + v.z * v.z);
        if (s > 1e-9) {
          final crawl = s < crawlSpeed ? 1 - s / crawlSpeed : 0.0;
          final brake = rollFriction * (1 + crawlBrake * crawl * crawl);
          final drop = math.min(s, brake * fixedDt);
          final k = (s - drop) / s;
          ball.velocity = Vec3(v.x * k, 0, v.z * k);
        } else {
          ball.velocity = Vec3(0, 0, 0);
        }
      }

      final before = ball.step();
      final after = ball.position;

      if (dropping) {
        // The moment it crosses the mouth on the way down, the hole is made.
        // Everything after this point is the ball finding the bottom of the
        // cup — watchable, but it cannot change the outcome, which is already
        // decided here.
        if (!sunk &&
            Surfaces.passesDownThroughDisc(
              before,
              after,
              cup,
              MiniGolfCourse.cupRadius,
            )) {
          sunk = true;
          mark(PuttEventKind.sink);
        }

        // Inside the cup the ball is in a short cylinder: it clatters off the
        // wall on the way down (the rattle) and lands on the bottom.
        final off = Offset(after.x - cup.x, after.z - cup.z);
        final reach = MiniGolfCourse.cupRadius - r;
        if (sunk && off.distance > reach && off.distance > 1e-6) {
          final n = off / off.distance;
          ball.position = Vec3(
            cup.x + n.dx * reach,
            ball.position.y,
            cup.z + n.dy * reach,
          );
          final radial = ball.velocity.x * n.dx + ball.velocity.z * n.dy;
          if (radial > 0) {
            ball.velocity = Vec3(
              ball.velocity.x - (1 + cupWallRestitution) * radial * n.dx,
              ball.velocity.y,
              ball.velocity.z - (1 + cupWallRestitution) * radial * n.dy,
            );
            if (radial > rattleSpeed) {
              mark(PuttEventKind.rattle, strength: severity(radial));
            }
          }
        }

        // The floor of the cup.
        if (ball.position.y <= MiniGolfWorld.cupRestY) {
          final impact = -ball.velocity.y;
          ball.position =
              Vec3(ball.position.x, MiniGolfWorld.cupRestY, ball.position.z);
          if (impact > rattleSpeed) {
            mark(PuttEventKind.rattle, strength: severity(impact));
            ball.velocity = Vec3(
              ball.velocity.x * 0.55,
              impact * cupFloorRestitution,
              ball.velocity.z * 0.55,
            );
          } else {
            ball.velocity = Vec3.zero;
          }
          settledInCup++;
          if (settledInCup >= 3 || !sunk) {
            ball.velocity = Vec3.zero;
            record();
            break;
          }
        }

        if (after.y < -1.2) {
          // Fell past the cup without ever crossing the mouth: treat as settled
          // at the lip. Defensive; the mouth test above catches the real case.
          ball.position = Vec3(after.x, MiniGolfWorld.ballY, after.z);
          ball.velocity = Vec3.zero;
          break;
        }
        if (steps % _sampleEvery == 0) record();
        continue;
      }

      // Keep the roll pinned to the green — except while a horseshoeing ball is
      // riding the rim, when it sits a little below it.
      var groundY = MiniGolfWorld.ballY;
      if (lipDip > 0) {
        lipDip--;
        final phase = 1 - lipDip / lipOutDipSteps;
        groundY -= r * lipOutDip * math.sin(phase * math.pi);
      }
      ball.position = Vec3(ball.position.x, groundY, ball.position.z);

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
          // The lip catches it. It keeps some of its pace — which is what makes
          // it clatter off the far wall on the way down — and it topples in from
          // where it actually was, not from a teleport to the cup's centre.
          final toward = course.cup - here;
          final pull = toward.distance < 1e-6
              ? Offset.zero
              : toward / toward.distance * (horizontal * 0.30 + 0.25);
          ball.velocity = Vec3(
            ball.velocity.x * 0.45 + pull.dx,
            -dropSpeed,
            ball.velocity.z * 0.45 + pull.dy,
          );
          record();
          mark(PuttEventKind.drop, at: course.cup);
          continue;
        }
        // Too quick: it rides round the rim and spins away. The rim throws it
        // off line — outward from wherever it crossed the hole — and drops it a
        // fraction while it goes, so the horseshoe is something you watch
        // rather than a silent 14% speed penalty.
        lipCooldown = true;
        lipDip = lipOutDipSteps;
        var dir = Offset(ball.velocity.x, ball.velocity.z);
        dir = dir / math.max(1e-6, dir.distance);
        // Which side of the hole it went past, measured across its line of
        // travel — *not* the radius to where it happens to be standing, which
        // for a straight-through pass points backwards along the travel and
        // deflects nothing at all.
        final perp = Offset(-dir.dy, dir.dx);
        final off = here - course.cup;
        final lateral = off.dx * perp.dx + off.dy * perp.dy;
        final q = (lateral / MiniGolfCourse.cupRadius).clamp(-1.0, 1.0);
        final side = q < 0 ? -1.0 : 1.0;
        // Even a dead-centre pass gets thrown: the far lip is what it hits, and
        // a ball leaving the rim perfectly straight is the one thing a lip-out
        // never looks like.
        final kick = side * lipOutDeflect * (0.40 + 0.60 * q.abs());
        final speed = horizontal * 0.80;
        dir = dir + perp * kick;
        dir = dir / math.max(1e-6, dir.distance);
        ball.velocity = Vec3(dir.dx * speed, 0, dir.dy * speed);
        if (steps % _sampleEvery == 0) record();
        mark(PuttEventKind.lipOut,
            at: course.cup, strength: severity(horizontal));
        continue;
      }
      if (lipCooldown &&
          (here - course.cup).distance > MiniGolfCourse.cupRadius + r * 2) {
        lipCooldown = false;
      }

      // --- solids ------------------------------------------------------------
      final hit = _resolveContacts(ball, rails, course.obstacles, r);
      if (hit != null && horizontal > 0.35) {
        mark(hit.kind, at: hit.at, strength: severity(hit.speed));
      }

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

      // --- roll + settle -----------------------------------------------------
      final sp = math.sqrt(
        ball.velocity.x * ball.velocity.x + ball.velocity.z * ball.velocity.z,
      );
      spin += (sp / r) * fixedDt;
      // Turn the ball by however far it actually moved this step, about the
      // axis across its travel — so the markings track the direction it is
      // going and keep working after it banks off a rail.
      roll = roll.rolled(
        ball.position.x - before.x,
        ball.position.z - before.z,
        r,
      );
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
      mark(oob ? PuttEventKind.outOfBounds : PuttEventKind.rest, at: end);
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
  /// it out of penetration and reflecting its velocity.
  ///
  /// Returns the contact that actually reversed the ball — its kind, where it
  /// happened, and how fast the ball was going *into* the surface — or null.
  /// The speed is what makes a bounce carry weight downstream: the sound is
  /// gated on it, the haptic is graded by it, and the scuff on the rail is
  /// sized by it.
  static ({PuttEventKind kind, Offset at, double speed})? _resolveContacts(
    Projectile ball,
    List<_Rail> rails,
    List<MiniGolfObstacle> obstacles,
    double r,
  ) {
    ({PuttEventKind kind, Offset at, double speed})? hit;

    void note(PuttEventKind kind, Offset at, double speed) {
      // An obstacle strike outranks a rail graze in the same step, and a harder
      // contact outranks a softer one.
      if (hit == null ||
          (kind == PuttEventKind.obstacle && hit!.kind != kind) ||
          speed > hit!.speed) {
        hit = (kind: kind, at: at, speed: speed);
      }
    }

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
        final into = -(before.x * n.dx + before.z * n.dy);
        ball.bounce(
          Vec3(n.dx, 0, n.dy),
          restitution: railRestitution,
          friction: bounceFriction,
        );
        if (before != ball.velocity) {
          note(PuttEventKind.rail, closest, into);
        }
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
        final into = -(before.x * n.normal.dx + before.z * n.normal.dy);
        ball.bounce(
          Vec3(n.normal.dx, 0, n.normal.dy),
          restitution: obstacleRestitution,
          friction: bounceFriction,
        );
        if (before != ball.velocity) {
          note(
            PuttEventKind.obstacle,
            here - n.normal * r,
            into,
          );
        }
        touched = true;
      }

      if (!touched) break;
    }
    return hit;
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
