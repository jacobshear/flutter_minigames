import 'dart:math' as math;

import 'package:minigames_3d/minigames_3d.dart';

import 'basketball_court.dart';

/// Something worth hearing or feeling.
enum BasketballHitKind {
  /// A ball left the spawn line.
  launch,

  /// A ball passed down through the hoop.
  made,

  /// A ball rattled the iron.
  rim,

  /// A ball slapped the backboard.
  backboard,

  /// A ball hit the floor.
  bounce,
}

/// One notable contact, carrying the impact speed so audio can be
/// velocity-parameterised rather than a single flat sample.
class BasketballHit {
  final BasketballHitKind kind;

  /// Impact speed, world units/s.
  final double speed;

  /// The ball involved.
  final LiveBall ball;

  const BasketballHit(this.kind, this.speed, this.ball);
}

/// One ball: waiting on the spawn line, in flight, or loose on the floor.
///
/// Missed balls are **not** despawned on contact — they bounce, roll, slow down
/// and only then fade out. Several are alive at once, which is what makes the
/// court feel busy at four shots a second.
class LiveBall {
  /// Monotonic id, handy for keys and for stable test assertions.
  final int id;

  /// Ballistic body.
  final Projectile body;

  /// Lateral offset this ball spawned at — the thing the player must read.
  final double spawnX;

  /// True once it has been flicked.
  bool launched = false;

  /// True once it has passed down through the hoop.
  bool made = false;

  /// True once it has stopped rolling.
  bool atRest = false;

  /// Seconds since launch.
  double age = 0;

  /// Seconds spent at rest.
  double restAge = 0;

  /// 0..1, non-zero just after this ball whipped the net.
  double netWobble = 0;

  LiveBall({required this.id, required this.body, required this.spawnX});

  Vec3 get position => body.position;
  double get spin => body.spin;

  /// Seconds a loose ball lies around before it starts fading.
  static const double lingerSeconds = 1.1;

  /// Seconds the fade-out takes.
  static const double fadeSeconds = 0.9;

  /// Hard ceiling on a ball's life, so a pathological roll still leaves.
  static const double maxAge = 9.0;

  /// 1 while fully present, ramping to 0 as the ball leaves.
  double get opacity {
    final overAge = age - maxAge;
    if (overAge > 0) return (1 - overAge / fadeSeconds).clamp(0.0, 1.0);
    if (!atRest) return 1;
    final over = restAge - lingerSeconds;
    if (over <= 0) return 1;
    return (1 - over / fadeSeconds).clamp(0.0, 1.0);
  }

  bool get gone => opacity <= 0;
}

/// One player's timed round, simulated headlessly at a fixed step.
///
/// The widget owns nothing but a ticker: it calls [advance] and [shoot] and
/// reads [balls]. Everything that decides a point lives here, which is how a
/// whole round can be replayed in a unit test with no Flutter binding — and how
/// the make-rate regression guard works.
///
/// Collision order per step is deliberate:
/// 1. **Make** first, as a *swept descending* disc test
///    ([Surfaces.passesDownThroughDisc]). Swept, so a 10 m/s shot cannot tunnel
///    through the hoop between frames; descending-only, so a ball rising
///    through the rim from underneath is correctly not a basket. Purely
///    geometric — it never asks whether iron was touched first.
/// 2. **Rim**, then **backboard**, only for a ball that has not gone in — once
///    through, it is inside the net and must not rattle back out.
/// 3. **Floor**, always: bounce, then roll, then rest.
class BasketballRoundSim {
  /// Match-level rig behaviour.
  final BasketballHoopMode mode;

  /// Round length in seconds.
  final double duration;

  /// The one launch speed every ball in this match is thrown at, solved once.
  final double launchSpeed;

  final math.Random _rng;

  /// Round clock, seconds elapsed.
  double time = 0;

  /// Baskets made this round.
  int makes = 0;

  /// Balls thrown this round.
  int shots = 0;

  /// The ball waiting to be flicked, or null during the respawn cooldown.
  LiveBall? ready;

  /// Balls that have been thrown (in flight, rolling, or fading).
  final List<LiveBall> live = [];

  /// True once the clock has run out; no further shots are accepted.
  bool get expired => time >= duration;

  double _cooldown = 0;
  double _accumulator = 0;
  int _nextId = 0;

  /// Never keep more than this many loose balls around.
  static const int maxLoose = 8;

  BasketballRoundSim({
    required this.mode,
    required math.Random rng,
    this.duration = 45,
    double? launchSpeed,
  })  : _rng = rng,
        launchSpeed = launchSpeed ?? BasketballAim.solveSpeed(mode) {
    _spawn();
  }

