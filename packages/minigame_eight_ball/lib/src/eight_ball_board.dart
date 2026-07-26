import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Picture, PictureRecorder;

// Flame's game.dart re-exports the non-64 vector_math Vector2; forge2d (which
// the harness API speaks) uses vector_math_64. Hide Flame's so the single
// Vector2 in this file is forge2d's — the type TableSimulation expects.
import 'package:flame/game.dart' hide Vector2;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge2d/forge2d.dart' show Vector2;
import 'package:minigames_core/minigames_core.dart';
import 'package:minigames_flame/minigames_flame.dart';

import 'eight_ball_game.dart';
import 'eight_ball_style.dart';

/// Animated 8-ball table wired to a [MatchController].
///
/// The board owns an [EightBallScene] (a Flame `GameWidget`) that runs the
/// break/roll simulation locally via the [minigames_flame] harness. Drag back
/// from the cue ball and release to aim + power the stroke; the scene simulates
/// it to rest, packages the settled positions + first contact into an
/// [EightBallMove], and hands it back so this widget submits it through the
/// controller. After a foul the incoming player drags the cue to a legal spot
/// (a placement move) before shooting. Hot-seat pass-and-play, perfect info.
class EightBallBoard extends StatefulWidget {
  final MatchController<EightBallState, EightBallMove> controller;
  final EightBallStyle style;

  const EightBallBoard({
    super.key,
    required this.controller,
    this.style = const EightBallStyle(),
  });

  @override
  State<EightBallBoard> createState() => _EightBallBoardState();
}

