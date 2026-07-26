import 'dart:async';
import 'dart:math' as math;

// Flame's game.dart re-exports the non-64 vector_math Vector2; forge2d (which
// the harness API speaks) uses vector_math_64. Hide Flame's so the single
// Vector2 in this file is forge2d's — the type TableSimulation expects.
import 'package:flame/game.dart' hide Vector2;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge2d/forge2d.dart' show Vector2;
import 'package:minigames_core/minigames_core.dart';
import 'package:minigames_flame/minigames_flame.dart';

import 'knockout_game.dart';
import 'knockout_style.dart';

/// Animated knockout board wired to a [MatchController].
///
/// The board owns a [KnockoutScene] (a Flame `GameWidget`) that runs the flick
/// simulation locally via the [minigames_flame] harness. Drag back from one of
/// your own pucks and release to aim + power a flick; the scene simulates it to
/// rest, packages the settled positions (with `fell` flags) into a
/// [KnockoutMove], and hands it back so this widget can submit it through the
/// controller. Hot-seat pass-and-play with perfect information — no handoff
/// cover.
class KnockoutBoard extends StatefulWidget {
  final MatchController<KnockoutState, KnockoutMove> controller;
  final KnockoutStyle style;

  const KnockoutBoard({
    super.key,
    required this.controller,
    this.style = const KnockoutStyle(),
  });

  @override
  State<KnockoutBoard> createState() => _KnockoutBoardState();
}

