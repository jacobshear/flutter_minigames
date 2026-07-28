import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:minigames_3d/minigames_3d.dart';
import 'package:minigames_core/minigames_core.dart';
import 'package:minigames_ui/minigames_ui.dart';

import 'cup_pong_game.dart';
import 'cup_pong_painter.dart';
import 'cup_pong_sim.dart';
import 'cup_pong_style.dart';
import 'cup_pong_world.dart';

/// First-person Cup Pong board wired to a [MatchController].
///
/// The board owns the simulation: a [Ticker] advances a [CupPongThrowSim] in
/// fixed steps, swept [Surfaces] tests run every step, and when the throw
/// resolves the *outcome* — which cup was sunk, or nothing — is submitted as a
/// [CupPongThrow]. The rules reducer trusts it and never re-simulates.
///
/// Rendering is a plain [CustomPaint] over [paintCupPongTable], so there is no
/// engine state anywhere in the visual path.
///
/// ## Input
///
/// One gesture: swipe. The ball sits ready in the near foreground, a swipe up
/// throws it, the swipe's angle steers which cup the solver powers for and its
/// length sets the power. There is no cursor and nothing to place. While the
/// finger is down the only feedback is a power ring and a short arrow, both
/// drawn on the ball itself; nothing — not a marker, not a predicted arc — is
/// ever projected onto the table or the rack ahead of a throw.
class CupPongBoard extends StatefulWidget {
  final MatchController<CupPongState, CupPongThrow> controller;
  final CupPongStyle style;

  /// Physics/feel tuning. Exposed so a host can make a friendlier or crueller
  /// variant without forking the board.
  final CupPongTuning tuning;

  const CupPongBoard({
    super.key,
    required this.controller,
    this.style = const CupPongStyle(),
    this.tuning = const CupPongTuning(),
  });

  @override
  State<CupPongBoard> createState() => _CupPongBoardState();
}

enum _Phase { aiming, flying, resolving }