class _EightBallBoardState extends State<EightBallBoard>
    with TickerProviderStateMixin {
  static const _game = EightBallGame();

  EightBallScene? _scene;
  StreamSubscription<EightBallState>? _sub;
  EightBallState? _state;
  GameOutcome? _outcome;

  String _pill = '';
  Timer? _pillTimer;
  bool _celebrated = false;

  // Built in initState — NOT a `late` inline initializer. A late field runs its
  // initializer the first time it's touched, and dispose() touches it; if
  // confetti never fired that would build an AnimationController(vsync: this)
  // during teardown and illegally look up a deactivated element's ancestor.
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
  void didUpdateWidget(covariant EightBallBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    _sub?.cancel();
    _bind();
  }

  static final ColorScheme _fallbackScheme =
      ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A4D));

  void _bind() {
    final scene = EightBallScene(style: widget.style, scheme: _fallbackScheme)
      ..onBreak = _onBreak
      ..onCollision = _onCollision
      ..onPocket = _onPocket
      ..onShotSettled = _onShotSettled
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
        _showPill(s.shotsTaken == 0
            ? '${_labelFor(s.currentPlayerId)} breaks'
            : '${_labelFor(s.currentPlayerId)}’s shot');
      }
    }
    _sub = widget.controller.stateStream.listen(_onState);
  }

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

  String _actingFor(EightBallState s) =>
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

  void _onBreak() {
    if (!mounted) return;
    widget.style.sounds.onBreak?.call();
    if (widget.style.haptics) HapticFeedback.mediumImpact();
    setState(() => _showPill(''));
  }

  Duration _lastClack = Duration.zero;
  final Stopwatch _clock = Stopwatch()..start();

  void _onCollision() {
    if (!mounted) return;
    final now = _clock.elapsed;
    if (now - _lastClack < const Duration(milliseconds: 55)) return;
    _lastClack = now;
    widget.style.sounds.onCollision?.call();
    if (widget.style.haptics) HapticFeedback.selectionClick();
  }

  void _onPocket() {
    if (!mounted) return;
    widget.style.sounds.onPocket?.call();
    if (widget.style.haptics) HapticFeedback.lightImpact();
  }

  void _onShotSettled(EightBallMove move) {
    if (!mounted) return;
    final prev = _state;
    final style = widget.style;
    // Diff the outcome for a transient pill + foul SFX.
    final wasPotted = {
      for (final b in prev?.balls ?? const <Ball>[])
        if (b.pocketed) b.number,
    };
    final newlyObject = <int>[];
    var cueScratched = false;
    for (final p in move.positions!) {
      if (!p.pocketed || wasPotted.contains(p.number)) continue;
      if (p.number == EightBallGame.cueNumber) {
        cueScratched = true;
      } else {
        newlyObject.add(p.number);
      }
    }
    final contactFoul = move.firstHitNumber == null;
    final foul = cueScratched || contactFoul;
    if (foul) {
      style.sounds.onFoul?.call();
      if (style.haptics) HapticFeedback.heavyImpact();
    }

    final pill = cueScratched
        ? 'Scratch — ball in hand'
        : (newlyObject.contains(EightBallGame.eightNumber)
            ? '8-ball!'
            : (newlyObject.isNotEmpty
                ? 'Potted ${newlyObject.length == 1 ? "a ball" : "${newlyObject.length} balls"}'
                : (contactFoul ? 'No contact — foul' : 'Miss')));

    widget.controller.submitMove(move);
    if (mounted) setState(() => _showPill(pill));
  }

  void _onState(EightBallState next) {
    if (!mounted) return;
    final prev = _state;
    final outcome = _game.outcome(next);

    _scene?.applyState(next, _actingFor(next));

    if (outcome != null && !_celebrated) {
      _celebrate(outcome, next);
    } else if (outcome == null) {
      // Group just assigned? Announce it.
      final acting = _actingFor(next);
      final justAssigned = (prev?.isOpenTable ?? true) && !next.isOpenTable;
      final isFresh =
          next.shotsTaken == 0 && next.groups.isEmpty && !next.ballInHand;
      if (justAssigned && next.groups[acting] != null) {
        _showPill(
          next.groups[acting] == BallGroup.solids
              ? '${_labelFor(acting)}: solids'
              : '${_labelFor(acting)}: stripes',
        );
      } else if (next.ballInHand) {
        _showPill('${_labelFor(next.currentPlayerId)}: ball in hand');
      } else if (isFresh) {
        _showPill('${_labelFor(next.currentPlayerId)} breaks');
      }
    }

    setState(() {
      _state = next;
      _outcome = outcome;
    });
  }

  void _celebrate(GameOutcome outcome, EightBallState state) {
    _celebrated = true;
    final style = widget.style;
    final localWon = outcome.winnerId == _actingFor(state) ||
        outcome.winnerId == state.currentPlayerId;
    if (localWon) {
      style.sounds.onWin?.call();
    } else {
      style.sounds.onLoss?.call();
    }
    if (style.haptics) HapticFeedback.heavyImpact();
    _showPill('${_labelFor(outcome.winnerId!)} wins'.toUpperCase(),
        sticky: true);
    if (style.confetti) {
      _confetti = _spawnConfetti();
      _confettiCtrl.forward(from: 0);
    }
  }

  List<_Confetto> _spawnConfetti() {
    final palette = [
      const Color(0xFFF2C31E),
      const Color(0xFFD8352A),
      const Color(0xFF1E52B0),
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
  // Gestures — meaning depends on ball-in-hand vs aim.
  // ---------------------------------------------------------------------------

  bool get _placing => (_state?.ballInHand ?? false) && _outcome == null;

  void _panStart(DragStartDetails d) {
    final scene = _scene;
    if (scene == null || _outcome != null) return;
    if (_placing) {
      scene.updatePlacement(d.localPosition);
      setState(() {});
      return;
    }
    if (!scene.canAim) return;
    if (!scene.hitsCue(d.localPosition)) return;
    scene.beginAim(d.localPosition);
  }

  void _panUpdate(DragUpdateDetails d) {
    final scene = _scene;
    if (scene == null) return;
    if (_placing) {
      scene.updatePlacement(d.localPosition);
      setState(() {});
      return;
    }
    scene.updateAim(d.localPosition);
  }

  void _panEnd(DragEndDetails d) {
    final scene = _scene;
    if (scene == null) return;
    if (_placing) {
      final spot = scene.commitPlacement();
      if (spot != null) {
        widget.controller.submitMove(
          EightBallMove.place(
            owner: _actingFor(_state!),
            cueNx: spot.dx,
            cueNy: spot.dy,
          ),
        );
      }
      return;
    }
    scene.endAim();
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

    final p1 = state.playerIds.first;
    final p2 = state.playerIds.last;

    final hint = _outcome != null
        ? 'Tap New game to play again'
        : (_placing
            ? 'Drag to place the cue ball, then release'
            : (scene.canAim
                ? 'Drag back from the cue ball to aim and shoot'
                : 'Rolling…'));

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            offset: const Offset(0, 6),
            blurRadius: 18,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: CustomPaint(
          painter: const _PoolRoomPainter(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _PlayerChip(
                    label: _labelFor(p2),
                    group: state.groups[p2],
                    remaining: state.remainingCountOf(p2),
                    accent: const Color(0xFF2E6FB0),
                    active: _outcome == null && state.currentPlayerId == p2,
                    winner: _outcome?.winnerId == p2,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: AspectRatio(
                        aspectRatio:
                            EightBallScene.tableW / EightBallScene.tableL,
                        child: DecoratedBox(
                          // The table has to sit *in* the room, not float on it.
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.62),
                                offset: const Offset(0, 14),
                                blurRadius: 30,
                                spreadRadius: -4,
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                offset: const Offset(0, 3),
                                blurRadius: 8,
                              ),
                            ],
                          ),
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
                                        duration:
                                            const Duration(milliseconds: 220),
                                        child: _pill.isEmpty
                                            ? const SizedBox.shrink()
                                            : _Pill(
                                                key: ValueKey(_pill),
                                                text: _pill),
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
                ),
                const SizedBox(height: 6),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: _PlayerChip(
                    label: _labelFor(p1),
                    group: state.groups[p1],
                    remaining: state.remainingCountOf(p1),
                    accent: const Color(0xFFD8443C),
                    active: _outcome == null && state.currentPlayerId == p1,
                    winner: _outcome?.winnerId == p1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the room behind the table (see [paintPoolRoom]).
class _PoolRoomPainter extends CustomPainter {
  const _PoolRoomPainter();

  @override
  void paint(Canvas canvas, Size size) => paintPoolRoom(canvas, size);

  @override
  bool shouldRepaint(_PoolRoomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// The Flame scene: drives a TableSimulation and renders the felt table.
// ---------------------------------------------------------------------------

/// A Flame [FlameGame] that runs one 8-ball rack's physics via a
/// [TableSimulation] and renders the table each frame. Rendering is manual
/// (canvas drawing in [render]) — the harness supplies the physics, the scene
/// supplies the look.
class EightBallScene extends FlameGame {
  EightBallScene({required this.style, required this.scheme});

  final EightBallStyle style;
  ColorScheme scheme;

  // Table geometry (sim world units, y-down: y=0 foot rail, y=tableL head rail).
  // Canonical values live on EightBallGame so the pure rack maths and the
  // physics can never disagree about how big a ball is.
  static const double tableW = EightBallGame.tableW;
  static const double tableL = EightBallGame.tableL;
  static const double ballR = EightBallGame.ballR;
  static const double pocketCaptureR = 0.95;

  /// Pockets in sim world coords: 4 corners + 2 sides.
  static const List<(double, double)> _pocketsWorld = [
    (-tableW / 2, 0),
    (tableW / 2, 0),
    (-tableW / 2, tableL),
    (tableW / 2, tableL),
    (-tableW / 2, tableL / 2),
    (tableW / 2, tableL / 2),
  ];

  // A firm break at full power; a gentle tap at the low end. Not finely tuned —
  // approximated for GP feel (see game doc: no spin/english modelled).
  static const _aim = AimToImpulse(
    maxDrag: 210,
    maxImpulse: 16,
    minImpulse: 2.5,
    deadZone: 8,
  );

  // Lively rails, low rolling drag so a break scatters the whole rack.
  static const _simConfig = TableSimConfig(
    linearDamping: 0.62,
    angularDamping: 1.2,
    friction: 0.02,
    restitution: 0.94,
    wallRestitution: 0.9,
    density: 1.0,
    settleLinearSpeed: 0.06,
    settleFrames: 16,
    maxSteps: 2600,
  );

  late TableSimulation _sim;
  EightBallState? _state;
  String _acting = '';
  DiscBody? _cue;
  bool _launched = false;
  double _accum = 0;

  int? _firstHit; // first object-ball number the cue struck this shot
  final Set<int> _pocketedIds = {};

  // Rolling: per-ball orientation, and last position to derive the roll from.
  // Orientation persists across sim rebuilds (a ball keeps the face it came to
  // rest on); the position map is cleared so a rebuild never rolls a teleport.
  final Map<int, _Orient> _orient = {};
  final Map<int, Vector2> _lastBallPos = {};

  // Ball-in-hand placement ghost (normalized).
  Offset? _placeGhost;

  Offset? _aimStart;
  Offset? _aimNow;

  void Function()? onBreak;
  void Function()? onCollision;
  void Function()? onPocket;
  void Function()? onAimChanged;
  void Function(EightBallMove move)? onShotSettled;

  bool get canAim =>
      _cue != null &&
      !_launched &&
      !_sim.isRunning &&
      (_state != null && !_state!.ballInHand && !_state!.over);

  bool get isAiming => _aimStart != null && _aimNow != null;

  @override
  Color backgroundColor() => const Color(0xFF1A130C);

  TableSimulation _buildSim(EightBallState? state) {
    final sim = TableSimulation(
      config: _simConfig,
      shouldRemove: (d) {
        for (final (px, py) in _pocketsWorld) {
          final dx = d.position.x - px, dy = d.position.y - py;
          if (dx * dx + dy * dy < pocketCaptureR * pocketCaptureR) return true;
        }
        // Safety net: a ball that somehow escapes the rails is treated as
        // pocketed rather than lost to infinity.
        return d.position.x.abs() > tableW ||
            d.position.y < -1 ||
            d.position.y > tableL + 1;
      },
    )
      ..onDiscCollision = _handleCollision
      ..onSettled = _handleSettled;
    // Full rails; pockets are handled by capture, not gaps.
    sim.addBounds(const Rect.fromLTRB(-tableW / 2, 0, tableW / 2, tableL));
    _cue = null;
    if (state != null) {
      for (final b in state.balls) {
        if (b.pocketed) continue;
        final disc = sim.addDisc(
          id: '${b.number}',
          owner: b.number,
          position: _simPos(b.nx, b.ny),
          radius: ballR,
        );
        if (b.isCue) _cue = disc;
      }
    }
    return sim;
  }

  void applyState(EightBallState state, String acting) {
    _state = state;
    _acting = acting;
    _launched = false;
    _aimStart = null;
    _aimNow = null;
    _accum = 0;
    _firstHit = null;
    _pocketedIds.clear();
    // Balls are re-seated from state here; drop the roll baseline so the jump
    // isn't integrated as a spin. Orientation itself carries over.
    _lastBallPos.clear();
    _placeGhost = state.ballInHand ? const Offset(0.5, 0.8) : null;
    _sim = _buildSim(state);
  }

  Vector2 _simPos(double nx, double ny) =>
      Vector2((nx - 0.5) * tableW, ny * tableL);

  ({double nx, double ny}) _toNorm(Vector2 p) =>
      (nx: p.x / tableW + 0.5, ny: p.y / tableL);

  // -- placement (ball in hand) --

  void updatePlacement(Offset local) {
    if (size.x < 2 || size.y < 2) return;
    final felt = poolFeltRect(Size(size.x, size.y));
    final nx = ((local.dx - felt.left) / felt.width).clamp(0.03, 0.97);
    final ny = ((local.dy - felt.top) / felt.height).clamp(0.03, 0.97);
    _placeGhost = Offset(nx, ny);
  }

  /// Commit the current ghost as the placement spot, nudged off overlaps.
  Offset? commitPlacement() {
    final g = _placeGhost;
    if (g == null) return null;
    var nx = g.dx, ny = g.dy;
    final minSep = (ballR * 2.05) / tableW; // normalized (nx units)
    // ny is a *longer* axis than nx (the table is twice as long as wide), so a
    // step of 1 ny covers tableL/tableW = 2 nx-widths. Multiply ny deltas by
    // that to compare distances on one scale, and divide when pushing back.
    // (This used to be tableW/tableL, which shrank ny gaps instead of growing
    // them and let the ghost settle overlapping a ball along the long axis.)
    const nyToNx = tableL / tableW;
    // Push away from any resting ball it overlaps (a few relaxation passes).
    for (var pass = 0; pass < 6; pass++) {
      var moved = false;
      for (final b in _state?.balls ?? const <Ball>[]) {
        if (b.pocketed || b.isCue) continue;
        final ddx = nx - b.nx;
        final ddy = (ny - b.ny) * nyToNx; // to a common scale
        final dist = math.sqrt(ddx * ddx + ddy * ddy);
        final minD = minSep;
        if (dist < minD && dist > 1e-4) {
          final push = (minD - dist);
          nx += (ddx / dist) * push;
          ny += (ddy / dist) * push / nyToNx;
          moved = true;
        }
      }
      nx = nx.clamp(0.03, 0.97);
      ny = ny.clamp(0.03, 0.97);
      if (!moved) break;
    }
    return Offset(nx, ny);
  }

  bool hitsCue(Offset local) {
    final c = _cue;
    if (c == null || c.removed || size.x < 2 || size.y < 2) return false;
    final felt = poolFeltRect(Size(size.x, size.y));
    final n = _toNorm(c.position);
    final center = Offset(
      felt.left + n.nx * felt.width,
      felt.top + n.ny * felt.height,
    );
    final ballPx = (ballR / tableW) * felt.width;
    final hitR = math.max(ballPx * 2.2, 44.0);
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
    final cue = _cue;
    if (cue == null || _launched || start == null || now == null) return;
    final drag = Vector2(now.dx - start.dx, now.dy - start.dy);
    final impulse = _aim.impulse(drag);
    if (impulse.length2 == 0) return; // dead zone
    _launched = true;
    _firstHit = null;
    onBreak?.call();
    _sim.launch(cue, impulse);
  }

  void _handleCollision(DiscBody a, DiscBody b) {
    onCollision?.call();
    if (!_launched || _firstHit != null) return;
    final an = a.owner as int, bn = b.owner as int;
    if (an == EightBallGame.cueNumber) {
      _firstHit = bn;
    } else if (bn == EightBallGame.cueNumber) {
      _firstHit = an;
    }
  }

  // -- loop --

  @override
  void update(double dt) {
    super.update(dt);
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
    _integrateRoll();
    // Pocket SFX for anything captured this frame.
    for (final d in _sim.discs) {
      if (!d.removed) continue;
      final n = d.owner as int;
      if (_pocketedIds.add(n)) onPocket?.call();
    }
  }

  /// Roll every moving ball by how far it travelled this frame. A ball rolling
  /// along d̂ spins about `up × d̂` by `distance / radius`, so the markings track
  /// the direction of travel and keep working when balls carom off each other.
  void _integrateRoll() {
    for (final d in _sim.discs) {
      if (d.removed) continue;
      final n = d.owner as int;
      final p = d.position;
      final prev = _lastBallPos[n];
      if (prev != null) {
        (_orient[n] ??= _Orient()).roll(p.x - prev.x, p.y - prev.y, ballR);
      }
      _lastBallPos[n] = Vector2(p.x, p.y);
    }
  }

  void _handleSettled(SimOutcome outcome) {
    final state = _state;
    if (state == null) return;
    final byNumber = <int, DiscBody>{
      for (final d in _sim.discs) d.owner as int: d,
    };
    final positions = <BallPosition>[];
    for (final b in state.balls) {
      final d = byNumber[b.number];
      if (d == null) {
        // Already pocketed before this shot — carry it forward.
        positions.add(BallPosition(
          number: b.number,
          nx: b.nx,
          ny: b.ny,
          pocketed: true,
        ));
      } else {
        final n = _toNorm(d.position);
        positions.add(BallPosition(
          number: b.number,
          nx: n.nx.clamp(0.0, 1.0),
          ny: n.ny.clamp(0.0, 1.0),
          pocketed: d.removed,
        ));
      }
    }
    onShotSettled?.call(EightBallMove.shot(
      owner: _acting,
      positions: positions,
      firstHitNumber: _firstHit,
    ));
  }

  // -- render --

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (size.x < 2 || size.y < 2) return;

    final balls = <RenderBall>[];
    for (final d in _sim.discs) {
      if (d.removed) continue;
      final n = _toNorm(d.position);
      final number = d.owner as int;
      balls.add(RenderBall(
        nx: n.nx,
        ny: n.ny,
        number: number,
        radiusFrac: ballR / tableW,
        isCue: number == EightBallGame.cueNumber,
        spin: _orient[number]?.spin ?? BallSpin.identity,
      ));
    }

    PoolAim? aim;
    if (isAiming && _cue != null) {
      final n = _toNorm(_cue!.position);
      final drag = Vector2(
        _aimNow!.dx - _aimStart!.dx,
        _aimNow!.dy - _aimStart!.dy,
      );
      final impulse = _aim.impulse(drag);
      final power = _aim.power01(drag);
      final dir = impulse.length2 == 0
          ? const Offset(0, -1)
          : Offset(impulse.x, impulse.y) / impulse.length;
      aim = PoolAim(nx: n.nx, ny: n.ny, dir: dir, power: power);
    }

    PoolGhost? ghost;
    final st = _state;
    if (st != null && st.ballInHand && !st.over && _placeGhost != null) {
      ghost = PoolGhost(
          nx: _placeGhost!.dx, ny: _placeGhost!.dy, radiusFrac: ballR / tableW);
    }

    paintPoolTable(
      canvas,
      Size(size.x, size.y),
      PoolView(balls: balls, aim: aim, ghost: ghost),
      style,
      scheme,
    );
  }
}

// ---------------------------------------------------------------------------
// Shared table painter — used by the live scene AND by static previews/tests.
// ---------------------------------------------------------------------------

/// A ball to draw, in normalized table coords.
/// A unit 3-vector in view space: +x right, +y down (screen), +z toward the
/// viewer. Used to place a rolling ball's markings.
typedef V3 = ({double x, double y, double z});

/// Mutable roll state for one ball: the images of its local axes, rotated a
/// little every frame by however far the ball moved.
class _Orient {
  // Local X, Y, Z after all rolling so far.
  var _ax = (x: 1.0, y: 0.0, z: 0.0);
  var _ay = (x: 0.0, y: 1.0, z: 0.0);
  var _az = (x: 0.0, y: 0.0, z: 1.0);

  BallSpin get spin => BallSpin(ax: _ax, ay: _ay, az: _az);

  /// Roll after moving ([dx], [dy]) with the given [radius] (same units).
  void roll(double dx, double dy, double radius) {
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1e-6 || radius <= 0) return;
    // A ball rolling along d̂ spins about `up × d̂`, i.e. (-dy, dx, 0)/dist,
    // by distance/radius — so the face toward the viewer travels forward.
    final kx = -dy / dist;
    final ky = dx / dist;
    final angle = dist / radius;
    _ax = _rodrigues(_ax, kx, ky, angle);
    _ay = _rodrigues(_ay, kx, ky, angle);
    _az = _rodrigues(_az, kx, ky, angle);
  }

  /// Rotate [v] about the in-plane unit axis ([kx], [ky], 0) by [angle].
  static V3 _rodrigues(V3 v, double kx, double ky, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    // k × v  (with k.z == 0)
    final cx = ky * v.z;
    final cy = -kx * v.z;
    final cz = kx * v.y - ky * v.x;
    final dot = kx * v.x + ky * v.y; // k · v
    return (
      x: v.x * c + cx * s + kx * dot * (1 - c),
      y: v.y * c + cy * s + ky * dot * (1 - c),
      z: v.z * c + cz * s, // k.z == 0, so the third term drops out
    );
  }
}

/// A ball's 3-D orientation: the images of its local axes after rolling.
///
/// A ball that only translates reads as *sliding*; real balls roll, so the
/// markings have to travel across the visible face. The scene integrates roll
/// from each ball's motion (angle = distance / radius about the axis
/// `up × travel`) and the painter projects the markings through this basis —
/// a marking is visible when its axis has `z > 0`, and foreshortens as it
/// approaches the rim.
class BallSpin {
  /// Images of the ball's local X / Y / Z axes.
  final V3 ax;
  final V3 ay;
  final V3 az;

  const BallSpin({required this.ax, required this.ay, required this.az});

  /// Unrolled (the local axes still aligned with view space).
  static const identity = BallSpin(
    ax: (x: 1, y: 0, z: 0),
    ay: (x: 0, y: 1, z: 0),
    az: (x: 0, y: 0, z: 1),
  );
}

class RenderBall {
  final double nx;
  final double ny;
  final int number;

  /// Radius as a fraction of the felt width.
  final double radiusFrac;
  final bool isCue;

  /// Current roll orientation; markings are drawn through it.
  final BallSpin spin;

  const RenderBall({
    required this.nx,
    required this.ny,
    required this.number,
    required this.radiusFrac,
    this.isCue = false,
    this.spin = BallSpin.identity,
  });
}

/// The aim / power indicator overlay.
class PoolAim {
  final double nx;
  final double ny;

  /// Unit shot direction in screen space (y-down).
  final Offset dir;

  /// 0..1 power for the meter.
  final double power;

  const PoolAim({
    required this.nx,
    required this.ny,
    required this.dir,
    required this.power,
  });
}

/// A translucent cue ghost shown during ball-in-hand placement.
class PoolGhost {
  final double nx;
  final double ny;
  final double radiusFrac;

  const PoolGhost({
    required this.nx,
    required this.ny,
    required this.radiusFrac,
  });
}

/// Everything one frame of the table needs.
class PoolView {
  final List<RenderBall> balls;
  final PoolAim? aim;
  final PoolGhost? ghost;

  const PoolView({required this.balls, this.aim, this.ghost});
}

/// Rail band width as a fraction of the table width — the felt inset.
const double _railFrac = 0.085;

/// How much of the rail band is cushion (cloth) rather than wood.
const double _cushionFrac = 0.38;

/// Pocket mouth radius as a fraction of the table width.
const double _pocketFrac = 0.062;

/// The felt (playing area) rect inside the rail frame for a table of [size].
/// Shared by the scene (for hit-testing) and the painter (for drawing) so the
/// two never drift. Pocket centres sit on this rect's corners + side midpoints.
Rect poolFeltRect(Size size) {
  final m = size.width * _railFrac;
  return Rect.fromLTRB(m, m, size.width - m, size.height - m);
}

Color _lighten(Color c, double t) => Color.lerp(c, Colors.white, t)!;
Color _darken(Color c, double t) => Color.lerp(c, Colors.black, t)!;

/// Paints the pool hall around the table into [size]: a dark hardwood floor,
/// the pool of light a low pendant lamp throws onto it, and a vignette into the
/// corners. Pure, so the board and any static preview share one room.
///
/// [lightCenter] is where the lamp hangs, in fractional coords — normally the
/// centre of the table so the falloff frames it.
void paintPoolRoom(Canvas canvas, Size size,
    {Offset lightCenter = const Offset(0.5, 0.46)}) {
  final full = Offset.zero & size;
  const floor = Color(0xFF241A12);
  canvas.drawRect(full, Paint()..color = floor);

  // Hardwood planks running across the room.
  final plankH = math.max(10.0, size.height / 11);
  final rows = (size.height / plankH).ceil() + 1;
  for (var i = 0; i < rows; i++) {
    final y = i * plankH;
    final tone = _noise(i * 17 + 5);
    final rect = Rect.fromLTWH(0, y, size.width, plankH);
    canvas.drawRect(
      rect,
      Paint()
        ..color = (tone > 0 ? Colors.white : Colors.black)
            .withValues(alpha: 0.008 + tone.abs() * 0.028),
    );
    // Grain within the plank.
    for (var g = 1; g < 6; g++) {
      final n = _noise(i * 31 + g * 7);
      final gy = y + plankH * (g / 6 + n * 0.05);
      final path = Path();
      const segs = 14;
      for (var k = 0; k <= segs; k++) {
        final x = size.width * k / segs;
        final v = gy + math.sin(x * 0.035 + n * 6) * plankH * 0.05;
        k == 0 ? path.moveTo(x, v) : path.lineTo(x, v);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = Colors.black.withValues(alpha: 0.10 + n.abs() * 0.08),
      );
    }
    // Plank seam + the light catching its edge.
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..strokeWidth = 1.1
        ..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawLine(
      Offset(0, y + 1.2),
      Offset(size.width, y + 1.2),
      Paint()
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.045),
    );
  }

  // Lamp light spilling onto the floor, then dark into the corners.
  final c = Alignment(lightCenter.dx * 2 - 1, lightCenter.dy * 2 - 1);
  canvas.drawRect(
    full,
    Paint()
      ..shader = RadialGradient(
        center: c,
        radius: 0.95,
        colors: [
          const Color(0xFFFFD9A0).withValues(alpha: 0.16),
          const Color(0xFFFFC98A).withValues(alpha: 0.05),
          Colors.black.withValues(alpha: 0.30),
          Colors.black.withValues(alpha: 0.62),
        ],
        stops: const [0.0, 0.42, 0.75, 1.0],
      ).createShader(full),
  );
}

/// Cheap deterministic hash noise in [-1, 1]. Used for wood grain and cloth
/// weave so the backdrop looks hand-made without shipping a texture asset.
double _noise(int i) {
  final s = math.sin(i * 12.9898) * 43758.5453;
  return (s - s.floorToDouble()) * 2 - 1;
}

/// Pocket centres (screen coords) for a table of [size].
List<Offset> poolPockets(Size size) {
  final f = poolFeltRect(size);
  return [
    f.topLeft,
    f.topRight,
    f.bottomLeft,
    f.bottomRight,
    Offset(f.left, f.center.dy),
    Offset(f.right, f.center.dy),
  ];
}

/// Cached, resolution-and-palette-keyed render of everything on the table that
/// never moves: the wood frame, the cushions, the cloth with its nap and
/// vignette, the sight diamonds, and the pocket jaws. Rebuilt only when the
/// board is resized or restyled, so the per-frame cost of all that detail is a
/// single `drawPicture`.
class _Backdrop {
  final double w;
  final double h;
  final int felt;
  final int rail;
  final ui.Picture picture;

  _Backdrop(this.w, this.h, this.felt, this.rail, this.picture);

  bool matches(Size size, Color f, Color r) =>
      w == size.width &&
      h == size.height &&
      // ignore: deprecated_member_use
      felt == f.value &&
      // ignore: deprecated_member_use
      rail == r.value;
}

/// Two slots, not one: the board and a preview can be on screen at different
/// sizes, and a single slot would thrash — re-recording the whole backdrop
/// every frame for both.
final List<_Backdrop> _backdrops = [];

ui.Picture _backdropFor(Size size, Color felt, Color rail) {
  for (final b in _backdrops) {
    if (b.matches(size, felt, rail)) return b.picture;
  }
  final recorder = ui.PictureRecorder();
  _paintBackdrop(Canvas(recorder), size, felt, rail);
  final made = _Backdrop(
    size.width,
    size.height,
    // ignore: deprecated_member_use
    felt.value,
    // ignore: deprecated_member_use
    rail.value,
    recorder.endRecording(),
  );
  _backdrops.insert(0, made);
  while (_backdrops.length > 2) {
    _backdrops.removeLast().picture.dispose();
  }
  return made.picture;
}

/// Draws the full felt table, wood rails, six pockets, balls, and aim indicator
/// into [size]. Pure — no Flame or widget state — so a `CustomPainter` can call
/// it for a static snapshot (screenshots/tests) exactly as the live scene does.
void paintPoolTable(
  Canvas canvas,
  Size size,
  PoolView view,
  EightBallStyle style,
  ColorScheme scheme,
) {
  final rail = style.resolveRail(scheme);
  final felt = style.resolveFelt(scheme);
  final feltRect = poolFeltRect(size);

  canvas.drawPicture(_backdropFor(size, felt, rail));

  double xOf(double nx) => feltRect.left + nx * feltRect.width;
  double yOf(double ny) => feltRect.top + ny * feltRect.height;

  // Ghost cue (ball in hand).
  final ghost = view.ghost;
  if (ghost != null) {
    final c = Offset(xOf(ghost.nx), yOf(ghost.ny));
    final r = ghost.radiusFrac * feltRect.width;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, r * 0.14)
        ..color = Colors.white.withValues(alpha: 0.8),
    );
  }

  final aim = view.aim;

  // The aim guide belongs to the cloth, so it stops at the cushions.
  if (aim != null) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(feltRect, Radius.circular(size.width * 0.026)),
    );
    _paintAim(canvas, Offset(xOf(aim.nx), yOf(aim.ny)), aim, feltRect, size);
    canvas.restore();
  }

  // Cue stick goes under the balls so its tip tucks behind the cue ball, and
  // may overhang the rails — it is held above the table, not on it.
  canvas.save();
  canvas.clipRRect(
    RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.055),
    ),
  );
  if (aim != null) {
    _paintCueStick(
      canvas,
      Offset(xOf(aim.nx), yOf(aim.ny)),
      aim,
      (view.balls.isEmpty ? 0.02 : view.balls.first.radiusFrac) *
          feltRect.width,
      feltRect,
    );
  }

  // Balls.
  for (final b in view.balls) {
    _paintBall(
        canvas, Offset(xOf(b.nx), yOf(b.ny)), b.radiusFrac * feltRect.width, b);
  }
  canvas.restore();
}

