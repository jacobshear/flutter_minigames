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
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/flame/flame.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

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

  // The transient centre message. A single GameNotice owns the animation and
  // the retract timer, so repeating the same text — "Miss" twice in a row is
  // ordinary play — can never collide with its own outgoing copy.
  String? _notice;
  GameNoticeTone _noticeTone = GameNoticeTone.info;
  Color? _noticeAccent;
  bool _noticeSticky = false;
  bool _noticeStrong = false;
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
      ..onRail = _onRail
      ..onPocket = _onPocket
      ..onShotSettled = _onShotSettled
      ..onAimChanged = () => setState(() {});
    _scene = scene;
    _celebrated = false;
    _clearNotice();
    _confetti = const [];
    final s = widget.controller.state;
    _state = s;
    _outcome = s == null ? null : _game.outcome(s);
    if (s != null) {
      scene.applyState(s, _actingFor(s));
      // Whose shot it is, and whether they have ball in hand, are standing
      // facts — they live in the header GamePill, not in a message.
      if (_outcome != null) _celebrated = true;
    }
    _sub = widget.controller.stateStream.listen(_onState);
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

  /// Seat colours, matching the chips in the header strip.
  static const _seat1 = Color(0xFFD8443C);
  static const _seat2 = Color(0xFF2E6FB0);

  Color _accentFor(String playerId) {
    final s = _state;
    return s == null || playerId == s.playerIds.first ? _seat1 : _seat2;
  }

  String _actingFor(EightBallState s) =>
      _hotSeat ? s.currentPlayerId : widget.controller.localPlayerId;

  @override
  void dispose() {
    _sub?.cancel();
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
    setState(_clearNotice);
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

  Duration _lastRail = Duration.zero;

  /// A cushion bounce, weighted by how hard the ball arrived: a graze is
  /// silent, a firm bank clacks and thumps.
  void _onRail(double strength) {
    if (!mounted) return;
    final now = _clock.elapsed;
    // A soft contact needs to be much more separated to earn a second sound
    // than a hard one — that is what stops a ball dying against a rail from
    // machine-gunning the clack.
    final gap = Duration(milliseconds: (120 - 60 * strength).round());
    if (now - _lastRail < gap) return;
    _lastRail = now;
    final sounds = widget.style.sounds;
    (sounds.onRail ?? sounds.onCollision)?.call();
    if (!widget.style.haptics) return;
    if (strength > 0.55) {
      HapticFeedback.mediumImpact();
    } else if (strength > 0.22) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.selectionClick();
    }
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

    // The seat that took the shot, read before submitMove hands the turn on.
    final shooter = _state?.currentPlayerId;
    final (text, tone) = cueScratched
        ? ('SCRATCH', GameNoticeTone.warn)
        : (newlyObject.contains(EightBallGame.eightNumber)
            ? ('8-BALL DOWN', GameNoticeTone.score)
            : (newlyObject.isNotEmpty
                ? (
                    newlyObject.length == 1
                        ? 'POTTED'
                        : 'POTTED ${newlyObject.length}',
                    GameNoticeTone.score,
                  )
                : (contactFoul
                    ? ('NO CONTACT — FOUL', GameNoticeTone.warn)
                    : ('MISS', GameNoticeTone.warn))));

    widget.controller.submitMove(move);
    if (!mounted) return;
    setState(() => _showNotice(
          text,
          tone: tone,
          // A pot wears the potter's colour, so the notice says who as well as
          // what; a foul keeps the warn red.
          accent: tone == GameNoticeTone.score && shooter != null
              ? _accentFor(shooter)
              : null,
          strong: newlyObject.contains(EightBallGame.eightNumber),
        ));
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
      // Getting a group is a one-off event worth calling out. Ball-in-hand and
      // whose-break are standing facts and read off the header pill instead.
      if (justAssigned && next.groups[acting] != null) {
        _showNotice(
          next.groups[acting] == BallGroup.solids
              ? '${_labelFor(acting).toUpperCase()} IS SOLIDS'
              : '${_labelFor(acting).toUpperCase()} IS STRIPES',
          accent: _accentFor(acting),
        );
      } else if (isFresh) {
        _clearNotice();
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
    _showNotice('${_labelFor(outcome.winnerId!)} WINS'.toUpperCase(),
        tone: GameNoticeTone.win, sticky: true);
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

  /// The standing phase line: what the table is waiting for right now.
  String _phaseText(EightBallState s) {
    if (_outcome != null) return 'Match over';
    if (s.ballInHand) return 'Ball in hand';
    if (s.shotsTaken == 0) return 'To break';
    return 'To shoot';
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
          painter: _PoolRoomPainter(scheme),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                // Both players on one strip. Stacking them above *and* below the
                // table cost ~40pt of height, and on a 2:1 portrait table height
                // is the only thing deciding how wide the table gets — that is
                // what left it stranded in the middle of the screen.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: _PlayerChip(
                        label: _labelFor(p1),
                        group: state.groups[p1],
                        remaining: state.remainingCountOf(p1),
                        accent: _seat1,
                        active: _outcome == null && state.currentPlayerId == p1,
                        winner: _outcome?.winnerId == p1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: _PlayerChip(
                        label: _labelFor(p2),
                        group: state.groups[p2],
                        remaining: state.remainingCountOf(p2),
                        accent: _seat2,
                        active: _outcome == null && state.currentPlayerId == p2,
                        winner: _outcome?.winnerId == p2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      // Fill the width on a phone; stop growing on a tablet,
                      // where a table taller than an arm's reach is no fun.
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: AspectRatio(
                        // NOT tableW/tableL: the rail band is measured off the
                        // width and eats the height too. See [boardAspect].
                        aspectRatio: EightBallScene.boardAspect,
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
                                      child: GameNotice(
                                        message: _notice,
                                        tone: _noticeTone,
                                        accent: _noticeAccent,
                                        strong: _noticeStrong || _noticeSticky,
                                        autoDismiss: _noticeSticky
                                            ? null
                                            : const Duration(
                                                milliseconds: 1800),
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
                // Standing phase beside the instruction, not squeezed into the
                // header: three chips on one 402pt strip truncated both player
                // names to "Pla…". A fact, so a pill — not a message.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GamePill(
                      text: _phaseText(state),
                      accent: _outcome == null
                          ? _accentFor(state.currentPlayerId)
                          : null,
                      dot: _outcome == null,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        hint,
                        maxLines: 2,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
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
  final ColorScheme scheme;

  const _PoolRoomPainter(this.scheme);

  @override
  void paint(Canvas canvas, Size size) =>
      paintPoolRoom(canvas, size, scheme: scheme);

  @override
  bool shouldRepaint(_PoolRoomPainter oldDelegate) =>
      oldDelegate.scheme != scheme;
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

  /// Width ÷ height the **board widget** must be given so the felt inside it
  /// comes out at exactly [tableW] : [tableL].
  ///
  /// The rail band is [poolRailFrac] of the board's *width* on all four sides,
  /// so a board sized 1:2 (the world's own ratio) leaves a felt of
  /// `0.83w × 1.83w` — 2.20:1, a 10% stretch along the table. That stretch is
  /// not cosmetic: normalized ny maps onto the felt's height, so with the wrong
  /// box the pixels-per-world-unit differ between the axes, angles come out
  /// wrong, and an aim prediction computed in world units would not line up
  /// with what is drawn. Sized to this, screen space is a plain uniform scaling
  /// of sim space.
  ///
  ///     feltH / feltW = (h - 2fw) / (w - 2fw) = tableL / tableW
  ///  ⇒  h / w = (tableL / tableW)(1 - 2f) + 2f
  static const double boardAspect =
      1 / ((tableL / tableW) * (1 - 2 * poolRailFrac) + 2 * poolRailFrac);

  /// Pockets in sim world coords: 4 corners + 2 sides.
  static const List<(double, double)> _pocketsWorld = [
    (-tableW / 2, 0),
    (tableW / 2, 0),
    (-tableW / 2, tableL),
    (tableW / 2, tableL),
    (-tableW / 2, tableL / 2),
    (tableW / 2, tableL / 2),
  ];

  /// A firm break at full power; a gentle tap at the low end. Not finely tuned —
  /// approximated for GP feel (see game doc: no spin/english modelled).
  /// Full power was 16, which measured badly: on a straight break five of the
  /// fifteen object balls finished less than a ball's width from where they
  /// were racked — the cue shoved the front of the rack and stalled. 20 opens
  /// the rack completely (every ball moves, mean travel up from 2.8 to 5.2
  /// world units) without going so fast that a ball tunnels a rail: 24 break
  /// angles at 20 produced zero escapes, and past ~22 the fixed 1/60 step
  /// starts losing energy in the pile-up and the spread gets *worse* again.
  static const aimConfig = AimToImpulse(
    maxDrag: 210,
    maxImpulse: 20,
    minImpulse: 2.5,
    deadZone: 8,
  );
  static const _aim = aimConfig;

  /// Lively rails, low rolling drag so a break scatters the whole rack.
  ///
  /// Public so the physics can be measured rather than eyeballed: the tests
  /// build the very same table through [createSim] and check the break's spread
  /// and the angle a cushion actually returns.
  static const simConfig = TableSimConfig(
    linearDamping: 0.62,
    angularDamping: 1.2,
    friction: 0.02,
    // Object balls are ivory-hard: a near-elastic ball↔ball collision is what
    // makes a break transfer its energy through the rack instead of the cue
    // shoving the front three and stopping.
    restitution: 0.94,
    // Box2D mixes restitution as `max(a, b)`, so this is a *floor*, not a cap:
    // with balls at 0.94 the cushions bounce at 0.94 whatever this says, and
    // measurement agrees (a rail returns 93–97% of the ball's speed). Making
    // rails genuinely deader than balls would mean dropping the ball figure,
    // which is what powers the break — so the rails stay lively on purpose.
    wallRestitution: 0.9,
    density: 1.0,
    settleLinearSpeed: 0.06,
    settleFrames: 16,
    maxSteps: 2600,
  );

  /// How long a ball takes to fall out of sight down a pocket, seconds.
  static const double dropSeconds = 0.52;

  /// How long a cushion takes to spring back after a strike, seconds.
  static const double impactSeconds = 0.26;

  /// The speed a cushion strike is measured against — roughly the normal speed
  /// of a firm break hitting a rail head-on. Impacts scale 0..1 against it, so
  /// both the sound gate and the compression depth track how hard the ball
  /// actually arrived.
  static const double railRefSpeed = 12.0;

  /// Below this normal speed a cushion contact is a nudge: no sound, no dent.
  static const double railQuietSpeed = 0.9;

  late TableSimulation _sim;
  EightBallState? _state;
  String _acting = '';
  DiscBody? _cue;
  bool _launched = false;
  double _accum = 0;

  int? _firstHit; // first object-ball number the cue struck this shot
  final Set<int> _pocketedIds = {};

  // Presentation-only: balls falling into pockets, cushions still relaxing, and
  // the settled outcome waiting for those drops to finish. The outcome is built
  // the instant the physics settles and only *delivered* later, so the animation
  // can never change what was potted.
  final List<_Drop> _drops = [];
  final List<_Impact> _impacts = [];
  EightBallMove? _pendingSettle;
  final Map<int, Vector2> _lastBallVel = {};

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

  /// A ball banked off a cushion, with 0..1 strength relative to [railRefSpeed].
  void Function(double strength)? onRail;
  void Function()? onAimChanged;
  void Function(EightBallMove move)? onShotSettled;

  bool get canAim =>
      _cue != null &&
      !_launched &&
      !_sim.isRunning &&
      _pendingSettle == null &&
      (_state != null && !_state!.ballInHand && !_state!.over);

  /// True while balls are still dropping into pockets after the physics settled.
  bool get isDropping => _drops.isNotEmpty;

  bool get isAiming => _aimStart != null && _aimNow != null;

  @override
  Color backgroundColor() => const Color(0xFF1A130C);

  /// Build the physical table for [state]: rails, pockets and a body per ball
  /// still on the cloth.
  ///
  /// Static and public so a test can hold the *same* table the board plays on
  /// and measure it — the break's spread and a cushion's angle of return are
  /// numbers, and numbers should be asserted, not squinted at.
  static ({TableSimulation sim, DiscBody? cue}) createSim(
    EightBallState? state,
  ) {
    final sim = TableSimulation(
      config: simConfig,
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
    );
    // Full rails; pockets are handled by capture, not gaps.
    sim.addBounds(const Rect.fromLTRB(-tableW / 2, 0, tableW / 2, tableL));
    DiscBody? cue;
    if (state != null) {
      for (final b in state.balls) {
        if (b.pocketed) continue;
        final disc = sim.addDisc(
          id: '${b.number}',
          owner: b.number,
          position: simPos(b.nx, b.ny),
          radius: ballR,
        );
        if (b.isCue) cue = disc;
      }
    }
    return (sim: sim, cue: cue);
  }

  TableSimulation _buildSim(EightBallState? state) {
    final built = createSim(state);
    _cue = built.cue;
    return built.sim
      ..onDiscCollision = _handleCollision
      ..onSettled = _handleSettled;
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
    _drops.clear();
    _impacts.clear();
    _pendingSettle = null;
    // Balls are re-seated from state here; drop the roll baseline so the jump
    // isn't integrated as a spin. Orientation itself carries over.
    _lastBallPos.clear();
    _lastBallVel.clear();
    _placeGhost = state.ballInHand ? const Offset(0.5, 0.8) : null;
    _sim = _buildSim(state);
  }

  /// Normalized table coords → sim world units.
  static Vector2 simPos(double nx, double ny) =>
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
    if (_sim.isRunning) {
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
      _detectRailHits();
      _spawnDrops();
    }
    _advanceFlourishes(dt);
    // The move was packaged when the physics settled; hold it only until the
    // last ball has finished falling, so the drop is watched rather than cut.
    final pending = _pendingSettle;
    if (pending != null && !_sim.isRunning && _drops.isEmpty) {
      _pendingSettle = null;
      onShotSettled?.call(pending);
    }
  }

  /// Turn newly captured balls into falling ones. The sim has already decided
  /// they are pocketed; this only gives them somewhere to go.
  void _spawnDrops() {
    for (final d in _sim.discs) {
      if (!d.removed) continue;
      final n = d.owner as int;
      if (!_pocketedIds.add(n)) continue;
      final at = _toNorm(d.position);
      _drops.add(_Drop(
        number: n,
        isCue: n == EightBallGame.cueNumber,
        pocket: _nearestPocket(d.position),
        nx: at.nx.clamp(-0.2, 1.2),
        ny: at.ny.clamp(-0.2, 1.2),
        spin: _orient[n]?.spin ?? BallSpin.identity,
      ));
    }
  }

  /// Advance drops and cushion compressions, and fire the pocket cue on the
  /// frame a ball actually disappears below the rim — that is the moment the
  /// sound belongs to, not the moment the solver removed the body.
  void _advanceFlourishes(double dt) {
    for (var i = _drops.length - 1; i >= 0; i--) {
      final d = _drops[i];
      final was = d.t;
      d.t += dt / dropSeconds;
      if (was < _Drop.rimCross && d.t >= _Drop.rimCross) onPocket?.call();
      if (d.t >= 1) _drops.removeAt(i);
    }
    for (var i = _impacts.length - 1; i >= 0; i--) {
      final im = _impacts[i];
      im.t += dt / impactSeconds;
      if (im.t >= 1) _impacts.removeAt(i);
    }
  }

  /// Which pocket a captured ball went down, by proximity to the capture points.
  int _nearestPocket(Vector2 p) {
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < _pocketsWorld.length; i++) {
      final (px, py) = _pocketsWorld[i];
      final dx = p.x - px, dy = p.y - py;
      final d = dx * dx + dy * dy;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /// Detect cushion bounces from the velocity the solver actually produced.
  ///
  /// Forge2D reports contacts between *discs* only, so a rail bounce arrives
  /// with no callback at all — which is why the cushions used to be silent. A
  /// bounce is a sign flip in the velocity component normal to a rail while the
  /// ball is within a ball's width of it; the pre-flip normal speed is how hard
  /// it hit, and everything downstream (sound gate, haptic weight, how far the
  /// cloth compresses) is scaled by that.
  void _detectRailHits() {
    const nearBand = ballR * 2.2;
    for (final d in _sim.discs) {
      if (d.removed) continue;
      final n = d.owner as int;
      final v = d.body.linearVelocity;
      final prev = _lastBallVel[n];
      _lastBallVel[n] = Vector2(v.x, v.y);
      if (prev == null) continue;
      final p = d.position;

      void hit(double speed, Offset normal, double nx, double ny) {
        final strength =
            ((speed - railQuietSpeed) / railRefSpeed).clamp(0.0, 1.0);
        if (speed < railQuietSpeed) return;
        _impacts
            .add(_Impact(nx: nx, ny: ny, normal: normal, strength: strength));
        onRail?.call(strength);
      }

      final norm = _toNorm(p);
      // Left / right rails: the x component reverses.
      if (prev.x < -0.15 && v.x > 0 && p.x < -tableW / 2 + nearBand) {
        hit(-prev.x, const Offset(1, 0), 0, norm.ny);
      } else if (prev.x > 0.15 && v.x < 0 && p.x > tableW / 2 - nearBand) {
        hit(prev.x, const Offset(-1, 0), 1, norm.ny);
      }
      // Foot / head rails: the y component reverses.
      if (prev.y < -0.15 && v.y > 0 && p.y < nearBand) {
        hit(-prev.y, const Offset(0, 1), norm.nx, 0);
      } else if (prev.y > 0.15 && v.y < 0 && p.y > tableL - nearBand) {
        hit(prev.y, const Offset(0, -1), norm.nx, 1);
      }
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
    // Packaged now, delivered once the last ball has finished dropping. The
    // outcome is read off the settled bodies here and never touched again, so
    // no amount of animation can move it.
    _pendingSettle = EightBallMove.shot(
      owner: _acting,
      positions: positions,
      firstHitNumber: _firstHit,
    );
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
      // Predicted off the live bodies, in world units. Read-only: the solver
      // copies the centres out and hands back numbers for the painter.
      final cuePos = _cue!.position;
      aim = PoolAim(
        nx: n.nx,
        ny: n.ny,
        dir: dir,
        power: power,
        assist: poolAimAssist(
          cue: Offset(cuePos.x, cuePos.y),
          aim: dir,
          balls: [
            for (final d in _sim.discs)
              if (!d.removed && (d.owner as int) != EightBallGame.cueNumber)
                (
                  number: d.owner as int,
                  centre: Offset(d.position.x, d.position.y),
                ),
          ],
          power: power,
          ballR: ballR,
        ),
      );
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
      PoolView(
        balls: balls,
        aim: aim,
        ghost: ghost,
        drops: [
          for (final d in _drops)
            PoolDrop(
              pocket: d.pocket,
              fromNx: d.nx,
              fromNy: d.ny,
              radiusFrac: ballR / tableW,
              number: d.number,
              isCue: d.isCue,
              spin: d.spin,
              t: d.t,
            ),
        ],
        impacts: [
          for (final im in _impacts)
            PoolImpact(
              nx: im.nx,
              ny: im.ny,
              normal: im.normal,
              strength: im.strength,
              t: im.t,
            ),
        ],
      ),
      style,
      scheme,
    );
  }
}

/// A ball falling into a pocket — presentation state only.
class _Drop {
  final int number;
  final bool isCue;
  final int pocket;
  final double nx;
  final double ny;
  final BallSpin spin;
  double t = 0;

  /// Fraction of the drop at which the ball is swallowed by the rim — the beat
  /// the pocket sound belongs on.
  static const double rimCross = 0.30;

  _Drop({
    required this.number,
    required this.isCue,
    required this.pocket,
    required this.nx,
    required this.ny,
    required this.spin,
  });
}

/// A cushion still springing back from a strike.
class _Impact {
  final double nx;
  final double ny;
  final Offset normal;
  final double strength;
  double t = 0;

  _Impact({
    required this.nx,
    required this.ny,
    required this.normal,
    required this.strength,
  });
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

  /// The predicted contact + cut, if one was solved. Display only — it is
  /// re-derived from the live table every frame and never fed back into the
  /// shot (see [PoolAimAssist]).
  final PoolAimAssist? assist;

  const PoolAim({
    required this.nx,
    required this.ny,
    required this.dir,
    required this.power,
    this.assist,
  });
}

// ---------------------------------------------------------------------------
// Aim assist: where this line of travel ends up.
// ---------------------------------------------------------------------------

/// Where the cue ball's line of travel first meets something, in **sim world
/// units** — the frame [EightBallScene.simPos] produces (x across the table
/// about 0, y along it from the foot rail, y-down on screen).
///
/// Pure geometry over the balls that are on the cloth right now. It predicts;
/// it never decides. The solver runs on a copy of the positions and its output
/// only ever reaches a paint call, so no aim line can move a ball.
class PoolShotPrediction {
  /// Cue-ball centre at the moment of contact. With a ball hit this sits
  /// exactly one ball *diameter* back along the aim line from that ball's
  /// centre; with nothing hit it is where the cue's centre meets the cushion.
  final Offset contact;

  /// The ball that would be struck, or null when the line dies on a rail.
  final int? ballNumber;

  /// Centre of the struck ball (null when nothing is hit).
  final Offset? objectCentre;

  /// Unit direction the struck ball leaves along: the centre-to-centre line
  /// from [contact] through [objectCentre]. [Offset.zero] when nothing is hit.
  final Offset objectDir;

  /// Unit direction the cue deflects along — the tangent, perpendicular to
  /// [objectDir], taking the side the cue was already travelling toward.
  /// [Offset.zero] when nothing is hit.
  final Offset cueDir;

  /// Cut angle in radians between the aim line and [objectDir]: 0 is a dead
  /// straight pot, → π/2 is the thinnest of feathers.
  final double cut;

  /// How far the cue ball travels to reach [contact].
  final double travel;

  const PoolShotPrediction({
    required this.contact,
    required this.ballNumber,
    required this.objectCentre,
    required this.objectDir,
    required this.cueDir,
    required this.cut,
    required this.travel,
  });

  bool get hitsBall => ballNumber != null;
}

/// A solved prediction plus how far each leg of it should be *drawn* — the
/// power read the player is asked to feel.
class PoolAimAssist {
  /// Cue-ball centre, world units.
  final Offset origin;

  final PoolShotPrediction shot;

  /// Length of the struck ball's line, world units. Zero when nothing is hit.
  final double objectLen;

  /// Length of the cue's deflection line, world units.
  final double cueLen;

  /// 0..1 stroke power — also drives the guide's opacity.
  final double power;

  /// Ball radius in world units, for the ghost ring.
  final double ballR;

  const PoolAimAssist({
    required this.origin,
    required this.shot,
    required this.objectLen,
    required this.cueLen,
    required this.power,
    required this.ballR,
  });
}

/// Ray-cast the cue ball's line of travel against the balls on the cloth.
///
/// A moving ball of radius r contacts a resting one of radius r when their
/// *centres* are 2r apart, so this is a ray against circles of radius 2r about
/// each object ball — take the nearest root ahead of the cue. If no ball is in
/// the way the line runs on to the first cushion the cue's centre can reach
/// (one radius short of the rail) and stops there.
PoolShotPrediction predictPoolShot({
  required Offset cue,
  required Offset aim,
  required Iterable<({int number, Offset centre})> balls,
  double ballR = EightBallGame.ballR,
  double tableW = EightBallGame.tableW,
  double tableL = EightBallGame.tableL,
}) {
  final len = aim.distance;
  final d = len < 1e-9 ? const Offset(0, -1) : aim / len;

  // How far the cue centre can run before a cushion stops it.
  final hw = tableW / 2 - ballR;
  var tEnd = double.infinity;
  void cushion(double t) {
    if (t > 1e-9 && t < tEnd) tEnd = t;
  }

  if (d.dx > 1e-9) cushion((hw - cue.dx) / d.dx);
  if (d.dx < -1e-9) cushion((-hw - cue.dx) / d.dx);
  if (d.dy > 1e-9) cushion((tableL - ballR - cue.dy) / d.dy);
  if (d.dy < -1e-9) cushion((ballR - cue.dy) / d.dy);
  if (!tEnd.isFinite) tEnd = tableL;

  final sumR = ballR * 2;
  int? hitNumber;
  Offset? hitCentre;
  for (final b in balls) {
    final m = cue - b.centre;
    final along = m.dx * d.dx + m.dy * d.dy;
    final c = m.distanceSquared - sumR * sumR;
    // Already touching/overlapping: there is no contact ahead to predict.
    if (c <= 0) continue;
    final disc = along * along - c;
    if (disc < 0) continue;
    final t = -along - math.sqrt(disc);
    if (t <= 1e-6 || t >= tEnd) continue;
    tEnd = t;
    hitNumber = b.number;
    hitCentre = b.centre;
  }

  final contact = cue + d * tEnd;
  if (hitNumber == null || hitCentre == null) {
    return PoolShotPrediction(
      contact: contact,
      ballNumber: null,
      objectCentre: null,
      objectDir: Offset.zero,
      cueDir: Offset.zero,
      cut: 0,
      travel: tEnd,
    );
  }

  // Centre-to-centre: the only direction a frictionless ball can be sent.
  final line = hitCentre - contact;
  final lineLen = line.distance;
  final objectDir = lineLen < 1e-9 ? d : line / lineLen;
  // The cue takes the tangent. Two perpendiculars exist; keep the one the cue
  // was already heading toward, so a cut throws it to the correct side.
  var cueDir = Offset(-objectDir.dy, objectDir.dx);
  if (d.dx * cueDir.dx + d.dy * cueDir.dy < 0) cueDir = -cueDir;
  final cut =
      math.acos((d.dx * objectDir.dx + d.dy * objectDir.dy).clamp(-1.0, 1.0));

  return PoolShotPrediction(
    contact: contact,
    ballNumber: hitNumber,
    objectCentre: hitCentre,
    objectDir: objectDir,
    cueDir: cueDir,
    cut: cut,
    travel: tEnd,
  );
}

/// How far a guide leg reaches at full power, world units — a little under half
/// the table, so a hard shot's prediction spans it without papering over it.
const double _assistReach = EightBallGame.tableL * 0.40;

/// Solve the aim assist for a stroke and decide how long to draw each leg.
///
/// Both channels the player was promised move here: **power** stretches the
/// whole prediction (a tap barely pokes past the ghost, a hard shot runs half
/// the table), and the **cut angle** splits that reach between the two legs the
/// way the collision splits the energy — the struck ball keeps `cos²θ`, the cue
/// keeps `sin²θ`. A straight pot therefore shows one long line and almost no
/// deflection; a thin cut shows the cue running away and the object barely
/// moving. Floors on both keep either leg from vanishing entirely.
PoolAimAssist poolAimAssist({
  required Offset cue,
  required Offset aim,
  required Iterable<({int number, Offset centre})> balls,
  required double power,
  double ballR = EightBallGame.ballR,
}) {
  final shot = predictPoolShot(cue: cue, aim: aim, balls: balls, ballR: ballR);
  final p = power.clamp(0.0, 1.0);
  final reach = _assistReach * (0.22 + 0.78 * p);
  final cosCut = math.cos(shot.cut);
  final sinCut = math.sin(shot.cut);
  return PoolAimAssist(
    origin: cue,
    shot: shot,
    objectLen: shot.hitsBall ? reach * (0.28 + 0.72 * cosCut * cosCut) : 0,
    cueLen: shot.hitsBall ? reach * (0.12 + 0.88 * sinCut * sinCut) : 0,
    power: p,
    ballR: ballR,
  );
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

/// A ball on its way down a pocket.
///
/// **Purely presentational.** The sim decided this ball was captured before the
/// drop existed; the animation only draws the fall the physics already
/// committed to, so it can never change whether a ball was potted. See
/// [_paintPocketDrop] for the staging.
class PoolDrop {
  /// Index into [poolPocketGeometry] — which pocket it is falling into.
  final int pocket;

  /// Where the sim captured it, in normalized table coords. The ball is drawn
  /// travelling from here into the mouth.
  final double fromNx;
  final double fromNy;

  /// Radius as a fraction of the felt width (same scale as [RenderBall]).
  final double radiusFrac;

  final int number;
  final bool isCue;

  /// Orientation at capture — the ball keeps the face it fell in on.
  final BallSpin spin;

  /// 0 = just captured, 1 = settled out of sight.
  final double t;

  const PoolDrop({
    required this.pocket,
    required this.fromNx,
    required this.fromNy,
    required this.radiusFrac,
    required this.number,
    required this.t,
    this.isCue = false,
    this.spin = BallSpin.identity,
  });
}

/// A cushion strike, drawn as a compression in the cloth at the contact point.
class PoolImpact {
  /// Contact point in normalized table coords (on the cushion nose).
  final double nx;
  final double ny;

  /// Unit inward normal of the cushion that was struck, in screen space.
  final Offset normal;

  /// 0..1 impact speed relative to a hard strike — drives width and depth.
  final double strength;

  /// 0 = just happened, 1 = fully relaxed.
  final double t;

  const PoolImpact({
    required this.nx,
    required this.ny,
    required this.normal,
    required this.strength,
    required this.t,
  });
}

/// Everything one frame of the table needs.
class PoolView {
  final List<RenderBall> balls;
  final PoolAim? aim;
  final PoolGhost? ghost;

  /// Balls currently falling into pockets.
  final List<PoolDrop> drops;

  /// Live cushion compressions.
  final List<PoolImpact> impacts;

  const PoolView({
    required this.balls,
    this.aim,
    this.ghost,
    this.drops = const [],
    this.impacts = const [],
  });
}

/// Rail band width as a fraction of the table **width** — the felt inset, the
/// same absolute band on all four sides.
///
/// Public because the board has to size itself around it: the band is measured
/// off the width but eats into the height too, so the outer box's aspect is not
/// the felt's aspect. See [EightBallScene.boardAspect].
const double poolRailFrac = 0.085;

/// How much of the rail band is cushion (cloth) rather than wood.
const double _cushionFrac = 0.38;

/// Pocket mouth radius as a fraction of the table width.
const double _pocketFrac = 0.062;

/// The felt (playing area) rect inside the rail frame for a table of [size].
/// Shared by the scene (for hit-testing) and the painter (for drawing) so the
/// two never drift. Pocket centres sit on this rect's corners + side midpoints.
Rect poolFeltRect(Size size) {
  final m = size.width * poolRailFrac;
  return Rect.fromLTRB(m, m, size.width - m, size.height - m);
}

Color _lighten(Color c, double t) => Color.lerp(c, Colors.white, t)!;
Color _darken(Color c, double t) => Color.lerp(c, Colors.black, t)!;

/// Paints the pool hall around the table into [size]: a hardwood floor with the
/// lamp's sheen skating along the boards, the pool of light a low pendant throws
/// onto them, and a vignette into the corners. Pure, so the board and any static
/// preview share one room.
///
/// [lightCenter] is where the lamp hangs, in fractional coords — normally the
/// centre of the table so the falloff frames it.
///
/// [scheme] switches the hall between a late-night bar (dark) and a bright
/// daytime hall with pale oak boards (light). Without it the room was the same
/// dark room in either theme, which is what made a light-mode app look like it
/// had one screen someone forgot about.
void paintPoolRoom(
  Canvas canvas,
  Size size, {
  Offset lightCenter = const Offset(0.5, 0.46),
  ColorScheme? scheme,
}) {
  final full = Offset.zero & size;
  final day = scheme?.brightness == Brightness.light;
  final floor = day ? const Color(0xFF8A6642) : const Color(0xFF241A12);
  // A hint of the app's own palette in the boards keeps the hall from reading
  // as a stock texture bolted under the table.
  final tint =
      scheme == null ? floor : Color.lerp(floor, scheme.primary, 0.06)!;
  canvas.drawRect(full, Paint()..color = tint);

  final grainAlpha = day ? 0.055 : 0.10;
  final seamAlpha = day ? 0.26 : 0.45;

  // Hardwood planks running across the room.
  final plankH = math.max(10.0, size.height / 11);
  final rows = (size.height / plankH).ceil() + 1;
  final lamp =
      Offset(size.width * lightCenter.dx, size.height * lightCenter.dy);
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
          ..color = Colors.black
              .withValues(alpha: grainAlpha + n.abs() * grainAlpha * 0.8),
      );
    }

    // Sheen: varnished boards are anisotropic, so the lamp doesn't make a round
    // spot on them — it smears into a long streak *along* the grain, brightest
    // on the planks level with the lamp and fading away up and down the room.
    // This is the cue that separates polished floorboards from flat brown.
    final band = (1 - ((y + plankH / 2) - lamp.dy).abs() / (size.height * 0.42))
        .clamp(0.0, 1.0);
    if (band > 0.01) {
      final gloss = band * band * (day ? 0.30 : 0.22);
      canvas.save();
      canvas.clipRect(rect);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              const Color(0xFFFFE6BE).withValues(alpha: gloss * 0.55),
              const Color(0xFFFFF3DC).withValues(alpha: gloss),
              const Color(0xFFFFE6BE).withValues(alpha: gloss * 0.55),
              Colors.transparent,
            ],
            stops: [
              0.0,
              (lightCenter.dx - 0.34).clamp(0.02, 0.9),
              lightCenter.dx.clamp(0.05, 0.95),
              (lightCenter.dx + 0.34).clamp(0.1, 0.98),
              1.0,
            ],
          ).createShader(rect),
      );
      // The hard specular line the varnish holds right at the board's crown.
      canvas.drawLine(
        Offset(lamp.dx - size.width * 0.42, y + plankH * 0.34),
        Offset(lamp.dx + size.width * 0.42, y + plankH * 0.34),
        Paint()
          ..strokeWidth = math.max(0.8, plankH * 0.05)
          ..shader = LinearGradient(
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: gloss * 0.7),
              Colors.transparent,
            ],
          ).createShader(Rect.fromLTWH(
              lamp.dx - size.width * 0.42, y, size.width * 0.84, plankH)),
      );
      canvas.restore();
    }

    // Plank seam + the light catching its edge.
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..strokeWidth = 1.1
        ..color = Colors.black.withValues(alpha: seamAlpha),
    );
    canvas.drawLine(
      Offset(0, y + 1.2),
      Offset(size.width, y + 1.2),
      Paint()
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: day ? 0.10 : 0.045),
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
        colors: day
            ? [
                const Color(0xFFFFF4DF).withValues(alpha: 0.22),
                const Color(0xFFFFE9C6).withValues(alpha: 0.08),
                Colors.black.withValues(alpha: 0.10),
                Colors.black.withValues(alpha: 0.34),
              ]
            : [
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
///
/// These are the *capture* points — the felt corners and side-rail midpoints the
/// simulation pockets against. The drawn mouth sits a little further out (see
/// [poolPocketGeometry]), because a real pocket is cut back into the frame.
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

/// One pocket as the painter needs it: where its mouth is drawn, how big it is,
/// and which way it faces out of the table.
///
/// Corner pockets are mitred — the two cushions meeting there are cut back at
/// 45° and the mouth opens on the diagonal — so the jaw painter and the
/// ball-drop painter both need the outward axis, not just a centre.
typedef PoolPocket = ({
  /// Capture point: the felt corner / side midpoint the sim pockets against.
  Offset capture,

  /// Centre of the drawn mouth, pushed out along [outward] from [capture].
  Offset centre,

  /// Mouth radius in pixels.
  double mouthR,

  /// Unit vector pointing out of the table through the pocket.
  Offset outward,

  /// True for the four mitred corner pockets, false for the two side pockets.
  bool corner,
});

/// Geometry for all six pockets, in the same order as [poolPockets]. Shared by
/// the jaw painter and the drop animation so the ball always falls into the hole
/// that is actually drawn.
List<PoolPocket> poolPocketGeometry(Size size) {
  final f = poolFeltRect(size);
  final w = size.width;
  final mouthR = w * _pocketFrac;
  const k = 0.70710678; // 1/√2
  PoolPocket make(Offset capture, Offset outward, bool corner) {
    final r = corner ? mouthR : mouthR * 0.92;
    return (
      capture: capture,
      centre: capture + outward * (r * (corner ? 0.30 : 0.24)),
      mouthR: r,
      outward: outward,
      corner: corner,
    );
  }

  return [
    make(f.topLeft, const Offset(-k, -k), true),
    make(f.topRight, const Offset(k, -k), true),
    make(f.bottomLeft, const Offset(-k, k), true),
    make(f.bottomRight, const Offset(k, k), true),
    make(Offset(f.left, f.center.dy), const Offset(-1, 0), false),
    make(Offset(f.right, f.center.dy), const Offset(1, 0), false),
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

  // Cushion compressions sit on the cloth, under everything that moves.
  for (final hit in view.impacts) {
    _paintRailImpact(canvas, size, feltRect, hit);
  }

  // Balls on their way down a pocket are *below* the table surface, so they go
  // under the resting balls: a ball sitting on the jaw correctly covers the one
  // dropping past it.
  for (final d in view.drops) {
    _paintPocketDrop(canvas, size, feltRect, d);
  }

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
    _paintMoveArrows(canvas, c, r);
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
  final cushion = w * poolRailFrac * _cushionFrac;
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
  final railBand = felt.left; // == size.width * poolRailFrac
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

/// Pockets as real cut mouths.
///
/// A corner pocket on a table is not a round hole punched in the cloth: the two
/// cushions meeting there are **mitred** — each ends in a straight facing angled
/// 45° back from its nose — and the wedge between those two facings is a plate
/// of cut frame with the throat opening on the diagonal. Side pockets are the
/// same idea with a much shallower flare. Drawing that, instead of a circle,
/// is what makes a ball look like it is being funnelled *into* something.
void _paintPockets(
  Canvas canvas,
  Size size,
  Rect feltRect,
  Color felt,
  Color rail,
) {
  final w = size.width;
  final cushion = w * poolRailFrac * _cushionFrac;
  final cloth = _darken(felt, 0.42);
  // The mouth is a hole cut through rail and cushion alike, so the plate around
  // it is the cut edge of the frame, not another patch of cloth.
  final cut = _darken(rail, 0.46);

  for (final p in poolPocketGeometry(size)) {
    final jaw = _jawShape(size, p, cushion);

    // The cut plate: the wedge of frame the mouth is bored through.
    canvas.drawPath(
      jaw.plate,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          colors: [_lighten(cut, 0.24), cut, _darken(cut, 0.5)],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(jaw.plate.getBounds().inflate(1)),
    );

    // The apron: the triangle of cloth between the two cushion noses, sloping
    // away from the playing surface into the mouth. This is the part a ball
    // actually rolls across on its way in, and drawing it — rather than butting
    // the felt straight up against a black circle — is what makes the pocket
    // read as a funnel with a hole behind it.
    canvas.drawPath(
      jaw.apron,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-p.outward.dx, -p.outward.dy),
          end: Alignment(p.outward.dx, p.outward.dy),
          // Already in shadow at the nose line: the apron tips away from the
          // lamp, so it must sit *under* the bed's own shading rather than
          // popping out of it as a bright wedge.
          colors: [
            _darken(felt, 0.16),
            _darken(felt, 0.46),
            _darken(felt, 0.86),
          ],
          stops: const [0.0, 0.42, 1.0],
        ).createShader(jaw.apron.getBounds().inflate(1)),
    );
    // The chamfer where the bed drops onto the apron.
    canvas.drawLine(
      jaw.cuts[0].a,
      jaw.cuts[1].a,
      Paint()
        ..strokeWidth = math.max(1.4, w * 0.008)
        ..color = Colors.black.withValues(alpha: 0.34)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.006),
    );

    // Stitched leather pocket facing around the mouth.
    canvas.drawCircle(
      p.centre,
      p.mouthR * 1.18,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          colors: const [
            Color(0xFF9A7048),
            Color(0xFF56381F),
            Color(0xFF2A1A0C)
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(
            Rect.fromCircle(center: p.centre, radius: p.mouthR * 1.18)),
    );
    _paintPocketThroat(canvas, w, p);

    // The mitred cut across each cushion end: a hard shadowed edge with the
    // lit crown of the cloth nose just inside it.
    for (final cutLine in jaw.cuts) {
      canvas.drawLine(
        cutLine.a,
        cutLine.b,
        Paint()
          ..strokeWidth = math.max(1.1, w * 0.006)
          ..color = Colors.black.withValues(alpha: 0.55),
      );
      final inset = cutLine.inward * math.max(1.3, w * 0.006);
      canvas.drawLine(
        cutLine.a + inset,
        cutLine.b + inset,
        Paint()
          ..strokeWidth = math.max(0.9, w * 0.004)
          ..color = _lighten(cloth, 0.22).withValues(alpha: 0.45),
      );
    }
  }
}

/// The dark shaft of a pocket: the throat gradient, the lit rim and the inner
/// shadow that gives the hole depth. Re-run over a falling ball so the ball is
/// swallowed by the same shading the empty pocket has.
void _paintPocketThroat(Canvas canvas, double w, PoolPocket p) {
  canvas.drawCircle(
    p.centre,
    p.mouthR,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.3, 0.42),
        radius: 0.95,
        colors: const [Color(0xFF060606), Color(0xFF0B0A09), Color(0xFF17130E)],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: p.centre, radius: p.mouthR)),
  );
  _paintPocketRim(canvas, w, p);
}

