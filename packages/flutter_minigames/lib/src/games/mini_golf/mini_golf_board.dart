import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/src/engine3d/engine3d.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

import 'mini_golf_camera.dart';
import 'mini_golf_course.dart';
import 'mini_golf_game.dart';
import 'mini_golf_render.dart';
import 'mini_golf_sim.dart';
import 'mini_golf_style.dart';
import 'mini_golf_view.dart';
import 'mini_golf_world.dart';

/// The 3-D mini-golf board, wired to a [MatchController].
///
/// ## Simulate on release, play the recording back
///
/// A putt is simulated **in full** the moment you let go ([MiniGolfPutt]), which
/// returns the whole roll as a recorded path plus the events that happened along
/// it. A ticker then walks that recording, and every frame is
/// [paintMiniGolfScene] over a plain value object. Three things fall out of
/// that: the frame you see is the outcome the reducer receives (they cannot
/// drift), sounds fire on the sample the simulation actually produced them on
/// rather than off a timer, and any frame of any hole can be rendered headlessly
/// in a test.
///
/// ## The camera
///
/// A [MiniGolfCamera] rig, driven by its own [Ticker] and a small phase machine
/// (preview → aim → flight → settle → aim). The rig is purely *derived* — it
/// reads the ball, its velocity and the phase, and never consumes or perturbs
/// the aim drag. During a drag it is frozen outright, so the mapping from
/// screen to green cannot shift under the player's finger mid-shot.
///
/// Multi-hole hot-seat: on each hole Player 1 putts to the cup, then a handoff
/// cover for Player 2 on the same hole, then the match advances to the next
/// (distinct) hole. A running scorecard is always visible; the match ends with a
/// full per-hole scorecard and winner banner. Fewest total strokes wins.
class MiniGolfBoard extends StatefulWidget {
  final MatchController<MiniGolfState, MiniGolfMove> controller;
  final MiniGolfStyle style;

  const MiniGolfBoard({
    super.key,
    required this.controller,
    this.style = const MiniGolfStyle(),
  });

  @override
  State<MiniGolfBoard> createState() => _MiniGolfBoardState();
}