// ---------------------------------------------------------------------------
// Backdrop: wood frame, cushions, cloth, sight diamonds, pocket jaws.
// ---------------------------------------------------------------------------

void _paintBackdrop(Canvas canvas, Size size, Color felt, Color rail) {
  final w = size.width;
  final outerRR = RRect.fromRectAndRadius(
    Offset.zero & size,
    Radius.circular(w * 0.055),
  );
  canvas.save();
  canvas.clipRRect(outerRR);

  final feltRect = poolFeltRect(size);
  final cushion = w * _railFrac * _cushionFrac;
  final feltRR = RRect.fromRectAndRadius(feltRect, Radius.circular(w * 0.026));
  final cushRect = feltRect.inflate(cushion);
  final cushRR = RRect.fromRectAndRadius(
    cushRect,
    Radius.circular(w * 0.026 + cushion),
  );

  _paintWoodFrame(canvas, size, outerRR, cushRect, rail);
  _paintCushions(canvas, size, cushRR, feltRR, felt);
  _paintBed(canvas, size, feltRect, feltRR, felt);
  _paintPockets(canvas, size, feltRect, felt, rail);

  canvas.restore();
}

/// Stained hardwood frame: base stain, four mitred faces each with grain
/// running along its own length, bevelled edges, and mother-of-pearl sight
/// diamonds.
void _paintWoodFrame(
  Canvas canvas,
  Size size,
  RRect outerRR,
  Rect inner,
  Color rail,
) {
  final w = size.width, h = size.height;
  final rect = outerRR.outerRect;

  canvas.drawRRect(
    outerRR,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _lighten(rail, 0.20),
          rail,
          _darken(rail, 0.30),
          _darken(rail, 0.52),
        ],
        stops: const [0.0, 0.32, 0.7, 1.0],
      ).createShader(rect),
  );

  final l = inner.left, t = inner.top, r = inner.right, b = inner.bottom;

  // (path, grain runs horizontally?, light bias) for each mitred rail face.
  final faces = <(Path, bool, double)>[
    (
      Path()
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..lineTo(r, t)
        ..lineTo(l, t)
        ..close(),
      true,
      0.13,
    ),
    (
      Path()
        ..moveTo(0, h)
        ..lineTo(w, h)
        ..lineTo(r, b)
        ..lineTo(l, b)
        ..close(),
      true,
      -0.14,
    ),
    (
      Path()
        ..moveTo(0, 0)
        ..lineTo(l, t)
        ..lineTo(l, b)
        ..lineTo(0, h)
        ..close(),
      false,
      0.05,
    ),
    (
      Path()
        ..moveTo(w, 0)
        ..lineTo(r, t)
        ..lineTo(r, b)
        ..lineTo(w, h)
        ..close(),
      false,
      -0.09,
    ),
  ];

  var seed = 0;
  for (final (path, horizontal, bias) in faces) {
    canvas.save();
    canvas.clipPath(path);
    final bounds = path.getBounds();
    // Face shading: which way this rail turns to the overhead light.
    canvas.drawPath(
      path,
      Paint()
        ..color = bias >= 0
            ? Colors.white.withValues(alpha: bias)
            : Colors.black.withValues(alpha: -bias),
    );
    // Grain: closely spaced wavering lines along the rail's length.
    final span = horizontal ? bounds.height : bounds.width;
    final step = math.max(1.1, span / 16);
    final len = horizontal ? bounds.width : bounds.height;
    final lineCount = (span / step).ceil();
    for (var i = 0; i <= lineCount; i++) {
      seed++;
      final n = _noise(seed);
      final base = (horizontal ? bounds.top : bounds.left) + i * step;
      final amp = step * (0.25 + 0.5 * _noise(seed * 3).abs());
      final freq = (1.2 + _noise(seed * 7).abs() * 2.4) * math.pi / len;
      final phase = _noise(seed * 11) * math.pi;
      final path2 = Path();
      const segs = 22;
      for (var k = 0; k <= segs; k++) {
        final u = (horizontal ? bounds.left : bounds.top) + len * k / segs;
        final v = base + math.sin(u * freq + phase) * amp;
        final pt = horizontal ? Offset(u, v) : Offset(v, u);
        k == 0 ? path2.moveTo(pt.dx, pt.dy) : path2.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(
        path2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.55 + n.abs() * 0.9
          ..color = (n > 0 ? Colors.white : Colors.black)
              .withValues(alpha: 0.045 + n.abs() * 0.085),
      );
    }
    canvas.restore();
  }

  // Mitre seams.
  final seam = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.7, w * 0.0025)
    ..color = Colors.black.withValues(alpha: 0.22);
  canvas.drawLine(Offset.zero, Offset(l, t), seam);
  canvas.drawLine(Offset(w, 0), Offset(r, t), seam);
  canvas.drawLine(Offset(0, h), Offset(l, b), seam);
  canvas.drawLine(Offset(w, h), Offset(r, b), seam);

  _paintSightDiamonds(canvas, size, inner, rail);

  // Outer bevel: a lit top-left edge falling to a dark bottom-right one.
  canvas.drawRRect(
    outerRR.deflate(math.max(0.6, w * 0.003)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.006)
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.24),
          Colors.white.withValues(alpha: 0.04),
          Colors.black.withValues(alpha: 0.34),
        ],
      ).createShader(rect),
  );

  // Inner bevel where the wood steps down onto the cushions.
  canvas.drawRRect(
    RRect.fromRectAndRadius(inner, Radius.circular(w * 0.026 + w * 0.02)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, w * 0.005)
      ..color = Colors.black.withValues(alpha: 0.34),
  );
}