/// Rim highlight + inner throat shadow only — the pass that has to go back over
/// a ball inside the mouth so the near lip overhangs it.
void _paintPocketRim(Canvas canvas, double w, PoolPocket p) {
  // Rim highlight on the lit edge only.
  canvas.drawArc(
    Rect.fromCircle(center: p.centre, radius: p.mouthR * 1.02),
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
    p.centre,
    p.mouthR * 0.86,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = p.mouthR * 0.34
      ..color = Colors.black.withValues(alpha: 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.mouthR * 0.22),
  );
}

/// The mitre at one pocket.
///
/// Everything is derived from the pocket's [PoolPocket.outward] axis, so corners
/// come out on the diagonal and side pockets come out square with no per-pocket
/// special cases beyond how wide the mouth opens and how hard the facings flare.
///
/// * [plate] — the wedge of cut frame the mouth is bored through, reaching out
///   to the edge of the table.
/// * [apron] — the cloth between the two cushion noses, which slopes away into
///   the mouth.
/// * [cuts] — the two angled cushion ends, each with the direction that points
///   back into its own cushion (so the lit crown of the nose can be inset).
({
  Path plate,
  Path apron,
  List<({Offset a, Offset b, Offset inward})> cuts,
}) _jawShape(Size size, PoolPocket p, double cushion) {
  final o = p.outward;
  // Along-rail unit vectors, pointing back into the table away from the pocket.
  // A corner has two rails leaving on the two axes; a side pocket has one rail
  // running past it in both directions.
  final alongs = p.corner
      ? [Offset(-o.dx.sign, 0), Offset(0, -o.dy.sign)]
      : const [Offset(0, -1), Offset(0, 1)];
  // Per-rail outward normals — which way that cushion faces out of the felt.
  final outs = p.corner ? [Offset(0, o.dy.sign), Offset(o.dx.sign, 0)] : [o, o];

  // How far back from the capture point each cushion is cut. A corner pocket
  // measures a shade under two ball widths between the noses; a side pocket a
  // little more, because the ball has to turn a sharper corner to fall in.
  final open = p.mouthR * (p.corner ? 1.75 : 1.60);
  // How far the cut runs back toward the pocket as it goes out — the mitre
  // angle. Corners are a true angled facing; side pockets barely flare.
  final flare = cushion * (p.corner ? 0.95 : 0.35);

  final noses = <Offset>[for (final a in alongs) p.capture + a * open];
  final backs = <Offset>[
    for (var i = 0; i < 2; i++)
      noses[i] + outs[i] * cushion - alongs[i] * flare,
  ];

  /// Where [from] meets the outer edge of the table travelling along [dir].
  Offset toEdge(Offset from, Offset dir) {
    if (dir.dx < -0.5) return Offset(0, from.dy);
    if (dir.dx > 0.5) return Offset(size.width, from.dy);
    if (dir.dy < -0.5) return Offset(from.dx, 0);
    return Offset(from.dx, size.height);
  }

  final plate = Path()..moveTo(noses[0].dx, noses[0].dy);
  plate.lineTo(backs[0].dx, backs[0].dy);
  final e0 = toEdge(backs[0], outs[0]);
  plate.lineTo(e0.dx, e0.dy);
  if (p.corner) {
    final corner =
        Offset(o.dx < 0 ? 0 : size.width, o.dy < 0 ? 0 : size.height);
    plate.lineTo(corner.dx, corner.dy);
  }
  final e1 = toEdge(backs[1], outs[1]);
  plate.lineTo(e1.dx, e1.dy);
  plate.lineTo(backs[1].dx, backs[1].dy);
  plate.lineTo(noses[1].dx, noses[1].dy);
  plate.close();

  // The apron spans nose to nose and runs out past the mouth, so the mouth
  // circle always lands on cloth rather than half on cloth and half on frame.
  final reach = p.capture + o * (p.mouthR * 1.35);
  final apron = Path()
    ..moveTo(noses[0].dx, noses[0].dy)
    ..lineTo(noses[1].dx, noses[1].dy)
    ..lineTo(reach.dx + alongs[1].dx * open * 0.55,
        reach.dy + alongs[1].dy * open * 0.55)
    ..lineTo(reach.dx + alongs[0].dx * open * 0.55,
        reach.dy + alongs[0].dy * open * 0.55)
    ..close();

  return (
    plate: plate,
    apron: apron,
    cuts: [
      for (var i = 0; i < 2; i++) (a: noses[i], b: backs[i], inward: alongs[i]),
    ],
  );
}

