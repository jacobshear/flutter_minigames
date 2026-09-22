import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_minigames/src/engine3d/engine3d.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

import 'basketball_court.dart';
import 'basketball_game.dart';
import 'basketball_scoreboard.dart';
import 'basketball_shot.dart';
import 'basketball_sim.dart';
import 'basketball_style.dart';
import 'basketball_view.dart';

/// A compressed, intelligent replay of one player's already-finished round.
///
/// This is not a real-time re-run — a 45 s round replayed frame-for-frame
/// would be exactly as long as the live round. Instead it re-flies each
/// logged [BasketballShot] through the same [BasketballRoundSim] the board
/// runs (so a make looks and lands exactly as it did live), but cuts the dead
/// time between shots: the next ball releases shortly after the last one
/// resolves, runs of misses get skipped through with a quick fade, and the
/// whole thing is budgeted to land around [capSeconds] regardless of how many
/// balls the round actually threw.
///
/// Fast-forward ([RoundReplayController] / [ReplayTimeDilation]) needs no
/// extra plumbing here: every frame's `dt` comes from this widget's own
/// [Ticker], and `Ticker` already divides its elapsed timestamp by the global
/// `timeDilation` before it reaches [_onTick] — feeding that (already
/// dilated) `dt` into [BasketballRoundSim.advance] is what makes the physics
/// itself run faster, not just the paint rate. (This is the "steps by
/// elapsed time" case the shared doc calls out — `advance` is not a
/// fixed-steps-per-tick sim, so [ReplayTimeDilation.stepsPerTick] does not
/// apply here.)
///
/// A [state] whose [BasketballState.shotsOf] for [playerId] is empty — a
/// LEGACY match played before shot logging existed — gets no flight replay at
/// all: just a short final-score reveal, then [RoundReplayController.markFinished].
class BasketballRoundReplay extends StatefulWidget {
  final BasketballGame game;
  final BasketballState state;

  /// Whose round is being replayed.
  final String playerId;

  /// Who is watching. Not used to gate anything today — kept so a host can
  /// tell "replaying your own round" from "replaying the opponent's" without
  /// threading a second flag through, and so haptics (deliberately not fired
  /// here — see [_onHit]) have a documented reason not to depend on it later.
  final String viewerId;

  final RoundReplayController controller;

  /// Match-level rig behaviour, chosen at match creation — not part of
  /// [BasketballState], so it must be passed in exactly as it was to the live
  /// [BasketballRoundBoard]. A mismatch only matters for
  /// [BasketballHoopMode.moving]: the hoop's lateral position at a given
  /// round-clock time depends on it, so a wrong mode replays a moving-hoop
  /// round against the wrong rim position.
  final BasketballHoopMode mode;

  final BasketballStyle style;

  const BasketballRoundReplay({
    super.key,
    required this.game,
    required this.state,
    required this.playerId,
    required this.viewerId,
    required this.controller,
    this.mode = BasketballHoopMode.normal,
    this.style = const BasketballStyle(),
  });

  /// Total on-screen runtime this widget aims for, compressing gaps and then
  /// skipping runs of misses to stay under it. A round that is short to begin
  /// with finishes sooner than this — it is a ceiling, not a target.
  static const double capSeconds = 15.0;

  @override
  State<BasketballRoundReplay> createState() => _BasketballRoundReplayState();
}

/// One shot's slot in the compressed timeline.
class _PlannedShot {
  final BasketballShot shot;
  final double holdSeconds;
  final bool fastCut;
  final bool roundTransitionBefore;

  const _PlannedShot({
    required this.shot,
    required this.holdSeconds,
    required this.fastCut,
    required this.roundTransitionBefore,
  });
}

