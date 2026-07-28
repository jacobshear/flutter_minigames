import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

import 'darts_game.dart';
import 'darts_scene.dart';
import 'darts_style.dart';
import 'darts_throw.dart';

/// The playable darts scene, wired to a [MatchController].
///
/// Owns exactly three things the pure layers cannot: the [Ticker] that advances
/// [DartsFlight], the gesture state, and the transient chrome (pill, confetti,
/// wire wobble). Everything drawn goes through [paintDartsScene] as a
/// [DartsView], so the visuals stay snapshot-testable without this widget.
///
/// **Interaction: swipe to throw, and nothing else.** Drag up-screen from
/// anywhere and let go. The swipe's length sets how high the dart lands, its
/// angle sets how far across — see [DartsSwing], which is the whole input
/// model. Nothing is ever drawn on the board face — no cursor, no landing
/// prediction — so the only mark on the board is a dart that has already
/// arrived. While a swipe is live the scene draws the gesture itself, anchored
/// where the finger is.
///
/// **Darts stay stuck** in the board until the next throw begins, so all three
/// darts of a visit are visible together before they are pulled.
class DartsBoardWidget extends StatefulWidget {
  final MatchController<DartsState, DartsMove> controller;
  final DartsStyle style;

  const DartsBoardWidget({
    super.key,
    required this.controller,
    this.style = const DartsStyle(),
  });

  @override
  State<DartsBoardWidget> createState() => _DartsBoardWidgetState();
}