/// The staging of a pocket drop at time [t] (0 = captured, 1 = out of sight).
///
/// Pulled out of the painter so the shape of the fall is a value that can be
/// asserted rather than a curve buried in a draw call: `travel` is how far along
/// the funnel from the capture point to the mouth the ball has come, `fall` is
/// how far down the throat it is, and `scale`/`veil` are what that does to it.
({double travel, double fall, double scale, double veil}) poolDropStage(
  double t,
) {
  final u = t.clamp(0.0, 1.0);
  // Approach: eased travel from where the sim captured it, across the apron and
  // into the mouth.
  final a = (u / 0.30).clamp(0.0, 1.0);
  final travel = 1 - (1 - a) * (1 - a);
  // Fall: begins as the ball tips over the lip and runs the rest of the drop's
  // life. Not a pure `t²` — the ball arrives already moving, so most of the
  // descent is linear, which is what makes the first frames of the drop visible
  // at all instead of the ball appearing to hang at full size and then vanish.
  final f = ((u - 0.18) / 0.82).clamp(0.0, 1.0);
  var fall = f * (0.58 + 0.42 * f);
  // A short rebound off the bottom of the net so it lands rather than fading.
  if (f > 0.84) fall -= math.sin((f - 0.84) / 0.16 * math.pi) * 0.08;
  return (
    travel: travel,
    fall: fall,
    scale: 1 - 0.68 * fall,
    veil: (0.82 * fall).clamp(0.0, 1.0),
  );
}

