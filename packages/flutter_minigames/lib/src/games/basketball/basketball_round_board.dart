import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/src/engine3d/engine3d.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

import 'basketball_court.dart';
import 'basketball_game.dart';
import 'basketball_scoreboard.dart';
import 'basketball_sim.dart';
import 'basketball_style.dart';
import 'basketball_view.dart';

/// One player's whole turn: both timed rounds, back to back.
///
/// Owns the simulation — a [Ticker] pumps [BasketballRoundSim] and a plain
/// [CustomPaint] draws whatever the sim currently holds. No engine, no game
/// loop framework: the scene is a pure function of the sim's state, so the same
/// frames a player sees can be rendered in a test.
///
/// The cadence is the point. A ball waits on the spawn line at a random lateral
/// offset; you flick left or right to pick its line; 250 ms later the next one
/// appears while the last is still in the air. Misses bounce and roll and hang
/// around. [onComplete] fires once, with one score per round.
class BasketballRoundBoard extends StatefulWidget {
  final BasketballGame game;

  /// Match-level rig behaviour, chosen at match creation.
  final BasketballHoopMode mode;

  /// Label on the shooting player's side of the scoreboard.
  final String playerLabel;

  /// Label on the other side.
  final String opponentLabel;

  /// The other player's total, shown live on the scoreboard (0 if they haven't
  /// shot yet).
  final int opponentScore;

  /// Which seat is shooting — tints the chip.
  final bool isPlayerOne;

  /// Seeds the spawn-offset randomiser, so a round is reproducible.
  final int seed;

  final BasketballStyle style;

  /// Fires exactly once with one score per round.
  final ValueChanged<List<int>> onComplete;

  const BasketballRoundBoard({
    super.key,
    required this.game,
    required this.playerLabel,
    required this.opponentLabel,
    required this.onComplete,
    this.mode = BasketballHoopMode.normal,
    this.opponentScore = 0,
    this.isPlayerOne = true,
    this.seed = 1,
    this.style = const BasketballStyle(),
  });

  @override
  State<BasketballRoundBoard> createState() => _BasketballRoundBoardState();
}