class _DartsBoardWidgetState extends State<DartsBoardWidget>
    with TickerProviderStateMixin {
  static const _game = DartsGame();

  StreamSubscription<DartsState>? _sub;
  DartsState? _state;
  GameOutcome? _outcome;

  // Assigned in initState — never `late final x = AnimationController(...)`.
  // A lazy initializer would build the controller during dispose() if it had
  // never been touched, looking up a deactivated element's ancestor.
  late final AnimationController _confettiCtrl;
  late final AnimationController _wobbleCtrl;
  late final Ticker _ticker;

  DartsFlight? _flight;
  Duration _lastTick = Duration.zero;

  final List<StuckDart> _stuck = [];
  double _wobbleX = 0;
  double _wobbleY = 0;

  /// Arrival speed of the dart that is currently settling, 0..1. Everything
  /// the impact does — the thud, the haptic, how far the beds move, how hard
  /// the shaft rings — is scaled by this, so a floated dart and a rifled one
  /// do not land the same way.
  double _wobbleStrength = 1;

  /// The live swipe: origin, current point, and the throw it describes. All
  /// null between throws — the board is clean at rest.
  Offset? _swipeFrom;
  Offset? _swipeTo;
  DartsSwing? _swing;

  // The transient centre message. A single GameNotice owns the animation and
  // the retract timer, so repeating the same text — two "MISS"es in a row is
  // ordinary play — can never collide with its own outgoing copy.
  String? _notice;
  GameNoticeTone _noticeTone = GameNoticeTone.info;
  Color? _noticeAccent;
  bool _noticeSticky = false;
  bool _noticeStrong = false;
  bool _celebrated = false;

  final math.Random _rnd = math.Random(7);
  List<_Confetto> _confetti = const [];

  @override
  void initState() {
    super.initState();
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _wobbleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _ticker = createTicker(_onTick);
    _bind();
  }

  @override
  void didUpdateWidget(covariant DartsBoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    _sub?.cancel();
    _bind();
  }

  void _bind() {
    _flight = null;
    _stuck.clear();
    _celebrated = false;
    _clearNotice();
    _confetti = const [];
    _clearSwipe();
    final s = widget.controller.state;
    _state = s;
    _outcome = s == null ? null : _game.outcome(s);
    // Whose throw it is, and how many darts are left in the visit, are
    // standing facts — they live in the header GamePill, not in a message.
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.dispose();
    _wobbleCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Rules stream
  // -------------------------------------------------------------------------

  void _onState(DartsState next) {
    if (!mounted) return;
    final outcome = _game.outcome(next);
    final fresh = next.dartsThrown == 0 && next.visit.isEmpty;
    if (fresh) {
      _stuck.clear();
      _celebrated = false;
      _confetti = const [];
    }
    if (outcome != null && !_celebrated) {
      _celebrate(outcome, next);
    } else if (outcome == null && next.lastVisit != null) {
      final v = next.lastVisit!;
      if (next.visit.isEmpty && v.darts.isNotEmpty) {
        if (v.busted) {
          widget.style.sounds.onBust?.call();
          if (widget.style.haptics) HapticFeedback.heavyImpact();
          _showNotice('BUST', tone: GameNoticeTone.warn);
        } else {
          // The visit total lands behind the third dart's announcement —
          // GameNotice queues it, so the two never fight for the same slot.
          // (The old guard only let this through when the pill happened to be
          // empty, which after an announcement it never was, so the turn total
          // was effectively never shown.)
          _showNotice(
            '${v.total} SCORED',
            tone: GameNoticeTone.score,
            accent: _colorFor(v.playerId),
            strong: v.total >= 100,
          );
        }
      }
    }
    setState(() {
      _state = next;
      _outcome = outcome;
    });
  }

  void _celebrate(GameOutcome outcome, DartsState state) {
    _celebrated = true;
    widget.style.sounds.onWin?.call();
    if (widget.style.haptics) HapticFeedback.heavyImpact();
    _showNotice(
      '${_labelFor(outcome.winnerId ?? state.currentPlayerId)} WINS'
          .toUpperCase(),
      tone: GameNoticeTone.win,
      sticky: true,
    );
    if (widget.style.confetti) {
      _confetti = _spawnConfetti();
      _confettiCtrl.forward(from: 0);
    }
  }

  /// Raises the centre notice. Assigns synchronously — callers own the
  /// surrounding setState. [sticky] holds it (the win); everything else
  /// retracts itself via [GameNotice.autoDismiss].
  void _showNotice(
    String text, {
    GameNoticeTone tone = GameNoticeTone.info,
    Color? accent,
    bool sticky = false,
    bool strong = false,
  }) {
    _notice = text;
    _noticeTone = tone;
    _noticeAccent = accent;
    _noticeSticky = sticky;
    _noticeStrong = strong;
  }

  void _clearNotice() {
    _notice = null;
    _noticeSticky = false;
    _noticeStrong = false;
  }

  String _labelFor(String playerId) {
    final s = _state;
    if (s == null) return playerId;
    return widget.style.labelFor(playerId, s.playerIds);
  }

  Color _colorFor(String playerId) {
    final s = _state;
    if (s == null) return widget.style.player1;
    return widget.style.colorFor(playerId, s.playerIds);
  }

  // -------------------------------------------------------------------------
  // Flight
  // -------------------------------------------------------------------------

  bool get _canThrow => _state != null && _outcome == null && _flight == null;

  void _onTick(Duration elapsed) {
    final flight = _flight;
    if (flight == null) return;
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    flight.advance(dt.clamp(0.0, 0.05));
    if (flight.done) {
      _land(flight.impact!);
    } else {
      setState(() {});
    }
  }

  void _throw(DartsSwing swing) {
    final state = _state;
    if (state == null || !_canThrow) return;
    // Pull the previous visit's darts the moment a new visit's first throw
    // starts, so all three stay visible until then.
    if (state.visit.isEmpty) _stuck.clear();

    final velocity = swing.velocity;
    if (velocity == null) return;

    widget.style.sounds.onThrow?.call();
    if (widget.style.haptics) HapticFeedback.mediumImpact();

    _flight = DartsFlight(velocity: velocity);
    _lastTick = Duration.zero;
    _ticker.stop();
    _ticker.start();
    setState(() {
      _clearSwipe();
      _clearNotice();
    });
  }

  void _land(DartsImpact impact) {
    _ticker.stop();
    final state = _state;
    _flight = null;
    if (state == null) return;

    final style = widget.style;
    // A dart kicked off a wire is still ringing harder than one that went
    // cleanly into sisal: it hit steel on the way in.
    final strength = impact.deflected
        ? math.min(1.0, impact.strength + 0.3)
        : impact.strength;
    if (!impact.onFloor) {
      _stuck.add(
        StuckDart(
          boardX: impact.boardX,
          boardY: impact.boardY,
          direction: impact.direction,
          color: _colorFor(state.currentPlayerId),
          hit: impact.hit,
          strength: strength,
        ),
      );
      _wobbleX = impact.boardX;
      _wobbleY = impact.boardY;
      _wobbleStrength = strength;
      _wobbleCtrl.forward(from: 0);
    }

    // The thud is chosen by how hard the dart arrived, not only by what it
    // scored: [DartsSounds.onBigScore] is the deep one, so a rifled dart gets
    // it whatever bed it found, and a floated single gets the light tick.
    if (impact.hit.isMiss) {
      style.sounds.onMiss?.call();
      if (style.haptics) HapticFeedback.selectionClick();
    } else if (impact.hit.multiplier > 1 || strength > 0.55) {
      style.sounds.onBigScore?.call();
      if (style.haptics) {
        if (strength > 0.55) {
          HapticFeedback.mediumImpact();
        } else {
          HapticFeedback.lightImpact();
        }
      }
    } else {
      style.sounds.onStick?.call();
      if (style.haptics) HapticFeedback.selectionClick();
    }

    final hit = impact.hit;
    _showNotice(
      (impact.deflected && !hit.isMiss
              ? 'OFF THE WIRE · ${hit.announcement}'
              : hit.announcement)
          .replaceAll('!', '')
          .toUpperCase(),
      tone: hit.isMiss ? GameNoticeTone.warn : GameNoticeTone.score,
      accent: hit.isMiss ? null : _colorFor(state.currentPlayerId),
      // A treble or a bull is the shot of the visit — it lands bigger.
      strong: !hit.isMiss && (hit.multiplier == 3 || hit.sector == 25),
    );
    setState(() {});

    widget.controller.submitMove(
      DartsMove(playerId: state.currentPlayerId, hit: impact.hit),
    );
  }

  // -------------------------------------------------------------------------
  // Gestures
  // -------------------------------------------------------------------------

  void _clearSwipe() {
    _swipeFrom = null;
    _swipeTo = null;
    _swing = null;
  }

  void _panStart(DragStartDetails d) {
    if (!_canThrow) return;
    setState(() {
      _clearSwipe();
      _swipeFrom = d.localPosition;
      _swipeTo = d.localPosition;
    });
  }

  void _panUpdate(DragUpdateDetails d) {
    final from = _swipeFrom;
    if (from == null) return;
    final delta = d.localPosition - from;
    // Read the swipe and hold it for the release. Nothing is simulated here:
    // the throw is only flown when the finger lifts, because nothing on the
    // board is allowed to move ahead of the dart.
    final swing = DartsSwing.read(delta.dx, delta.dy);
    setState(() {
      _swipeTo = d.localPosition;
      _swing = swing;
    });
  }

  void _panEnd(DragEndDetails d) {
    final swing = _swing;
    if (swing != null) {
      _throw(swing);
    } else {
      setState(_clearSwipe);
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  List<_Confetto> _spawnConfetti() {
    final palette = [
      widget.style.player1,
      widget.style.player2,
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

  DartsView _buildView(DartsState state) {
    final flight = _flight;
    final settling = _wobbleCtrl.isAnimating ? 1 - _wobbleCtrl.value : 0.0;
    // Only the dart that just arrived is still ringing; the ones already in the
    // board from earlier in the visit are dead still.
    final stuck = [
      for (var i = 0; i < _stuck.length; i++)
        i == _stuck.length - 1
            ? StuckDart(
                boardX: _stuck[i].boardX,
                boardY: _stuck[i].boardY,
                direction: _stuck[i].direction,
                color: _stuck[i].color,
                hit: _stuck[i].hit,
                settle: settling,
                strength: _stuck[i].strength,
              )
            : _stuck[i],
    ];
    return DartsView(
      stuck: List.unmodifiable(stuck),
      dartPosition: flight?.position,
      dartVelocity: flight?.velocity,
      dartColor: _colorFor(state.currentPlayerId),
      swipeFrom: _swipeFrom,
      swipeTo: _swipeTo,
      power: _swing?.power ?? 0,
      wobble: settling,
      wobbleX: _wobbleX,
      wobbleY: _wobbleY,
      wobbleStrength: _wobbleStrength,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final p1 = state.playerIds.first;
    final p2 = state.playerIds.last;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _panStart,
            onPanUpdate: _panUpdate,
            onPanEnd: _panEnd,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _wobbleCtrl,
                    builder: (context, _) => CustomPaint(
                      painter: _DartsScenePainter(
                        view: _buildView(state),
                        style: style,
                        scheme: scheme,
                      ),
                      size: size,
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  top: 10,
                  // Three-up strip on a 402pt phone: the chips scale down
                  // rather than overflow, and the turn pill ellipsises.
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: _PlayerChip(
                            label: style.labelFor(p1, state.playerIds),
                            score: state.scoreOf(p1),
                            accent: style.player1,
                            active:
                                _outcome == null && state.currentPlayerId == p1,
                            winner: _outcome?.winnerId == p1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Standing turn state: whose throw, and how many darts
                      // are left in the visit. A fact, so a pill.
                      Flexible(
                        child: GamePill(
                          text: _outcome == null
                              ? '${state.dartsLeft} '
                                  '${state.dartsLeft == 1 ? 'dart' : 'darts'} left'
                              : 'Match over',
                          accent: _outcome == null
                              ? _colorFor(state.currentPlayerId)
                              : null,
                          dot: _outcome == null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: _PlayerChip(
                            label: style.labelFor(p2, state.playerIds),
                            score: state.scoreOf(p2),
                            accent: style.player2,
                            active:
                                _outcome == null && state.currentPlayerId == p2,
                            winner: _outcome?.winnerId == p2,
                          ),
                        ),
                      ),
                    ],
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
                            boardSize: size.width,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      // full-bleed Stack that stretched the capsule edge to
                      child: GameNotice(
                        message: _notice,
                        tone: _noticeTone,
                        accent: _noticeAccent,
                        strong: _noticeStrong || _noticeSticky,
                        autoDismiss: _noticeSticky
                            ? null
                            : const Duration(milliseconds: 1500),
                      ),
                    ),
                  ),
                ),
                // The visit strip lives low, over the floor: at the top it
                // would sit exactly on the 20 — the number players stare at.
                // Clear of the two-line swipe hint below it.
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 48,
                  child: IgnorePointer(
                    child: _VisitStrip(
                      state: state,
                      accent: _colorFor(state.currentPlayerId),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 8,
                  child: IgnorePointer(
                    child: Text(
                      _outcome != null
                          ? 'Tap New game to play again'
                          : (_flight != null
                              ? 'In flight…'
                              : 'Swipe up to throw\n'
                                  'Longer swipe lands higher · angle it to aim across'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _chalk.withValues(alpha: 0.62),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DartsScenePainter extends CustomPainter {
  final DartsView view;
  final DartsStyle style;
  final ColorScheme scheme;

  const _DartsScenePainter({
    required this.view,
    required this.style,
    required this.scheme,
  });

  @override
  void paint(Canvas canvas, Size size) =>
      paintDartsScene(canvas, size, view, style, scheme);

  @override
  bool shouldRepaint(_DartsScenePainter old) => true;
}

// ---------------------------------------------------------------------------
// Chrome
//
// Scored on slate. An oche keeps its numbers on a chalkboard on the wall, so
// the chips, the visit strip and the pill are slate panels with a chalk-dust
// rule round them and chalk-white figures on top — the same material the room
// is built from, rather than generic translucent black.
// ---------------------------------------------------------------------------

/// Slate the scores are chalked on.
const Color _slate = Color(0xFF1E2229);

/// Chalk, and the dust it leaves on an edge.
const Color _chalk = Color(0xFFF2EDE0);
const Color _chalkDust = Color(0x33F2EDE0);

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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: _slate.withValues(alpha: active || winner ? 0.92 : 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: winner
              ? const Color(0xFFF4B740)
              : _chalk.withValues(alpha: active ? 0.42 : 0.12),
          width: winner ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: _chalk.withValues(alpha: active || winner ? 1 : 0.65),
              fontWeight: active || winner ? FontWeight.w800 : FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          // The number left to check out is the whole game — it dominates the
          // chip rather than sitting level with the name.
          Text(
            '$score',
            style: TextStyle(
              color: _chalk,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              height: 1,
              letterSpacing: -0.8,
              shadows: active || winner
                  ? [
                      Shadow(
                          color: accent.withValues(alpha: 0.6), blurRadius: 10)
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// The three darts of the current visit, the running turn total, and the
/// checkout hint when one exists.
class _VisitStrip extends StatelessWidget {
  final DartsState state;
  final Color accent;

  const _VisitStrip({required this.state, required this.accent});

  @override
  Widget build(BuildContext context) {
    final hint = state.checkoutHint;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < state.dartsPerVisit; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _DartSlot(
                  label: i < state.visit.length ? state.visit[i].label : '–',
                  filled: i < state.visit.length,
                  accent: accent,
                ),
              ),
            const SizedBox(width: 8),
            // The running turn total, which is what a player actually watches
            // during a visit — it was set level with the dart labels beside it
            // and read as a fourth slot rather than the sum of the other three.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
              decoration: BoxDecoration(
                color: _slate.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: state.visitTotal > 0
                      ? accent.withValues(alpha: 0.8)
                      : _chalkDust,
                ),
              ),
              child: Text(
                '${state.visitTotal}',
                style: TextStyle(
                  color: _chalk,
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                  height: 1.15,
                  letterSpacing: -0.5,
                  shadows: state.visitTotal > 0
                      ? [
                          Shadow(
                              color: accent.withValues(alpha: 0.55),
                              blurRadius: 9)
                        ]
                      : null,
                ),
              ),
            ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF2E8B4F).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              'Checkout: $hint',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DartSlot extends StatelessWidget {
  final String label;
  final bool filled;
  final Color accent;

  const _DartSlot({
    required this.label,
    required this.filled,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _slate.withValues(alpha: filled ? 0.92 : 0.62),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: filled
              ? accent.withValues(alpha: 0.85)
              : _chalk.withValues(alpha: 0.12),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _chalk.withValues(alpha: filled ? 1 : 0.42),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
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