/// Mother-of-pearl sight diamonds: three per short rail, six per long rail
/// (the seventh position is the side pocket).
void _paintSightDiamonds(Canvas canvas, Size size, Rect inner, Color rail) {
  final w = size.width;
  final felt = poolFeltRect(size);
  final railBand = felt.left; // == size.width * _railFrac
  final cushion = railBand * _cushionFrac;
  final mid = (railBand - cushion) * 0.52; // centre of the visible wood
  final rx = w * 0.0085, ry = w * 0.0125;

  void diamond(Offset at) {
    final path = Path()
      ..moveTo(at.dx, at.dy - ry)
      ..lineTo(at.dx + rx, at.dy)
      ..lineTo(at.dx, at.dy + ry)
      ..lineTo(at.dx - rx, at.dy)
      ..close();
    canvas.drawPath(
      path.shift(const Offset(0, 0.6)),
      Paint()..color = Colors.black.withValues(alpha: 0.40),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEDE3CD), Color(0xFFCFC2A6), Color(0xFF9E9077)],
        ).createShader(path.getBounds()),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.55
        ..color = Colors.black.withValues(alpha: 0.32),
    );
  }

  for (final f in const [0.125, 0.25, 0.375, 0.625, 0.75, 0.875]) {
    final y = felt.top + felt.height * f;
    diamond(Offset(mid, y));
    diamond(Offset(size.width - mid, y));
  }
  for (final f in const [0.25, 0.5, 0.75]) {
    final x = felt.left + felt.width * f;
    diamond(Offset(x, mid));
    diamond(Offset(x, size.height - mid));
  }
}