/// One ball falling into a pocket.
///
/// Three beats over the drop's life: it is funnelled off the jaw into the mouth,
/// it falls — shrinking and darkening as the throat swallows it — and it settles
/// with a short rebound off the bottom. From the moment it is inside the mouth
/// it is clipped to it and the rim is repainted on top, so the lip genuinely
/// occludes it instead of the ball sitting on a painted circle.
void _paintPocketDrop(
  Canvas canvas,
  Size size,
  Rect feltRect,
  PoolDrop d,
) {
  final pockets = poolPocketGeometry(size);
  if (d.pocket < 0 || d.pocket >= pockets.length) return;
  final p = pockets[d.pocket];
  final r = d.radiusFrac * feltRect.width;
  final from = Offset(
    feltRect.left + d.fromNx * feltRect.width,
    feltRect.top + d.fromNy * feltRect.height,
  );
  final stage = poolDropStage(d.t);
  final centre = Offset.lerp(from, p.centre, stage.travel)!;
  final fall = stage.fall;
  final drawR = r * stage.scale;
  if (drawR <= 0.4) return;
  // It slides down the far wall of the throat as it goes.
  final sunkCentre = centre + p.outward * (p.mouthR * 0.26 * fall);

  canvas.save();
  if (fall > 0) {
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: p.centre, radius: p.mouthR)),
    );
  }
  _paintBall(
    canvas,
    sunkCentre,
    drawR,
    RenderBall(
      nx: 0,
      ny: 0,
      number: d.number,
      radiusFrac: d.radiusFrac,
      isCue: d.isCue,
      spin: d.spin,
    ),
    veil: stage.veil,
    shadow: fall <= 0,
  );
  canvas.restore();

  // The lip goes back over the top: this is what turns "a small ball drawn on a
  // black circle" into "a ball down a hole".
  _paintPocketRim(canvas, size.width, p);
}

