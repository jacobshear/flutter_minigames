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
import 'package:minigames_ui/minigames_ui.dart';

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

  // The transient centre message. A single GameNotice owns the animation and
  // the retract timer, so repeating the same text — "No contact" twice in a
  // row is ordinary play — can never collide with its own outgoing copy.
  String? _notice;
  GameNoticeTone _noticeTone = GameNoticeTone.info;
  Color? _noticeAccent;
  bool _noticeSticky = false;
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
    _clearNotice();
    _confetti = const [];
    final s = widget.controller.state;
    _state = s;
    _outcome = s == null ? null : _game.outcome(s);
    if (s != null) {
      scene.applyState(s, _actingFor(s));
      // Whose turn it is is a standing fact and lives in the header GamePill,
      // so binding announces nothing.
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
  }) {
    _notice = text;
    _noticeTone = tone;
    _noticeAccent = accent;
    _noticeSticky = sticky;
  }

  void _clearNotice() {
    _notice = null;
    _noticeSticky = false;
  }

  /// Seat colour, resolved against the cached scheme so callbacks off the
  /// build path can use it too.
  Color _accentFor(String playerId) {
    final s = _state;
    final isP1 = s == null || playerId == s.playerIds.first;
    return isP1
        ? widget.style.resolvePlayer1(_scheme)
        : widget.style.resolvePlayer2(_scheme);
  }

  String _actingFor(KnockoutState s) =>
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

  void _onLaunch() {
    if (!mounted) return;
    widget.style.sounds.onLaunch?.call();
    if (widget.style.haptics) HapticFeedback.mediumImpact();
    setState(_clearNotice);
  }

  Duration _lastClack = Duration.zero;
  double _lastClackStrength = 0;
  final Stopwatch _clock = Stopwatch()..start();

  /// A puck-on-puck contact, [strength] 0..1 scaled by closing speed.
  ///
  /// The sound hook takes no arguments (the host app owns the SFX bank), so the
  /// weight of an impact is carried by *what* fires rather than how loud: a
  /// graze is silent, a nudge clicks, a solid hit thumps. The haptic steps up
  /// with the same curve, which is what actually sells the hit on device.
  void _onCollision(double strength) {
    if (!mounted) return;
    if (strength < 0.06) return; // a graze, not a hit
    // Throttle: one contact can report many times per settle. A noticeably
    // harder hit still gets through — otherwise the loudest moment of a
    // scatter is the one that gets swallowed.
    final now = _clock.elapsed;
    final tooSoon = now - _lastClack < const Duration(milliseconds: 70);
    if (tooSoon && strength < _lastClackStrength + 0.25) return;
    _lastClack = now;
    _lastClackStrength = strength;
    widget.style.sounds.onCollision?.call();
    if (!widget.style.haptics) return;
    if (strength > 0.55) {
      HapticFeedback.mediumImpact();
    } else if (strength > 0.25) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.selectionClick();
    }
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
    final String text;
    final GameNoticeTone tone;
    if (result.isOwnGoal) {
      // Knocking your own puck off is the sting of this game — it shakes.
      text = result.ownLost == 1
          ? 'OWN PUCK LOST'
          : '${result.ownLost} OWN PUCKS LOST';
      tone = GameNoticeTone.warn;
    } else if (result.isCleanHit) {
      text = result.oppKnocked == 1
          ? '${_labelFor(opp).toUpperCase()} KNOCKED OFF'
          : '${result.oppKnocked} KNOCKED OFF';
      tone = GameNoticeTone.score;
    } else {
      text = 'NO CONTACT';
      tone = GameNoticeTone.warn;
    }
    // Submit the settled outcome as the move.
    widget.controller.submitMove(move);
    if (!mounted) return;
    setState(() => _showNotice(
          text,
          tone: tone,
          // A clean hit wears the knocker's colour; a mistake keeps warn red.
          accent: tone == GameNoticeTone.score ? _accentFor(move.owner) : null,
        ));
  }

  void _onState(KnockoutState next) {
    if (!mounted) return;
    final outcome = _game.outcome(next);
    final isFresh = next.frame == 0;

    _scene?.applyState(next, _actingFor(next));

    if (outcome != null && !_celebrated) {
      _celebrate(outcome, next);
    } else if (outcome == null && isFresh) {
      // New game: drop whatever the last match ended on.
      _celebrated = false;
      _clearNotice();
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
    _showNotice(
      outcome.isDraw
          ? 'DRAW'
          : '${_labelFor(outcome.winnerId!)} WINS'.toUpperCase(),
      tone: outcome.isDraw ? GameNoticeTone.info : GameNoticeTone.win,
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
        // A square platform in a tall column leaves a lot of shell showing
        // above and below it. At a 6% highlight that was flat black — dead
        // space rather than a lit room. The light now comes from the upper
        // left, which is also where the platform and every puck are lit from.
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.62),
          radius: 1.45,
          colors: [
            Color.lerp(shell, const Color(0xFFB9C6DA), 0.20)!,
            Color.lerp(shell, Colors.white, 0.04)!,
            shell,
            Color.lerp(shell, Colors.black, 0.55)!,
          ],
          stops: const [0.0, 0.28, 0.62, 1.0],
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
          // Far player (top), and the standing "whose turn" pill beside it.
          // Turn is a fact, not an event: it sits here permanently instead of
          // flashing across the platform for three seconds and leaving.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _PlayerChip(
                label: _labelFor(p2),
                remaining: state.liveCountOf(p2),
                pucksPerPlayer: state.pucksPerPlayer,
                accent: style.resolvePlayer2(scheme),
                active: _outcome == null && state.currentPlayerId == p2,
                winner: _outcome?.winnerId == p2,
              ),
              const SizedBox(width: 8),
              // No Spacer here: a Spacer is a flex-1 Expanded, so it split the
              // free width with the pill and left it ellipsising its own
              // player name. spaceBetween does the same job for free.
              Flexible(
                child: GamePill(
                  text: _outcome == null
                      ? '${_labelFor(state.currentPlayerId)}’s turn'
                      : 'Match over',
                  accent: _outcome == null
                      ? _accentFor(state.currentPlayerId)
                      : null,
                  dot: _outcome == null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                // Was 340, which left a 34pt margin of empty shell on a
                // 402pt phone for no reason. The tablet ceiling still applies.
                constraints: const BoxConstraints(maxWidth: 420),
                child: AspectRatio(
                  aspectRatio: 1, // square platform
                  // Clipped like every other board here: unclipped, the scene's
                  // own black backdrop met the shell in a hard rectangle.
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
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
                                strong: _noticeSticky,
                                autoDismiss: _noticeSticky
                                    ? null
                                    : const Duration(milliseconds: 1700),
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

  // Power mapping, measured against the sim: a light flick nudges, a flick at
  // ~40% starts clearing pucks, and full power scatters the far row (two off
  // on an angled strike) without the shooter running off the far lip on its
  // own — full power should be greedy, not suicidal.
  static const _aim = AimToImpulse(
    maxDrag: 200,
    maxImpulse: 22,
    minImpulse: 4,
    deadZone: 10,
  );

  // Livelier than the harness default: this is a game about momentum going
  // *through* a puck and out the other side, so contacts keep more of their
  // energy (restitution 0.3 -> 0.55) while friction takes speed out sooner.
  static const _simConfig = TableSimConfig(
    linearDamping: 0.8,
    restitution: 0.55,
  );

  /// Constant deceleration (world units/s²) applied on top of Forge2D's viscous
  /// [TableSimConfig.linearDamping], i.e. Coulomb friction — the kind a real
  /// surface applies, taking a fixed bite out of speed per second rather than a
  /// fraction of it.
  ///
  /// Why: pure viscous damping decays exponentially, so pucks never stop, they
  /// creep. Measured on the old constants every flick took **3.5–4.1 s** to
  /// trip the settle threshold, nearly all of it spent crawling. With this term
  /// the same flicks settle in 1.5–2.4 s and end on a definite stop.
  static const double _glideFriction = 1.2;

  late TableSimulation _sim;
  KnockoutState? _state;
  String _acting = '';
  DiscBody? _shooter;
  bool _launched = false;
  double _accum = 0;

  // Off-the-lip fall animation: purely visual, decoupled from the (trusted)
  // physics. When a disc is removed at an edge we spawn a [_Falling] that tips
  // over the lip; the reducer already treats it as gone.
  static const double _fallDuration = kKnockoutFallDuration;
  final List<_Falling> _falling = [];
  final Set<String> _fellIds = {};

  // Slide spin: a puck that only translates reads as gliding on rails. Each
  // disc integrates a facing angle from how far it has travelled, and the
  // painter turns its markings through it.
  final Map<String, SlideSpin> _spin = {};
  final Map<String, Vector2> _lastPos = {};

  // Contact rings — a short expanding pulse at the point of impact so a hit
  // lands as a beat rather than an instantaneous change of direction.
  static const double _impactDuration = 0.3;

  /// Closing speed that reads as a full-strength hit.
  static const double _impactReferenceSpeed = 14;
  final List<_Impact> _impacts = [];

  Offset? _aimStart;
  Offset? _aimNow;

  void Function()? onLaunch;

  /// Puck-on-puck contact, with a 0..1 strength from the closing speed.
  void Function(double strength)? onCollision;
  void Function()? onAimChanged;
  void Function(KnockoutMove move, KnockoutShotResult result)? onSettled;

  bool get canAim =>
      !_launched &&
      !_sim.isRunning &&
      (_state != null && _game.outcome(_state!) == null);

  bool get isAiming => _shooter != null && _aimStart != null && _aimNow != null;

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
      ..onDiscCollision = _handleContact
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
    // Discs are re-seated from state here, so drop the roll baseline — the jump
    // from the old pose to the new one must not be integrated as travel. The
    // accumulated facing itself carries over.
    _lastPos.clear();
    // A fresh match (New game) starts clean; mid-match rebuilds keep any
    // in-flight fall animating across the settle→rebuild.
    if (state.frame == 0) {
      _falling.clear();
      _fellIds.clear();
      _spin.clear();
      _impacts.clear();
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
    if (_impacts.isNotEmpty) {
      for (final i in _impacts) {
        i.t += dt;
      }
      _impacts.removeWhere((i) => i.t >= _impactDuration);
    }
    if (!_sim.isRunning) return;
    _accum += dt;
    var steps = 0;
    final h = _sim.config.fixedDt;
    while (_accum >= h && steps < 8) {
      _applyGlideFriction(h);
      _sim.step();
      _integrateSpin();
      _accum -= h;
      steps++;
      if (!_sim.isRunning) break;
    }
    _spawnFallsForNewlyRemoved();
  }

  /// Take a fixed bite out of every disc's speed each step — see
  /// [_glideFriction] for why viscous damping alone isn't enough.
  void _applyGlideFriction(double h) {
    for (final d in _sim.discs) {
      if (d.removed) continue;
      final v = d.body.linearVelocity;
      final speed = v.length;
      if (speed <= 1e-6) continue;
      final drop = math.min(_glideFriction * h, speed);
      v.scale((speed - drop) / speed);
    }
  }

  /// Turn each moving disc by how far it travelled this step.
  void _integrateSpin() {
    for (final d in _sim.discs) {
      if (d.removed) continue;
      final p = d.position;
      final prev = _lastPos[d.id];
      if (prev != null) {
        (_spin[d.id] ??= SlideSpin(d.id))
            .advance(p.x - prev.x, p.y - prev.y, d.radius);
      }
      _lastPos[d.id] = Vector2(p.x, p.y);
    }
  }

  /// Bridge a Forge2D contact into a strength-scaled cue plus a contact ring.
  /// Strength is the closing speed along the line of centres, normalized — a
  /// graze reads ~0, a full-power strike reads 1.
  void _handleContact(DiscBody a, DiscBody b) {
    final n = b.position - a.position;
    final len = n.length;
    if (len < 1e-6) return;
    n.scale(1 / len);
    final rel = a.body.linearVelocity - b.body.linearVelocity;
    final closing = rel.dot(n);
    if (closing <= 0) return; // separating — the tail of a contact, not a hit
    final strength = (closing / _impactReferenceSpeed).clamp(0.0, 1.0);
    final mid = (a.position + b.position)..scale(0.5);
    final nm = _toNorm(mid);
    _impacts.add(_Impact(nx: nm.nx, ny: nm.ny, strength: strength));
    onCollision?.call(strength);
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
      final maxOver = math.max(
          math.max(overTop, overBottom), math.max(overLeft, overRight));
      late final FallEdge edge;
      late final double along;
      late final double carry;
      late final double spinDir;
      if (maxOver == overLeft) {
        edge = FallEdge.left;
        along = n.ny.clamp(0.0, 1.0);
        carry = v.y / platform;
        spinDir = v.y >= 0 ? 1.0 : -1.0;
      } else if (maxOver == overRight) {
        edge = FallEdge.right;
        along = n.ny.clamp(0.0, 1.0);
        carry = v.y / platform;
        spinDir = v.y >= 0 ? -1.0 : 1.0;
      } else if (maxOver == overBottom) {
        edge = FallEdge.bottom;
        along = n.nx.clamp(0.0, 1.0);
        carry = v.x / platform;
        spinDir = v.x >= 0 ? -1.0 : 1.0;
      } else {
        edge = FallEdge.top;
        along = n.nx.clamp(0.0, 1.0);
        carry = v.x / platform;
        spinDir = v.x >= 0 ? 1.0 : -1.0;
      }
      // Exit speed perpendicular to the lip, normalized — a puck that dribbles
      // over topples slowly, one that is blasted off launches clear of it.
      final exit = switch (edge) {
        FallEdge.top || FallEdge.bottom => (v.y / platform).abs(),
        FallEdge.left || FallEdge.right => (v.x / platform).abs(),
      };
      _falling.add(_Falling(
        edge: edge,
        along: along,
        carry: carry,
        color: color,
        spinDir: spinDir,
        exit: exit.clamp(0.0, 1.6),
        spin0: _spin[d.id]?.angle ?? 0,
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
      // How close this puck is to a lip (0 = mid-slab, 1 = on the edge). The
      // painter tightens its contact shadow with it — there is less and less
      // slab under the puck to catch one.
      final margin = math.min(
        math.min(n.nx, 1 - n.nx),
        math.min(n.ny, 1 - n.ny),
      );
      pucks.add(
        RenderPuck(
          nx: n.nx,
          ny: n.ny,
          radiusFrac: puckR / platform,
          color: style.colorFor(scheme, owner, playerIds),
          flickable: highlightAll && owner == _acting,
          isShooter: identical(d, _shooter),
          spin: (_spin[d.id]?.angle ?? 0) + d.angle,
          edgeT: (1 - margin / 0.16).clamp(0.0, 1.0),
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
      falling.add(knockoutFallFrame(
        edge: f.edge,
        along: f.along,
        carry: f.carry,
        exit: f.exit,
        spinDir: f.spinDir,
        spin0: f.spin0,
        color: f.color,
        radiusFrac: puckR / platform,
        progress: (f.t / _fallDuration).clamp(0.0, 1.0),
      ));
    }

    final impacts = <ImpactRing>[
      for (final i in _impacts)
        ImpactRing(
          nx: i.nx,
          ny: i.ny,
          strength: i.strength,
          t: (i.t / _impactDuration).clamp(0.0, 1.0),
          radiusFrac: puckR / platform,
        ),
    ];

    paintKnockoutTable(
      canvas,
      Size(size.x, size.y),
      KnockoutView(
        pucks: pucks,
        aim: aim,
        falling: falling,
        impacts: impacts,
      ),
      style,
      scheme,
    );
  }
}

/// One in-flight off-the-lip fall. Scene-private; the painter gets a computed
/// [FallingPuck] each frame from [knockoutFallFrame].
class _Falling {
  final FallEdge edge;

  /// Position along the exiting lip (nx for [FallEdge.top]/[FallEdge.bottom];
  /// ny for the sides).
  final double along;

  /// Normalized velocity component parallel to that lip.
  final double carry;

  /// Normalized speed perpendicular to the lip at the moment it left.
  final double exit;
  final double spinDir;

  /// Facing the disc had accumulated when it went over.
  final double spin0;
  final Color color;
  double t = 0;

  _Falling({
    required this.edge,
    required this.along,
    required this.carry,
    required this.exit,
    required this.color,
    required this.spinDir,
    required this.spin0,
  });
}

/// One live contact pulse (scene-private; the painter gets an [ImpactRing]).
class _Impact {
  final double nx;
  final double ny;
  final double strength;
  double t = 0;

  _Impact({required this.nx, required this.ny, required this.strength});
}

/// A disc's accumulated facing, integrated from how far it has slid.
///
/// A knockout puck is a flat disc: it does not roll like a ball, but it does
/// *turn* as it travels, and its markings turning is the difference between a
/// puck that slides and a sprite that is being dragged around. The angle grows
/// with distance travelled over radius (so it is frame-rate and speed
/// independent — the same journey always produces the same turn), scaled by
/// [turnsPerRadius] to keep it a lazy drift rather than a spin.
///
/// Direction is fixed per disc id, so neighbouring pucks turn opposite ways.
class SlideSpin {
  /// Radians turned per radius travelled.
  static const double turnsPerRadius = 0.16;

  double _angle = 0;
  final double _dir;

  SlideSpin(String id) : _dir = (id.hashCode & 1) == 0 ? 1.0 : -1.0;

  /// Accumulated facing in radians.
  double get angle => _angle;

  /// Turn after travelling ([dx], [dy]) with the given [radius] (same units).
  void advance(double dx, double dy, double radius) {
    if (radius <= 0) return;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1e-9) return;
    _angle += (dist / radius) * turnsPerRadius * _dir;
  }
}

/// How long a puck takes to tip over a lip and fall out of sight.
const double kKnockoutFallDuration = 0.68;

/// Fraction of [kKnockoutFallDuration] spent tipping over the lip before the
/// puck is clear of it and simply falling into the void.
const double _kTipPhase = 0.30;

/// The drawable state of a puck [progress] (0..1) through its fall off [edge].
///
/// Pure, so the fall reads identically in the live scene and in tests. This is
/// the animation the whole game hangs on — knocking pucks off IS knockout — so
/// it is modelled in two beats rather than a fade:
///
/// 1. **Tip** — the puck pivots over the lip. It walks outward from the edge
///    while foreshortening along the axis perpendicular to the lip, and its
///    cylindrical side wall comes into view ([FallingPuck.rim]), which is what
///    actually reads as *tipping* rather than shrinking.
/// 2. **Fall** — clear of the lip, it drops into the void. Because the camera
///    looks down on the slab, a falling puck tracks outward along the ray it
///    left on while getting smaller, so drift and scale move together. It keeps
///    the lateral momentum it left with ([carry]), keeps tumbling, sinks into
///    the dark and fades.
FallingPuck knockoutFallFrame({
  required FallEdge edge,
  required double along,
  required double carry,
  required double exit,
  required double spinDir,
  required double spin0,
  required Color color,
  required double radiusFrac,
  required double progress,
}) {
  final p = progress.clamp(0.0, 1.0);
  final tip = (p / _kTipPhase).clamp(0.0, 1.0);
  final fall = p <= _kTipPhase ? 0.0 : (p - _kTipPhase) / (1 - _kTipPhase);
  // Gravity: distance grows with the square of time, and a puck blasted off
  // carries further out before the drop takes over.
  final drop = fall * fall;
  final outward =
      0.010 * tip + (0.070 + 0.055 * exit) * drop + 0.028 * exit * fall;

  // Tumble: the disc pitches over the lip, so the face we see foreshortens to
  // an edge and then opens back out — |cos| of a pitch that keeps turning.
  // Tumbling is constant angular velocity, so the pitch runs on *time*
  // ([fall]), not on the quadratic drop — driving it from the drop left the
  // puck stuck edge-on and invisible through the middle of the animation.
  final pitch = 3.1 * (0.42 * tip + 0.58 * fall);
  final foreshorten = math.max(0.06, math.cos(pitch).abs());
  final rim = (1 - foreshorten).clamp(0.0, 1.0);

  // Perspective: further away is smaller.
  final scale = 1 / (1 + 1.8 * drop);

  // Lateral momentum keeps carrying it along the lip, bleeding off as it falls.
  final slide = carry * (0.10 * tip + 0.16 * fall);

  double nx, ny, sx, sy, rimDx, rimDy;
  switch (edge) {
    case FallEdge.top:
      nx = along + slide;
      ny = -outward;
      sx = 1;
      sy = foreshorten;
      rimDx = 0;
      rimDy = -1;
    case FallEdge.bottom:
      nx = along + slide;
      ny = 1 + outward;
      sx = 1;
      sy = foreshorten;
      rimDx = 0;
      rimDy = 1;
    case FallEdge.left:
      nx = -outward;
      ny = along + slide;
      sx = foreshorten;
      sy = 1;
      rimDx = -1;
      rimDy = 0;
    case FallEdge.right:
      nx = 1 + outward;
      ny = along + slide;
      sx = foreshorten;
      sy = 1;
      rimDx = 1;
      rimDy = 0;
  }

  return FallingPuck(
    nx: nx,
    ny: ny,
    radiusFrac: radiusFrac,
    color: Color.lerp(color, Colors.black, 0.26 * tip + 0.46 * drop)!,
    scale: scale,
    squashX: sx,
    squashY: sy,
    alpha: p < 0.66 ? 1.0 : (1 - (p - 0.66) / 0.34),
    spin: spin0 + spinDir * (0.5 * tip + 2.4 * fall),
    rim: rim,
    rimDx: rimDx,
    rimDy: rimDy,
  );
}

// ---------------------------------------------------------------------------
// Shared table painter — used by the live scene AND by static previews/tests.
// ---------------------------------------------------------------------------

/// Which open lip a disc slid off — drives how its fall tips over the edge.
enum FallEdge { top, bottom, left, right }

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

  /// Accumulated facing in radians (see [SlideSpin]). The markings turn through
  /// it; the body shading does not, since the light does not move.
  final double spin;

  /// 0 mid-slab, 1 right on a lip. Tightens the contact shadow — there is less
  /// and less slab under the puck for one to fall on.
  final double edgeT;

  const RenderPuck({
    required this.nx,
    required this.ny,
    required this.radiusFrac,
    required this.color,
    this.flickable = false,
    this.isShooter = false,
    this.spin = 0,
    this.edgeT = 0,
  });
}

/// A short expanding pulse at the point of a puck-on-puck contact.
class ImpactRing {
  final double nx;
  final double ny;

  /// 0..1 closing speed of the hit.
  final double strength;

  /// 0..1 progress through the pulse.
  final double t;

  /// Puck radius as a fraction of the platform width (sets the ring's scale).
  final double radiusFrac;

  const ImpactRing({
    required this.nx,
    required this.ny,
    required this.strength,
    required this.t,
    required this.radiusFrac,
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

  /// How much of the puck's cylindrical side wall is turned toward the viewer
  /// (0 = flat on, face only; 1 = fully edge-on). Seeing the edge come round is
  /// what reads as *tipping* rather than merely shrinking.
  final double rim;

  /// Unit direction, in screen space, pointing away from the lip it left by —
  /// the side wall is drawn on that side of the face.
  final double rimDx;
  final double rimDy;

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
    this.rim = 0,
    this.rimDx = 0,
    this.rimDy = -1,
  });
}

/// Everything one frame of the board needs.
class KnockoutView {
  final List<RenderPuck> pucks;
  final AimView? aim;
  final List<FallingPuck> falling;
  final List<ImpactRing> impacts;

  const KnockoutView({
    required this.pucks,
    this.aim,
    this.falling = const [],
    this.impacts = const [],
  });
}

/// The one committed light for this board: a source above and to the
/// upper-left. Every bevel, edge and cast shadow in this file obeys it —
/// highlights sit on the upper-left of a form, shadows fall down-right.
const Alignment _kLight = Alignment(-0.40, -0.55);
const Offset _kShadowDir = Offset(0.42, 0.66);

/// Draws the void, the raised slab with its lit top face and visible edge
/// thickness, the pucks and the aim indicator into [size]. Pure — no Flame or
/// widget state — so a `CustomPainter` can call it for a static snapshot
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

  final w = size.width;
  final full = Offset.zero & size;

  // Platform inset so a ring of void shows all round — the cliff you fall off.
  // Slightly tighter at the top than the bottom: the camera is above and in
  // front, so more of the slab's near side is visible than its far side.
  // The margin is deliberately generous: knocking pucks off IS this game, so
  // the fall needs somewhere to happen. Too tight a ring of void and a puck
  // leaves the canvas before it has finished tipping.
  final margin = w * 0.135;
  final platRect = Rect.fromLTRB(
    margin,
    margin * 0.82,
    size.width - margin,
    size.height - margin * 1.18,
  );
  final platRR = RRect.fromRectAndRadius(platRect, Radius.circular(w * 0.085));

  /// How thick the slab is, in pixels of its exposed side wall.
  final depth = w * 0.055;

  _paintVoid(canvas, size, voidColor, platRect);

  // --- the slab's own body: a real extruded edge, not a drop shadow ---------
  // Occlusion pooling under the slab where it meets the void.
  canvas.drawRRect(
    platRR.shift(Offset(depth * 0.45, depth * 1.5)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.72)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.055),
  );
  // Side wall, built up from the bottom of the extrusion to the top face so it
  // reads as a continuous surface curving out of the light.
  const steps = 56;
  for (var i = steps; i >= 1; i--) {
    final t = i / steps;
    canvas.drawRRect(
      platRR.shift(Offset(0, depth * t)),
      Paint()
        ..color = Color.lerp(
          Color.lerp(platformColor, Colors.black, 0.86)!,
          Color.lerp(platformColor, Colors.black, 0.42)!,
          1 - t,
        )!,
    );
  }

  // --- the lit top face -----------------------------------------------------
  canvas.drawRRect(
    platRR,
    Paint()
      ..shader = RadialGradient(
        center: _kLight,
        radius: 1.25,
        colors: [
          Color.lerp(platformColor, Colors.white, 0.30)!,
          platformColor,
          Color.lerp(platformColor, Colors.black, 0.30)!,
        ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(platRect),
  );

  canvas.save();
  canvas.clipRRect(platRR);

  double xOf(double nx) => platRect.left + nx * platRect.width;
  double yOf(double ny) => platRect.top + ny * platRect.height;

  _paintStoneSurface(canvas, platRect, platformColor);

  // Faint half-court line so the two territories read.
  canvas.drawLine(
    Offset(platRect.left, yOf(0.5)),
    Offset(platRect.right, yOf(0.5)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.13)
      ..strokeWidth = math.max(1, w * 0.005),
  );
  canvas.drawLine(
    Offset(platRect.left, yOf(0.5) + math.max(1, w * 0.004)),
    Offset(platRect.right, yOf(0.5) + math.max(1, w * 0.004)),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = math.max(0.8, w * 0.003),
  );
  // Centre emblem, cut into the stone.
  for (final (rf, alpha, dy) in [
    (0.062, 0.12, 0.0),
    (0.062, 0.16, 0.004),
    (0.030, 0.09, 0.0),
  ]) {
    canvas.drawCircle(
      Offset(xOf(0.5), yOf(0.5) + w * dy),
      w * rf,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, w * 0.005)
        ..color =
            (dy > 0 ? Colors.white : Colors.black).withValues(alpha: alpha),
    );
  }

  // Inner occlusion: the slab's own rim shades the surface just inside it.
  canvas.drawRRect(
    platRR.deflate(w * 0.026),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.052
      ..color = Colors.black.withValues(alpha: 0.16)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.026),
  );

  // Pucks.
  for (final p in view.pucks) {
    _paintPuck(
      canvas,
      Offset(xOf(p.nx), yOf(p.ny)),
      p.radiusFrac * platRect.width,
      p,
    );
  }

  // Contact pulses, over the pucks so a hit reads even in a cluster.
  for (final i in view.impacts) {
    _paintImpact(
      canvas,
      Offset(xOf(i.nx), yOf(i.ny)),
      i.radiusFrac * platRect.width,
      i,
    );
  }

  // Aim indicator.
  final aim = view.aim;
  if (aim != null) {
    _paintAim(
        canvas, Offset(xOf(aim.nx), yOf(aim.ny)), aim, platRect.width, size);
  }

  canvas.restore();

  // The lip: the edge you fall off. Catches the light on the upper-left and
  // turns hard into shadow on the lower-right, which is what makes the slab
  // read as a solid object with a top rather than a painted rectangle.
  canvas.drawRRect(
    platRR.deflate(w * 0.004),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, w * 0.007)
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.10),
          Colors.black.withValues(alpha: 0.35),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(platRect),
  );
  // Dark shoulder just past the lip, so the edge has a hard silhouette against
  // the void no matter what is behind it.
  canvas.drawRRect(
    platRR.inflate(w * 0.002),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.005)
      ..color = Colors.black.withValues(alpha: 0.55),
  );

  // Vignette, so the board sits in a space rather than on a page.
  canvas.drawRect(
    full,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.1, -0.2),
        radius: 1.1,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.16),
          Colors.black.withValues(alpha: 0.44),
        ],
        stops: const [0.5, 0.8, 1.0],
      ).createShader(full),
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