/// The cloth-covered cushions: a band between the wood and the bed, lit from
/// the top-left, with a crisp nose line where they meet the playing surface.
void _paintCushions(
  Canvas canvas,
  Size size,
  RRect cushRR,
  RRect feltRR,
  Color felt,
) {
  final w = size.width;
  // Cushions are covered in the same cloth as the bed, but they face sideways
  // under an overhead lamp — so they sit noticeably darker than the playing
  // surface, which is what makes the bed read as recessed.
  final cloth = _darken(felt, 0.42);
  final band = Path.combine(
    PathOperation.difference,
    Path()..addRRect(cushRR),
    Path()..addRRect(feltRR),
  );
  canvas.drawPath(
    band,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _lighten(cloth, 0.26),
          cloth,
          _darken(cloth, 0.42),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(cushRR.outerRect),
  );
  // Highlight where the cushion face meets the wood — the lit top of the bevel.
  canvas.drawRRect(
    cushRR.deflate(math.max(0.6, w * 0.003)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.9, w * 0.004)
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.13),
          Colors.white.withValues(alpha: 0.03),
          Colors.black.withValues(alpha: 0.26),
        ],
      ).createShader(cushRR.outerRect),
  );
  // The nose: a hard dark edge at the play boundary.
  canvas.drawRRect(
    feltRR,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, w * 0.005)
      ..color = Colors.black.withValues(alpha: 0.55),
  );
}