  /// Hoop centre right now.
  Vec3 get hoopCentre => BasketballCourt.hoopCentreAt(mode, time);

  /// Seconds left on the clock.
  double get remaining => (duration - time).clamp(0.0, duration);

  /// Everything that should be drawn, ready ball included.
  List<LiveBall> get balls => [if (ready != null) ready!, ...live];

  void _spawn() {
    final x = (_rng.nextDouble() * 2 - 1) * BasketballCourt.spawnSpread;
    ready = LiveBall(
      id: _nextId++,
      spawnX: x,
      body: Projectile(
        position: Vec3(x, BasketballCourt.spawnPoint.y, BasketballCourt.spawnPoint.z),
        velocity: Vec3.zero,
        config: BasketballCourt.throwConfig,
        // Randomised idle spin: the ball is never sitting the same way twice.
        spin: _rng.nextDouble() * math.pi * 2,
        spinRate: (_rng.nextDouble() - 0.5) * 1.4,
      ),
    );
  }

  /// Flick the waiting ball with [aim] in -1..1. Returns the launched ball, or
  /// null when there is nothing to throw (cooldown, or the clock has expired).
  LiveBall? shoot(double aim) {
    final ball = ready;
    if (ball == null || expired) return null;
    ball.body.velocity = BasketballAim.launchVelocity(
      from: ball.position,
      aim: aim,
      speed: launchSpeed,
      mode: mode,
    );
    // Backspin, scaled by how hard the ball was steered — a cut shot spins more.
    ball.body.spinRate = -7.5 - aim.abs() * 3.0;
    ball.launched = true;
    ready = null;
    live.add(ball);
    shots++;
    _cooldown = BasketballCourt.respawnCooldown;
    _trim();
    return ball;
  }

  void _trim() {
    // Oldest loose balls go first, so the newest action stays on screen.
    while (live.length > maxLoose) {
      final idx = live.indexWhere((b) => b.atRest);
      live.removeAt(idx >= 0 ? idx : 0);
    }
  }

  /// Advance the round by [dt] real seconds, reporting contacts to [onHit].
  ///
  /// Physics runs at [ThrowConfig.fixedDt] regardless of frame rate, so a round
  /// plays identically on a 60 Hz phone, a 120 Hz phone and a headless test.
  void advance(double dt, {void Function(BasketballHit hit)? onHit}) {
    final step = BasketballCourt.throwConfig.fixedDt;
    _accumulator += dt.clamp(0.0, 0.25);
    var guard = 0;
    while (_accumulator >= step && guard++ < 40) {
      _accumulator -= step;
      _stepOnce(step, onHit);
    }
  }

  void _stepOnce(double dt, void Function(BasketballHit hit)? onHit) {
    if (!expired) time = math.min(duration, time + dt);
    final hoop = hoopCentre;

    if (ready == null && !expired) {
      _cooldown -= dt;
      if (_cooldown <= 0) _spawn();
    }
    // The waiting ball only spins in place; it has no velocity to integrate.
    ready?.body.spin += ready!.body.spinRate * dt;

    for (final ball in live) {
      ball.age += dt;
      if (ball.netWobble > 0) {
        ball.netWobble = (ball.netWobble - dt * 2.4).clamp(0.0, 1.0);
      }
      if (ball.atRest) {
        ball.restAge += dt;
        continue;
      }
      _stepBall(ball, dt, hoop, onHit);
    }
    live.removeWhere((b) => b.gone);
  }

  void _stepBall(
    LiveBall ball,
    double dt,
    Vec3 hoop,
    void Function(BasketballHit hit)? onHit,
  ) {
    final body = ball.body;
    final from = body.step();
    final to = body.position;

    if (!ball.made &&
        Surfaces.passesDownThroughDisc(
          from,
          to,
          hoop,
          BasketballCourt.makeRadius,
        )) {
      ball.made = true;
      ball.netWobble = 1;
      makes++;
      onHit?.call(
        BasketballHit(BasketballHitKind.made, body.velocity.length, ball),
      );
    } else if (!ball.made) {
      final normal = Surfaces.rimContact(
        to,
        BasketballCourt.ballRadius,
        hoop,
        BasketballCourt.rimRadius,
        BasketballCourt.rimThickness,
      );
      if (normal != null) {
        final impact = body.velocity.length;
        body.bounce(normal, restitution: 0.5, friction: 0.22);
        onHit?.call(BasketballHit(BasketballHitKind.rim, impact, ball));
      } else {
        const half = BasketballCourt.backboardWidth / 2;
        final boardZ = BasketballCourt.backboardZ - BasketballCourt.ballRadius;
        final t = Surfaces.backboardCrossing(
          from,
          to,
          boardZ,
          hoop.x - half,
          hoop.x + half,
          BasketballCourt.backboardBottom,
          BasketballCourt.backboardBottom + BasketballCourt.backboardHeight,
        );
        if (t != null) {
          final impact = body.velocity.length;
          body.position = Vec3(to.x, to.y, boardZ);
          body.bounce(const Vec3(0, 0, -1), restitution: 0.42, friction: 0.15);
          onHit?.call(
            BasketballHit(BasketballHitKind.backboard, impact, ball),
          );
        }
      }
    }

    _confine(ball, onHit);
  }