/// The void the slab floats over. Not a flat dark rectangle: a shaft with a
/// faint floor a long way down, so "off the edge" reads as *depth* — which is
/// the whole stake of the game.
void _paintVoid(Canvas canvas, Size size, Color voidColor, Rect plat) {
  final full = Offset.zero & size;
  canvas.drawRect(
    full,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.05),
        radius: 0.95,
        colors: [
          Color.lerp(voidColor, Colors.white, 0.08)!,
          voidColor,
          Color.lerp(voidColor, Colors.black, 0.7)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(full),
  );

  final c = plat.center;
  // Walls of the shaft: lines running from the slab's corners toward the
  // vanishing point, i.e. straight down into the pit.
  final wall = Paint()
    ..color = Colors.white.withValues(alpha: 0.032)
    ..strokeWidth = math.max(0.8, size.width * 0.003);
  for (var i = 0; i <= 6; i++) {
    final t = i / 6;
    for (final p in [
      Offset(plat.left, plat.top + plat.height * t),
      Offset(plat.right, plat.top + plat.height * t),
      Offset(plat.left + plat.width * t, plat.top),
      Offset(plat.left + plat.width * t, plat.bottom),
    ]) {
      final away = p + (p - c) * 0.42;
      canvas.drawLine(p, away, wall);
    }
  }
  // The floor of the shaft, glimpsed: concentric rings fading out.
  for (var i = 1; i <= 3; i++) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: c,
          width: plat.width * (1 + i * 0.16),
          height: plat.height * (1 + i * 0.16),
        ),
        Radius.circular(size.width * 0.085 * (1 + i * 0.16)),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, size.width * 0.003)
        ..color = Colors.white.withValues(alpha: 0.075 - i * 0.018),
    );
  }
  // Motes drifting in the shaft — the cheapest possible read of "there is air
  // between the slab and the bottom".
  final rnd = math.Random(19);
  for (var i = 0; i < 26; i++) {
    final p = Offset(
      rnd.nextDouble() * size.width,
      rnd.nextDouble() * size.height,
    );
    if (plat.deflate(-size.width * 0.01).contains(p)) continue;
    canvas.drawCircle(
      p,
      size.width * (0.0015 + rnd.nextDouble() * 0.0025),
      Paint()
        ..color =
            Colors.white.withValues(alpha: 0.05 + rnd.nextDouble() * 0.09),
    );
  }
}