/// The cloth bed: clean colour, directional nap along the table, an overhead
/// light pool, a vignette into the rails, and the table markings.
void _paintBed(
  Canvas canvas,
  Size size,
  Rect feltRect,
  RRect feltRR,
  Color felt,
) {
  final w = size.width;
  canvas.drawRRect(feltRR, Paint()..color = felt);

  canvas.save();
  canvas.clipRRect(feltRR);

  // Nap: the pile lies along the table, so the weave reads as fine lengthwise
  // lines with a much fainter crossweave.
  final napStep = math.max(1.6, w / 64);
  for (var i = 0; i * napStep < feltRect.width; i++) {
    final x = feltRect.left + i * napStep;
    final n = _noise(i * 5 + 1);
    canvas.drawLine(
      Offset(x, feltRect.top),
      Offset(x, feltRect.bottom),
      Paint()
        ..strokeWidth = 0.8
        ..color = (n > 0 ? Colors.white : Colors.black)
            .withValues(alpha: 0.010 + n.abs() * 0.020),
    );
  }
  final weaveStep = napStep * 1.7;
  for (var i = 0; i * weaveStep < feltRect.height; i++) {
    final y = feltRect.top + i * weaveStep;
    final n = _noise(i * 13 + 3);
    canvas.drawLine(
      Offset(feltRect.left, y),
      Offset(feltRect.right, y),
      Paint()
        ..strokeWidth = 0.7
        ..color = (n > 0 ? Colors.white : Colors.black)
            .withValues(alpha: 0.008 + n.abs() * 0.016),
    );
  }

  // Markings, under the light so they sit in the cloth.
  double xOf(double nx) => feltRect.left + nx * feltRect.width;
  double yOf(double ny) => feltRect.top + ny * feltRect.height;

  const headY = EightBallGame.headStringNy;
  canvas.drawLine(
    Offset(feltRect.left, yOf(headY)),
    Offset(feltRect.right, yOf(headY)),
    Paint()
      ..strokeWidth = math.max(0.9, w * 0.004)
      ..color = Colors.white.withValues(alpha: 0.09),
  );

  void spot(Offset at) {
    final r = math.max(1.6, w * 0.011);
    canvas.drawCircle(
      at,
      r,
      Paint()..color = Colors.black.withValues(alpha: 0.30),
    );
    canvas.drawCircle(
      at.translate(0, -r * 0.22),
      r * 0.72,
      Paint()..color = Colors.white.withValues(alpha: 0.20),
    );
  }

  spot(Offset(xOf(0.5), yOf(EightBallGame.rackApexNy)));
  spot(Offset(xOf(0.5), yOf(headY)));

  // Overhead light pool + vignette into the rails, in one pass.
  canvas.drawRect(
    feltRect,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.06, -0.18),
        radius: 1.12,
        colors: [
          Colors.white.withValues(alpha: 0.19),
          Colors.white.withValues(alpha: 0.05),
          Colors.black.withValues(alpha: 0.14),
          Colors.black.withValues(alpha: 0.50),
        ],
        stops: const [0.0, 0.32, 0.6, 1.0],
      ).createShader(feltRect),
  );

  // Cushion shadow cast onto the bed.
  canvas.drawRRect(
    feltRR.deflate(w * 0.012),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.026
      ..color = Colors.black.withValues(alpha: 0.30)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.016),
  );

  canvas.restore();
}