/// The cloth compressing where a ball banked off a cushion: a short bright
/// crease at the contact point that relaxes out over the impact's life, scaled
/// by how hard the ball arrived.
void _paintRailImpact(
  Canvas canvas,
  Size size,
  Rect feltRect,
  PoolImpact hit,
) {
  final t = hit.t.clamp(0.0, 1.0);
  final s = hit.strength.clamp(0.0, 1.0);
  if (s <= 0.02) return;
  final at = Offset(
    feltRect.left + hit.nx * feltRect.width,
    feltRect.top + hit.ny * feltRect.height,
  );
  final w = size.width;
  final cushion = w * poolRailFrac * _cushionFrac;
  // Springs in fast, relaxes slowly.
  final press =
      t < 0.22 ? t / 0.22 : math.pow(1 - (t - 0.22) / 0.78, 1.6) * 1.0;
  final amount = press.toDouble() * s;
  if (amount <= 0.01) return;

  final n = hit.normal;
  final perp = Offset(-n.dy, n.dx);
  final half = cushion * (1.0 + 2.0 * s);
  final depth = cushion * 0.55 * amount;

  // A dent pushed into the cushion nose, away from the felt.
  final path = Path()
    ..moveTo(at.dx + perp.dx * half, at.dy + perp.dy * half)
    ..quadraticBezierTo(
      at.dx - n.dx * depth,
      at.dy - n.dy * depth,
      at.dx - perp.dx * half,
      at.dy - perp.dy * half,
    )
    ..lineTo(
      at.dx - perp.dx * half - n.dx * cushion,
      at.dy - perp.dy * half - n.dy * cushion,
    )
    ..lineTo(
      at.dx + perp.dx * half - n.dx * cushion,
      at.dy + perp.dy * half - n.dy * cushion,
    )
    ..close();
  canvas.drawPath(
    path,
    Paint()..color = Colors.black.withValues(alpha: 0.44 * amount),
  );
  // Lit crest of the compression, right on the nose.
  canvas.drawPath(
    Path()
      ..moveTo(at.dx + perp.dx * half, at.dy + perp.dy * half)
      ..quadraticBezierTo(
        at.dx - n.dx * depth,
        at.dy - n.dy * depth,
        at.dx - perp.dx * half,
        at.dy - perp.dy * half,
      ),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, w * 0.007 * (0.5 + s))
      ..color = Colors.white.withValues(alpha: 0.40 * amount),
  );
}