/// Cast-stone texture on the top face: fine speckle plus a couple of shallow
/// scuffs, at an alpha that registers as material rather than as noise.
void _paintStoneSurface(Canvas canvas, Rect plat, Color base) {
  final rnd = math.Random(5);
  for (var i = 0; i < 220; i++) {
    final p = Offset(
      plat.left + rnd.nextDouble() * plat.width,
      plat.top + rnd.nextDouble() * plat.height,
    );
    final dark = rnd.nextBool();
    canvas.drawCircle(
      p,
      plat.width * (0.0012 + rnd.nextDouble() * 0.0022),
      Paint()
        ..color = (dark ? Colors.black : Colors.white)
            .withValues(alpha: dark ? 0.055 : 0.075),
    );
  }
  for (var i = 0; i < 7; i++) {
    final y = plat.top + (0.1 + 0.8 * rnd.nextDouble()) * plat.height;
    final x = plat.left + (0.1 + 0.7 * rnd.nextDouble()) * plat.width;
    canvas.drawLine(
      Offset(x, y),
      Offset(x + plat.width * (0.04 + rnd.nextDouble() * 0.12),
          y + plat.height * (rnd.nextDouble() - 0.5) * 0.02),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.05)
        ..strokeWidth = math.max(0.8, plat.width * 0.0035),
    );
  }
}