/// Pockets as cut mouths: a cloth-wrapped jaw collar, a leather rim, and a
/// throat that darkens away from the light.
void _paintPockets(
  Canvas canvas,
  Size size,
  Rect feltRect,
  Color felt,
  Color rail,
) {
  final w = size.width;
  final mouthR = w * _pocketFrac;
  final jawR = mouthR * 1.30;
  // The mouth is a hole cut through rail and cushion alike, so the collar is
  // the cut edge of the frame, not another patch of cloth.
  final cut = _darken(rail, 0.46);

  for (final p in poolPockets(size)) {
    canvas.drawCircle(
      p,
      jawR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          colors: [_lighten(cut, 0.22), cut, _darken(cut, 0.5)],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: p, radius: jawR)),
    );
    // Stitched leather pocket facing around the mouth.
    canvas.drawCircle(
      p,
      mouthR * 1.16,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          colors: const [
            Color(0xFF9A7048),
            Color(0xFF56381F),
            Color(0xFF2A1A0C)
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: p, radius: mouthR * 1.16)),
    );
    // The throat: near-black, biased so the lit side of the rim reads.
    canvas.drawCircle(
      p,
      mouthR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.3, 0.42),
          radius: 0.95,
          colors: const [
            Color(0xFF060606),
            Color(0xFF0B0A09),
            Color(0xFF17130E)
          ],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(Rect.fromCircle(center: p, radius: mouthR)),
    );
    // Rim highlight on the lit edge only.
    canvas.drawArc(
      Rect.fromCircle(center: p, radius: mouthR * 1.02),
      math.pi * 0.86,
      math.pi * 0.82,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.9, w * 0.005)
        ..color = Colors.white.withValues(alpha: 0.16),
    );
    // Inner throat shadow so the hole has depth rather than being a decal.
    canvas.drawCircle(
      p,
      mouthR * 0.86,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = mouthR * 0.34
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, mouthR * 0.22),
    );
  }
}

void _paintBall(Canvas canvas, Offset c, double r, RenderBall b) {
  if (r <= 0.4) return;
  final base = EightBallStyle.ballColor(b.number);
  final isStripe = b.number >= 9 && b.number <= 15;
  const ivory = Color(0xFFF6F1E7);

  // Contact shadow.
  canvas.drawCircle(
    c.translate(0, r * 0.22),
    r * 1.02,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.35),
  );

  // Body: flat base, markings on top, then one shading pass over the lot — so
  // the rolling markings pick up the same sphere shading as the body.
  canvas.drawCircle(c, r, Paint()..color = isStripe ? ivory : base);

  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));

  if (isStripe) {
    // The stripe is a band about the ball's local Y axis; it sweeps across the
    // face as the ball rolls.
    _paintRollingBand(canvas, c, r, base, b.spin.ay);
  }

  if (b.isCue) {
    // Measle-style spots: a plain white cue would show no rolling at all.
    const spot = Color(0xFFD2453F);
    for (final axis in [b.spin.ax, b.spin.ay, b.spin.az]) {
      _paintRollingSpot(canvas, c, r, axis, spot, r * 0.17);
      _paintRollingSpot(
          canvas, c, r, (x: -axis.x, y: -axis.y, z: -axis.z), spot, r * 0.17);
    }
  } else {
    // Real balls carry the number on both poles, so one is almost always in
    // view — which is exactly what sells the roll.
    _paintRollingBadge(canvas, c, r, b.spin.az, b.number);
    _paintRollingBadge(canvas, c, r,
        (x: -b.spin.az.x, y: -b.spin.az.y, z: -b.spin.az.z), b.number);
  }

  // Sphere shading over body + markings.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        colors: [
          Colors.white.withValues(alpha: 0.42),
          Colors.white.withValues(alpha: 0.06),
          Colors.black.withValues(alpha: 0.42),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r)),
  );
  canvas.restore();

  // Silhouette outline.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06
      ..color = Colors.black.withValues(alpha: 0.28),
  );

  // Specular highlight.
  canvas.drawCircle(
    c.translate(-r * 0.32, -r * 0.36),
    r * 0.2,
    Paint()..color = Colors.white.withValues(alpha: 0.5),
  );
}

/// Fills the stripe band — the sphere points within `bandHalf` of the equator
/// about [axis] — by scanning rows of the visible hemisphere. Scanning handles
/// every orientation uniformly (a band seen edge-on becomes a bar across the
/// face; seen pole-on it becomes a ring near the rim) with no special cases.
void _paintRollingBand(
    Canvas canvas, Offset c, double r, Color color, V3 axis) {
  const bandHalf = 0.52; // half-thickness of the band, in sphere units
  const rows = 26;
  const cols = 22;
  final paint = Paint()..color = color;
  // Half-height of a row's rect, overlapped slightly so rounding never leaves
  // hairline seams of the body colour showing through the band.
  final rowH = (r / rows) * 1.25;
  for (var i = 0; i < rows; i++) {
    final y = -1 + 2 * (i + 0.5) / rows;
    final halfW = math.sqrt(math.max(0.0, 1 - y * y));
    if (halfW <= 0) continue;
    double? spanStart;
    for (var j = 0; j <= cols; j++) {
      final x = -halfW + 2 * halfW * (j / cols);
      final z2 = 1 - x * x - y * y;
      final z = z2 > 0 ? math.sqrt(z2) : 0.0;
      // Distance from the band's equator plane.
      final d = (x * axis.x + y * axis.y + z * axis.z).abs();
      final inside = j < cols && d <= bandHalf;
      if (inside && spanStart == null) spanStart = x;
      if (!inside && spanStart != null) {
        canvas.drawRect(
          Rect.fromLTRB(
            c.dx + spanStart * r,
            c.dy + y * r - rowH,
            c.dx + x * r,
            c.dy + y * r + rowH,
          ),
          paint,
        );
        spanStart = null;
      }
    }
  }
}