class _KnockoutBoardState extends State<KnockoutBoard>
    with TickerProviderStateMixin {
  static const _game = KnockoutGame();

  KnockoutScene? _scene;
  StreamSubscription<KnockoutState>? _sub;
  KnockoutState? _state;
  GameOutcome? _outcome;

  String _pill = '';
  Timer? _pillTimer;
  bool _celebrated = false;

  // Assigned in initState — NOT a `late` inline initializer. A `late` field
  // would run its initializer the first time it's touched, and dispose() touches
  // it via _confettiCtrl.dispose(); if confetti never fired, that would build an
  // AnimationController(vsync: this) during teardown and illegally look up a
  // deactivated element's ancestor.
  late final AnimationController _confettiCtrl;
  final math.Random _rnd = math.Random();
  List<_Confetto> _confetti = const [];

  bool get _hotSeat => widget.controller.hotSeat;

  @override
  void initState() {
    super.initState();
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _bind();
  }

  @override
  void didUpdateWidget(covariant KnockoutBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    _sub?.cancel();
    _bind();
  }

  // Context-free fallback; build() overwrites _scheme + scene.scheme with the
  // real one. Cached so callbacks never touch Theme.of off the build path.
  static final ColorScheme _fallbackScheme =
      ColorScheme.fromSeed(seedColor: const Color(0xFF007AFF));
  ColorScheme _scheme = _fallbackScheme;

  void _bind() {
    final scene = KnockoutScene(style: widget.style, scheme: _fallbackScheme)
      ..onLaunch = _onLaunch
      ..onCollision = _onCollision
      ..onSettled = _onFlickSettled
      ..onAimChanged = () => setState(() {});
    _scene = scene;
    _celebrated = false;
    _pill = '';
    _confetti = const [];
    final s = widget.controller.state;
    _state = s;
    _outcome = s == null ? null : _game.outcome(s);
    if (s != null) {
      scene.applyState(s, _actingFor(s));
      if (_outcome != null) {
        _celebrated = true;
      } else {
        _showPill('${_labelFor(s.currentPlayerId)}’s turn');
      }
    }
    _sub = widget.controller.stateStream.listen(_onState);
  }

  /// Sets the centre pill. Transient pills auto-clear after a few seconds; the
  /// win/draw pill is [sticky] and stays. Assigns synchronously — callers own
  /// the surrounding setState.
  void _showPill(String text, {bool sticky = false}) {
    _pillTimer?.cancel();
    _pill = text;
    if (!sticky && text.isNotEmpty) {
      _pillTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _pill = '');
      });
    }
  }

  String _actingFor(KnockoutState s) =>
      _hotSeat ? s.currentPlayerId : widget.controller.localPlayerId;

  @override
  void dispose() {
    _sub?.cancel();
    _pillTimer?.cancel();
    _confettiCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Scene callbacks (fired from real sim events, never timers)
  // ---------------------------------------------------------------------------

  void _onLaunch() {
    if (!mounted) return;
    widget.style.sounds.onLaunch?.call();
    if (widget.style.haptics) HapticFeedback.mediumImpact();
    setState(() => _showPill(''));
  }

  Duration _lastClack = Duration.zero;
  final Stopwatch _clock = Stopwatch()..start();

  void _onCollision() {
    if (!mounted) return;
    // Throttle: a single contact can report many times per settle.
    final now = _clock.elapsed;
    if (now - _lastClack < const Duration(milliseconds: 70)) return;
    _lastClack = now;
    widget.style.sounds.onCollision?.call();
    if (widget.style.haptics) HapticFeedback.selectionClick();
  }

  void _onFlickSettled(KnockoutMove move, KnockoutShotResult result) {
    if (!mounted) return;
    final style = widget.style;
    if (result.oppKnocked > 0) {
      style.sounds.onKnockOff?.call();
      if (style.haptics) HapticFeedback.heavyImpact();
    }
    if (result.ownLost > 0) {
      style.sounds.onOwnLoss?.call();
      if (style.haptics) HapticFeedback.mediumImpact();
    }
    final opp = _state?.playerIds.firstWhere((p) => p != move.owner) ?? '';
    final String pill;
    if (result.isOwnGoal) {
      pill = result.ownLost == 1 ? 'Own puck lost!' : '${result.ownLost} own pucks lost!';
    } else if (result.isCleanHit) {
      pill = result.oppKnocked == 1
          ? '${_labelFor(opp)} knocked off!'
          : '${result.oppKnocked} knocked off!';
    } else {
      pill = 'No contact';
    }
    // Submit the settled outcome as the move.
    widget.controller.submitMove(move);
    if (mounted) setState(() => _showPill(pill));
  }

  void _onState(KnockoutState next) {
    if (!mounted) return;
    final outcome = _game.outcome(next);
    final isFresh = next.frame == 0;

    _scene?.applyState(next, _actingFor(next));

    if (outcome != null && !_celebrated) {
      _celebrate(outcome, next);
    } else if (outcome == null && isFresh) {
      _showPill('${_labelFor(next.currentPlayerId)}’s turn');
    }

    setState(() {
      _state = next;
      _outcome = outcome;
    });
  }

  void _celebrate(GameOutcome outcome, KnockoutState state) {
    _celebrated = true;
    final style = widget.style;
    if (outcome.isDraw) {
      style.sounds.onDraw?.call();
    } else {
      style.sounds.onWin?.call();
    }
    if (style.haptics) HapticFeedback.heavyImpact();
    _showPill(
      outcome.isDraw
          ? 'DRAW'
          : '${_labelFor(outcome.winnerId!)} wins'.toUpperCase(),
      sticky: true,
    );
    if (style.confetti && !outcome.isDraw) {
      _confetti = _spawnConfetti();
      _confettiCtrl.forward(from: 0);
    }
  }

  List<_Confetto> _spawnConfetti() {
    final scheme = _scheme;
    final palette = [
      widget.style.resolvePlayer1(scheme),
      widget.style.resolvePlayer2(scheme),
      const Color(0xFFF4B740),
      Colors.white,
    ];
    return List.generate(34, (i) {
      final angle = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 2.6;
      return _Confetto(
        angle: angle,
        speed: 0.5 + _rnd.nextDouble(),
        size: 0.012 + _rnd.nextDouble() * 0.02,
        color: palette[i % palette.length],
        spin: (_rnd.nextDouble() - 0.5) * 12,
        phase: _rnd.nextDouble() * math.pi,
        round: _rnd.nextBool(),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Aiming (Flutter-level pan -> scene, in the board's local coords)
  // ---------------------------------------------------------------------------

  void _panStart(DragStartDetails d) {
    final scene = _scene;
    if (scene == null || !scene.canAim || _outcome != null) return;
    // A flick drag must begin on one of the acting player's own pucks.
    scene.beginAim(d.localPosition);
  }

  void _panUpdate(DragUpdateDetails d) => _scene?.updateAim(d.localPosition);

  void _panEnd(DragEndDetails d) => _scene?.endAim();

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  String _labelFor(String playerId) {
    final s = _state;
    if (s == null) return playerId;
    return playerId == s.playerIds.first
        ? widget.style.player1Label
        : widget.style.player2Label;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final state = _state;
    final scene = _scene;
    if (state == null || scene == null) {
      return const Center(child: CircularProgressIndicator());
    }
    scene.scheme = scheme;
    _scheme = scheme;

    final p1 = state.playerIds.first;
    final p2 = state.playerIds.last;
    const shell = Color(0xFF1B1E24);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: RadialGradient(
          center: const Alignment(0, -0.4),
          radius: 1.5,
          colors: [
            Color.lerp(shell, Colors.white, 0.06)!,
            shell,
            Color.lerp(shell, Colors.black, 0.4)!,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            offset: const Offset(0, 6),
            blurRadius: 18,
          ),
        ],
      ),
      child: Column(
        children: [
          // Far player (top).
          Align(
            alignment: Alignment.centerLeft,
            child: _PlayerChip(
              label: _labelFor(p2),
              remaining: state.liveCountOf(p2),
              pucksPerPlayer: state.pucksPerPlayer,
              accent: style.resolvePlayer2(scheme),
              active: _outcome == null && state.currentPlayerId == p2,
              winner: _outcome?.winnerId == p2,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: AspectRatio(
                  aspectRatio: 1, // square platform
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: _panStart,
                          onPanUpdate: _panUpdate,
                          onPanEnd: _panEnd,
                          child: GameWidget(game: scene),
                        ),
                      ),
                      if (style.confetti && _confetti.isNotEmpty)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _confettiCtrl,
                              builder: (context, _) => LayoutBuilder(
                                builder: (context, c) => CustomPaint(
                                  painter: _ConfettiPainter(
                                    confetti: _confetti,
                                    t: _confettiCtrl.value,
                                    boardSize: c.maxWidth,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: _pill.isEmpty
                                  ? const SizedBox.shrink()
                                  : _Pill(key: ValueKey(_pill), text: _pill),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _outcome != null
                ? 'Tap New game to play again'
                : (scene.canAim
                    ? 'Drag back from one of your pucks to aim, then release'
                    : 'Sliding…'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          // Near player (bottom).
          Align(
            alignment: Alignment.centerRight,
            child: _PlayerChip(
              label: _labelFor(p1),
              remaining: state.liveCountOf(p1),
              pucksPerPlayer: state.pucksPerPlayer,
              accent: style.resolvePlayer1(scheme),
              active: _outcome == null && state.currentPlayerId == p1,
              winner: _outcome?.winnerId == p1,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The Flame scene: drives a TableSimulation and renders the platform.
// ---------------------------------------------------------------------------

/// A Flame [FlameGame] that runs one knockout board's physics via a
/// [TableSimulation] and renders the platform each frame. Rendering is manual
/// (canvas drawing in [render]) — the harness supplies the physics, the scene
/// supplies the look, keeping the harness game-agnostic.
class KnockoutScene extends FlameGame {
  KnockoutScene({required this.style, required this.scheme}) {
    _sim = _buildSim(null);
  }

  final KnockoutStyle style;
  ColorScheme scheme;

  // Square platform (sim world units, y-down: y=0 far lip, y=platform near lip).
  static const double platform = 10;
  static const double puckR = 0.5;

  // Tuned so a full-power flick crosses the platform and clears an opposing
  // puck; a light flick nudges. Momentum transfer does the knocking-off.
  static const _aim = AimToImpulse(
    maxDrag: 200,
    maxImpulse: 24,
    minImpulse: 4,
    deadZone: 10,
  );

  // A touch livelier than the harness default so struck pucks carry off the
  // lip; damping still brings everything to rest.
  static const _simConfig = TableSimConfig(
    linearDamping: 1.3,
    restitution: 0.3,
  );

  late TableSimulation _sim;
  KnockoutState? _state;
  String _acting = '';
  DiscBody? _shooter;
  bool _launched = false;
  double _accum = 0;

  // Off-the-lip fall animation: purely visual, decoupled from the (trusted)
  // physics. When a disc is removed at an edge we spawn a [_Falling] that tips
  // over the lip; the reducer already treats it as gone.
  static const double _fallDuration = 0.5;
  final List<_Falling> _falling = [];
  final Set<String> _fellIds = {};

  Offset? _aimStart;
  Offset? _aimNow;

  void Function()? onLaunch;
  void Function()? onCollision;
  void Function()? onAimChanged;
  void Function(KnockoutMove move, KnockoutShotResult result)? onSettled;

  bool get canAim =>
      !_launched &&
      !_sim.isRunning &&
      (_state != null && _game.outcome(_state!) == null);

  bool get isAiming =>
      _shooter != null && _aimStart != null && _aimNow != null;

  static const _game = KnockoutGame();

  @override
  Color backgroundColor() => style.resolveVoid(scheme);

  TableSimulation _buildSim(KnockoutState? state) {
    final sim = TableSimulation(
      config: _simConfig,
      // All four lips are open: a puck whose center leaves the platform falls.
      shouldRemove: (d) =>
          d.position.y < 0 ||
          d.position.y > platform ||
          d.position.x < -platform / 2 ||
          d.position.x > platform / 2,
    )
      ..onDiscCollision = ((_, __) => onCollision?.call())
      ..onSettled = _handleSettled;
    // No bounds walls — every edge is a cliff.
    if (state != null) {
      for (final p in state.pucks) {
        sim.addDisc(
          id: p.id,
          owner: p.owner,
          position: _simPos(p.nx, p.ny),
          radius: puckR,
        );
      }
    }
    return sim;
  }

  /// Rebuild the sim to match [state] before each flick.
  void applyState(KnockoutState state, String acting) {
    _state = state;
    _acting = acting;
    _launched = false;
    _shooter = null;
    _aimStart = null;
    _aimNow = null;
    _accum = 0;
    _sim = _buildSim(state);
    // A fresh match (New game) starts clean; mid-match rebuilds keep any
    // in-flight fall animating across the settle→rebuild.
    if (state.frame == 0) {
      _falling.clear();
      _fellIds.clear();
    }
  }

  Vector2 _simPos(double nx, double ny) =>
      Vector2((nx - 0.5) * platform, ny * platform);

  ({double nx, double ny}) _toNorm(Vector2 p) =>
      (nx: p.x / platform + 0.5, ny: p.y / platform);

  /// The acting player's live disc under [local] (board-pixel coords), or null.
  DiscBody? _ownPuckAt(Offset local) {
    if (size.x < 2 || size.y < 2) return null;
    final puckPx = (puckR / platform) * size.x;
    final hitR = math.max(puckPx * 1.7, 40.0);
    DiscBody? best;
    var bestD = double.infinity;
    for (final d in _sim.discs) {
      if (d.removed || d.owner != _acting) continue;
      final n = _toNorm(d.position);
      final center = Offset(n.nx * size.x, n.ny * size.y);
      final dist = (local - center).distance;
      if (dist <= hitR && dist < bestD) {
        best = d;
        bestD = dist;
      }
    }
    return best;
  }

  // -- aiming --

  void beginAim(Offset local) {
    if (!canAim) return;
    final puck = _ownPuckAt(local);
    if (puck == null) return; // drag didn't start on one of your pucks
    _shooter = puck;
    _aimStart = local;
    _aimNow = local;
    onAimChanged?.call();
  }

  void updateAim(Offset local) {
    if (_aimStart == null) return;
    _aimNow = local;
    onAimChanged?.call();
  }

  void endAim() {
    final start = _aimStart;
    final now = _aimNow;
    final shooter = _shooter;
    _aimStart = null;
    _aimNow = null;
    onAimChanged?.call();
    if (shooter == null || _launched || start == null || now == null) return;
    final drag = Vector2(now.dx - start.dx, now.dy - start.dy);
    final impulse = _aim.impulse(drag);
    if (impulse.length2 == 0) {
      _shooter = null; // dead zone: no shot, release the puck
      return;
    }
    _launched = true;
    onLaunch?.call();
    _sim.launch(shooter, impulse);
  }

  // -- loop --

  @override
  void update(double dt) {
    super.update(dt);
    // Advance any fall animations regardless of sim state (they outlive the
    // settle that ends the flick).
    if (_falling.isNotEmpty) {
      for (final f in _falling) {
        f.t += dt;
      }
      _falling.removeWhere((f) => f.t >= _fallDuration);
    }
    if (!_sim.isRunning) return;
    _accum += dt;
    var steps = 0;
    final h = _sim.config.fixedDt;
    while (_accum >= h && steps < 8) {
      _sim.step();
      _accum -= h;
      steps++;
      if (!_sim.isRunning) break;
    }
    _spawnFallsForNewlyRemoved();
  }

  /// Any disc removed this frame gets one fall animation, carrying its exit
  /// momentum over whichever lip it crossed.
  void _spawnFallsForNewlyRemoved() {
    for (final d in _sim.discs) {
      if (!d.removed || _fellIds.contains(d.id)) continue;
      _fellIds.add(d.id);
      final n = _toNorm(d.position);
      final v = d.lastVelocity;
      final ids = _state?.playerIds ?? const ['p1', 'p2'];
      final color = style.colorFor(scheme, d.owner as String, ids);

      // Which lip did it cross? Compare how far past each open edge it went.
      final overTop = -n.ny;
      final overBottom = n.ny - 1;
      final overLeft = -n.nx;
      final overRight = n.nx - 1;
      final maxOver =
          math.max(math.max(overTop, overBottom), math.max(overLeft, overRight));
      late final _FallEdge edge;
      late final double along;
      late final double carry;
      late final double spinDir;
      if (maxOver == overLeft) {
        edge = _FallEdge.left;
        along = n.ny.clamp(0.0, 1.0);
        carry = v.y / platform;
        spinDir = v.y >= 0 ? 1.0 : -1.0;
      } else if (maxOver == overRight) {
        edge = _FallEdge.right;
        along = n.ny.clamp(0.0, 1.0);
        carry = v.y / platform;
        spinDir = v.y >= 0 ? -1.0 : 1.0;
      } else if (maxOver == overBottom) {
        edge = _FallEdge.bottom;
        along = n.nx.clamp(0.0, 1.0);
        carry = v.x / platform;
        spinDir = v.x >= 0 ? -1.0 : 1.0;
      } else {
        edge = _FallEdge.top;
        along = n.nx.clamp(0.0, 1.0);
        carry = v.x / platform;
        spinDir = v.x >= 0 ? 1.0 : -1.0;
      }
      _falling.add(_Falling(
        edge: edge,
        along: along,
        carry: carry,
        color: color,
        spinDir: spinDir,
      ));
    }
  }

  void _handleSettled(SimOutcome outcome) {
    final flickedId = _shooter?.id ?? '';
    final positions = <KnockoutPosition>[];
    for (final d in _sim.discs) {
      final n = _toNorm(d.position);
      positions.add(
        KnockoutPosition(
          id: d.id,
          owner: d.owner as String,
          nx: d.removed ? n.nx : n.nx.clamp(0.0, 1.0),
          ny: d.removed ? n.ny : n.ny.clamp(0.0, 1.0),
          fell: d.removed,
        ),
      );
    }
    final move = KnockoutMove(
      flickedPuckId: flickedId,
      owner: _acting,
      positions: positions,
    );
    final result = _state == null
        ? const KnockoutShotResult(ownLost: 0, oppKnocked: 0)
        : _game.classifyShot(_state!, move);
    onSettled?.call(move, result);
  }

  // -- render --

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (size.x < 2 || size.y < 2) return;

    final state = _state;
    final playerIds = state?.playerIds ?? const ['p1', 'p2'];
    final highlightAll = canAim && !isAiming;

    final pucks = <RenderPuck>[];
    for (final d in _sim.discs) {
      if (d.removed) continue;
      final n = _toNorm(d.position);
      final owner = d.owner as String;
      pucks.add(
        RenderPuck(
          nx: n.nx,
          ny: n.ny,
          radiusFrac: puckR / platform,
          color: style.colorFor(scheme, owner, playerIds),
          flickable: highlightAll && owner == _acting,
          isShooter: identical(d, _shooter),
        ),
      );
    }

    AimView? aim;
    if (isAiming) {
      final n = _toNorm(_shooter!.position);
      final drag = Vector2(
        _aimNow!.dx - _aimStart!.dx,
        _aimNow!.dy - _aimStart!.dy,
      );
      final impulse = _aim.impulse(drag);
      final power = _aim.power01(drag);
      final dir = impulse.length2 == 0
          ? const Offset(0, -1)
          : Offset(impulse.x, impulse.y) / impulse.length;
      aim = AimView(nx: n.nx, ny: n.ny, dir: dir, power: power);
    }

    final falling = <FallingPuck>[];
    for (final f in _falling) {
      final p = (f.t / _fallDuration).clamp(0.0, 1.0);
      // A lip sits right at the platform edge with no runway, so the puck tips
      // over IN PLACE: it stays at the edge, foreshortens hard along the axis
      // perpendicular to that lip, sinks into shadow and fades. A little
      // momentum carry + spin sells the drop.
      const edgeIn = 0.012;
      final edgeOut = 0.012 - 0.032 * p;
      final carry = f.carry * p * 0.12;
      final foreshorten = 1 - 0.9 * p; // perpendicular squash
      double nx, ny, sx, sy;
      switch (f.edge) {
        case _FallEdge.top:
          nx = f.along + carry;
          ny = edgeOut;
          sx = 1;
          sy = foreshorten;
        case _FallEdge.bottom:
          nx = f.along + carry;
          ny = 1 - edgeIn + 0.032 * p;
          sx = 1;
          sy = foreshorten;
        case _FallEdge.left:
          nx = edgeOut;
          ny = f.along + carry;
          sx = foreshorten;
          sy = 1;
        case _FallEdge.right:
          nx = 1 - edgeIn + 0.032 * p;
          ny = f.along + carry;
          sx = foreshorten;
          sy = 1;
      }
      falling.add(
        FallingPuck(
          nx: nx,
          ny: ny,
          radiusFrac: puckR / platform,
          color: Color.lerp(f.color, Colors.black, 0.55 * p)!,
          scale: 1 - 0.3 * p,
          squashX: sx,
          squashY: sy,
          alpha: p < 0.5 ? 1.0 : (1 - (p - 0.5) / 0.5),
          spin: p * 0.4 * f.spinDir,
        ),
      );
    }

    paintKnockoutTable(
      canvas,
      Size(size.x, size.y),
      KnockoutView(pucks: pucks, aim: aim, falling: falling),
      style,
      scheme,
    );
  }
}

/// Which open lip a disc slid off — drives how its fall tips over the edge.
enum _FallEdge { top, bottom, left, right }

/// One in-flight off-the-lip fall. Scene-private; the painter gets a computed
/// [FallingPuck] each frame.
class _Falling {
  final _FallEdge edge;

  /// Position along the exiting lip (nx for [top]/[bottom]; ny for sides).
  final double along;

  /// Normalized velocity component parallel to that lip.
  final double carry;
  final double spinDir;
  final Color color;
  double t = 0;

  _Falling({
    required this.edge,
    required this.along,
    required this.carry,
    required this.color,
    required this.spinDir,
  });
}

// ---------------------------------------------------------------------------
// Shared table painter — used by the live scene AND by static previews/tests.
// ---------------------------------------------------------------------------

/// A puck to draw, in normalized platform coords.
class RenderPuck {
  final double nx;
  final double ny;

  /// Radius as a fraction of the platform width.
  final double radiusFrac;
  final Color color;

  /// True for the acting player's pucks when a flick can start (soft halo).
  final bool flickable;

  /// True for the puck currently being aimed (stronger halo).
  final bool isShooter;

  const RenderPuck({
    required this.nx,
    required this.ny,
    required this.radiusFrac,
    required this.color,
    this.flickable = false,
    this.isShooter = false,
  });
}

/// The aim/power indicator overlay.
class AimView {
  final double nx;
  final double ny;

  /// Unit launch direction in screen space (y-down).
  final Offset dir;

  /// 0..1 power for the meter.
  final double power;

  const AimView({
    required this.nx,
    required this.ny,
    required this.dir,
    required this.power,
  });
}

/// A puck mid-fall off a lip — drawn over the void (outside the platform clip)
/// with a shrink, foreshorten, tumble and fade.
class FallingPuck {
  final double nx;
  final double ny;
  final double radiusFrac;
  final Color color;
  final double scale;

  /// Foreshorten squash as it tips over a lip (1 = round, →0 flattened). Only
  /// the axis perpendicular to the exiting lip shrinks.
  final double squashX;
  final double squashY;
  final double alpha;
  final double spin;

  const FallingPuck({
    required this.nx,
    required this.ny,
    required this.radiusFrac,
    required this.color,
    required this.scale,
    this.squashX = 1,
    this.squashY = 1,
    required this.alpha,
    required this.spin,
  });
}

/// Everything one frame of the board needs.
class KnockoutView {
  final List<RenderPuck> pucks;
  final AimView? aim;
  final List<FallingPuck> falling;

  const KnockoutView({
    required this.pucks,
    this.aim,
    this.falling = const [],
  });
}

/// Draws the void, the raised platform (rounded square) with its lip + center
/// line, the pucks and the aim indicator into [size]. Pure — no Flame or widget
/// state — so a `CustomPainter` can call it for a static snapshot
/// (screenshots/tests) exactly as the live scene does.
void paintKnockoutTable(
  Canvas canvas,
  Size size,
  KnockoutView view,
  KnockoutStyle style,
  ColorScheme scheme,
) {
  final voidColor = style.resolveVoid(scheme);
  final platformColor = style.resolvePlatform(scheme);

  final full = Offset.zero & size;

  // Void backdrop (radial so the platform reads as floating over a pit).
  canvas.drawRect(
    full,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.1),
        radius: 0.9,
        colors: [
          Color.lerp(voidColor, Colors.white, 0.05)!,
          voidColor,
          Color.lerp(voidColor, Colors.black, 0.6)!,
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(full),
  );

  // Platform inset so a ring of void shows all round — the cliff you fall off.
  final margin = size.width * 0.11;
  final platRect = Rect.fromLTRB(
    margin,
    margin,
    size.width - margin,
    size.height - margin,
  );
  final platRR =
      RRect.fromRectAndRadius(platRect, Radius.circular(size.width * 0.10));

  // Drop shadow into the void beneath the slab.
  canvas.drawRRect(
    platRR.shift(const Offset(0, 6)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
  );

  // Slab surface.
  canvas.drawRRect(
    platRR,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(platformColor, Colors.white, 0.22)!,
          platformColor,
          Color.lerp(platformColor, Colors.black, 0.22)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(platRect),
  );

  canvas.save();
  canvas.clipRRect(platRR);

  double xOf(double nx) => platRect.left + nx * platRect.width;
  double yOf(double ny) => platRect.top + ny * platRect.height;

  // Faint half-court line so the two territories read.
  canvas.drawLine(
    Offset(platRect.left, yOf(0.5)),
    Offset(platRect.right, yOf(0.5)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.10)
      ..strokeWidth = math.max(1, size.width * 0.006),
  );
  // Center emblem.
  canvas.drawCircle(
    Offset(xOf(0.5), yOf(0.5)),
    size.width * 0.05,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, size.width * 0.006)
      ..color = Colors.black.withValues(alpha: 0.08),
  );

  // Pucks.
  for (final p in view.pucks) {
    _paintPuck(canvas, Offset(xOf(p.nx), yOf(p.ny)),
        p.radiusFrac * platRect.width, p);
  }

  // Aim indicator.
  final aim = view.aim;
  if (aim != null) {
    _paintAim(canvas, Offset(xOf(aim.nx), yOf(aim.ny)), aim,
        platRect.width, size);
  }

  canvas.restore();

  // Bright inner lip so the edge you fall off reads sharply.
  canvas.drawRRect(
    platRR.deflate(1.0),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.white.withValues(alpha: 0.28),
  );
  // Dark outer shoulder just past the lip.
  canvas.drawRRect(
    platRR.inflate(1.5),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.black.withValues(alpha: 0.5),
  );

  // Falling pucks — drawn last and OUTSIDE the platform clip so they tumble
  // over the lip and into the void instead of being clipped at the boundary.
  for (final f in view.falling) {
    _paintFallingPuck(
      canvas,
      Offset(xOf(f.nx), yOf(f.ny)),
      f.radiusFrac * platRect.width,
      f,
    );
  }
}

void _paintFallingPuck(Canvas canvas, Offset c, double r, FallingPuck f) {
  if (r <= 0.3 || f.alpha <= 0.01) return;
  final bounds = Rect.fromCircle(center: c, radius: r * 2);
  canvas.saveLayer(
    bounds,
    Paint()..color = Colors.white.withValues(alpha: f.alpha.clamp(0.0, 1.0)),
  );
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(f.spin);
  canvas.scale(f.scale * f.squashX, f.scale * f.squashY);
  canvas.translate(-c.dx, -c.dy);

  final base = f.color;
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        colors: [
          Color.lerp(base, Colors.white, 0.5)!,
          base,
          Color.lerp(base, Colors.black, 0.35)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r)),
  );
  canvas.drawCircle(
    c,
    r * 0.5,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.35),
        colors: [
          Color.lerp(base, Colors.white, 0.32)!,
          Color.lerp(base, Colors.black, 0.15)!,
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r * 0.5)),
  );

  canvas.restore();
  canvas.restore();
}

void _paintPuck(Canvas canvas, Offset c, double r, RenderPuck p) {
  if (r <= 0.4) return;
  // Contact shadow.
  canvas.drawCircle(
    c.translate(0, r * 0.24),
    r * 1.02,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.4),
  );
  // Flickable halo behind the acting player's pucks.
  if (p.flickable) {
    canvas.drawCircle(
      c,
      r * 1.32,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.14
        ..color = Colors.white.withValues(alpha: 0.5),
    );
  }
  // Weight body.
  final base = p.color;
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        colors: [
          Color.lerp(base, Colors.white, 0.5)!,
          base,
          Color.lerp(base, Colors.black, 0.35)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r)),
  );
  // Cap ring (the puck's chrome collar).
  canvas.drawCircle(
    c,
    r * 0.66,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.1
      ..color = Colors.white.withValues(alpha: 0.4),
  );
  canvas.drawCircle(
    c,
    r * 0.5,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.35),
        colors: [
          Color.lerp(base, Colors.white, 0.32)!,
          Color.lerp(base, Colors.black, 0.15)!,
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r * 0.5)),
  );
  // Silhouette outline.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06
      ..color = Colors.black.withValues(alpha: 0.3),
  );
  // Aimed puck gets a stronger halo.
  if (p.isShooter) {
    canvas.drawCircle(
      c,
      r * 1.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..color = Colors.white.withValues(alpha: 0.75),
    );
  }
}

void _paintAim(
  Canvas canvas,
  Offset origin,
  AimView aim,
  double platWidth,
  Size size,
) {
  final maxLen = size.height * 0.34;
  final len = maxLen * (0.25 + 0.75 * aim.power);
  final tip = origin + aim.dir * len;

  // Power-tinted shaft: green -> amber -> red as power climbs.
  final col = aim.power < 0.5
      ? Color.lerp(const Color(0xFF3FBF63), const Color(0xFFF5A623),
          aim.power / 0.5)!
      : Color.lerp(const Color(0xFFF5A623), const Color(0xFFE5322B),
          (aim.power - 0.5) / 0.5)!;
  canvas.drawLine(
    origin,
    tip,
    Paint()
      ..color = col.withValues(alpha: 0.9)
      ..strokeWidth = math.max(2, platWidth * 0.03)
      ..strokeCap = StrokeCap.round,
  );
  // Arrowhead.
  final perp = Offset(-aim.dir.dy, aim.dir.dx);
  final head = platWidth * 0.07;
  final p1 = tip - aim.dir * head + perp * head * 0.7;
  final p2 = tip - aim.dir * head - perp * head * 0.7;
  canvas.drawPath(
    Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close(),
    Paint()..color = col,
  );
}

// ---------------------------------------------------------------------------
// Chrome
// ---------------------------------------------------------------------------

class _Pill extends StatelessWidget {
  final String text;

  const _Pill({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 15,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  final String label;
  final int remaining;
  final int pucksPerPlayer;
  final Color accent;
  final bool active;
  final bool winner;

  const _PlayerChip({
    required this.label,
    required this.remaining,
    required this.pucksPerPlayer,
    required this.accent,
    required this.active,
    required this.winner,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: active || winner ? 0.36 : 0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: winner
              ? const Color(0xFFF4B740)
              : Colors.white.withValues(alpha: active ? 0.45 : 0.12),
          width: winner ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black26),
              gradient: RadialGradient(
                center: const Alignment(-0.35, -0.4),
                colors: [Color.lerp(accent, Colors.white, 0.45)!, accent],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: active || winner ? 1 : 0.7),
              fontWeight: active || winner ? FontWeight.w800 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$remaining',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 6),
          _Quiver(remaining: remaining, total: pucksPerPlayer, accent: accent),
        ],
      ),
    );
  }
}

/// Little row of dots showing pucks a player still has on the platform.
class _Quiver extends StatelessWidget {
  final int remaining;
  final int total;
  final Color accent;

  const _Quiver({
    required this.remaining,
    required this.total,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < remaining
                    ? accent.withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Confetti (compact port of the shared GP burst)
// ---------------------------------------------------------------------------

class _Confetto {
  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double spin;
  final double phase;
  final bool round;

  const _Confetto({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.spin,
    required this.phase,
    required this.round,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Confetto> confetti;
  final double t;
  final double boardSize;

  _ConfettiPainter({
    required this.confetti,
    required this.t,
    required this.boardSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final o = Offset(size.width / 2, size.height / 2);
    const gravity = 2.4;
    final fade = t < 0.8 ? 1.0 : (1 - (t - 0.8) / 0.2);
    for (final c in confetti) {
      final dx = math.cos(c.angle) * c.speed * t;
      final dy = math.sin(c.angle) * c.speed * t + 0.5 * gravity * t * t;
      final pos = o + Offset(dx * boardSize, dy * boardSize);
      final paint = Paint()
        ..color = c.color.withValues(alpha: fade.clamp(0.0, 1.0));
      final dim = c.size * boardSize;
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(c.phase + c.spin * t);
      if (c.round) {
        canvas.drawCircle(Offset.zero, dim * 0.5, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: dim, height: dim * 0.55),
            Radius.circular(dim * 0.12),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