void _paintImpact(Canvas canvas, Offset c, double r, ImpactRing i) {
  final t = i.t.clamp(0.0, 1.0);
  if (t >= 1 || i.strength <= 0.02) return;
  final ease = 1 - math.pow(1 - t, 2.2).toDouble();
  final radius = r * (0.55 + 1.7 * ease);
  final fade = (1 - t) * (1 - t);
  canvas.drawCircle(
    c,
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, r * 0.18 * (1 - 0.7 * t))
      ..color = Colors.white.withValues(alpha: 0.6 * i.strength * fade),
  );
  if (t < 0.35) {
    canvas.drawCircle(
      c,
      r * 0.7,
      Paint()
        ..color =
            Colors.white.withValues(alpha: 0.25 * i.strength * (1 - t / 0.35))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.4),
    );
  }
}

void _paintFallingPuck(Canvas canvas, Offset c, double r, FallingPuck f) {
  if (r <= 0.3 || f.alpha <= 0.01) return;
  final bounds = Rect.fromCircle(center: c, radius: r * 3);
  canvas.saveLayer(
    bounds,
    Paint()..color = Colors.white.withValues(alpha: f.alpha.clamp(0.0, 1.0)),
  );

  final sx = f.scale * f.squashX;
  final sy = f.scale * f.squashY;

  // The cylindrical side wall, revealed on the far side of the face as the
  // puck tips over the lip. Drawn first so the face sits on top of it.
  if (f.rim > 0.02) {
    final thick = r * 0.36 * f.rim * f.scale;
    final side = Offset(f.rimDx, f.rimDy) * thick;
    canvas.save();
    canvas.translate(c.dx + side.dx, c.dy + side.dy);
    canvas.scale(sx, sy);
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()..color = Color.lerp(f.color, Colors.black, 0.58)!,
    );
    canvas.restore();
  }

  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.scale(sx, sy);
  canvas.translate(-c.dx, -c.dy);
  _paintPuckFace(canvas, c, r, f.color, f.spin);
  canvas.restore();

  canvas.restore();
}