class _BasketballRoundReplayState extends State<BasketballRoundReplay>
    with TickerProviderStateMixin {
  // Built in initState, NOT as a `late final x = AnimationController(...)`
  // inline initializer — see BasketballRoundBoard for why: a field
  // initializer that first runs during dispose() touches a deactivated
  // element and throws.
  late final AnimationController _entrance;
  late final AnimationController _flash;
  late final Ticker _ticker;

  late final List<_PlannedShot> _plan;
  late bool _legacy;
  late BasketballRoundSim _sim;

  /// Which round [_sim] currently represents, or -1 before the first shot has
  /// been set up.
  int _simRound = -1;

  int _planIndex = 0;
  double _holdRemaining = 0;
  bool _currentFastCut = false;
  bool _awaitingTransition = false;
  bool _awaitingFinalReveal = false;
  bool _finished = false;

  /// Makes already locked in from completed rounds. [_liveScore] adds the
  /// sim's in-progress round tally on top while one is in flight.
  int _bankedScore = 0;

  Duration _lastTick = Duration.zero;

  String? _notice;
  GameNoticeTone _noticeTone = GameNoticeTone.info;
  bool _noticeStrong = false;
  double _noticeTtl = 0;

  /// Bumped on every [_showNotice] call and passed to [GameNotice] as its
  /// `token` — see [BasketballRoundBoard] for why an identical repeated
  /// message needs this to re-fire as its own occurrence.
  int _noticeSeq = 0;

  double _lastImpactCue = -1;
  double _fadeOpacity = 0;

  final List<Vec3> _trail = [];
  int? _trailBallId;

  // --------------------------------------------------------------- timing

  static const double _madeHoldSeconds = 0.62;
  static const double _missHoldSeconds = 0.50;
  static const double _fastMissHoldSeconds = 0.14;
  static const double _roundTransitionHoldSeconds = 0.45;
  static const double _finalRevealHoldSeconds = 0.70;
  static const double _legacyRevealHoldSeconds = 1.0;
  static const double _minHoldFloor = 0.06;
  static const double _minAudibleImpact = 0.6;
  static const double _impactCueGap = 0.085;

  /// Seconds a miss notice holds — shorter than a make's 0.8s, mirroring
  /// [BasketballRoundBoard.missNoticeSeconds]. Distinct from [_missHoldSeconds]
  /// above, which paces the *timeline* (how long the replay lingers on a
  /// missed shot before cutting to the next), not how long the notice text
  /// itself stays up.
  static const double _missNoticeSeconds = 0.45;

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
    widget.controller.addListener(_onControllerChanged);

    _plan = _buildPlan();
    _legacy = _plan.isEmpty;
    _sim = _freshSim();

    if (_legacy) {
      _holdRemaining = _legacyRevealHoldSeconds;
      _showNotice('FINAL', _legacyRevealHoldSeconds,
          strong: true, tone: GameNoticeTone.win);
    } else {
      _beginShot(0);
    }

    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _ticker.dispose();
    _flash.dispose();
    _entrance.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (widget.controller.skipRequested && !_finished) _finishNow();
  }

  BasketballRoundSim _freshSim() => BasketballRoundSim(
        mode: widget.mode,
        // Never consulted for a replayed shot: every ready ball is replaced
        // with the logged spawnX before shoot() is called. It only seeds the
        // cosmetic auto-respawned ball that idles on the line between shots.
        rng: math.Random(0),
        duration: widget.game.roundSeconds.toDouble(),
      );

  // ------------------------------------------------------------- planning

  /// Builds the compressed timeline once, up front: base hold times per
  /// shot, then (only if the round needs it) marking runs of misses for a
  /// fast cut, then (only if it still needs it) a uniform scale-down — the
  /// same order the spec asks for: compress gaps first, skip runs second.
  List<_PlannedShot> _buildPlan() {
    final shots = List<BasketballShot>.of(widget.state.shotsOf(widget.playerId))
      ..sort((a, b) {
        final byRound = a.round.compareTo(b.round);
        return byRound != 0 ? byRound : a.tMs.compareTo(b.tMs);
      });
    if (shots.isEmpty) return const [];

    final holds = [
      for (final s in shots) s.made ? _madeHoldSeconds : _missHoldSeconds
    ];
    final fast = List<bool>.filled(shots.length, false);

    // Runs of 2+ consecutive misses within a round get a fast cut on every
    // entry after the first — the first miss of a run still plays at normal
    // pace, so the run reads as "missing", not as a gap in the tape.
    var runStart = -1;
    for (var i = 0; i <= shots.length; i++) {
      final isMiss = i < shots.length && !shots[i].made;
      final continuesRun =
          isMiss && runStart >= 0 && shots[i].round == shots[runStart].round;
      if (continuesRun) continue;
      if (runStart >= 0 && i - runStart >= 2) {
        for (var k = runStart + 1; k < i; k++) {
          holds[k] = _fastMissHoldSeconds;
          fast[k] = true;
        }
      }
      runStart = isMiss ? i : -1;
    }

    // A "ROUND n" card before the first shot of every round after the first.
    final transitionBefore = List<bool>.filled(shots.length, false);
    var seenRound = -1;
    for (var i = 0; i < shots.length; i++) {
      if (shots[i].round != seenRound) {
        if (seenRound >= 0) transitionBefore[i] = true;
        seenRound = shots[i].round;
      }
    }

    final transitions = transitionBefore.where((t) => t).length;
    var total = _finalRevealHoldSeconds +
        holds.fold(0.0, (a, b) => a + b) +
        transitions * _roundTransitionHoldSeconds;

    // Compressing gaps plus skipping runs usually lands well under budget. A
    // very high-volume round (or a very miss-light one, which the run-skip
    // above cannot shorten) falls back to a uniform, floored scale-down so
    // the cap is never blown regardless of shot count.
    if (total > BasketballRoundReplay.capSeconds) {
      final scalable = total - _finalRevealHoldSeconds;
      final scale = scalable <= 0
          ? 1.0
          : ((BasketballRoundReplay.capSeconds - _finalRevealHoldSeconds) /
                  scalable)
              .clamp(0.0, 1.0);
      for (var i = 0; i < holds.length; i++) {
        holds[i] = math.max(_minHoldFloor, holds[i] * scale);
      }
    }

    return [
      for (var i = 0; i < shots.length; i++)
        _PlannedShot(
          shot: shots[i],
          holdSeconds: holds[i],
          fastCut: fast[i],
          roundTransitionBefore: transitionBefore[i],
        ),
    ];
  }

  // ------------------------------------------------------------------ loop

  void _onTick(Duration elapsed) {
    // The sim's own accumulator caps at 40 fixed steps (~0.33 s of physics)
    // per advance() call; 0.2 s comfortably covers up to 8x fast-forward at a
    // normal frame rate without ever asking it to make up lost time.
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.2);
    _lastTick = elapsed;

    if (widget.controller.skipRequested) {
      _finishNow();
      return;
    }
    if (_finished || dt <= 0) return;

    if (_noticeTtl > 0) {
      _noticeTtl = math.max(0, _noticeTtl - dt);
      if (_noticeTtl == 0) _notice = null;
    }

    if (_legacy) {
      _holdRemaining -= dt;
      if (_holdRemaining <= 0) {
        _finishNow();
        return;
      }
      setState(() {});
      return;
    }

    if (_awaitingTransition || _awaitingFinalReveal) {
      _holdRemaining -= dt;
      if (_holdRemaining <= 0) {
        if (_awaitingFinalReveal) {
          _finishNow();
          return;
        }
        _awaitingTransition = false;
        _beginShot(_planIndex);
      }
      setState(() {});
      return;
    }

    _sim.advance(dt, onHit: _onHit);
    _trackTrail();
    _holdRemaining -= dt;
    _fadeOpacity = _currentFastCut
        ? (1 - _holdRemaining / _plan[_planIndex].holdSeconds).clamp(0.0, 1.0) *
            0.35
        : 0.0;
    if (_holdRemaining <= 0) _advanceIndex();
    setState(() {});
  }

  void _onHit(BasketballHit hit) {
    switch (hit.kind) {
      case BasketballHitKind.made:
        widget.style.sounds.onSwish?.call();
        // No haptics: unlike the live board, this round was not shot by the
        // person holding the phone, so it should not buzz for someone else's
        // makes.
        _flash.reverse(from: 1);
        _showNotice(
          hit.ball.swish ? 'SWISH!' : 'BUCKET!',
          0.8,
          tone: GameNoticeTone.score,
        );
      case BasketballHitKind.rim:
      case BasketballHitKind.backboard:
        if (hit.speed < _minAudibleImpact) return;
        if (_cueReady) widget.style.sounds.onRim?.call(hit.speed);
      case BasketballHitKind.bounce:
        if (hit.speed < _minAudibleImpact) return;
        if (_cueReady) widget.style.sounds.onBounce?.call(hit.speed);
      case BasketballHitKind.missed:
        _showMissNotice(hit.ball.touchedIron ? 'RIM OUT' : 'AIRBALL');
      case BasketballHitKind.launch:
        break;
    }
  }

  /// Mirrors [BasketballRoundBoard._showMissNotice]: never interrupts a make
  /// or a round/final banner still showing, and never restarts on top of a
  /// miss notice already up — a fast-cut run of misses would otherwise
  /// machine-gun this capsule with a fresh pop on every skipped shot.
  void _showMissNotice(String text) {
    if (_notice != null) return;
    _showNotice(text, _missNoticeSeconds, tone: GameNoticeTone.warn);
  }

  bool get _cueReady {
    if (_sim.time - _lastImpactCue < _impactCueGap) return false;
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

  // -------------------------------------------------------------- timeline

  /// Sets up and releases the shot at [index]: rolls a fresh sim over on a
  /// round change, places a ball at the logged spawn offset (mirroring the
  /// `simulateShot` test helper), and throws it with the logged aim.
  void _beginShot(int index) {
    final planned = _plan[index];
    final shot = planned.shot;
    if (shot.round != _simRound) {
      _sim = _freshSim();
      _simRound = shot.round;
      _trail.clear();
      _trailBallId = null;
      widget.style.sounds.onWhistle?.call();
    }
    // Forward-only: a compressed hold can already have carried the clock
    // past this shot's original timestamp, and time must never run backwards
    // for a moving hoop.
    _sim.time = math.max(_sim.time, shot.tMs / 1000);
    _sim.ready = LiveBall(
      id: -1000 - shot.ballIndex,
      spawnX: shot.spawnX,
      body: Projectile(
        position: Vec3(
          shot.spawnX,
          BasketballCourt.spawnPoint.y,
          BasketballCourt.spawnPoint.z,
        ),
        velocity: Vec3.zero,
        config: BasketballCourt.throwConfig,
      ),
    );
    _sim.shoot(shot.aim);

    _planIndex = index;
    _holdRemaining = planned.holdSeconds;
    _currentFastCut = planned.fastCut;
  }

  void _advanceIndex() {
    _planIndex++;
    if (_planIndex >= _plan.length) {
      _bankRound();
      _awaitingFinalReveal = true;
      _holdRemaining = _finalRevealHoldSeconds;
      _showNotice('FINAL', _finalRevealHoldSeconds,
          strong: true, tone: GameNoticeTone.win);
      return;
    }
    final next = _plan[_planIndex];
    if (next.roundTransitionBefore) {
      _bankRound();
      _awaitingTransition = true;
      _holdRemaining = _roundTransitionHoldSeconds;
      _showNotice('ROUND ${next.shot.round + 1}', _roundTransitionHoldSeconds,
          strong: true);
    } else {
      _beginShot(_planIndex);
    }
  }

  void _bankRound() => _bankedScore += _sim.makes;

  void _finishNow() {
    if (_finished) return;
    _finished = true;
    if (mounted) {
      setState(() {
        _notice = null;
      });
    }
    // Fast-forward does not own timeDilation — the host applied it and the
    // host resets it; see ReplayTimeDilation's doc.
    widget.controller.markFinished();
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
    _noticeSeq++;
  }

  // -------------------------------------------------------------- display

  /// Running total: completed rounds' makes, plus whatever the current
  /// round's sim has landed so far. Once [_finished], the authoritative
  /// [BasketballState.scoreOf] wins outright — the on-screen number must
  /// always end on the true final score even if a replayed shot's outcome
  /// were ever to disagree with the log (it should not, physics being
  /// deterministic, but the final number is cheap insurance either way).
  int get _liveScore {
    if (_finished) return widget.state.scoreOf(widget.playerId);
    if (_legacy) return widget.state.scoreOf(widget.playerId);
    final inRound =
        (_awaitingTransition || _awaitingFinalReveal) ? 0 : _sim.makes;
    return _bankedScore + inRound;
  }

  int get _currentRound => _legacy ? 0 : math.max(_simRound, 0);

  BasketballView _buildView() {
    if (_legacy) return BasketballView.ready(mode: widget.mode);
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final playerIds = widget.state.playerIds;
    final isPlayerOne =
        playerIds.isNotEmpty && playerIds.first == widget.playerId;
    final accent = isPlayerOne
        ? style.resolvePlayer1(scheme)
        : style.resolvePlayer2(scheme);
    final other = isPlayerOne
        ? style.resolvePlayer2(scheme)
        : style.resolvePlayer1(scheme);
    final otherId = playerIds.firstWhere(
      (id) => id != widget.playerId,
      orElse: () => widget.playerId,
    );
    final playerLabel = isPlayerOne ? style.player1Label : style.player2Label;
    final opponentLabel = isPlayerOne ? style.player2Label : style.player1Label;
    final secondsLeft = _legacy
        ? 0
        : (widget.game.roundSeconds - _sim.time)
            .ceil()
            .clamp(0, widget.game.roundSeconds);

    return AnimatedBuilder(
      animation: Listenable.merge([_entrance, _flash]),
      builder: (context, _) {
        final enter = Curves.easeOutCubic.transform(_entrance.value);
        return Opacity(
          opacity: enter.clamp(0.0, 1.0),
          child: Column(
            children: [
              BasketballScoreboard(
                leftLabel: playerLabel,
                rightLabel: opponentLabel,
                leftScore: _liveScore,
                rightScore: widget.state.scoreOf(otherId),
                secondsLeft: secondsLeft,
                leftAccent: accent,
                rightAccent: other,
                flash: _flash.value,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ReplayCourtPainter(
                            view: _buildView(),
                            style: style,
                            scheme: scheme,
                          ),
                        ),
                      ),
                      if (_fadeOpacity > 0)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ColoredBox(
                              color:
                                  Colors.black.withValues(alpha: _fadeOpacity),
                            ),
                          ),
                        ),
                      if (!_legacy)
                        Positioned(
                          top: 10,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Center(
                              child: GamePill(
                                text: 'Replay · Round ${_currentRound + 1}/'
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
                            child: GameNotice(
                              message: _notice,
                              tone: _noticeTone,
                              strong: _noticeStrong,
                              accent: _noticeTone == GameNoticeTone.score
                                  ? null
                                  : accent,
                              token: _noticeSeq,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _ReplayCourtPainter extends CustomPainter {
  final BasketballView view;
  final BasketballStyle style;
  final ColorScheme scheme;

  _ReplayCourtPainter({
    required this.view,
    required this.style,
    required this.scheme,
  });

  @override
  void paint(Canvas canvas, Size size) =>
      paintBasketballCourt(canvas, size, view, style, scheme);

  @override
  bool shouldRepaint(_ReplayCourtPainter old) => true;
}