  /// Floor, walls, rolling and rest.
  void _confine(LiveBall ball, void Function(BasketballHit hit)? onHit) {
    final body = ball.body;
    var p = body.position;

    if (p.y <= BasketballCourt.ballRadius) {
      p = Vec3(p.x, BasketballCourt.ballRadius, p.z);
      body.position = p;
      final vy = body.velocity.y;
      if (vy < -0.55) {
        final impact = body.velocity.length;
        body.bounce(const Vec3(0, 1, 0), restitution: 0.52, friction: 0.16);
        onHit?.call(BasketballHit(BasketballHitKind.bounce, impact, ball));
      } else if (vy < 0) {
        // Too slow to bounce: the ball is now rolling, not falling.
        body.velocity = Vec3(body.velocity.x, 0, body.velocity.z);
      }
      // Rolling friction, and spin that matches the roll.
      final dt = BasketballCourt.throwConfig.fixedDt;
      final damp = (1 - 1.9 * dt).clamp(0.0, 1.0);
      body.velocity = Vec3(
        body.velocity.x * damp,
        body.velocity.y,
        body.velocity.z * damp,
      );
      body.spinRate = -body.velocity.horizontalLength / BasketballCourt.ballRadius;
      if (body.velocity.horizontalLength < 0.14) {
        body.velocity = Vec3.zero;
        body.spinRate = 0;
        ball.atRest = true;
      }
    }

    // Keep loose balls inside the gym. Re-read the position: the floor branch
    // above may already have moved it.
    const sideWall = 7.2;
    p = body.position;
    if (p.x.abs() > sideWall) {
      body.position = Vec3(p.x.sign * sideWall, p.y, p.z);
      body.bounce(Vec3(-p.x.sign, 0, 0), restitution: 0.4, friction: 0.2);
      p = body.position;
    }
    if (p.z > BasketballCourt.backWallZ) {
      body.position = Vec3(p.x, p.y, BasketballCourt.backWallZ);
      body.bounce(const Vec3(0, 0, -1), restitution: 0.4, friction: 0.2);
      p = body.position;
    }
    if (p.z < BasketballCourt.cameraEye.z) {
      // A ball rolling back past the camera would pop out of frame; send it on.
      body.position = Vec3(p.x, p.y, BasketballCourt.cameraEye.z);
      body.bounce(const Vec3(0, 0, 1), restitution: 0.35, friction: 0.25);
    }

    if (ball.age > LiveBall.maxAge + LiveBall.fadeSeconds) ball.atRest = true;
  }
}

/// Fire one shot headlessly, from a ball spawned at [spawnX], and run it to
/// rest. The single entry point the tuning tests use, so they exercise exactly
/// the aiming path the game does.
LiveBall simulateShot({
  required BasketballHoopMode mode,
  required double aim,
  double spawnX = 0,
  double atTime = 0,
  double? launchSpeed,
}) {
  final sim = BasketballRoundSim(
    mode: mode,
    rng: math.Random(1),
    launchSpeed: launchSpeed,
  );
  sim.time = atTime;
  // Replace the randomly-placed ready ball with the requested spawn offset.
  sim.ready = LiveBall(
    id: -1,
    spawnX: spawnX,
    body: Projectile(
      position: Vec3(
        spawnX,
        BasketballCourt.spawnPoint.y,
        BasketballCourt.spawnPoint.z,
      ),
      velocity: Vec3.zero,
      config: BasketballCourt.throwConfig,
    ),
  );
  final ball = sim.shoot(aim)!;
  var guard = 0;
  while (!ball.atRest && guard++ < 2400) {
    sim.advance(BasketballCourt.throwConfig.fixedDt);
  }
  return ball;
}