/// Draws the numbered badge sitting at sphere direction [axis]. Hidden when the
/// pole has turned away; foreshortened into an ellipse as it nears the rim.
void _paintRollingBadge(
    Canvas canvas, Offset c, double r, V3 axis, int number) {
  if (axis.z <= 0.02) return; // facing away
  final badgeR = r * 0.46;
  final at = Offset(c.dx + axis.x * r, c.dy + axis.y * r);
  final tilt = math.atan2(axis.y, axis.x);

  canvas.save();
  canvas.translate(at.dx, at.dy);
  canvas.rotate(tilt);
  // Squash along the radial direction by how far the pole has tipped away.
  canvas.scale(axis.z.clamp(0.0, 1.0), 1.0);
  canvas.drawCircle(
      Offset.zero, badgeR, Paint()..color = const Color(0xFFF8F4EC));
  canvas.restore();

  // Only draw the digits while the badge is reasonably face-on — squashed to a
  // sliver they turn to mush at this scale.
  if (axis.z < 0.6 || r < 7) return;
  final tp = TextPainter(
    text: TextSpan(
      text: '$number',
      style: TextStyle(
        color: const Color(0xFF1A1A1A),
        fontSize: r * (number >= 10 ? 0.58 : 0.68),
        fontWeight: FontWeight.w700,
        height: 1.0,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  canvas.save();
  canvas.translate(at.dx, at.dy);
  canvas.rotate(tilt);
  canvas.scale(axis.z.clamp(0.0, 1.0), 1.0);
  tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  canvas.restore();
}

/// A small round spot at sphere direction [axis] (measle cue ball).
void _paintRollingSpot(
    Canvas canvas, Offset c, double r, V3 axis, Color color, double spotR) {
  if (axis.z <= 0.05) return;
  final at = Offset(c.dx + axis.x * r, c.dy + axis.y * r);
  final tilt = math.atan2(axis.y, axis.x);
  canvas.save();
  canvas.translate(at.dx, at.dy);
  canvas.rotate(tilt);
  canvas.scale(axis.z.clamp(0.0, 1.0), 1.0);
  canvas.drawCircle(Offset.zero, spotR, Paint()..color = color);
  canvas.restore();
}

void _paintAim(
  Canvas canvas,
  Offset origin,
  PoolAim aim,
  Rect felt,
  Size size,
) {
  // Faint long projection guide (where the cue would travel).
  final guideLen = felt.height * 0.9;
  final guideTip = origin + aim.dir * guideLen;
  canvas.drawLine(
    origin,
    guideTip,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = math.max(1, felt.width * 0.01),
  );

  // The cue stick itself carries the power read: it draws back further the
  // harder the shot, exactly like a real stroke, so no separate meter is needed.
}

/// Draws the cue stick behind the cue ball, pointing along the shot line and
/// drawn back in proportion to power.
void _paintCueStick(
  Canvas canvas,
  Offset cueCenter,
  PoolAim aim,
  double ballR,
  Rect felt,
) {
  // The stick lies opposite the shot direction, tip nearest the ball.
  final back = Offset(-aim.dir.dx, -aim.dir.dy);
  final pull = ballR * (0.55 + 6.5 * aim.power);
  final tip = cueCenter + back * (ballR + pull);
  final len = math.max(felt.height * 0.46, ballR * 14);
  final perp = Offset(-back.dy, back.dx);

  final wTip = math.max(1.1, felt.width * 0.0075);
  final wButt = wTip * 2.6;

  Offset at(double t) => tip + back * (len * t);
  double halfW(double t) => (wTip + (wButt - wTip) * t) / 2;

  /// A tapered segment of the stick between [t0] and [t1] along its length.
  void segment(double t0, double t1, Paint paint) {
    final a = at(t0), b = at(t1);
    final wa = halfW(t0), wb = halfW(t1);
    canvas.drawPath(
      Path()
        ..moveTo(a.dx + perp.dx * wa, a.dy + perp.dy * wa)
        ..lineTo(b.dx + perp.dx * wb, b.dy + perp.dy * wb)
        ..lineTo(b.dx - perp.dx * wb, b.dy - perp.dy * wb)
        ..lineTo(a.dx - perp.dx * wa, a.dy - perp.dy * wa)
        ..close(),
      paint,
    );
  }

  // Drop shadow so the cue reads as hovering over the cloth.
  canvas.save();
  canvas.translate(0, ballR * 0.35);
  segment(
    0,
    1,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.26)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, ballR * 0.3),
  );
  canvas.restore();

  // Tip (blue chalk) → ferrule (ivory) → maple shaft → joint → stained butt.
  segment(0.0, 0.018, Paint()..color = const Color(0xFF3E68B0));
  segment(0.018, 0.05, Paint()..color = const Color(0xFFEDE6D6));
  segment(
    0.05,
    0.6,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFE3C48E),
          const Color(0xFFC79A5D),
          const Color(0xFF9E7440),
        ],
      ).createShader(Rect.fromPoints(at(0.05), at(0.6))),
  );
  segment(0.6, 0.63, Paint()..color = const Color(0xFFD8CDB4)); // joint collar
  segment(
    0.63,
    1.0,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF6E3B24),
          const Color(0xFF4A2416),
          const Color(0xFF2E1710),
        ],
      ).createShader(Rect.fromPoints(at(0.63), at(1.0))),
  );
  // Grip wrap.
  segment(0.74, 0.9, Paint()..color = const Color(0xFF1C1C1C));

  // Lengthwise sheen.
  final s0 = at(0.05), s1 = at(0.97);
  canvas.drawLine(
    Offset(s0.dx + perp.dx * wTip * 0.35, s0.dy + perp.dy * wTip * 0.35),
    Offset(s1.dx + perp.dx * wButt * 0.35, s1.dy + perp.dy * wButt * 0.35),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = math.max(0.8, wTip * 0.5),
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
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 15,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  final String label;
  final BallGroup? group;
  final int remaining;
  final Color accent;
  final bool active;
  final bool winner;

  const _PlayerChip({
    required this.label,
    required this.group,
    required this.remaining,
    required this.accent,
    required this.active,
    required this.winner,
  });

  @override
  Widget build(BuildContext context) {
    final groupLabel = group == null
        ? 'open'
        : (group == BallGroup.solids ? 'solids' : 'stripes');
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
          _GroupDot(group: group, accent: accent),
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
            group == null ? groupLabel : '$groupLabel · $remaining',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// A little emblem showing a player's group: a solid disc, a striped disc, or a
/// hollow ring for an open table.
class _GroupDot extends StatelessWidget {
  final BallGroup? group;
  final Color accent;

  const _GroupDot({required this.group, required this.accent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child:
          CustomPaint(painter: _GroupDotPainter(group: group, accent: accent)),
    );
  }
}

class _GroupDotPainter extends CustomPainter {
  final BallGroup? group;
  final Color accent;

  _GroupDotPainter({required this.group, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    if (group == null) {
      canvas.drawCircle(
        c,
        r - 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withValues(alpha: 0.6),
      );
      return;
    }
    if (group == BallGroup.solids) {
      canvas.drawCircle(c, r, Paint()..color = accent);
    } else {
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFFF6F1E7));
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
      canvas.drawRect(
        Rect.fromCenter(center: c, width: r * 2, height: r * 1.1),
        Paint()..color = accent,
      );
      canvas.restore();
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.3),
    );
  }

  @override
  bool shouldRepaint(_GroupDotPainter old) =>
      old.group != group || old.accent != accent;
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
