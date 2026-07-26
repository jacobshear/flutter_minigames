import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:minigames_3d/minigames_3d.dart';
import 'package:minigames_core/minigames_core.dart';

import 'archery_game.dart';
import 'archery_shot.dart';
import 'archery_style.dart';
import 'archery_view.dart';

/// The playable archery range: a `CustomPaint` scene plus the draw controller,
/// wired to a [MatchController].
///
/// The seam is strict. This widget owns *timing and input*: how long the string
/// has been held, where the finger has dragged the aim, and the playback of a
/// flight. It owns **no rules**. When an arrow lands it asks
/// [ArcheryBallistics] where it struck, wraps that in an [ArcheryMove], and
/// hands it to the controller; [ArcheryGame] decides what it scored and what
/// happens next.
class ArcheryRange extends StatefulWidget {
  final MatchController<ArcheryState, ArcheryMove> controller;
  final ArcheryStyle style;

  const ArcheryRange({
    super.key,
    required this.controller,
    this.style = const ArcheryStyle(),
  });

  @override
  State<ArcheryRange> createState() => _ArcheryRangeState();
}

class _ArcheryRangeState extends State<ArcheryRange>
    with TickerProviderStateMixin {
  static const _game = ArcheryGame();

  // Assigned in initState — never as `late final x = AnimationController(...)`.
  // A lazy initializer would build the controller the first time it is touched,
  // and dispose() touches it; a shot that never happened would then create a
  // ticker against a deactivated element during teardown.
  late final AnimationController _flight;
  late final AnimationController _wobble;
  late final AnimationController _confettiCtrl;
  Ticker? _ticker;

  StreamSubscription<ArcheryState>? _sub;
  ArcheryState? _state;
  GameOutcome? _outcome;

  /// Free-running seconds, for ambient motion.
  double _time = 0;

  /// Draw timing, measured on the ticker clock rather than a `Stopwatch`.
  /// The ticker is the same monotonic clock the animation system uses, so the
  /// hold is frame-rate independent in production *and* advances under a
  /// widget test's fake clock — a `Stopwatch` would silently read ~0 there.
  double _drawStart = 0;
  double _held = 0;
  bool _drawing = false;
  bool _warned = false;

  /// How far off the solved line the sight can be dragged, radians. At the
  /// shortest range that is still ±0.9 m at the face — well past the edge of a
  /// 122 cm target — so the clamp never becomes the thing stopping a player
  /// from aiming where they want.
  static const double _aimLimit = 0.06;

  double _aimYaw = 0;
  double _aimPitch = 0;
  Offset? _lastPointer;
  Size _size = const Size(390, 640);

  ArcheryShotResult? _shot;
  bool _resolving = false;
  bool _lastHitFace = false;

  /// Arrows shown in the face right now — kept locally so the third arrow of an
  /// end stays visible while its pill is up, instead of vanishing the instant
  /// the state advances to the next target.
  List<ArrowShot> _stuck = const [];
  int _displayTarget = 0;

  String _pill = '';
  Timer? _pillTimer;
  bool _celebrated = false;
  bool _handoffAcknowledged = false;

  final math.Random _rnd = math.Random();
  List<_Confetto> _confetti = const [];

  static final ColorScheme _fallbackScheme =
      ColorScheme.fromSeed(seedColor: const Color(0xFF007AFF));
  ColorScheme _scheme = _fallbackScheme;

  bool get _hotSeat => widget.controller.hotSeat;

  @override
  void initState() {
    super.initState();
    _flight = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addStatusListener(_onFlightStatus);
    _wobble = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..addStatusListener(_onWobbleStatus);
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _ticker = createTicker(_onTick)..start();
    _bind();
  }

  @override
  void didUpdateWidget(covariant ArcheryRange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    _sub?.cancel();
    _bind();
  }

  void _bind() {
    _celebrated = false;
    _handoffAcknowledged = false;
    _resolving = false;
    _shot = null;
    _stuck = const [];
    _aimYaw = 0;
    _aimPitch = 0;
    _pill = '';
    _confetti = const [];
    final s = widget.controller.state;
    _state = s;
    _outcome = s == null ? null : _game.outcome(s);
    if (s != null) {
      _displayTarget = s.targetIndex;
      _stuck = s.arrowsAt(s.currentPlayerId, s.targetIndex);
      if (_outcome != null) _celebrated = true;
    }
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pillTimer?.cancel();
    _ticker?.dispose();
    _flight.dispose();
    _wobble.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Clock
  // ---------------------------------------------------------------------------

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    _time = elapsed.inMicroseconds / 1e6;
    if (_drawing) {
      _held = _time - _drawStart;
      if (!_warned && ArcheryDraw.isWarning(_held)) {
        _warned = true;
        widget.style.sounds.onFocusWarn?.call();
        if (widget.style.haptics) HapticFeedback.selectionClick();
      }
    }
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Input: press to draw, drag to aim, release to loose
  // ---------------------------------------------------------------------------

  bool get _canShoot {
    final s = _state;
    if (s == null || _outcome != null) return false;
    if (_resolving) return false;
    if (_hotSeat &&
        s.phase == ArcheryPhase.handoff &&
        !_handoffAcknowledged) {
      return false;
    }
    return widget.controller.canActLocally;
  }

  void _pointerDown(PointerDownEvent e) {
    if (!_canShoot) return;
    _lastPointer = e.localPosition;
    _drawing = true;
    _warned = false;
    _drawStart = _time;
    _held = 0;
    widget.style.sounds.onBowDraw?.call();
    if (widget.style.haptics) HapticFeedback.selectionClick();
    setState(() => _showPill(''));
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_drawing) return;
    final last = _lastPointer ?? e.localPosition;
    final delta = e.localPosition - last;
    _lastPointer = e.localPosition;
    // Pixels → radians through the live focal length, so the sight tracks the
    // finger at the same rate however far the sight is zoomed in.
    //
    // The `1 - followFactor` is not a feel tweak, it is the inverse of the
    // camera: the view swings toward the aim by `followFactor`, so a reticle
    // drawn at `focal·tan(yaw)` only travels `focal·(1 - followFactor)·yaw`
    // across the frame. Dividing by the raw focal moved the sight at half the
    // speed of the finger — the reticle lagged the thumb, which is the first
    // thing that makes an aim feel disconnected from its own input.
    final focal = _camera.focal * (1 - ArcheryCamera.followFactor);
    if (focal <= 0) return;
    setState(() {
      _aimYaw = (_aimYaw + delta.dx / focal).clamp(-_aimLimit, _aimLimit);
      _aimPitch = (_aimPitch - delta.dy / focal).clamp(-_aimLimit, _aimLimit);
    });
  }

  void _pointerUp(PointerUpEvent e) => _loose();

  void _pointerCancel(PointerCancelEvent e) => _loose();

  Camera3 get _camera => ArcheryCamera.of(_size, _buildView());

  int get _shotSeed {
    final s = _state;
    if (s == null) return 0;
    return s.seed * 131 +
        s.playerIds.indexOf(s.currentPlayerId) * 17 +
        s.arrowsShotBy(s.currentPlayerId);
  }

  void _loose() {
    if (!_drawing) return;
    final s = _state;
    _drawing = false;
    _held = math.max(0, _time - _drawStart);
    if (s == null || _resolving) return;

    final held = _held;
    final (swayYaw, swayPitch) =
        ArcheryDraw.swayOffset(heldSeconds: held, shotSeed: _shotSeed);
    final result = ArcheryBallistics.fire(
      conditions: s.conditions,
      power: ArcheryDraw.power(held),
      aimYaw: _aimYaw + swayYaw,
      aimPitch: _aimPitch + swayPitch,
    );

    widget.style.sounds.onLoose?.call();
    if (widget.style.haptics) HapticFeedback.mediumImpact();

    final slowMo = widget.style.slowMotionOnBullseye && result.isBullseye;
    _shot = result;
    _resolving = true;
    _flight
      ..duration = Duration(
        milliseconds:
            (result.flightSeconds * 1000 * (slowMo ? 1.9 : 1.15)).round().clamp(200, 4000),
      )
      ..forward(from: 0);
    setState(() {});
  }

  void _onFlightStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    _onImpact();
  }

  void _onImpact() {
    final s = _state;
    final result = _shot;
    if (s == null || result == null) return;
    final style = widget.style;

    if (result.onFace) {
      if (result.isBullseye) {
        style.sounds.onBullseye?.call();
        if (style.haptics) HapticFeedback.heavyImpact();
      } else {
        style.sounds.onHit?.call();
        if (style.haptics) HapticFeedback.lightImpact();
      }
    } else {
      style.sounds.onMiss?.call();
      if (style.haptics) HapticFeedback.mediumImpact();
    }

    final move = ArcheryMove.fromImpact(
      shooter: s.currentPlayerId,
      targetIndex: s.targetIndex,
      arrowIndex: s.arrowIndex,
      offsetX: result.offsetX,
      offsetY: result.offsetY,
    );

    // Show the arrow in the face immediately; the state catches up on the next
    // frame and the local list is re-synced when the end is over.
    setState(() {
      _stuck = [
        ..._stuck,
        ArrowShot(
          ring: move.ring,
          offsetX: move.offsetX,
          offsetY: move.offsetY,
          onFace: move.onFace,
        ),
      ];
      _showPill(
        result.isBullseye
            ? 'BULLSEYE! +10'
            : (result.onFace ? '+${result.ring}' : 'MISS'),
      );
    });
    // The wobble timer always runs — it is also the beat that lets the pill be
    // read and the submitted move land before the display rolls forward.
    _lastHitFace = result.onFace;
    _wobble.forward(from: 0);
    widget.controller.submitMove(move);
  }

  void _onWobbleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    _finishArrow();
  }

  /// The arrow is done: clear the flight, reset the aim, and roll the display
  /// forward if the state has moved to a new target or a new shooter.
  void _finishArrow() {
    if (!_resolving || !mounted) return;
    final s = _state;
    _resolving = false;
    _shot = null;
    _aimYaw = 0;
    _aimPitch = 0;
    if (s == null) return;
    final movedOn = s.targetIndex != _displayTarget ||
        s.arrowsShotBy(s.currentPlayerId) == 0;
    if (movedOn && _outcome == null) {
      _displayTarget = s.targetIndex;
      _stuck = s.arrowsAt(s.currentPlayerId, s.targetIndex);
      if (s.phase != ArcheryPhase.handoff) {
        widget.style.sounds.onNextTarget?.call();
        _showPill(s.conditions.summary());
      }
    }
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  void _onState(ArcheryState next) {
    if (!mounted) return;
    final outcome = _game.outcome(next);
    final fresh = next.arrowsShotBy(next.playerIds.first) == 0 &&
        next.arrowsShotBy(next.playerIds.last) == 0;
    if (fresh) {
      _displayTarget = next.targetIndex;
      _stuck = const [];
      _handoffAcknowledged = false;
      _celebrated = false;
      _resolving = false;
      _shot = null;
    }
    if (outcome != null && !_celebrated) _celebrate(outcome);
    setState(() {
      _state = next;
      _outcome = outcome;
    });
  }

  void _celebrate(GameOutcome outcome) {
    _celebrated = true;
    final style = widget.style;
    if (outcome.isDraw) {
      style.sounds.onTie?.call();
    } else {
      style.sounds.onWin?.call();
    }
    if (style.haptics) HapticFeedback.heavyImpact();
    if (style.confetti && !outcome.isDraw) {
      _confetti = _spawnConfetti();
      _confettiCtrl.forward(from: 0);
    }
  }

  List<_Confetto> _spawnConfetti() {
    final palette = [
      widget.style.resolvePlayer1(_scheme),
      widget.style.resolvePlayer2(_scheme),
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

  /// Transient pills clear themselves; the win pill is [sticky]. Assigns
  /// synchronously — callers own the surrounding setState.
  void _showPill(String text, {bool sticky = false}) {
    _pillTimer?.cancel();
    _pill = text;
    if (!sticky && text.isNotEmpty) {
      _pillTimer = Timer(const Duration(milliseconds: 2200), () {
        if (!mounted) return;
        setState(() => _pill = '');
      });
    }
  }

  // ---------------------------------------------------------------------------
  // View assembly
  // ---------------------------------------------------------------------------

  ArcheryView _buildView() {
    final s = _state;
    final conditions = s?.conditions ??
        const TargetConditions(
            index: 0, distance: 18, windSpeed: 0, windAngle: 0);
    final held = _held;
    final drawing = _drawing;
    final progress = drawing ? ArcheryDraw.progress(held) : 0.0;
    final focus = drawing ? ArcheryDraw.focusBreak(held) : 0.0;
    final sway = drawing
        ? ArcheryDraw.swayAmplitude(held)
        : ArcheryDraw.swayAmplitude(0);
    final (swayYaw, swayPitch) = drawing
        ? ArcheryDraw.swayOffset(heldSeconds: held, shotSeed: _shotSeed)
        : (0.0, 0.0);

    final result = _shot;
    ArrowInFlight? flight;
    if (result != null && _flight.isAnimating) {
      final curve = widget.style.slowMotionOnBullseye && result.isBullseye
          ? Curves.easeOutCubic
          : Curves.linear;
      final t = curve.transform(_flight.value) * result.flightSeconds;
      flight = ArrowInFlight(
        position: result.positionAt(t),
        direction: result.directionAt(t),
        trail: [
          for (var i = 6; i >= 1; i--)
            result.positionAt(math.max(0, t - i * 0.018)),
        ],
      );
    }

    final accent = s == null
        ? widget.style.resolvePlayer1(_scheme)
        : widget.style.colorFor(_scheme, s.currentPlayerId, s.playerIds);

    return ArcheryView(
      conditions: conditions,
      stuckArrows: _stuck,
      flight: flight,
      aimYaw: _aimYaw + swayYaw,
      aimPitch: _aimPitch + swayPitch,
      // The sight rides the draw. Idle, it shows the centred shot; through the
      // hold it climbs from the under-drawn miss to the over-held one, and the
      // arrow always goes where it is pointing. Without this the draw moved
      // the arrow up to a third of a metre with nothing on screen to show it.
      drawBias: ArcheryBallistics.drawBias(
        conditions.distance,
        drawing ? ArcheryDraw.power(held) : 0.5,
      ),
      drawProgress: progress,
      holdProgress: drawing ? ArcheryDraw.holdProgress(held) : 0.0,
      focusBreak: focus,
      drawing: drawing,
      showReticle: _canShoot && !_resolving,
      // The zoom holds through the flight instead of snapping back to wide.
      zoom: _resolving ? 1 : progress,
      swayAmplitude: sway,
      time: _time,
      targetWobble:
          _lastHitFace && _wobble.isAnimating ? (1 - _wobble.value) : 0,
      arrowsLeft:
          ArcheryGame.arrowsPerTarget - _stuck.length.clamp(0, ArcheryGame.arrowsPerTarget),
      accent: accent,
    );
  }

  String _labelFor(String playerId) {
    final s = _state;
    if (s == null) return playerId;
    return widget.style.labelFor(s.playerIds.indexOf(playerId));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    _scheme = scheme;
    final style = widget.style;
    final state = _state;
    if (state == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final p1 = state.playerIds.first;
    final p2 = state.playerIds.last;
    final phase = state.phase;
    final showCover =
        _hotSeat && phase == ArcheryPhase.handoff && !_handoffAcknowledged;
    final finished = phase == ArcheryPhase.finished;

    return Column(
      children: [
        Row(
          children: [
            // FittedBox rather than a fixed Row: two long player names on a
            // narrow phone must scale, not overflow.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _PlayerChip(
                  label: _labelFor(p1),
                  score: state.totalOf(p1),
                  accent: style.resolvePlayer1(scheme),
                  active: !finished && state.currentPlayerId == p1,
                  winner: _outcome?.winnerId == p1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: _PlayerChip(
                  label: _labelFor(p2),
                  score: state.totalOf(p2),
                  accent: style.resolvePlayer2(scheme),
                  active: !finished && state.currentPlayerId == p2,
                  winner: _outcome?.winnerId == p2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: LayoutBuilder(
              builder: (context, c) {
                _size = Size(c.maxWidth, c.maxHeight);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _pointerDown,
                      onPointerMove: _pointerMove,
                      onPointerUp: _pointerUp,
                      onPointerCancel: _pointerCancel,
                      child: CustomPaint(
                        painter: ArcheryScenePainter(
                          view: _buildView(),
                          style: style,
                          scheme: scheme,
                        ),
                      ),
                    ),
                    if (style.confetti && _confetti.isNotEmpty)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _confettiCtrl,
                            builder: (context, _) => CustomPaint(
                              painter: _ConfettiPainter(
                                confetti: _confetti,
                                t: _confettiCtrl.value,
                                boardSize: c.maxWidth,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Align(
                          alignment: const Alignment(0, -0.25),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _pill.isEmpty
                                ? const SizedBox.shrink()
                                : _Pill(key: ValueKey(_pill), text: _pill),
                          ),
                        ),
                      ),
                    ),
                    if (showCover)
                      _HandoffCover(
                        label: _labelFor(state.currentPlayerId),
                        accent: style.resolvePlayer2(scheme),
                        onReady: () {
                          setState(() {
                            _handoffAcknowledged = true;
                            _displayTarget = state.targetIndex;
                            _stuck = const [];
                            _showPill(state.conditions.summary());
                          });
                        },
                      ),
                    if (finished)
                      _Results(
                        state: state,
                        outcome: _outcome,
                        style: style,
                        scheme: scheme,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          finished
              ? 'Tap New game to shoot again'
              : (showCover
                  ? 'Pass the phone'
                  : (_resolving
                      ? 'Watch it fly…'
                      : 'Hold to draw, drag to aim, release to loose')),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
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
  final Color accent;
  final bool active;
  final bool winner;

  const _PlayerChip({
    required this.label,
    required this.score,
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
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent,
              border: Border.all(color: Colors.black26),
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
          const SizedBox(width: 10),
          Text(
            '$score',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _HandoffCover extends StatelessWidget {
  final String label;
  final Color accent;
  final VoidCallback onReady;

  const _HandoffCover({
    required this.label,
    required this.accent,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: const Color(0xFF12161C).withValues(alpha: 0.94),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Pass the phone',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$label ready?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 26,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Same four targets, same winds',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: onReady,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 11),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Text(
                  'Start shooting',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// End-of-match card: per-target breakdown for both shooters, then the result.
class _Results extends StatelessWidget {
  final ArcheryState state;
  final GameOutcome? outcome;
  final ArcheryStyle style;
  final ColorScheme scheme;

  const _Results({
    required this.state,
    required this.outcome,
    required this.style,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final p1 = state.playerIds.first;
    final p2 = state.playerIds.last;
    final t1 = state.targetTotalsOf(p1);
    final t2 = state.targetTotalsOf(p2);
    final conditions = state.allConditions;
    final headline = outcome == null
        ? ''
        : (outcome!.isDraw
            ? 'DRAW'
            : '${style.labelFor(state.playerIds.indexOf(outcome!.winnerId!))} wins'
                .toUpperCase());

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: const Color(0xFF12161C).withValues(alpha: 0.86),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                headline,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              _row(
                '',
                style.player1Label,
                style.player2Label,
                header: true,
              ),
              for (var i = 0; i < ArcheryGame.targetCount; i++)
                _row(
                  '${conditions[i].distance.toStringAsFixed(0)} m',
                  '${t1[i]}',
                  '${t2[i]}',
                ),
              const SizedBox(height: 6),
              _row('Total', '${state.totalOf(p1)}', '${state.totalOf(p2)}',
                  total: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    String label,
    String a,
    String b, {
    bool header = false,
    bool total = false,
  }) {
    final s = TextStyle(
      color: Colors.white.withValues(alpha: header ? 0.65 : 1),
      fontWeight: total ? FontWeight.w900 : FontWeight.w700,
      fontSize: total ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(label,
                style: s.copyWith(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(a, textAlign: TextAlign.center, style: s)),
          Expanded(child: Text(b, textAlign: TextAlign.center, style: s)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confetti (compact port of the shared burst)
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
