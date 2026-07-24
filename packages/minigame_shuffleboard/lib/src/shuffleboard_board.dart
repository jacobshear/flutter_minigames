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

import 'shuffleboard_game.dart';
import 'shuffleboard_style.dart';

/// Animated shuffleboard board wired to a [MatchController].
///
/// The board owns a [ShuffleboardScene] (a Flame `GameWidget`) that runs the
/// slide simulation locally via the [minigames_flame] harness. Drag back from
/// the near line and release to aim + power a slide; the scene simulates it to
/// rest, packages the settled positions into a [ShuffleboardMove], and hands it
/// back so this widget can submit it through the controller. Hot-seat pass-and-
/// play with perfect information — no handoff cover.
class ShuffleboardBoard extends StatefulWidget {
  final MatchController<ShuffleboardState, ShuffleboardMove> controller;
  final ShuffleboardStyle style;

  const ShuffleboardBoard({
    super.key,
    required this.controller,
    this.style = const ShuffleboardStyle(),
  });

  @override
  State<ShuffleboardBoard> createState() => _ShuffleboardBoardState();
}

class _ShuffleboardBoardState extends State<ShuffleboardBoard>
    with TickerProviderStateMixin {
  static const _game = ShuffleboardGame();

  ShuffleboardScene? _scene;
  StreamSubscription<ShuffleboardState>? _sub;
  ShuffleboardState? _state;
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
  void didUpdateWidget(covariant ShuffleboardBoard oldWidget) {
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
    final scene = ShuffleboardScene(style: widget.style, scheme: _fallbackScheme)
      ..onLaunch = _onLaunch
      ..onCollision = _onCollision
      ..onSettled = _onSlideSettled
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
        _showPill('${_labelFor(s.currentPlayerId)}’s slide');
      }
    }
    _sub = widget.controller.stateStream.listen(_onState);
  }

  /// Sets the centre pill. Transient pills (a shot result, whose-turn-it-is)
  /// auto-clear after a few seconds; the win/draw pill is [sticky] and stays.
  /// Assigns synchronously — callers own the surrounding setState.
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

  String _actingFor(ShuffleboardState s) =>
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

  void _onSlideSettled(ShuffleboardMove move, PuckStatus status, int value) {
    if (!mounted) return;
    final style = widget.style;
    if (status == PuckStatus.inZone && value > 0) {
      style.sounds.onScore?.call();
      if (style.haptics) HapticFeedback.lightImpact();
    } else if (status == PuckStatus.foul || status == PuckStatus.offEnd) {
      style.sounds.onFoul?.call();
      if (style.haptics) HapticFeedback.selectionClick();
    }
    final shotPill = switch (status) {
      PuckStatus.inZone => '+$value',
      PuckStatus.offEnd => 'Off the end!',
      PuckStatus.foul => 'Foul',
      PuckStatus.onBoard => 'On the board',
    };
    // Submit the settled outcome as the move.
    widget.controller.submitMove(move);
    if (mounted) setState(() => _showPill(shotPill));
  }

  void _onState(ShuffleboardState next) {
    if (!mounted) return;
    final prev = _state;
    final outcome = _game.outcome(next);

    // Fresh board => New game reset.
    final isFresh = next.pucks.isEmpty && next.frame == 0;
    if (prev != null && !isFresh || prev == null) {
      // ordinary update
    }

    _scene?.applyState(next, _actingFor(next));

    if (outcome != null && !_celebrated) {
      _celebrate(outcome, next);
    } else if (outcome == null) {
      // Announce whose slide is up next (only if we didn't just set a shot pill
      // via _onSlideSettled in the same frame — that pill wins for a beat).
      if (isFresh) _showPill('${_labelFor(next.currentPlayerId)}’s slide');
    }

    setState(() {
      _state = next;
      _outcome = outcome;
    });
  }

  void _celebrate(GameOutcome outcome, ShuffleboardState state) {
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
    // Launch drags must begin on the puck itself; anywhere else is ignored.
    if (!scene.hitsShooter(d.localPosition)) return;
    scene.beginAim(d.localPosition);
  }

  void _panUpdate(DragUpdateDetails d) => _scene?.updateAim(d.localPosition);

  void _panEnd(DragEndDetails d) => _scene?.endAim();

  void _onSlider(double v) {
    _scene?.setStartNx(v);
    setState(() {}); // reflect the thumb + repositioned puck
  }

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
    const felt = Color(0xFF3A2417);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: RadialGradient(
          center: const Alignment(0, -0.4),
          radius: 1.5,
          colors: [
            Color.lerp(felt, Colors.white, 0.06)!,
            felt,
            Color.lerp(felt, Colors.black, 0.3)!,
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
              score: state.scoreOf(p2),
              remaining: state.remainingOf(p2),
              accent: style.resolvePlayer2(scheme),
              active: _outcome == null && state.currentPlayerId == p2,
              winner: _outcome?.winnerId == p2,
            ),
          ),
          const SizedBox(height: 8),
          // Flex to the height we're given so the whole game fits on screen —
          // the lane sizes down to fit rather than forcing a scroll.
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: AspectRatio(
                  // Matches the sim table W:L (6:13) — tall lane.
                  aspectRatio:
                      ShuffleboardScene.tableW / ShuffleboardScene.tableL,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
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
            ),
          const SizedBox(height: 6),
          // Below-board aim slider: nudge the shooter left/right before the
          // slide. Centres for every new shot; disabled once the puck is moving.
          SizedBox(
            width: 300,
            child: Row(
              children: [
                const Icon(Icons.chevron_left, color: Colors.white38, size: 18),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: Colors.white.withValues(alpha: 0.45),
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
                      thumbColor: Colors.white,
                      overlayColor: Colors.white.withValues(alpha: 0.12),
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 16),
                    ),
                    child: Slider(
                      value: scene.startNx.clamp(
                        ShuffleboardScene.startEdgeInset,
                        1 - ShuffleboardScene.startEdgeInset,
                      ),
                      min: ShuffleboardScene.startEdgeInset,
                      max: 1 - ShuffleboardScene.startEdgeInset,
                      onChanged: (scene.canAim && _outcome == null)
                          ? _onSlider
                          : null,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: Colors.white38, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _outcome != null
                ? 'Tap New game to play again'
                : (scene.canAim
                    ? 'Slide to aim left/right, then drag back from the puck to shoot'
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
              score: state.scoreOf(p1),
              remaining: state.remainingOf(p1),
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
// The Flame scene: drives a TableSimulation and renders the wood lane.
// ---------------------------------------------------------------------------

/// A Flame [FlameGame] that runs one shuffleboard lane's physics via a
/// [TableSimulation] and renders the table each frame. Rendering is manual
/// (canvas drawing in [render]) — the harness supplies the physics, the scene
/// supplies the look, keeping the harness game-agnostic.
class ShuffleboardScene extends FlameGame {
  ShuffleboardScene({required this.style, required this.scheme}) {
    _sim = _buildSim(null, '');
  }

  final ShuffleboardStyle style;
  ColorScheme scheme;

  // Table geometry (sim world units, y-down: y=0 far edge, y=tableL near line).
  static const double tableW = 6;
  static const double tableL = 13;
  static const double puckR = 0.44;
  static const double _startNy = 0.93;

  /// Lateral start inset that keeps the shooter fully inside the rails at its
  /// extreme left/right start. Also the slider's min / (1 - max) bound.
  static const double startEdgeInset = puckR / tableW;

  // Tuned so a full-power flick clears the whole lane (overshoot is possible)
  // and the far 3-point band is reachable at roughly half-to-two-thirds power.
  static const _aim = AimToImpulse(
    maxDrag: 200,
    maxImpulse: 20,
    minImpulse: 3.5,
    deadZone: 10,
  );

  // Lower linear damping than the harness default (1.7) so the disc carries far
  // enough down a 13-unit lane to reach the far scoring bands.
  static const _simConfig = TableSimConfig(linearDamping: 1.15);

  late TableSimulation _sim;
  ShuffleboardState? _state;
  String _acting = '';
  DiscBody? _shooter;
  bool _launched = false;
  double _accum = 0;

  // Off-the-far-end fall animation: purely visual, decoupled from the (trusted)
  // physics. When a disc is removed at the edge we spawn a [_Falling] that
  // tumbles over the lip; scoring already treated it as off-end.
  static const double _fallDuration = 0.5;
  final List<_Falling> _falling = [];
  final Set<String> _fellIds = {};

  /// Where the current shooter starts across the lane (0 = left rail,
  /// 1 = right rail). Reset to centre for every new slide; the below-board
  /// slider drives it.
  double _startNx = 0.5;
  double get startNx => _startNx;

  Offset? _aimStart;
  Offset? _aimNow;

  void Function()? onLaunch;
  void Function()? onCollision;
  void Function()? onAimChanged;
  void Function(ShuffleboardMove move, PuckStatus status, int value)? onSettled;

  bool get canAim =>
      _shooter != null &&
      !_launched &&
      !_sim.isRunning &&
      (_state != null && _game.outcome(_state!) == null);

  bool get isAiming => _aimStart != null && _aimNow != null;

  static const _game = ShuffleboardGame();

  @override
  Color backgroundColor() => const Color(0xFF3A2417);

  TableSimulation _buildSim(ShuffleboardState? state, String acting) {
    final sim = TableSimulation(
      config: _simConfig,
      // Off any open edge => removed: the far end (y < 0) OR either side
      // (|x| past the rail). A puck knocked sideways can slide off too.
      shouldRemove: (d) =>
          d.position.y < 0 ||
          d.position.x < -tableW / 2 ||
          d.position.x > tableW / 2,
    )
      ..onDiscCollision = ((_, __) => onCollision?.call())
      ..onSettled = _handleSettled;
    // Only the near end (bottom, the shooter's baseline) is walled; the far end
    // and both sides are open so discs can slide off them.
    sim.addBounds(
      const Rect.fromLTRB(-tableW / 2, 0, tableW / 2, tableL),
      top: false,
      left: false,
      right: false,
    );
    if (state != null) {
      for (final p in state.pucks) {
        if (p.status == PuckStatus.offEnd) continue;
        sim.addDisc(
          id: p.id,
          owner: p.owner,
          position: _simPos(p.nx, p.ny),
          radius: puckR,
        );
      }
      if (state.remainingOf(acting) > 0 && _game.outcome(state) == null) {
        final idx = state.pucksPerPlayer - state.remainingOf(acting);
        _shooter = sim.addDisc(
          id: '$acting-$idx',
          owner: acting,
          position: _simPos(_startNx, _startNy),
          radius: puckR,
        );
      } else {
        _shooter = null;
      }
    } else {
      _shooter = null;
    }
    return sim;
  }

  /// Rebuild the sim to match [state] (keeps the sim authoritative-in-sync with
  /// the pure game state before each slide).
  void applyState(ShuffleboardState state, String acting) {
    _state = state;
    _acting = acting;
    _launched = false;
    _aimStart = null;
    _aimNow = null;
    _accum = 0;
    _startNx = 0.5; // every new slide starts centred
    _sim = _buildSim(state, acting);
    // A fresh match (New game) starts with a clean slate; mid-match rebuilds
    // keep any in-flight fall animating across the settle→rebuild.
    if (state.pucks.isEmpty && state.frame == 0) {
      _falling.clear();
      _fellIds.clear();
    }
  }

  Vector2 _simPos(double nx, double ny) =>
      Vector2((nx - 0.5) * tableW, ny * tableL);

  ({double nx, double ny}) _toNorm(Vector2 p) =>
      (nx: p.x / tableW + 0.5, ny: p.y / tableL);

  /// Slide the pre-launch shooter left/right along the base line. Ignored once
  /// the slide is under way (guarded by [canAim]).
  void setStartNx(double nx) {
    if (!canAim) return;
    final clamped = nx.clamp(startEdgeInset, 1 - startEdgeInset);
    _startNx = clamped;
    final s = _shooter;
    if (s != null && !s.removed) {
      s.body.setTransform(_simPos(clamped, _startNy), s.body.angle);
      s.body.linearVelocity.setZero();
    }
  }

  /// Whether [local] (board-pixel coords) lands on the shooter puck — the launch
  /// drag must start from the puck itself.
  bool hitsShooter(Offset local) {
    final s = _shooter;
    if (s == null || s.removed || size.x < 2 || size.y < 2) return false;
    final n = _toNorm(s.position);
    final center = Offset(n.nx * size.x, n.ny * size.y);
    final puckPx = (puckR / tableW) * size.x;
    final hitR = math.max(puckPx * 2.0, 44.0);
    return (local - center).distance <= hitR;
  }

  // -- aiming --

  void beginAim(Offset local) {
    if (!canAim) return;
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
    _aimStart = null;
    _aimNow = null;
    onAimChanged?.call();
    final shooter = _shooter;
    if (shooter == null || _launched || start == null || now == null) return;
    final drag = Vector2(now.dx - start.dx, now.dy - start.dy);
    final impulse = _aim.impulse(drag);
    if (impulse.length2 == 0) return; // dead zone: no shot
    _launched = true;
    onLaunch?.call();
    _sim.launch(shooter, impulse);
  }

  // -- loop --

  @override
  void update(double dt) {
    super.update(dt);
    // Advance any off-the-end fall animations regardless of sim state (they
    // outlive the settle that ends the shot).
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

  /// Any disc removed this frame (slid off the far end) gets one fall animation,
  /// carrying its exit momentum over the lip.
  void _spawnFallsForNewlyRemoved() {
    for (final d in _sim.discs) {
      if (!d.removed || _fellIds.contains(d.id)) continue;
      _fellIds.add(d.id);
      final n = _toNorm(d.position);
      final v = d.lastVelocity;
      final ids = _state?.playerIds ?? const ['p1', 'p2'];
      final color = style.colorFor(scheme, d.owner as String, ids);

      // Which edge did it cross? Compare how far past each open lip it went.
      final overTop = -n.ny; // >0 if past the far lip
      final overLeft = -n.nx;
      final overRight = n.nx - 1;
      late final _FallEdge edge;
      late final double along;
      late final double carry;
      late final double spinDir;
      if (overLeft >= overTop && overLeft >= overRight) {
        edge = _FallEdge.left;
        along = n.ny.clamp(0.0, 1.0);
        carry = v.y / tableL;
        spinDir = v.y >= 0 ? 1.0 : -1.0;
      } else if (overRight >= overTop && overRight >= overLeft) {
        edge = _FallEdge.right;
        along = n.ny.clamp(0.0, 1.0);
        carry = v.y / tableL;
        spinDir = v.y >= 0 ? -1.0 : 1.0;
      } else {
        edge = _FallEdge.top;
        along = n.nx.clamp(0.0, 1.0);
        carry = v.x / tableW;
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
    final shooterId = _shooter?.id ?? '';
    final positions = <PuckPosition>[];
    for (final d in _sim.discs) {
      final n = _toNorm(d.position);
      positions.add(
        PuckPosition(
          id: d.id,
          owner: d.owner as String,
          nx: d.removed ? n.nx : n.nx.clamp(0.0, 1.0),
          ny: d.removed ? n.ny : n.ny.clamp(0.0, 1.0),
          removed: d.removed,
        ),
      );
    }
    final launched = positions.firstWhere(
      (p) => p.id == shooterId,
      orElse: () => positions.isNotEmpty
          ? positions.last
          : const PuckPosition(id: '', owner: '', nx: 0.5, ny: 1),
    );
    final status =
        ShuffleboardGame.statusFor(launched.ny, removed: launched.removed);
    final value =
        status == PuckStatus.inZone ? ShuffleboardGame.zoneValue(launched.ny) : 0;
    onSettled?.call(
      ShuffleboardMove(
        launchedPuckId: shooterId,
        owner: _acting,
        positions: positions,
      ),
      status,
      value,
    );
  }

  // -- render --

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (size.x < 2 || size.y < 2) return;

    final pucks = <RenderPuck>[];
    final state = _state;
    final playerIds = state?.playerIds ?? const ['p1', 'p2'];
    for (final d in _sim.discs) {
      if (d.removed) continue;
      final n = _toNorm(d.position);
      final owner = d.owner as String;
      final score = ShuffleboardGame.statusFor(n.ny, removed: false) ==
              PuckStatus.inZone
          ? ShuffleboardGame.zoneValue(n.ny)
          : 0;
      pucks.add(
        RenderPuck(
          nx: n.nx,
          ny: n.ny,
          radiusFrac: puckR / tableW,
          color: style.colorFor(scheme, owner, playerIds),
          score: score,
          isShooter: identical(d, _shooter),
        ),
      );
    }

    AimView? aim;
    if (isAiming && _shooter != null) {
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
      // A lip is right at the board edge with no runway to fly into, so the
      // puck tips over IN PLACE: it stays at the edge, foreshortens hard along
      // the axis perpendicular to that edge, sinks into shadow and fades — a
      // little momentum carry + spin sells the drop. `edgeIn → edgeOut` walks
      // the centre from just inside the lip to just past it.
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
        case _FallEdge.left:
          nx = edgeOut;
          ny = f.along + carry;
          sx = foreshorten;
          sy = 1;
        case _FallEdge.right:
          nx = 1 - edgeIn + 0.032 * p; // mirror of edgeOut on the right rail
          ny = f.along + carry;
          sx = foreshorten;
          sy = 1;
      }
      falling.add(
        FallingPuck(
          nx: nx,
          ny: ny,
          radiusFrac: puckR / tableW,
          color: Color.lerp(f.color, Colors.black, 0.55 * p)!,
          scale: 1 - 0.3 * p,
          squashX: sx,
          squashY: sy,
          alpha: p < 0.5 ? 1.0 : (1 - (p - 0.5) / 0.5),
          spin: p * 0.4 * f.spinDir,
        ),
      );
    }

    paintShuffleboardTable(
      canvas,
      Size(size.x, size.y),
      ShuffleboardView(pucks: pucks, aim: aim, falling: falling),
      style,
      scheme,
    );
  }
}

/// Which open edge a disc slid off — drives how its fall tips over the lip.
enum _FallEdge { top, left, right }

/// One in-flight off-the-edge fall. Scene-private; the painter gets a computed
/// [FallingPuck] each frame.
class _Falling {
  final _FallEdge edge;

  /// Position along the exiting edge (nx for [top]; ny for [left]/[right]).
  final double along;

  /// Normalized velocity component parallel to that edge (carries the disc
  /// along the lip as it drops).
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

/// A puck to draw, in normalized lane coords.
class RenderPuck {
  final double nx;
  final double ny;

  /// Radius as a fraction of the lane width.
  final double radiusFrac;
  final Color color;

  /// Scoring band value (0 if not scoring) — drives the highlight ring.
  final int score;
  final bool isShooter;

  const RenderPuck({
    required this.nx,
    required this.ny,
    required this.radiusFrac,
    required this.color,
    this.score = 0,
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

/// A puck mid-fall off the far end — drawn over the lip (outside the lane clip)
/// with a shrink, foreshorten, tumble and fade.
class FallingPuck {
  final double nx;

  /// Normalized lane-length position; negative values sit above the far edge.
  final double ny;
  final double radiusFrac;
  final Color color;
  final double scale;

  /// Foreshorten squash as it tips over a lip (1 = round, →0 flattened). Only
  /// the axis perpendicular to the exiting edge shrinks: [squashX] for a side
  /// fall, [squashY] for a far-end fall.
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
    required this.squashY,
    required this.alpha,
    required this.spin,
  });
}

/// Everything one frame of the lane needs.
class ShuffleboardView {
  final List<RenderPuck> pucks;
  final AimView? aim;
  final List<FallingPuck> falling;

  const ShuffleboardView({
    required this.pucks,
    this.aim,
    this.falling = const [],
  });
}

/// Draws the full wood lane, scoring bands, foul line, pucks and aim indicator
/// into [size]. Pure — no Flame or widget state — so a `CustomPainter` can call
/// it for a static snapshot (screenshots/tests) exactly as the live scene does.
void paintShuffleboardTable(
  Canvas canvas,
  Size size,
  ShuffleboardView view,
  ShuffleboardStyle style,
  ColorScheme scheme,
) {
  final frame = style.resolveFrame(scheme);
  final lane = style.resolveLane(scheme);
  final zone = style.resolveZone(scheme);
  final foul = style.resolveFoulLine(scheme);

  final full = Offset.zero & size;

  // Walnut frame (full bleed).
  canvas.drawRect(
    full,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(frame, Colors.white, 0.12)!,
          frame,
          Color.lerp(frame, Colors.black, 0.3)!,
        ],
      ).createShader(full),
  );

  // Lane inset in the frame.
  final margin = size.width * 0.07;
  final laneRect = Rect.fromLTRB(
    margin,
    margin * 0.7,
    size.width - margin,
    size.height - margin * 0.7,
  );
  final laneRR =
      RRect.fromRectAndRadius(laneRect, Radius.circular(size.width * 0.04));

  // Recess shadow under the lane.
  canvas.drawRRect(
    laneRR.shift(const Offset(0, 2)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
  );
  canvas.drawRRect(
    laneRR,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(lane, Colors.white, 0.14)!,
          lane,
          Color.lerp(lane, const Color(0xFF9A6E3E), 0.5)!,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(laneRect),
  );

  canvas.save();
  canvas.clipRRect(laneRR);

  double xOf(double nx) => laneRect.left + nx * laneRect.width;
  double yOf(double ny) => laneRect.top + ny * laneRect.height;

  // Wood grain streaks (vertical, faint).
  final grain = Paint()
    ..color = Colors.black.withValues(alpha: 0.05)
    ..strokeWidth = math.max(0.6, size.width * 0.006);
  for (var i = 1; i < 10; i++) {
    final x = laneRect.left + laneRect.width * (i / 10);
    canvas.drawLine(
        Offset(x, laneRect.top), Offset(x, laneRect.bottom), grain);
  }

  // Scoring bands at the far end (top): 3 nearest the edge, then 2, then 1.
  final bandLines = [
    (ShuffleboardGame.zone3Line, 3, 0.30),
    (ShuffleboardGame.zone2Line, 2, 0.22),
    (ShuffleboardGame.zone1Line, 1, 0.15),
  ];
  var prevY = laneRect.top;
  for (final (line, label, alpha) in bandLines) {
    final bottom = yOf(line);
    final r = Rect.fromLTRB(laneRect.left, prevY, laneRect.right, bottom);
    canvas.drawRect(r, Paint()..color = zone.withValues(alpha: alpha));
    // Band divider.
    canvas.drawLine(
      Offset(laneRect.left, bottom),
      Offset(laneRect.right, bottom),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = math.max(1, size.width * 0.008),
    );
    _bandLabel(canvas, Offset(laneRect.left + laneRect.width * 0.5,
        (prevY + bottom) / 2), '$label', size.width * 0.11);
    prevY = bottom;
  }

  // Foul line — pucks must fully cross it (toward the far edge) to count.
  final foulY = yOf(ShuffleboardGame.foulLine);
  canvas.drawLine(
    Offset(laneRect.left, foulY),
    Offset(laneRect.right, foulY),
    Paint()
      ..color = foul
      ..strokeWidth = math.max(1.5, size.width * 0.012),
  );
  // Base line (near shooter line).
  final baseY = yOf(0.985);
  canvas.drawLine(
    Offset(laneRect.left, baseY),
    Offset(laneRect.right, baseY),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..strokeWidth = math.max(1, size.width * 0.01),
  );

  // Pucks.
  for (final p in view.pucks) {
    _paintPuck(canvas, Offset(xOf(p.nx), yOf(p.ny)),
        p.radiusFrac * laneRect.width, p);
  }

  // Aim indicator.
  final aim = view.aim;
  if (aim != null) {
    _paintAim(canvas, Offset(xOf(aim.nx), yOf(aim.ny)), aim,
        laneRect.width, size);
  }

  canvas.restore();

  // Inner lip.
  canvas.drawRRect(
    laneRR.deflate(0.8),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.14),
  );

  // Falling pucks — drawn last and OUTSIDE the lane clip so they tumble over the
  // far lip and off the top edge instead of being clipped at the boundary.
  for (final f in view.falling) {
    _paintFallingPuck(
      canvas,
      Offset(xOf(f.nx), yOf(f.ny)),
      f.radiusFrac * laneRect.width,
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
  // Tumble + shrink + foreshorten about the puck centre.
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

void _bandLabel(Canvas canvas, Offset center, String text, double fontSize) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.85),
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
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
  // Score highlight ring behind scoring pucks.
  if (p.score > 0) {
    canvas.drawCircle(
      c,
      r * 1.28,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16
        ..color = const Color(0xFFF4B740).withValues(alpha: 0.85),
    );
  }
  // Metal weight body.
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
  // Shooter gets a soft aim halo.
  if (p.isShooter) {
    canvas.drawCircle(
      c,
      r * 1.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.1
        ..color = Colors.white.withValues(alpha: 0.5),
    );
  }
}

void _paintAim(
  Canvas canvas,
  Offset origin,
  AimView aim,
  double laneWidth,
  Size size,
) {
  final maxLen = size.height * 0.34;
  final len = maxLen * (0.25 + 0.75 * aim.power);
  final tip = origin + aim.dir * len;

  // Power-tinted shaft: green -> amber -> red as power climbs (two-stop so the
  // mid range reads amber, not a muddy blend).
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
      ..strokeWidth = math.max(2, laneWidth * 0.03)
      ..strokeCap = StrokeCap.round,
  );
  // Arrowhead.
  final perp = Offset(-aim.dir.dy, aim.dir.dx);
  final head = laneWidth * 0.07;
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
  // A small dark anchor puck at the origin so the drag reads as a slingshot.
  canvas.drawCircle(
    origin,
    laneWidth * 0.03,
    Paint()..color = Colors.black.withValues(alpha: 0.35),
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
  final int score;
  final int remaining;
  final Color accent;
  final bool active;
  final bool winner;

  const _PlayerChip({
    required this.label,
    required this.score,
    required this.remaining,
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
            '$score',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 6),
          _Quiver(remaining: remaining, accent: accent),
        ],
      ),
    );
  }
}

/// Little row of dots showing pucks a player has left to slide.
class _Quiver extends StatelessWidget {
  final int remaining;
  final Color accent;

  const _Quiver({required this.remaining, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < remaining; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.9),
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