/// The body + cap of one puck, with every marking that should turn as it slides
/// drawn through [spin]. Shared by resting and falling pucks so a puck looks
/// like the same object on its way over the lip.
void _paintPuckFace(
    Canvas canvas, Offset c, double r, Color base, double spin) {
  // Moulded body.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = RadialGradient(
        center: _kLight,
        colors: [
          Color.lerp(base, Colors.white, 0.46)!,
          base,
          Color.lerp(base, Colors.black, 0.42)!,
        ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r)),
  );

  // Grip flutes around the rim — the clearest read of rotation on the puck.
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(spin);
  final flute = Paint()
    ..color = Colors.black.withValues(alpha: 0.20)
    ..strokeWidth = math.max(0.7, r * 0.075)
    ..strokeCap = StrokeCap.round;
  final fluteLit = Paint()
    ..color = Colors.white.withValues(alpha: 0.16)
    ..strokeWidth = math.max(0.5, r * 0.045)
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 12; i++) {
    final a = i * (math.pi * 2 / 12);
    final ca = math.cos(a), sa = math.sin(a);
    canvas.drawLine(
      Offset(ca * r * 0.74, sa * r * 0.74),
      Offset(ca * r * 0.93, sa * r * 0.93),
      flute,
    );
    final a2 = a + 0.13;
    canvas.drawLine(
      Offset(math.cos(a2) * r * 0.76, math.sin(a2) * r * 0.76),
      Offset(math.cos(a2) * r * 0.91, math.sin(a2) * r * 0.91),
      fluteLit,
    );
  }
  canvas.restore();

  // Rim light / rim shade, fixed to the light (these must NOT rotate).
  final rimRect = Rect.fromCircle(center: c, radius: r * 0.92);
  canvas.drawArc(
    rimRect,
    math.pi * 1.06,
    math.pi * 0.72,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.12
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.45),
  );
  canvas.drawArc(
    rimRect,
    math.pi * 0.10,
    math.pi * 0.70,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.12
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.32),
  );

  // Inset cap.
  final capR = r * 0.60;
  canvas.drawCircle(
    c,
    capR,
    Paint()
      ..shader = RadialGradient(
        center: -_kLight, // the cap is recessed, so its shading is inverted
        colors: [
          Color.lerp(base, Colors.white, 0.26)!,
          Color.lerp(base, Colors.black, 0.22)!,
        ],
      ).createShader(Rect.fromCircle(center: c, radius: capR)),
  );
  canvas.drawCircle(
    c,
    capR,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, r * 0.055)
      ..color = Colors.black.withValues(alpha: 0.26),
  );

  // Cap marking — a bar and an index pip, both turning with the puck.
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(spin);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset.zero, width: capR * 1.24, height: capR * 0.26),
      Radius.circular(capR * 0.13),
    ),
    Paint()..color = Colors.white.withValues(alpha: 0.34),
  );
  canvas.drawCircle(
    Offset(0, -capR * 0.62),
    capR * 0.16,
    Paint()..color = Colors.white.withValues(alpha: 0.30),
  );
  canvas.restore();

  // Specular hit, fixed to the light.
  canvas.save();
  canvas.translate(c.dx + _kLight.x * r * 0.52, c.dy + _kLight.y * r * 0.52);
  canvas.rotate(-0.6);
  canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: r * 0.60, height: r * 0.30),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.34)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.14),
  );
  canvas.restore();

  // Silhouette.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, r * 0.05)
      ..color = Colors.black.withValues(alpha: 0.42),
  );
}

