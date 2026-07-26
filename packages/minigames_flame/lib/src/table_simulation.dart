import 'dart:async';
import 'dart:ui' show Rect;

import 'package:forge2d/forge2d.dart';

import 'settle_detector.dart';
import 'sim_outcome.dart';

/// Tuning for a [TableSimulation]. Defaults describe a heavy disc sliding on a
/// waxed shuffleboard-style surface: no gravity, strong linear/angular damping
/// (the "friction" of the table), low bounce.
class TableSimConfig {
  /// Velocity bleed per second applied to translation — this is what brings a
  /// sliding disc to rest on a frictionless-looking top-down table.
  final double linearDamping;

  /// Velocity bleed per second applied to spin.
  final double angularDamping;

  /// Fixture friction used at disc↔disc and disc↔wall contacts.
  final double friction;

  /// Bounciness of discs (0 = dead, 1 = perfectly elastic).
  final double restitution;

  /// Bounciness of walls.
  final double wallRestitution;

  /// Default disc density (mass = density × area).
  final double density;

  /// Below this linear speed (m/s) a body counts as calm for settling.
  final double settleLinearSpeed;

  /// Below this angular speed (rad/s) a body counts as calm for settling.
  final double settleAngularSpeed;

  /// Consecutive calm steps required to declare the whole sim settled.
  final int settleFrames;

  /// Hard step budget; hitting it settles the run as timed-out.
  final int maxSteps;

  /// Seconds advanced per fixed step. Physics is always stepped at this rate.
  final double fixedDt;

  /// Downward acceleration (world units/s²). 0 keeps the default top-down
  /// "sliding" table; a positive value makes it a side-view world with gravity
  /// pulling toward +y, for arc games (cup pong, basketball) that throw a ball.
  final double gravityY;

  const TableSimConfig({
    this.linearDamping = 1.7,
    this.angularDamping = 2.2,
    this.friction = 0.04,
    this.restitution = 0.18,
    this.wallRestitution = 0.35,
    this.density = 1.4,
    this.settleLinearSpeed = 0.05,
    this.settleAngularSpeed = 0.08,
    this.settleFrames = 14,
    this.maxSteps = 1400,
    this.fixedDt = 1 / 60,
    this.gravityY = 0,
  });
}

/// A dynamic circular body (puck / disc / ball) tracked by the sim.
///
/// Holds the id and metadata the game cares about, plus the live Forge2D
/// [body]. Once [removed] is true the underlying body has been destroyed and
/// [position]/[angle] return the last-known pose captured at removal.
class DiscBody {
  /// Stable id used to match this body across the serialized [SimOutcome].
  final String id;

  /// Radius in world units.
  final double radius;

  /// Opaque game-supplied tag (e.g. owning player id). The harness never reads
  /// it — it only rides along so the game can recover context on settle.
  final Object? owner;

  Body _body;
  bool _removed = false;
  Vector2 _lastPos;
  double _lastAngle = 0;
  Vector2 _lastVel = Vector2.zero();

  DiscBody._(this.id, this._body, this.radius, this.owner)
      : _lastPos = _body.position.clone();

  /// The live physics body. Do not use after [removed] becomes true.
  Body get body => _body;

  /// Whether this disc has left the table and been destroyed.
  bool get removed => _removed;

  /// Current (or last-known, if [removed]) world position.
  Vector2 get position => _removed ? _lastPos : _body.position;

  /// Current (or last-known, if [removed]) rotation in radians.
  double get angle => _removed ? _lastAngle : _body.angle;

  /// Current (or, once [removed], the exit) linear velocity. Lets a game carry
  /// a disc's momentum into a fall/knockout flourish after it leaves the table.
  Vector2 get lastVelocity => _removed ? _lastVel : _body.linearVelocity;

  void _sync() {
    if (_removed) return;
    _lastPos = _body.position.clone();
    _lastAngle = _body.angle;
    _lastVel = _body.linearVelocity.clone();
  }
}

/// A top-down, zero-gravity Forge2D world for table games (shuffleboard, pool,
/// air hockey, mini golf…): a sliding world, not a falling one. Pieces are
/// circular [DiscBody]s that lose speed to damping and can knock into each
/// other and into static walls.
///
/// The class is deliberately **headless** — it owns a raw Forge2D [World] and
/// never touches Flame's game loop or any widget — so a shot can be simulated
/// and its outcome captured with no rendering, which is exactly what the seam
/// and the tests need. A Flame `GameWidget` can drive the same instance by
/// calling [step] each frame and reading disc positions to render.
///
/// Lifecycle of one shot:
/// 1. [addDisc] the pieces and [addWall]s once when the table is built.
/// 2. [launch] the shooter's disc with an impulse.
/// 3. Either pump [step] each frame (animated) and await [settled] / listen via
///    [onSettled], or call [runUntilSettled] to fast-forward headlessly.
/// 4. Read the returned [SimOutcome] and map it into a game move.
class TableSimulation {
  final TableSimConfig config;
  final World world;

  /// Every disc ever added, in insertion order (removed ones stay in the list
  /// so the settled outcome still reports where they left).
  final List<DiscBody> discs = <DiscBody>[];

  /// Predicate deciding when a disc has left the playfield (e.g. slid off an
  /// open end). Returning true destroys the body and flags it [DiscBody.removed].
  final bool Function(DiscBody disc)? shouldRemove;