class _BasketballRoundBoardState extends State<BasketballRoundBoard>
    with TickerProviderStateMixin {
  // Built in initState, NOT as `late final x = AnimationController(...)` — a
  // late inline initializer runs the first time the field is touched, and
  // dispose() touches it, which would build a ticker during teardown.
  late final AnimationController _entrance;
  late final AnimationController _flash;
  late final Ticker _ticker;

  late BasketballRoundSim _sim;
  late final math.Random _rng = math.Random(widget.seed);

  final List<int> _roundScores = [];
  int _roundIndex = 0;
  bool _completed = false;

  Duration _lastTick = Duration.zero;

  /// Countdown between rounds, seconds.
  double _interlude = 0;

  /// Seconds the outro runs after the buzzer so balls in the air can land.
  double _outro = 0;

  /// The transient message over the court, and how long it has left. Nulling
  /// it out is the *only* way it leaves: [GameNotice.autoDismiss] cannot be
  /// used here because this board rebuilds every tick, and the notice
  /// re-presents itself on any rebuild that happens after it has self-retracted
  /// while the message is still non-null. Ticking a TTL costs nothing — the
  /// ticker is already running — and needs no [Timer] to cancel.
  String? _notice;
  GameNoticeTone _noticeTone = GameNoticeTone.info;
  bool _noticeStrong = false;
  double _noticeTtl = 0;

  /// Sim-time of the last bounce/rim cue, for rate limiting.
  double _lastImpactCue = -1;

  /// Recent positions of the ball currently being watched.
  final List<Vec3> _trail = [];
  int? _trailBallId;

  double _dragX = 0;
  double _dragY = 0;
  bool _dragging = false;

  /// Seconds of tail on the buzzer before the round is banked.
  static const double outroSeconds = 1.1;

  /// Seconds the "Round 2" card holds.
  static const double interludeSeconds = 1.6;

  /// Minimum gap between impact cues, seconds.
  static const double impactCueGap = 0.085;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _sim = _newSim();
    _ticker = createTicker(_onTick)..start();
    widget.style.sounds.onWhistle?.call();
    _showNotice('ROUND 1', 1.4, strong: true);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _flash.dispose();
    _entrance.dispose();
    super.dispose();
  }

  BasketballRoundSim _newSim() => BasketballRoundSim(
        mode: widget.mode,
        rng: math.Random(_rng.nextInt(1 << 31)),
        duration: widget.game.roundSeconds.toDouble(),
      );

  // ------------------------------------------------------------------- loop

  void _onTick(Duration elapsed) {
    if (_completed) return;
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _lastTick = elapsed;
    if (dt <= 0) return;

    if (_noticeTtl > 0) {
      _noticeTtl = math.max(0, _noticeTtl - dt);
      if (_noticeTtl == 0) _notice = null;
    }

    if (_interlude > 0) {
      _interlude -= dt;
      if (_interlude <= 0) _startNextRound();
      setState(() {});
      return;
    }

    _sim.advance(dt, onHit: _onHit);
    _trackTrail();

    if (_sim.expired) {
      if (_outro == 0) {
        _outro = outroSeconds;
        widget.style.sounds.onBuzzer?.call();
      } else {
        _outro -= dt;
        if (_outro <= 0) _endRound();
      }
    }
    setState(() {});
  }

  void _onHit(BasketballHit hit) {
    switch (hit.kind) {
      case BasketballHitKind.made:
        widget.style.sounds.onSwish?.call();
        // Haptics fire on your own score only — and a clean drop feels
        // different in the hand from one that rattled its way in, which is the
        // one bit of the swish/rattle distinction that survives having a single
        // net sample to play.
        if (widget.style.haptics) {
          if (hit.ball.swish) {
            HapticFeedback.lightImpact();
          } else {
            HapticFeedback.mediumImpact();
          }
        }
        // Rest at 0, spike to 1 on a make, decay back.
        _flash.reverse(from: 1);
        // Balls land in quick succession, so this message repeats constantly —
        // two swishes in a row is ordinary play, not an edge case. That is the
        // sequence an AnimatedSwitcher could not survive.
        _showNotice(
          hit.ball.swish ? 'SWISH!' : 'BUCKET!',
          0.8,
          tone: GameNoticeTone.score,
        );
      case BasketballHitKind.rim:
      case BasketballHitKind.backboard:
        if (hit.speed < minAudibleImpact) return;
        if (_cueReady) widget.style.sounds.onRim?.call(hit.speed);
      case BasketballHitKind.bounce:
        if (hit.speed < minAudibleImpact) return;
        if (_cueReady) widget.style.sounds.onBounce?.call(hit.speed);
      case BasketballHitKind.launch:
        break;
    }
  }

  /// Contacts slower than this are grazes. Gating them here rather than only
  /// rate-limiting matters: a ball settling on the floor generates a run of
  /// near-zero-speed touches, and each one used to burn the rate-limit slot
  /// that the *next real* impact needed.
  static const double minAudibleImpact = 0.6;

  /// Rate limit: a floor full of loose balls would otherwise machine-gun the
  /// same sample.
  bool get _cueReady {
    if (_sim.time - _lastImpactCue < impactCueGap) return false;
    _lastImpactCue = _sim.time;
    return true;
  }

  void _trackTrail() {
    final newest = _sim.live.isEmpty ? null : _sim.live.last;
    if (newest == null || newest.atRest) {
      if (_trail.isNotEmpty) _trail.clear();
      _trailBallId = null;
      return;
    }
    if (newest.id != _trailBallId) {
      _trailBallId = newest.id;
      _trail.clear();
    }
    _trail.add(newest.position);
    if (_trail.length > 11) _trail.removeAt(0);
  }

  // ------------------------------------------------------------- round flow

  void _endRound() {
    _roundScores.add(_sim.makes);
    _outro = 0;
    if (_roundScores.length >= BasketballGame.roundCount) {
      _completed = true;
      _ticker.stop();
      widget.onComplete(List.of(_roundScores));
      return;
    }
    _roundIndex++;
    _interlude = interludeSeconds;
    _showNotice('ROUND ${_roundIndex + 1}', interludeSeconds, strong: true);
  }

  void _startNextRound() {
    _interlude = 0;
    _trail.clear();
    _sim = _newSim();
    widget.style.sounds.onWhistle?.call();
  }

  void _endRoundEarly() {
    if (_completed || _interlude > 0) return;
    _sim.time = _sim.duration;
    _outro = 0.001;
    widget.style.sounds.onBuzzer?.call();
  }

  void _showNotice(
    String text,
    double seconds, {
    GameNoticeTone tone = GameNoticeTone.info,
    bool strong = false,
  }) {
    _notice = text;
    _noticeTone = tone;
    _noticeStrong = strong;
    _noticeTtl = seconds;
  }

  // ----------------------------------------------------------------- input

  void _panDown(DragDownDetails d) {
    _dragging = true;
    _dragX = 0;
    _dragY = 0;
  }

  void _panUpdate(DragUpdateDetails d) {
    _dragX += d.delta.dx;
    _dragY += d.delta.dy;
  }

  void _panCancel() => _dragging = false;

  void _panEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    if (_completed || _interlude > 0 || _sim.expired) return;
    // Horizontal component only: a vertical flick adds nothing, because power
    // and arc are constants.
    final aim = BasketballAim.aimFromDrag(_dragX, _dragY);
    if (aim == null) return;
    _sim.shoot(aim);
  }

  // ------------------------------------------------------------------- view

  BasketballView _buildView() {
    final balls = _sim.balls;
    var wobble = 0.0;
    for (final b in balls) {
      if (b.netWobble > wobble) wobble = b.netWobble;
    }
    return BasketballView(
      hoopCentre: _sim.hoopCentre,
      netWobble: wobble,
      trail: List.of(_trail),
      balls: [
        for (final b in balls)
          BasketballBallView(
            position: b.position,
            spin: b.spin,
            opacity: b.opacity,
            ready: identical(b, _sim.ready),
          ),
      ],
    );
  }

  int get _liveScore =>
      _roundScores.fold(0, (a, b) => a + b) + (_completed ? 0 : _sim.makes);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final accent = widget.isPlayerOne
        ? style.resolvePlayer1(scheme)
        : style.resolvePlayer2(scheme);
    final other = widget.isPlayerOne
        ? style.resolvePlayer2(scheme)
        : style.resolvePlayer1(scheme);

    return AnimatedBuilder(
      animation: Listenable.merge([_entrance, _flash]),
      builder: (context, _) {
        final enter = Curves.easeOutCubic.transform(_entrance.value);
        return Opacity(
          opacity: enter.clamp(0.0, 1.0),
          child: Column(
            children: [
              BasketballScoreboard(
                leftLabel: widget.playerLabel,
                rightLabel: widget.opponentLabel,
                leftScore: _liveScore,
                rightScore: widget.opponentScore,
                secondsLeft: _sim.remaining.ceil(),
                leftAccent: accent,
                rightAccent: other,
                flash: _flash.value,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanDown: _panDown,
                    onPanUpdate: _panUpdate,
                    onPanCancel: _panCancel,
                    onPanEnd: _panEnd,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _CourtCustomPainter(
                              view: _buildView(),
                              style: style,
                              scheme: scheme,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Center(
                              child: GamePill(
                                text: widget.mode ==
                                        BasketballHoopMode.moving
                                    ? 'Round ${_roundIndex + 1}/'
                                        '${BasketballGame.roundCount} · Moving'
                                    : 'Round ${_roundIndex + 1}/'
                                        '${BasketballGame.roundCount}',
                                accent: accent,
                                dot: true,
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Center(
                              // One animating node. "SWISH!" fires on back-to-
                              // back makes, so the message genuinely repeats
                              // inside a single exit — an AnimatedSwitcher
                              // keyed on the text put two live children in its
                              // Stack and threw "Duplicate keys found".
                              child: GameNotice(
                                message: _notice,
                                tone: _noticeTone,
                                strong: _noticeStrong,
                                accent: _noticeTone == GameNoticeTone.score
                                    ? null
                                    : accent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Drag left or right to aim, then release',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.45),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _endRoundEarly,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Text(
                        'End round',
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.4),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CourtCustomPainter extends CustomPainter {
  final BasketballView view;
  final BasketballStyle style;
  final ColorScheme scheme;

  _CourtCustomPainter({
    required this.view,
    required this.style,
    required this.scheme,
  });

  @override
  void paint(Canvas canvas, Size size) =>
      paintBasketballCourt(canvas, size, view, style, scheme);

  // The view is rebuilt every tick, so any repaint request is a real one.
  @override
  bool shouldRepaint(_CourtCustomPainter old) => true;
}

// The round counter is *present*, not an event: it is true for the whole
// round and never animates. That makes it a [GamePill]; the things that
// happen — a make, a round ending — are [GameNotice]s.