void _paintPuck(Canvas canvas, Offset c, double r, RenderPuck p) {
  if (r <= 0.4) return;
  // Contact shadow. Near a lip it tightens and pulls in: there is less slab
  // left to catch it, which is the visual tell that this puck is one nudge
  // from going over.
  final e = p.edgeT.clamp(0.0, 1.0);
  canvas.drawCircle(
    c + _kShadowDir * (r * 0.30 * (1 - 0.55 * e)),
    r * (0.98 - 0.14 * e),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.42 - 0.10 * e)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * (0.32 - 0.16 * e)),
  );
  // Flickable halo behind the acting player's pucks.
  if (p.flickable) {
    canvas.drawCircle(
      c,
      r * 1.30,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..color = Colors.white.withValues(alpha: 0.45),
    );
  }
  // Aimed puck gets a stronger halo.
  if (p.isShooter) {
    canvas.drawCircle(
      c,
      r * 1.46,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.11
        ..color = Colors.white.withValues(alpha: 0.75),
    );
  }
  _paintPuckFace(canvas, c, r, p.color, p.spin);
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
      ? Color.lerp(
          const Color(0xFF3FBF63), const Color(0xFFF5A623), aim.power / 0.5)!
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
          // Pucks still standing is the whole scoreboard here — it outweighs
          // the name beside it rather than matching it.
          Text(
            '$remaining',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 19,
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