  /// Fired once per new disc↔disc contact — hook game collision SFX here.
  void Function(DiscBody a, DiscBody b)? onDiscCollision;

  /// Fired exactly once when a launched run settles.
  void Function(SimOutcome outcome)? onSettled;

  late final SettleDetector _detector = SettleDetector(
    framesRequired: config.settleFrames,
    maxSteps: config.maxSteps,
  );

  bool _running = false;
  Completer<SimOutcome>? _settleCompleter;

  TableSimulation({this.config = const TableSimConfig(), this.shouldRemove})
      : world = World(Vector2(0, config.gravityY)) {
    world.setContactListener(_DiscContactListener(this));
  }

  /// Whether a launched shot is still in motion (not yet settled).
  bool get isRunning => _running;

  /// Add a dynamic disc at [position] (world units).
  DiscBody addDisc({
    required String id,
    required Vector2 position,
    required double radius,
    Object? owner,
    double? density,
    double? friction,
    double? restitution,
  }) {
    final def = BodyDef(
      type: BodyType.dynamic,
      position: position,
      linearDamping: config.linearDamping,
      angularDamping: config.angularDamping,
    );
    final body = world.createBody(def);
    body.createFixtureFromShape(
      CircleShape(radius: radius),
      density: density ?? config.density,
      friction: friction ?? config.friction,
      restitution: restitution ?? config.restitution,
    );
    final disc = DiscBody._(id, body, radius, owner);
    body.userData = disc;
    discs.add(disc);
    return disc;
  }

  /// Add a static wall segment between [a] and [b] (world units).
  void addWall(Vector2 a, Vector2 b, {double? restitution}) {
    final body = world.createBody(BodyDef(type: BodyType.static));
    body.createFixtureFromShape(
      EdgeShape()..set(a, b),
      friction: config.friction,
      restitution: restitution ?? config.wallRestitution,
    );
  }

  /// Add straight walls around [bounds]. Any edge flag set false is left open
  /// (a disc can slide off that side — pair it with [shouldRemove]). Uses a
  /// y-down convention: [top] is the low-y edge, [bottom] the high-y edge.
  void addBounds(
    Rect bounds, {
    bool left = true,
    bool right = true,
    bool top = true,
    bool bottom = true,
  }) {
    final tl = Vector2(bounds.left, bounds.top);
    final tr = Vector2(bounds.right, bounds.top);
    final bl = Vector2(bounds.left, bounds.bottom);
    final br = Vector2(bounds.right, bounds.bottom);
    if (left) addWall(tl, bl);
    if (right) addWall(tr, br);
    if (top) addWall(tl, tr);
    if (bottom) addWall(bl, br);
  }

  /// Launch [disc] with [impulse] and begin a settle run. Resets the settle
  /// detector, so calling it starts a fresh shot.
  Future<SimOutcome> launch(DiscBody disc, Vector2 impulse) {
    _detector.reset();
    _running = true;
    _settleCompleter = Completer<SimOutcome>();
    disc.body.applyLinearImpulse(impulse);
    return _settleCompleter!.future;
  }

  /// Advance one fixed step. Handles removal, collision callbacks (via the
  /// world contact listener), and settle detection. Safe to call when idle
  /// (it just steps the world).
  void step() {
    world.stepDt(config.fixedDt);

    for (final d in discs) {
      if (d._removed) continue;
      if (shouldRemove?.call(d) ?? false) {
        d._sync();
        d._removed = true;
        world.destroyBody(d._body);
      } else {
        d._sync();
      }
    }

    if (_running && _detector.step(calm: _allCalm())) {
      _running = false;
      final outcome = buildOutcome();
      onSettled?.call(outcome);
      _settleCompleter?.complete(outcome);
      _settleCompleter = null;
    }
  }

  /// Fast-forward a launched shot to rest with no rendering, returning its
  /// outcome. If nothing is running it returns the current resting snapshot.
  SimOutcome runUntilSettled() {
    while (_running) {
      step();
    }
    return buildOutcome();
  }

  /// Snapshot every disc's current pose as a serializable outcome.
  SimOutcome buildOutcome() => SimOutcome(
        bodies: [
          for (final d in discs)
            SettledBody(
              id: d.id,
              x: d.position.x,
              y: d.position.y,
              angle: d.angle,
              removed: d._removed,
            ),
        ],
        steps: _detector.steps,
        timedOut: _detector.timedOut,
      );

  bool _allCalm() {
    final linSq = config.settleLinearSpeed * config.settleLinearSpeed;
    for (final d in discs) {
      if (d._removed) continue;
      if (d._body.linearVelocity.length2 > linSq) return false;
      if (d._body.angularVelocity.abs() > config.settleAngularSpeed) {
        return false;
      }
    }
    return true;
  }
}

/// Bridges Forge2D contacts to [TableSimulation.onDiscCollision], firing only
/// for disc↔disc pairs (both bodies carry a [DiscBody] user-data tag).
class _DiscContactListener extends ContactListener {
  final TableSimulation sim;

  _DiscContactListener(this.sim);

  @override
  void beginContact(Contact contact) {
    final a = contact.bodyA.userData;
    final b = contact.bodyB.userData;
    if (a is DiscBody && b is DiscBody) {
      sim.onDiscCollision?.call(a, b);
    }
  }
}