/// Draws one ball. [veil] darkens the whole sphere (a ball down a pocket loses
/// the lamp), and [shadow] can be dropped for a ball that is no longer on the
/// cloth to cast one.
void _paintBall(
  Canvas canvas,
  Offset c,
  double r,
  RenderBall b, {
  double veil = 0,
  bool shadow = true,
}) {
  if (r <= 0.4) return;
  final base = EightBallStyle.ballColor(b.number);
  final isStripe = b.number >= 9 && b.number <= 15;
  const ivory = Color(0xFFF6F1E7);

  // Contact shadow.
  if (shadow) {
    canvas.drawCircle(
      c.translate(0, r * 0.22),
      r * 1.02,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.35),
    );
  }

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
    Paint()..color = Colors.white.withValues(alpha: 0.5 * (1 - veil)),
  );

  // Down a pocket the lamp stops reaching it.
  if (veil > 0) {
    canvas.drawCircle(
      c,
      r,
      Paint()..color = Colors.black.withValues(alpha: veil.clamp(0.0, 1.0)),
    );
  }
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

/// The "you can move this" affordance: four chevrons at the ball's diagonals,
/// all pointing inward at it.
///
/// Rides on the placement ghost and nothing else, so it appears exactly when
/// the cue is in hand and disappears the moment the placement is committed.
/// Diagonals rather than the axes on purpose — the horizontal and vertical
/// around the cue are where the *aim* line lives, and the two affordances must
/// never be mistaken for each other.
void _paintMoveArrows(Canvas canvas, Offset c, double r) {
  // Solid heads, not open chevrons: an open V drawn at 45° reads as a corner
  // crop-mark (measured — the first pass looked like a focus reticle), and at
  // a 14pt ball on a phone there is no room for the difference to survive.
  final apexAt = r * 1.42; // just clear of the ball's outline
  final len = r * 0.66;
  final half = r * 0.40;
  final fill = Paint()..color = Colors.white.withValues(alpha: 0.86);
  final rim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.8, r * 0.07)
    ..strokeJoin = StrokeJoin.round
    ..color = Colors.black.withValues(alpha: 0.35);
  for (var i = 0; i < 4; i++) {
    final a = math.pi / 4 + i * math.pi / 2;
    final out = Offset(math.cos(a), math.sin(a));
    final perp = Offset(-out.dy, out.dx);
    final apex = c + out * apexAt;
    final base = apex + out * len;
    final head = Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(base.dx + perp.dx * half, base.dy + perp.dy * half)
      ..lineTo(base.dx - perp.dx * half, base.dy - perp.dy * half)
      ..close();
    canvas.drawPath(head, rim); // reads on pale cloth as well as dark
    canvas.drawPath(head, fill);
  }
}