class _MiniGolfBoardState extends State<MiniGolfBoard>
    with TickerProviderStateMixin {
  static const _game = MiniGolfGame();

  /// How far back you can pull, in world units. The full pull is a full-power
  /// putt.
  static const double _maxPull = 3.1;

  /// Shorter than that and it's a tap, not a putt.
  static const double _deadPull = 0.22;

  StreamSubscription<MiniGolfState>? _sub;
  MiniGolfState? _state;
  GameOutcome? _outcome;

  // The transient centre message. A single GameNotice owns the animation and
  // the retract timer, so repeating the same text — two "Out of bounds" in a
  // row is ordinary play — can never collide with its own outgoing copy.
  String? _notice;
  GameNoticeTone _noticeTone = GameNoticeTone.info;
  Color? _noticeAccent;
  bool _noticeStrong = false;
  bool _celebrated = false;
  String? _handoffFor;

  // Built in initState — NOT `late` inline initializers, so dispose() never
  // triggers construction of a ticker on a deactivated element.
  late final AnimationController _confettiCtrl;
  late final AnimationController _puttCtrl;

  final math.Random _rnd = math.Random();
  List<_Confetto> _confetti = const [];

  // Live putt playback.
  PuttResult? _putt;
  int _firedThrough = -1;
  int _lastSoundSample = -999;

  // Aim drag, in board-local screen coordinates.
  Offset? _dragFrom;
  Offset? _dragTo;
  Size _boardSize = Size.zero;

  // Camera rig. `_rigSize` tracks the viewport it was solved for so a rotation
  // or a resize re-seats it instead of easing across a discontinuity.
  MiniGolfCamera? _rig;
  Size _rigSize = Size.zero;
  MiniGolfCameraPhase _phase = MiniGolfCameraPhase.aim;
  bool _wantPreview = false;
  late final Ticker _cameraTicker;
  Duration _lastTick = Duration.zero;

  ColorScheme _scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3FA45A));

  bool get _hotSeat => widget.controller.hotSeat;
  bool get _rolling => _putt != null;

  @override
  void initState() {
    super.initState();
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _puttCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addListener(_onPuttTick);
    _cameraTicker = createTicker(_onCameraTick);
    _bind();
  }

  @override
  void didUpdateWidget(covariant MiniGolfBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    _sub?.cancel();
    _bind();
  }

  void _bind() {
    _celebrated = false;
    _clearNotice();
    _handoffFor = null;
    _confetti = const [];
    _putt = null;
    _dragFrom = null;
    _dragTo = null;
    _rig = null;
    _rigSize = Size.zero;
    _wantPreview = widget.style.previewPan;
    _phase = _wantPreview
        ? MiniGolfCameraPhase.preview
        : MiniGolfCameraPhase.aim;
    final s = widget.controller.state;
    _state = s;
    _outcome = s == null ? null : _game.outcome(s);
    if (s != null) {
      // Hole, par and stroke number are standing facts: they live in the
      // header hole chip and the on-course stroke pill, not in a message.
      if (_outcome != null) _celebrated = true;
    }
    _sub = widget.controller.stateStream.listen(_onState);
    _pumpCamera();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _cameraTicker.dispose();
    _confettiCtrl.dispose();
    _puttCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Chrome
  // ---------------------------------------------------------------------------

  /// The standing stroke label: which shot the player is standing over.
  String _strokePill(MiniGolfState s) =>
      'Stroke ${s.holeStrokesOf(s.currentPlayerId) + 1}';

  /// Raises the centre notice. Assigns synchronously — callers own the
  /// surrounding setState; [GameNotice.autoDismiss] retracts it.
  void _showNotice(
    String text, {
    GameNoticeTone tone = GameNoticeTone.info,
    Color? accent,
    bool strong = false,
  }) {
    _notice = text;
    _noticeTone = tone;
    _noticeAccent = accent;
    _noticeStrong = strong;
  }

  void _clearNotice() {
    _notice = null;
    _noticeStrong = false;
  }

  /// Seat colour, resolved against the cached scheme.
  Color _accentFor(String playerId) {
    final s = _state;
    final isP1 = s == null || playerId == s.playerIds.first;
    return isP1
        ? widget.style.resolvePlayer1(_scheme)
        : widget.style.resolvePlayer2(_scheme);
  }

  String _actingFor(MiniGolfState s) =>
      _hotSeat ? s.currentPlayerId : widget.controller.localPlayerId;

  String _labelFor(String playerId) {
    final s = _state;
    if (s == null) return playerId;
    return playerId == s.playerIds.first
        ? widget.style.player1Label
        : widget.style.player2Label;
  }

  // ---------------------------------------------------------------------------
  // Putting
  // ---------------------------------------------------------------------------

  MiniGolfCourse? get _course => _state?.currentCourse;

  /// The acting player's ball, world `(x, z)`.
  Offset? get _ballXZ {
    final s = _state;
    if (s == null) return null;
    final w = s.ballWorld(_actingFor(s));
    return Offset(w.x, w.z);
  }

  /// The camera the painter used for this frame — the *same* rig, so a drag
  /// maps onto exactly the ground the player is looking at.
  Camera3? _camera() {
    final rig = _rig;
    if (rig == null || _boardSize.isEmpty) return null;
    return rig.toCamera(_boardSize);
  }

  // ---------------------------------------------------------------------------
  // Camera rig
  // ---------------------------------------------------------------------------

  /// The ball's velocity at the current playback frame, from the recorded path.
  /// Two consecutive samples at a known rate — no differentiation of a smoothed
  /// signal, so the look-ahead can't wobble.
  Offset _liveVelocity() {
    final putt = _putt;
    if (putt == null || putt.path.length < 2) return Offset.zero;
    final last = putt.path.length - 1;
    final i = (_puttCtrl.value * last).round().clamp(0, last);
    final j = i >= last ? last : i + 1;
    if (j == i) return Offset.zero;
    final a = putt.path[i].position;
    final b = putt.path[j].position;
    return Offset(
      (b.x - a.x) * PuttResult.sampleHz,
      (b.z - a.z) * PuttResult.sampleHz,
    );
  }

  MiniGolfCamera _cameraTarget(MiniGolfCourse course) =>
      MiniGolfCamera.targetFor(
        viewport: _boardSize,
        course: course,
        ball: _liveBallXZ ?? course.tee,
        phase: _phase,
        velocity: _phase == MiniGolfCameraPhase.flight
            ? _liveVelocity()
            : Offset.zero,
      );

  /// The rig for this frame, seeded on first build (and after a resize) so the
  /// camera never eases in from a stale viewport's solution.
  MiniGolfCamera _ensureRig(MiniGolfCourse course, Offset ball) {
    var rig = _rig;
    if (rig != null && _rigSize == _boardSize) return rig;
    rig = _wantPreview
        ? MiniGolfCamera.previewStart(viewport: _boardSize, course: course)
        : MiniGolfCamera.targetFor(
            viewport: _boardSize,
            course: course,
            ball: ball,
            phase: MiniGolfCameraPhase.aim,
          );
    _wantPreview = false;
    _rig = rig;
    _rigSize = _boardSize;
    return rig;
  }

  /// Start the rig ticking. Stopped again as soon as it has arrived, so a board
  /// sitting at aim isn't repainting sixty times a second for nothing.
  void _pumpCamera() {
    // Only reset the clock when actually (re)starting: a Ticker's `elapsed`
    // keeps counting, so zeroing it on a live ticker would hand the next step a
    // dt of several seconds.
    if (_cameraTicker.isActive) return;
    _lastTick = Duration.zero;
    _cameraTicker.start();
  }

  void _onCameraTick(Duration elapsed) {
    if (!mounted) return;
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;
    // Clamp so a stalled frame eases rather than teleports.
    _stepCamera(math.min(dt, 1 / 15));
  }

  void _stepCamera(double dt) {
    final course = _course;
    final rig = _rig;
    // Frozen while the player is dragging: the camera must never move the
    // ground out from under an aim in progress.
    if (course == null || rig == null || _boardSize.isEmpty) return;
    if (_dragFrom != null) return;

    final target = _cameraTarget(course);
    final next = rig.step(target, _phase, dt);
    // `identical` means the aim dead zone swallowed the step — that counts as
    // arrived, otherwise the ticker would spin forever a dead-zone away.
    final arrived =
        identical(next, rig) || next.settledOn(target, epsilon: 0.08);
    setState(() => _rig = next);

    switch (_phase) {
      case MiniGolfCameraPhase.preview:
      case MiniGolfCameraPhase.settle:
        if (arrived) _phase = MiniGolfCameraPhase.aim;
      case MiniGolfCameraPhase.aim:
        if (arrived && !_rolling) _cameraTicker.stop();
      case MiniGolfCameraPhase.flight:
        break;
    }
  }

  Offset? get _liveBallXZ {
    final putt = _putt;
    if (putt != null) {
      final s = putt.sampleAt(_puttCtrl.value * _puttDuration);
      return Offset(s.position.x, s.position.z);
    }
    return _ballXZ;
  }

  double get _puttDuration {
    final putt = _putt;
    if (putt == null) return 0;
    return (putt.path.length - 1) / PuttResult.sampleHz;
  }

  bool get _canAim {
    final s = _state;
    if (s == null || _outcome != null) return false;
    if (_rolling || _handoffFor != null) return false;
    return !s.holedOutOf(_actingFor(s));
  }

  /// Where a board-local touch lands on the green, world `(x, z)`.
  Offset? _ground(Offset local) {
    final cam = _camera();
    if (cam == null) return null;
    final hit = cam.screenToGround(local, planeY: MiniGolfWorld.groundY);
    if (hit == null) return null;
    return Offset(hit.x, hit.z);
  }

  ({Offset direction, double power, Offset pullTo})? get _aim {
    final from = _dragFrom;
    final to = _dragTo;
    final ball = _ballXZ;
    if (from == null || to == null || ball == null) return null;
    final a = _ground(from);
    final b = _ground(to);
    if (a == null || b == null) return null;
    final pull = b - a;
    final len = pull.distance;
    if (len < _deadPull) return null;
    // Slingshot: you drag *back*, the ball goes the other way.
    final dir = -pull / len;
    final power = (len / _maxPull).clamp(0.0, 1.0);
    return (direction: dir, power: power, pullTo: ball + pull);
  }

  void _panStart(DragStartDetails d) {
    if (!_canAim) return;
    // Touch interrupts any cinematic: snap to the aim framing, then hold the
    // camera perfectly still for the duration of the drag.
    final course = _course;
    final ball = _ballXZ;
    if (course != null && ball != null && !_boardSize.isEmpty) {
      _phase = MiniGolfCameraPhase.aim;
      _rig = MiniGolfCamera.targetFor(
        viewport: _boardSize,
        course: course,
        ball: ball,
        phase: MiniGolfCameraPhase.aim,
      );
      _rigSize = _boardSize;
      _wantPreview = false;
      _cameraTicker.stop();
    }
    setState(() {
      _dragFrom = d.localPosition;
      _dragTo = d.localPosition;
    });
  }

  void _panUpdate(DragUpdateDetails d) {
    if (_dragFrom == null) return;
    setState(() => _dragTo = d.localPosition);
  }

  void _panEnd(DragEndDetails d) {
    final aim = _aim;
    setState(() {
      _dragFrom = null;
      _dragTo = null;
    });
    if (aim == null || !_canAim) {
      _pumpCamera();
      return;
    }
    _launch(aim.direction, aim.power);
  }

  void _launch(Offset direction, double power) {
    final course = _course;
    final ball = _ballXZ;
    if (course == null || ball == null) return;
    final result = MiniGolfPutt.simulate(
      course: course,
      from: ball,
      direction: direction,
      power: power,
    );
    _firedThrough = -1;
    _lastSoundSample = -999;
    _putt = result;
    _puttCtrl.duration = Duration(
      milliseconds: math.max(120, (_durationOf(result) * 1000).round()),
    );
    _clearNotice();
    _phase = MiniGolfCameraPhase.flight;
    _pumpCamera();
    setState(() {});
    _puttCtrl.forward(from: 0).whenCompleteOrCancel(_settlePutt);
  }

  double _durationOf(PuttResult r) => (r.path.length - 1) / PuttResult.sampleHz;

  void _onPuttTick() {
    final putt = _putt;
    if (putt == null || !mounted) return;
    final index =
        (_puttCtrl.value * (putt.path.length - 1)).round().clamp(0, 1 << 30);
    for (final e in putt.events) {
      if (e.sample <= _firedThrough || e.sample > index) continue;
      _fire(e);
    }
    _firedThrough = index;
    setState(() {});
  }

  void _fire(PuttEvent e) {
    if (!mounted) return;
    final style = widget.style;
    switch (e.kind) {
      case PuttEventKind.launch:
        style.sounds.onPutt?.call();
        if (style.haptics) HapticFeedback.mediumImpact();
      case PuttEventKind.rail:
      case PuttEventKind.obstacle:
      case PuttEventKind.lipOut:
        // A graze is not a bang. The simulator measures how fast the ball went
        // into the surface, so a nudge stays silent, a firm bank clacks, and
        // the haptic is graded — the package's sound hooks take no arguments,
        // so weight is expressed by gating and by feel rather than by volume.
        if (e.strength < 0.06) return;
        if (e.sample - _lastSoundSample < 5) return;
        _lastSoundSample = e.sample;
        style.sounds.onWallHit?.call();
        if (!style.haptics) break;
        if (e.strength > 0.5) {
          HapticFeedback.mediumImpact();
        } else if (e.strength > 0.2) {
          HapticFeedback.lightImpact();
        } else {
          HapticFeedback.selectionClick();
        }
      case PuttEventKind.rattle:
        // The ball clattering round the inside of the cup: felt, not heard —
        // the bank clip would read as another rail hit.
        if (style.haptics && e.strength > 0.12) HapticFeedback.lightImpact();
      case PuttEventKind.sink:
        style.sounds.onSink?.call();
        if (style.haptics) HapticFeedback.mediumImpact();
      case PuttEventKind.rest:
      case PuttEventKind.outOfBounds:
        style.sounds.onRest?.call();
        if (style.haptics) HapticFeedback.selectionClick();
      case PuttEventKind.drop:
        break;
    }
  }

  /// Playback finished: fire anything left, package the outcome and submit it.
  void _settlePutt() {
    // Also reached when the controller is cancelled mid-roll (a rebind, or the
    // board being torn down), so bail before touching the controller.
    if (!mounted) {
      _putt = null;
      return;
    }
    final putt = _putt;
    final s = _state;
    final course = _course;
    if (putt == null || s == null || course == null) return;
    for (final e in putt.events) {
      if (e.sample > _firedThrough) _fire(e);
    }
    _firedThrough = putt.path.length;

    final owner = _actingFor(s);
    final n = course.normalize(putt.settled);
    final move = MiniGolfMove(
      owner: owner,
      ballNx: n.dx,
      ballNy: n.dy,
      sunk: putt.sunk,
      outOfBounds: putt.outOfBounds,
    );
    _putt = null;
    _phase = MiniGolfCameraPhase.settle;
    _pumpCamera();
    final strokes = s.holeStrokesOf(owner) + 1;
    widget.controller.submitMove(move);
    if (!mounted) return;
    setState(() {
      // Only things that *happened* get a notice. An ordinary roll that ends
      // short is not news — the stroke pill on the course already ticked over.
      if (putt.sunk) {
        _showNotice(
          strokes == 1 ? 'HOLE IN ONE' : 'IN THE HOLE',
          tone: strokes == 1 ? GameNoticeTone.win : GameNoticeTone.score,
          accent: strokes == 1 ? null : _accentFor(owner),
          strong: strokes == 1,
        );
      } else if (putt.outOfBounds) {
        _showNotice('OUT OF BOUNDS', tone: GameNoticeTone.warn);
      } else {
        _clearNotice();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  void _onState(MiniGolfState next) {
    if (!mounted) return;
    final prev = _state;
    final outcome = _game.outcome(next);

    // Any change of who's up (mid-hole handoff, or a new hole handing back to
    // Player 1) raises the pass-and-play cover.
    if (prev != null &&
        outcome == null &&
        prev.currentPlayerId != next.currentPlayerId &&
        _hotSeat) {
      _handoffFor = next.currentPlayerId;
    }
    final newHole = prev != null && prev.currentHole != next.currentHole;

    if (outcome != null && !_celebrated) {
      _celebrate(outcome);
    } else if (outcome == null && _handoffFor == null && newHole) {
      // A new hole is a change of place, not a score — the header hole chip
      // carries it, so nothing is announced over the turf.
      _clearNotice();
    }

    // A new hole opens with the reveal sweep from the cup back to the tee —
    // unless a pass-and-play cover is going up, in which case _dismissHandoff
    // arms it once the next player is actually looking.
    if (newHole && _handoffFor == null && widget.style.previewPan) {
      _rig = null;
      _rigSize = Size.zero;
      _wantPreview = true;
      _phase = MiniGolfCameraPhase.preview;
    }

    setState(() {
      _state = next;
      _outcome = outcome;
    });
    _pumpCamera();
  }

  void _dismissHandoff() {
    setState(() {
      final s = _state;
      _handoffFor = null;
      if (s != null && _outcome == null) {
        _clearNotice();
        // The reveal is for the player who is about to putt, so it waits behind
        // the pass-and-play cover rather than playing to an empty room.
        if (widget.style.previewPan &&
            s.holeStrokesOf(s.currentPlayerId) == 0) {
          _rig = null;
          _rigSize = Size.zero;
          _wantPreview = true;
          _phase = MiniGolfCameraPhase.preview;
        }
      }
    });
    _pumpCamera();
  }

  void _celebrate(GameOutcome outcome) {
    _celebrated = true;
    _handoffFor = null;
    _clearNotice();
    final style = widget.style;
    if (outcome.isDraw) {
      style.sounds.onDraw?.call();
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  MiniGolfView _buildView(MiniGolfState state, ColorScheme scheme) {
    final course = state.currentCourse;
    final acting = _actingFor(state);
    final accent =
        widget.style.colorFor(scheme, acting, state.playerIds);
    final putt = _putt;

    MiniGolfBallView ball;
    if (putt != null) {
      final s = putt.sampleAt(_puttCtrl.value * _puttDuration);
      ball = MiniGolfBallView(
        position: s.position,
        spin: s.spin,
        roll: s.roll,
        accent: accent,
        holed: false,
      );
    } else if (state.holedOutOf(acting) || _outcome != null) {
      // Holed out: it is resting on the bottom of the cup, not balanced on the
      // lip. The painter draws it through the mouth, so it stays half-hidden.
      ball = MiniGolfBallView(
        position: Vec3(course.cup.dx, MiniGolfWorld.cupRestY, course.cup.dy),
        accent: accent,
        holed: true,
      );
    } else {
      final w = state.ballWorld(acting);
      ball = MiniGolfBallView(
        position: MiniGolfWorld.ballAt(Offset(w.x, w.z)),
        accent: accent,
      );
    }

    final aim = _aim;
    return MiniGolfView(
      course: course,
      ball: ball,
      rig: _ensureRig(course, Offset(ball.position.x, ball.position.z)),
      impacts: _liveImpacts(),
      aim: aim == null
          ? null
          : MiniGolfAimView(
              direction: aim.direction,
              power: aim.power,
              pullTo: aim.pullTo,
            ),
    );
  }

  /// How long a bank mark stays on the rail, in playback samples.
  static const int _scuffSamples = 22;

  /// Bank marks still fading at the current playback frame.
  ///
  /// Derived from the recorded events rather than kept as mutable state: the
  /// simulation already said where and how hard every contact was, so a scuff
  /// is a pure function of the frame index — which keeps a mid-putt frame
  /// snapshot-able and stops the marks from drifting out of step with the roll.
  List<MiniGolfImpactView> _liveImpacts() {
    final putt = _putt;
    if (putt == null) return const [];
    final index =
        (_puttCtrl.value * (putt.path.length - 1)).round().clamp(0, 1 << 30);
    final out = <MiniGolfImpactView>[];
    for (final e in putt.events) {
      if (e.kind != PuttEventKind.rail && e.kind != PuttEventKind.obstacle) {
        continue;
      }
      final age = index - e.sample;
      if (age < 0 || age > _scuffSamples) continue;
      // The ball is on the far side of the contact point from the surface, so
      // the outward direction of the mark points back at where it went.
      final ballAt = putt.path[index.clamp(0, putt.path.length - 1)].position;
      var n = Offset(ballAt.x - e.at.dx, ballAt.z - e.at.dy);
      n = n.distance < 1e-6 ? const Offset(0, 1) : n / n.distance;
      out.add(MiniGolfImpactView(
        at: e.at,
        normal: n,
        strength: e.strength,
        age: age / _scuffSamples,
      ));
    }
    return out;
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
    final hole = state.currentHole.clamp(0, state.holeCount - 1);
    final course = state.currentCourse;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: RadialGradient(
          center: const Alignment(0, -0.4),
          radius: 1.5,
          colors: [
            Color.lerp(style.resolveRough(scheme), Colors.white, 0.05)!,
            style.resolveRough(scheme),
            Color.lerp(style.resolveRough(scheme), Colors.black, 0.35)!,
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
          Row(
            children: [
              _PlayerChip(
                label: _labelFor(p1),
                total: state.totalStrokes(p1),
                accent: style.resolvePlayer1(scheme),
                active: _outcome == null && state.currentPlayerId == p1,
                winner: _outcome?.winnerId == p1,
              ),
              const Spacer(),
              _HoleChip(
                hole: hole + 1,
                holeCount: state.holeCount,
                par: course.par,
                shape: course.archetype.label,
              ),
              const Spacer(),
              _PlayerChip(
                label: _labelFor(p2),
                total: state.totalStrokes(p2),
                accent: style.resolvePlayer2(scheme),
                active: _outcome == null && state.currentPlayerId == p2,
                winner: _outcome?.winnerId == p2,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: LayoutBuilder(
                builder: (context, c) {
                  _boardSize = Size(c.maxWidth, c.maxHeight);
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: _panStart,
                          onPanUpdate: _panUpdate,
                          onPanEnd: _panEnd,
                          child: CustomPaint(
                            painter: MiniGolfScenePainter(
                              view: _buildView(state, scheme),
                              style: style,
                              scheme: scheme,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                      // Standing stroke label: which shot this player is
                      // over, in their colour. A fact, so a pill — it does not
                      // flash past and it is always there to check.
                      if (_outcome == null && _handoffFor == null)
                        Positioned(
                          left: 10,
                          top: 10,
                          child: IgnorePointer(
                            child: GamePill(
                              text: _strokePill(state),
                              accent: _accentFor(state.currentPlayerId),
                              dot: true,
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: GameNotice(
                              message: _notice,
                              tone: _noticeTone,
                              accent: _noticeAccent,
                              strong: _noticeStrong,
                              autoDismiss:
                                  const Duration(milliseconds: 1600),
                            ),
                          ),
                        ),
                      ),
                      if (_outcome != null)
                        Positioned.fill(
                          child: _ResultsOverlay(
                            state: state,
                            outcome: _outcome!,
                            style: style,
                            scheme: scheme,
                            labelFor: _labelFor,
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
                      if (_handoffFor != null)
                        Positioned.fill(
                          child: _HandoffCover(
                            label: _labelFor(_handoffFor!),
                            hole: hole + 1,
                            par: course.par,
                            accent: _handoffFor == p1
                                ? style.resolvePlayer1(scheme)
                                : style.resolvePlayer2(scheme),
                            onContinue: _dismissHandoff,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          _ScorecardStrip(
            state: state,
            style: style,
            scheme: scheme,
            outcome: _outcome,
          ),
          const SizedBox(height: 6),
          Text(
            _outcome != null
                ? 'Tap New game to play again'
                : (_handoffFor != null
                    ? 'Pass the device'
                    : (_rolling
                        ? 'Rolling…'
                        : 'Drag back from the ball to aim, release to putt')),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}

/// Paints a [MiniGolfView]. Trivial by design — all the work is in
/// [paintMiniGolfScene], which is a pure function, so this painter carries no
/// state of its own and the scene can be rendered without a widget tree.
class MiniGolfScenePainter extends CustomPainter {
  final MiniGolfView view;
  final MiniGolfStyle style;
  final ColorScheme scheme;

  const MiniGolfScenePainter({
    required this.view,
    required this.style,
    required this.scheme,
  });

  @override
  void paint(Canvas canvas, Size size) =>
      paintMiniGolfScene(canvas, size, view, style, scheme);

  @override
  bool shouldRepaint(MiniGolfScenePainter old) =>
      old.view != view || old.style != style || old.scheme != scheme;
}

// ---------------------------------------------------------------------------
// Chrome
// ---------------------------------------------------------------------------

class _HandoffCover extends StatelessWidget {
  final String label;
  final int hole;
  final int par;
  final Color accent;
  final VoidCallback onContinue;

  const _HandoffCover({
    required this.label,
    required this.hole,
    required this.par,
    required this.accent,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onContinue,
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_golf, color: accent, size: 44),
            const SizedBox(height: 12),
            Text(
              'Hole $hole · Par $par',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pass to $label',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Same hole — fewest total strokes wins',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Text(
                'Tap to continue',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// End-of-match results: a full per-hole scorecard plus the winner banner.
class _ResultsOverlay extends StatelessWidget {
  final MiniGolfState state;
  final GameOutcome outcome;
  final MiniGolfStyle style;
  final ColorScheme scheme;
  final String Function(String playerId) labelFor;

  const _ResultsOverlay({
    required this.state,
    required this.outcome,
    required this.style,
    required this.scheme,
    required this.labelFor,
  });

  @override
  Widget build(BuildContext context) {
    final banner = outcome.isDraw
        ? 'DRAW'
        : '${labelFor(outcome.winnerId!)} wins'.toUpperCase();
    return Container(
      color: Colors.black.withValues(alpha: 0.78),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events, color: Color(0xFFF4B740), size: 40),
          const SizedBox(height: 8),
          Text(
            banner,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 22,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 14),
          _ScorecardStrip(
            state: state,
            style: style,
            scheme: scheme,
            outcome: outcome,
            big: true,
          ),
        ],
      ),
    );
  }
}

/// Running scorecard: the par row plus a row per player of per-hole strokes and
/// a total. Par varies hole to hole now, so the par row earns its place.
class _ScorecardStrip extends StatelessWidget {
  final MiniGolfState state;
  final MiniGolfStyle style;
  final ColorScheme scheme;
  final GameOutcome? outcome;
  final bool big;

  const _ScorecardStrip({
    required this.state,
    required this.style,
    required this.scheme,
    required this.outcome,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final n = state.holeCount;
    final p1 = state.playerIds.first;
    final p2 = state.playerIds.last;
    final active = outcome == null ? state.currentHole : -1;
    final fs = big ? 12.0 : 9.5;

    Widget cell(String text, {bool head = false, bool hi = false, Color? c}) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(0.5),
          padding: EdgeInsets.symmetric(vertical: big ? 4 : 2),
          decoration: BoxDecoration(
            color: hi
                ? Colors.white.withValues(alpha: 0.16)
                : (head
                    ? Colors.transparent
                    : Colors.black.withValues(alpha: 0.16)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c ?? (head ? Colors.white54 : Colors.white),
              fontWeight: head ? FontWeight.w600 : FontWeight.w800,
              fontSize: fs,
            ),
          ),
        ),
      );
    }

    Widget leading(String text, {Color? c}) => SizedBox(
          width: big ? 34 : 26,
          child: Text(
            text,
            style: TextStyle(
              color: c ?? Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: fs,
            ),
          ),
        );

    String scoreFor(String p, int hole) {
      final card = state.scorecard[p] ?? const [];
      if (hole < card.length) return '${card[hole]}';
      if (hole == state.currentHole && outcome == null) {
        final s = state.holeStrokesOf(p);
        return s > 0 ? '$s' : '·';
      }
      return '·';
    }

    Widget playerRow(String p, Color accent) {
      return Row(
        children: [
          leading(
            p == p1
                ? style.player1Label.split(' ').last
                : style.player2Label.split(' ').last,
            c: accent,
          ),
          for (var h = 0; h < n; h++) cell(scoreFor(p, h), hi: h == active),
          cell('${state.totalStrokes(p)}', c: const Color(0xFFF4B740)),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            leading(''),
            for (var h = 0; h < n; h++)
              cell('${h + 1}', head: true, hi: h == active),
            cell('Tot', head: true),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            leading('Par'),
            for (var h = 0; h < n; h++)
              cell('${state.parOf(h)}', head: true, hi: h == active),
            cell('${state.totalPar}', head: true),
          ],
        ),
        const SizedBox(height: 2),
        playerRow(p1, style.resolvePlayer1(scheme)),
        const SizedBox(height: 2),
        playerRow(p2, style.resolvePlayer2(scheme)),
      ],
    );
  }
}

class _HoleChip extends StatelessWidget {
  final int hole;
  final int holeCount;
  final int par;
  final String shape;

  const _HoleChip({
    required this.hole,
    required this.holeCount,
    required this.par,
    required this.shape,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Hole $hole/$holeCount · Par $par',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          Text(
            shape,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  final String label;
  final int total;
  final Color accent;
  final bool active;
  final bool winner;

  const _PlayerChip({
    required this.label,
    required this.total,
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
              border: Border.all(color: Colors.black26),
              gradient: RadialGradient(
                center: const Alignment(-0.35, -0.4),
                colors: [Colors.white, accent],
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
            '$total',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
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