class _CupPongBoardState extends State<CupPongBoard>
    with TickerProviderStateMixin {
  static const _game = CupPongGame();

  StreamSubscription<CupPongState>? _sub;
  CupPongState? _state;
  GameOutcome? _outcome;

  late final CupPongAim _aimSolver = CupPongAim(tuning: widget.tuning);
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  _Phase _phase = _Phase.aiming;
  CupPongThrowSim? _sim;
  double _simCarry = 0;

  // Drag state, in board-local pixels.
  Offset? _dragFrom;
  Offset? _dragTo;
  CupPongAimSolution? _solution;

  /// Cups mid-removal: id → 0..1 progress, plus the position they died at.
  final Map<int, double> _removal = {};
  final Map<int, Vec3> _ghostMouth = {};
  final Map<int, double> _splash = {};

  /// Cups with a ball dropping into them: id → 0..1 through the drop, plus the
  /// ball's spin so it keeps turning on the way down.
  final Map<int, double> _drop = {};
  final Map<int, double> _dropSpin = {};

  /// Seconds a made ball takes to sink from the rim to the beer and settle.
  static const double _dropSeconds = 0.40;

  /// Seconds a sunk cup takes to leave. Longer than the drop, and held
  /// stationary for the first [_removalHold] of it — a cup that starts
  /// dissolving the instant the ball crosses the rim swallows the one animation
  /// the player actually wants to watch.
  static const double _removalSeconds = 0.85;
  static const double _removalHold = 0.45;

  /// Re-rack slide: id → the mouth position the cup is sliding from.
  final Map<int, Vec3> _rerackFrom = {};
  double _rerackT = 1;

  /// The last miss, left lying on the table until the next throw.
  BallView? _resting;

  /// The transient message over the table. [GameNotice] retracts it on its own
  /// via [_noticeDismiss] — no [Timer] here, and no ticker bookkeeping either.
  ///
  /// The notice keys on the message text plus [_noticeSeq]. 'MISS' twice
  /// running is ordinary play, so the sequence number is what makes the second
  /// one a distinct event rather than a repeat of the first — the board does
  /// not have to rely on clearing the field between throws to be seen.
  String? _notice;
  GameNoticeTone _noticeTone = GameNoticeTone.info;
  bool _noticeStrong = false;
  int _noticeSeq = 0;

  /// Null for a message that stays up until something replaces it — only the
  /// end of the match earns that.
  Duration? _noticeDismiss;

  Timer? _armTimer;
  bool _celebrated = false;

  // Built in initState, never as a `late` inline initializer: dispose() touches
  // it, and a lazy initializer would build an AnimationController(vsync: this)
  // during teardown against a deactivated element.
  late final AnimationController _confettiCtrl;
  final math.Random _rnd = math.Random();
  List<_Confetto> _confetti = const [];

  bool get _hotSeat => widget.controller.hotSeat;

  static final ColorScheme _fallbackScheme =
      ColorScheme.fromSeed(seedColor: const Color(0xFF007AFF));
  ColorScheme _scheme = _fallbackScheme;

  @override
  void initState() {
    super.initState();
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _ticker = createTicker(_onTick);
    _bind();
  }

  @override
  void didUpdateWidget(covariant CupPongBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    _sub?.cancel();
    _bind();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _armTimer?.cancel();
    _ticker.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  void _bind() {
    _celebrated = false;
    _notice = null;
    _noticeDismiss = null;
    _noticeStrong = false;
    _confetti = const [];
    _removal.clear();
    _ghostMouth.clear();
    _splash.clear();
    _drop.clear();
    _dropSpin.clear();
    _rerackFrom.clear();
    _rerackT = 1;
    _resting = null;
    _sim = null;
    _phase = _Phase.aiming;
    final s = widget.controller.state;
    _state = s;
    _outcome = s == null ? null : _game.outcome(s);
    _sub = widget.controller.stateStream.listen(_onState);
  }

  // ---------------------------------------------------------------------------
  // Ticker — the only clock. Sim steps, removal + splash + re-rack animations.
  // ---------------------------------------------------------------------------

  void _wake() {
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  bool get _needsTicker =>
      _sim != null ||
      _removal.values.any((v) => v < 1) ||
      _splash.isNotEmpty ||
      _drop.isNotEmpty ||
      _rerackT < 1;

  /// Removal progress the painter sees: zero until the ball has had time to
  /// land in the beer, then a full sink over what is left.
  static double _visualRemoval(double raw) =>
      ((raw - _removalHold) / (1 - _removalHold)).clamp(0.0, 1.0);

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final step = dt.clamp(0.0, 0.05);

    _advanceSim(step);

    for (final id in _removal.keys.toList()) {
      _removal[id] = math.min(1, _removal[id]! + step / _removalSeconds);
    }
    for (final id in _drop.keys.toList()) {
      final next = _drop[id]! + step / _dropSeconds;
      // The ball keeps turning as it falls and is stilled by the beer, so the
      // spin decays with the drop rather than stopping the instant it is in.
      _dropSpin[id] = (_dropSpin[id] ?? 0) + step * 9.0 * (1 - next).clamp(0.0, 1.0);
      if (next >= 1) {
        _drop[id] = 1;
      } else {
        _drop[id] = next;
      }
    }
    for (final id in _splash.keys.toList()) {
      final next = _splash[id]! + step / 0.5;
      if (next >= 1) {
        _splash.remove(id);
      } else {
        _splash[id] = next;
      }
    }
    if (_rerackT < 1) {
      _rerackT = math.min(1, _rerackT + step / 0.5);
      if (_rerackT >= 1) _rerackFrom.clear();
    }

    if (mounted) setState(() {});
    if (!_needsTicker) _ticker.stop();
  }

  void _advanceSim(double dt) {
    final sim = _sim;
    if (sim == null) return;
    _simCarry += dt;
    final fixed = widget.tuning.config.fixedDt;
    var budget = 400; // hard cap so a stall can't spiral
    while (_simCarry >= fixed && !sim.finished && budget-- > 0) {
      _simCarry -= fixed;
      final e = sim.step();
      if (e != null) _onSimEvent(e, sim);
    }
    if (sim.finished) {
      _simCarry = 0;
      _resolve(sim);
    }
  }

  void _onSimEvent(CupPongEvent e, CupPongThrowSim sim) {
    switch (e) {
      case CupPongEvent.tableBounce:
      case CupPongEvent.rimBounce:
      case CupPongEvent.cupBounce:
        _bounceCue(sim.lastImpactSpeed);
      case CupPongEvent.made:
        widget.style.sounds.onHit?.call();
        if (widget.style.haptics) HapticFeedback.mediumImpact();
        final id = sim.hitCupId;
        if (id != null) {
          _splash[id] = 0;
          _drop[id] = 0;
          _dropSpin[id] = sim.spin;
        }
      case CupPongEvent.missed:
        break;
    }
  }

  Duration _lastBounce = Duration.zero;
  final Stopwatch _clock = Stopwatch()..start();

  /// Fired from a real swept-surface contact, never a timer, and scaled by how
  /// hard the contact actually was: a graze below [_audibleImpact] makes no
  /// sound at all, and only a genuine slam earns the heavier haptic.
  void _bounceCue(double speed) {
    if (speed < _audibleImpact) return;
    // Rim rattles can report several steps running; throttle so it reads as one
    // impact rather than a buzz.
    final now = _clock.elapsed;
    if (now - _lastBounce < const Duration(milliseconds: 80)) return;
    _lastBounce = now;
    widget.style.sounds.onBounce?.call();
    widget.style.sounds.onImpact?.call(speed);
    if (widget.style.haptics) {
      if (speed > _hardImpact) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    }
  }

  /// Below this, a contact is a graze and is silent.
  static const double _audibleImpact = 0.35;

  /// Above this, a contact is worth a heavier haptic than a tick.
  static const double _hardImpact = 2.4;

  void _resolve(CupPongThrowSim sim) {
    final state = _state;
    if (state == null) {
      _sim = null;
      return;
    }
    final owner = _acting(state);
    final move = CupPongThrow(
      owner: owner,
      target: state.opponentOf(owner),
      hitCupId: sim.hitCupId,
      ballX: sim.position.x,
      ballZ: sim.position.z,
    );

    if (sim.hitCupId == null) {
      widget.style.sounds.onMiss?.call();
      // Only a ball that actually stopped on the felt is left lying there. One
      // that rolled off an edge, or timed out mid-flight, is gone — clamping
      // its last position onto the table plane used to strand it hovering out
      // past the rail with no shadow under it.
      _resting = sim.atRest
          ? BallView(
              position: Vec3(
                sim.position.x,
                CupPongWorld.ballRadius,
                sim.position.z,
              ),
              radius: CupPongWorld.ballRadius,
              spin: sim.spin,
            )
          : null;
    } else {
      _resting = null;
    }
    _sim = null;
    _phase = _Phase.resolving;
    // "MISS" twice running is ordinary play, and the turn label used to stomp
    // it a frame later — hence a notice, and no competing turn announcement.
    if (sim.hitCupId != null) {
      _showNotice(
        'CUP!',
        tone: GameNoticeTone.score,
        after: const Duration(milliseconds: 1200),
      );
    } else {
      _showNotice(
        'MISS',
        tone: GameNoticeTone.warn,
        after: const Duration(milliseconds: 1200),
      );
    }
    widget.controller.submitMove(move);

    _armTimer?.cancel();
    _armTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() {
        if (_outcome == null) _phase = _Phase.aiming;
      });
    });
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  String _acting(CupPongState s) =>
      _hotSeat ? s.currentPlayerId : widget.controller.localPlayerId;

  /// Whose throw it is and which of their balls is in hand. Persistent state,
  /// not an event — it rides in a [GamePill] in the corner of the table rather
  /// than flashing over the middle of it.
  String _turnLabel(CupPongState s) =>
      '${_labelFor(s.currentPlayerId)} · ball ${s.ballNumber}/'
      '${CupPongGame.ballsPerTurn}';

  void _onState(CupPongState next) {
    if (!mounted) return;
    final prev = _state;
    final outcome = _game.outcome(next);

    // Cache invalidation: a removal or a re-rack changes the geometry the aim
    // solver solved against.
    _aimSolver.invalidate();

    if (prev != null) {
      for (final player in next.playerIds) {
        final before = prev.cupsOf(player);
        final after = next.cupsOf(player);
        final afterIds = {for (final c in after) c.id};
        for (final c in before) {
          if (!afterIds.contains(c.id)) {
            _removal[c.id] = 0;
            _ghostMouth[c.id] = CupPongWorld.mouthOf(c);
          }
        }
      }
      if (next.didRerack) {
        final target = _rerackTargetOf(prev, next);
        if (target != null) {
          final before = {
            for (final c in prev.cupsOf(target)) c.id: CupPongWorld.mouthOf(c),
          };
          for (final c in next.cupsOf(target)) {
            final from = before[c.id];
            if (from != null) _rerackFrom[c.id] = from;
          }
          _rerackT = 0;
          widget.style.sounds.onRerack?.call();
          _showNotice('RE-RACK', after: const Duration(milliseconds: 1600));
        }
      } else if (next.ballsBack) {
        widget.style.sounds.onBallsBack?.call();
        if (widget.style.haptics) HapticFeedback.heavyImpact();
        _showNotice(
          'BALLS BACK!',
          tone: GameNoticeTone.score,
          after: const Duration(milliseconds: 1600),
          strong: true,
        );
      }
    }

    // No turn announcement: whose ball it is now lives permanently in the
    // turn pill over the table, and a handover notice fired one frame after
    // 'MISS' — killing the one message the thrower actually wanted to read.
    if (outcome != null && !_celebrated) {
      _celebrate(outcome);
    }

    setState(() {
      _state = next;
      _outcome = outcome;
      if (outcome != null) _phase = _Phase.resolving;
    });
    _wake();
  }

  /// Which player's rack just reformed — the one whose cup count is a re-rack
  /// trigger and whose positions moved.
  String? _rerackTargetOf(CupPongState prev, CupPongState next) {
    for (final p in next.playerIds) {
      if (CupPongGame.rerackAt.contains(next.remainingOf(p)) &&
          prev.remainingOf(p) != next.remainingOf(p)) {
        return p;
      }
    }
    return null;
  }

  /// Raise a transient message over the table. [sticky] keeps it up for good —
  /// only the end of the match earns that.
  void _showNotice(
    String text, {
    GameNoticeTone tone = GameNoticeTone.info,
    Duration after = const Duration(milliseconds: 1500),
    bool strong = false,
    bool sticky = false,
  }) {
    _notice = text;
    _noticeTone = tone;
    _noticeStrong = strong;
    _noticeDismiss = sticky ? null : after;
    _noticeSeq++;
  }

  void _celebrate(GameOutcome outcome) {
    _celebrated = true;
    final style = widget.style;
    if (outcome.isDraw) {
      style.sounds.onDraw?.call();
    } else {
      style.sounds.onWin?.call();
    }
    if (style.haptics) HapticFeedback.heavyImpact();
    _showNotice(
      outcome.isDraw
          ? 'DRAW'
          : '${_labelFor(outcome.winnerId!)} wins'.toUpperCase(),
      tone: GameNoticeTone.win,
      strong: true,
      sticky: true,
    );
    if (style.confetti && !outcome.isDraw) {
      _confetti = _spawnConfetti();
      _confettiCtrl.forward(from: 0);
    }
  }

  List<_Confetto> _spawnConfetti() {
    final palette = [
      widget.style.resolvePlayer1(_scheme),
      widget.style.resolvePlayer2(_scheme),
      widget.style.resolveCup(_scheme),
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
  // Aiming
  // ---------------------------------------------------------------------------

  bool get _canThrow {
    final s = _state;
    return s != null &&
        _outcome == null &&
        _phase == _Phase.aiming &&
        widget.controller.canActLocally &&
        s.remainingOf(s.opponentOf(_acting(s))) > 0;
  }

  List<CupPongCup> get _targetRack {
    final s = _state;
    if (s == null) return const [];
    return s.cupsOf(s.opponentOf(_acting(s)));
  }

  void _panStart(DragStartDetails d) {
    if (!_canThrow) return;
    setState(() {
      _dragFrom = d.localPosition;
      _dragTo = d.localPosition;
      _solution = null;
    });
  }

  void _panUpdate(DragUpdateDetails d) {
    if (_dragFrom == null) return;
    setState(() {
      _dragTo = d.localPosition;
      _solveSwipe();
    });
  }

  /// Solve the live swipe so the release has a velocity ready. The solution is
  /// *not* drawn down-range — only its 0..1 power reaches the screen, as the
  /// ring around the ball.
  void _solveSwipe() {
    final from = _dragFrom, to = _dragTo;
    if (from == null || to == null) {
      _solution = null;
      return;
    }
    _solution = _aimSolver.solve(
      cups: _targetRack,
      dx: to.dx - from.dx,
      dy: to.dy - from.dy,
    );
  }

  void _panEnd(DragEndDetails d) {
    final sol = _solution;
    setState(() {
      _dragFrom = null;
      _dragTo = null;
      _solution = null;
    });
    if (sol == null || !_canThrow) return;
    _launch(sol);
  }

  void _launch(CupPongAimSolution sol) {
    widget.style.sounds.onThrow?.call();
    if (widget.style.haptics) HapticFeedback.mediumImpact();
    setState(() {
      _resting = null;
      _drop.clear();
      _dropSpin.clear();
      _phase = _Phase.flying;
      _simCarry = 0;
      _sim = CupPongThrowSim(
        cups: _targetRack,
        velocity: sol.velocity,
        tuning: widget.tuning,
      );
      // The table clears as the ball leaves the hand. This is also what lets
      // the next 'MISS' show at all: the notice latches a message it has
      // auto-dismissed, and nulling the field is what releases the latch.
      _notice = null;
      _noticeDismiss = null;
    });
    _wake();
  }

  // ---------------------------------------------------------------------------
  // View assembly
  // ---------------------------------------------------------------------------

  CupPongView _buildView() {
    final s = _state;
    if (s == null) return CupPongView.empty;

    final cups = <CupView>[];
    for (final c in _targetRack) {
      var mouth = CupPongWorld.mouthOf(c);
      final from = _rerackFrom[c.id];
      if (from != null && _rerackT < 1) {
        final t = Curves.easeOutCubic.transform(_rerackT);
        mouth = Vec3(
          from.x + (mouth.x - from.x) * t,
          mouth.y,
          from.z + (mouth.z - from.z) * t,
        );
      }
      cups.add(CupView(
        id: c.id,
        mouth: mouth,
        mouthRadius: CupPongWorld.cupMouthRadius,
        baseRadius: CupPongWorld.cupBaseRadius,
        height: CupPongWorld.cupHeight,
        splash: _splash[c.id] ?? 0,
        drop: _drop[c.id],
        dropSpin: _dropSpin[c.id] ?? 0,
      ));
    }
    // Cups that were sunk keep drawing, sinking and fading, until done.
    for (final e in _removal.entries) {
      if (e.value >= 1) continue;
      final mouth = _ghostMouth[e.key];
      if (mouth == null) continue;
      cups.add(CupView(
        id: e.key,
        mouth: mouth,
        mouthRadius: CupPongWorld.cupMouthRadius,
        baseRadius: CupPongWorld.cupBaseRadius,
        height: CupPongWorld.cupHeight,
        removal: _visualRemoval(e.value),
        splash: _splash[e.key] ?? 0,
        drop: _drop[e.key],
        dropSpin: _dropSpin[e.key] ?? 0,
      ));
    }

    final sim = _sim;
    final BallView? ball;
    if (sim != null) {
      ball = BallView(
        position: sim.position,
        radius: CupPongWorld.ballRadius,
        spin: sim.spin,
      );
    } else if (_outcome == null) {
      // The next ball is presented the instant the last one resolves. Blanking
      // it for the arm delay left the foreground empty for half a second, which
      // is precisely the window in which the player wonders what they throw.
      ball = const BallView(
        position: CupPongWorld.launchPoint,
        radius: CupPongWorld.ballRadius,
        inHand: true,
      );
    } else {
      ball = null;
    }

    final sol = _solution;
    final from = _dragFrom, to = _dragTo;
    return CupPongView(
      cups: cups,
      ball: ball,
      restingBalls: _resting == null ? const [] : [_resting!],
      aim: sol == null || from == null || to == null
          ? null
          : AimView(power: sol.power, flick: to - from),
    );
  }

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
    _scheme = scheme;
    final style = widget.style;
    final state = _state;
    if (state == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final p1 = state.playerIds.first;
    final p2 = state.playerIds.last;
    final acting = _acting(state);
    final defender = state.opponentOf(acting);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: Color.lerp(style.roomColor, Colors.black, 0.35),
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
          // The rack you are throwing at.
          Row(
            children: [
              Flexible(
                child: _PlayerChip(
                  label: _labelFor(defender),
                  remaining: state.remainingOf(defender),
                  accent: style.colorFor(scheme, defender, state.playerIds),
                  cupColor: style.resolveCup(scheme),
                  active: false,
                  winner: _outcome?.winnerId == defender,
                ),
              ),
              const Spacer(),
              _BallDots(
                thrown: state.ballsThrown,
                total: CupPongGame.ballsPerTurn,
                color: style.resolveBall(scheme),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
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
                      child: CustomPaint(
                        painter: _CupPongPainter(
                          view: _buildView(),
                          style: style,
                          scheme: scheme,
                        ),
                        size: Size.infinite,
                      ),
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
                  if (_outcome == null)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: IgnorePointer(
                        child: GamePill(
                          text: _turnLabel(state),
                          accent: style.colorFor(
                            scheme,
                            state.currentPlayerId,
                            state.playerIds,
                          ),
                          dot: true,
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        // One animating node. 'MISS' twice running is ordinary
                        // play, and an AnimatedSwitcher keyed on the text put
                        // two live 'MISS' children in its Stack and threw
                        // "Duplicate keys found" on the second one.
                        child: GameNotice(
                          message: _notice,
                          tone: _noticeTone,
                          strong: _noticeStrong,
                          autoDismiss: _noticeDismiss,
                          token: _noticeSeq,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _outcome != null
                ? 'Tap New game to play again'
                : (_canThrow
                    ? 'Swipe up from the ball to throw — '
                        'angle steers, length powers'
                    : 'Throwing…'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          // Whose throw it is.
          Row(
            children: [
              Flexible(
                child: _PlayerChip(
                  label: _labelFor(p1),
                  remaining: state.remainingOf(p1),
                  accent: style.resolvePlayer1(scheme),
                  cupColor: style.resolveCup(scheme),
                  active: _outcome == null && state.currentPlayerId == p1,
                  winner: _outcome?.winnerId == p1,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: _PlayerChip(
                  label: _labelFor(p2),
                  remaining: state.remainingOf(p2),
                  accent: style.resolvePlayer2(scheme),
                  cupColor: style.resolveCup(scheme),
                  active: _outcome == null && state.currentPlayerId == p2,
                  winner: _outcome?.winnerId == p2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Thin `CustomPainter` shell — all the drawing lives in the pure
/// [paintCupPongTable] so the same scene can be rendered from a test.
class _CupPongPainter extends CustomPainter {
  final CupPongView view;
  final CupPongStyle style;
  final ColorScheme scheme;

  const _CupPongPainter({
    required this.view,
    required this.style,
    required this.scheme,
  });

  @override
  void paint(Canvas canvas, Size size) =>
      paintCupPongTable(canvas, size, view, style, scheme);

  @override
  bool shouldRepaint(_CupPongPainter old) =>
      !identical(old.view, view) || old.style != style;
}

// ---------------------------------------------------------------------------
// Chrome
// ---------------------------------------------------------------------------

/// Two dots showing how many of this turn's balls are still in hand.
class _BallDots extends StatelessWidget {
  final int thrown;
  final int total;
  final Color color;

  const _BallDots({
    required this.thrown,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < total - thrown
                    ? color
                    : Colors.white.withValues(alpha: 0.16),
              ),
            ),
          ),
      ],
    );
  }
}

class _PlayerChip extends StatelessWidget {
  final String label;
  final int remaining;
  final Color accent;
  final Color cupColor;
  final bool active;
  final bool winner;

  const _PlayerChip({
    required this.label,
    required this.remaining,
    required this.accent,
    required this.cupColor,
    required this.active,
    required this.winner,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
              border: Border.all(color: Colors.black26),
              gradient: RadialGradient(
                center: const Alignment(-0.35, -0.4),
                colors: [Color.lerp(accent, Colors.white, 0.45)!, accent],
              ),
            ),
          ),
          const SizedBox(width: 7),
          // Flexible + ellipsis: two chips share one row, and a long player
          // name must shrink rather than overflow it.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                color:
                    Colors.white.withValues(alpha: active || winner ? 1 : 0.7),
                fontWeight: active || winner ? FontWeight.w800 : FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Icon(Icons.local_drink, size: 13, color: cupColor),
          const SizedBox(width: 3),
          Text(
            '$remaining',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14.5,
            ),
          ),
        ],
      ),
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
              center: Offset.zero,
              width: dim,
              height: dim * 0.55,
            ),
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