/// The aiming aid: travel line, ghost ball at contact, and the cut's V.
///
/// Hairlines on purpose. This has to be readable *behind* the balls it is
/// predicting about, and a bright laser across the cloth would be worse than
/// nothing. Everything fades up with power, so a tap is a whisper and a hard
/// shot is legible from across the room.
///
/// Only ever drawn while a drag is in flight — [PoolView.aim] is null the
/// instant the finger lifts, so there is nothing to leave behind.
void _paintAim(
  Canvas canvas,
  Offset origin,
  PoolAim aim,
  Rect felt,
  Size size,
) {
  final assist = aim.assist;
  // World → screen. The board is sized to EightBallScene.boardAspect, so this
  // is one uniform scale on both axes and an angle survives the trip.
  final scale = felt.width / EightBallGame.tableW;
  Offset toScreen(Offset world) => Offset(
        felt.left + (world.dx / EightBallGame.tableW + 0.5) * felt.width,
        felt.top + (world.dy / EightBallGame.tableL) * felt.height,
      );

  final p = aim.power.clamp(0.0, 1.0);
  final hair = math.max(1.0, felt.width * 0.0055);

  if (assist == null) {
    // No solve (shouldn't happen in the live scene) — fall back to a plain ray.
    canvas.drawLine(
      origin,
      origin + aim.dir * felt.height * 0.9,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10 + 0.14 * p)
        ..strokeWidth = hair,
    );
    return;
  }

  final shot = assist.shot;
  final contact = toScreen(shot.contact);

  // 1. The travel line: cue ball → wherever this stroke first meets something.
  canvas.drawLine(
    origin,
    contact,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.13 + 0.17 * p)
      ..strokeWidth = hair,
  );

  if (!shot.hitsBall) return; // died on a cushion; no cut to show

  // 2. The ghost: where the cue ball sits at the moment of contact, one ball
  // diameter back from the object ball along the line.
  canvas.drawCircle(
    contact,
    assist.ballR * scale,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hair
      ..color = Colors.white.withValues(alpha: 0.20 + 0.30 * p),
  );

  // 3. The V. The struck ball leaves down the centre line (drawn from the
  // ghost through it, so the ball itself masks the near half and the line
  // reads as coming *out* of it); the cue peels off along the tangent.
  final objectEnd = toScreen(
    shot.contact + shot.objectDir * (assist.ballR * 2 + assist.objectLen),
  );
  canvas.drawLine(
    contact,
    objectEnd,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.16 + 0.26 * p)
      ..strokeWidth = hair,
  );

  final cueEnd = toScreen(shot.contact + shot.cueDir * assist.cueLen);
  _dashedLine(
    canvas,
    contact,
    cueEnd,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.12 + 0.20 * p)
      ..strokeWidth = hair
      ..strokeCap = StrokeCap.round,
    dash: hair * 3.2,
    gap: hair * 2.6,
  );
}

/// A dashed segment from [a] to [b]. The cue's own path is a *guess* — it is
/// the tangent line of an idealized collision, not the swerving thing the
/// solver will actually produce — so it is drawn as the softer of the two legs.
void _dashedLine(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint, {
  required double dash,
  required double gap,
}) {
  final total = (b - a).distance;
  if (total < 0.5 || dash <= 0 || gap <= 0) return;
  final step = dash + gap;
  final dir = (b - a) / total;
  for (var t = 0.0; t < total; t += step) {
    canvas.drawLine(a + dir * t, a + dir * math.min(t + dash, total), paint);
  }
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
          // Both chips now share one row, so a long player name has to give way
          // rather than overflow the strip.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color:
                    Colors.white.withValues(alpha: active || winner ? 1 : 0.7),
                fontWeight:
                    active || winner ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            groupLabel,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
          if (group != null) ...[
            const SizedBox(width: 6),
            // Balls left in your group is the scoreboard — it reads as a
            // number, not as the tail of a label.
            Text(
              '$remaining',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                height: 1,
                letterSpacing: -0.5,
                shadows: active || winner
                    ? [
                        Shadow(
                          color: accent.withValues(alpha: 0.7),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
            ),
          ],
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
