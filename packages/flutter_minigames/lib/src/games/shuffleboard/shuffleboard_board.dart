import 'dart:async';
import 'dart:math' as math;

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

  // The transient centre message. Held as plain fields and handed to a single
  // GameNotice, which owns the animation and the retract timer — the board no
  // longer runs a Timer of its own, and repeating the same text (two "+8"s in a
  // row is ordinary play) can never collide with its own outgoing copy.
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
    _clearNotice();
    _confetti = const [];
    final s = widget.controller.state;
    _state = s;
    _outcome = s == null ? null : _game.outcome(s);
    if (s != null) {
      scene.applyState(s, _actingFor(s));
      // Whose slide it is is a standing fact, not an event: it lives in the
      // header GamePill, so binding announces nothing.
      if (_outcome != null) _celebrated = true;
    }
    _sub = widget.controller.stateStream.listen(_onState);
  }

  /// Raises the centre notice. Assigns synchronously — callers own the
  /// surrounding setState. [sticky] keeps it up (the win); everything else
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

  String _actingFor(ShuffleboardState s) =>
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
    // harder hit still gets through — otherwise the loudest moment of a break
    // is the one that gets swallowed.
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
    // The seat that actually took this slide — read before submitMove, which
    // can hand the turn over synchronously.
    final shooter = _state?.currentPlayerId;
    final (text, tone) = switch (status) {
      PuckStatus.inZone when value > 0 => (
          '+$value ${value == 1 ? 'POINT' : 'POINTS'}',
          GameNoticeTone.score,
        ),
      PuckStatus.inZone => ('IN THE ZONE', GameNoticeTone.info),
      PuckStatus.offEnd => ('OFF THE END', GameNoticeTone.warn),
      PuckStatus.foul => ('FOUL', GameNoticeTone.warn),
      PuckStatus.onBoard => ('ON THE BOARD', GameNoticeTone.info),
    };
    // Submit the settled outcome as the move.
    widget.controller.submitMove(move);
    if (!mounted) return;
    setState(() => _showNotice(
          text,
          tone: tone,
          // A score wears the shooter's colour, so the notice says who as well
          // as what; a refusal keeps the warn red.
          accent: tone == GameNoticeTone.score && shooter != null
              ? _accentFor(shooter)
              : null,
        ));
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
    } else if (outcome == null && isFresh) {
      // New game: drop whatever the last match ended on. Whose slide it is
      // reads off the header pill, so there is nothing to announce.
      _celebrated = false;
      _clearNotice();
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

  /// Seat colour, resolved against the cached scheme so callbacks off the
  /// build path can use it too.
  Color _accentFor(String playerId) {
    final s = _state;
    final isP1 = s == null || playerId == s.playerIds.first;
    return isP1
        ? widget.style.resolvePlayer1(_scheme)
        : widget.style.resolvePlayer2(_scheme);
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
          // Far player (top), and the standing "whose slide" pill beside it.
          // Turn is a fact, not an event: it sits here permanently instead of
          // flashing across the lane for three seconds and leaving.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _PlayerChip(
                label: _labelFor(p2),
                score: state.scoreOf(p2),
                remaining: state.remainingOf(p2),
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
                      ? '${_labelFor(state.currentPlayerId)}’s slide'
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

  // Power mapping. Measured against the sim (see the tuning note on
  // [_glideFriction]): with the friction model below, an impulse of 14 is the
  // point where a straight slide just runs off the far lip, so mapping full
  // drag to 14 spends the *whole* drag range on outcomes the player wants —
  // foul → on-board → 1 → 2 → 3 → off the end. The old maxImpulse of 20 threw
  // away the top 40% of the drag (everything above ~0.6 power was "off the
  // end"), which is what made hard shots feel unreadable.
  static const _aim = AimToImpulse(
    maxDrag: 200,
    maxImpulse: 14,
    minImpulse: 4,
    deadZone: 10,
  );

  // Lower linear damping than the harness default (1.7) so the disc carries far
  // enough down a 13-unit lane to reach the far scoring bands.
  static const _simConfig = TableSimConfig(linearDamping: 0.95);

  /// Constant deceleration (world units/s²) applied on top of Forge2D's viscous
  /// [TableSimConfig.linearDamping], i.e. Coulomb friction — the wax-and-sand
  /// kind, which takes a fixed bite out of speed per second instead of a
  /// fraction of it.
  ///
  /// Why: pure viscous damping decays exponentially, so a puck never actually
  /// stops — it creeps. Measured on the old constants, every single slide took
  /// **4.2–5.2 s** to trip the settle threshold, most of it spent crawling the
  /// last half-unit. With this term the same shots settle in 1.6–2.7 s and,
  /// more importantly, the last moment of travel is a definite stop rather than
  /// an asymptote. [_simConfig] damping was dropped 1.15 → 0.95 so the reachable
  /// distance stays in the same ballpark.
  static const double _glideFriction = 1.6;

  late TableSimulation _sim;
  ShuffleboardState? _state;
  String _acting = '';
  DiscBody? _shooter;
  bool _launched = false;
  double _accum = 0;

  // Off-the-far-end fall animation: purely visual, decoupled from the (trusted)
  // physics. When a disc is removed at the edge we spawn a [_Falling] that
  // tumbles over the lip; scoring already treated it as off-end.
  static const double _fallDuration = kShuffleboardFallDuration;
  final List<_Falling> _falling = [];
  final Set<String> _fellIds = {};

  // Slide spin: a puck that only translates reads as gliding on rails. Each
  // disc integrates a facing angle from how far it has travelled, and the
  // painter turns its cap markings through it.
  final Map<String, ShuffleboardSlideSpin> _spin = {};
  final Map<String, Vector2> _lastPos = {};

  // Contact rings — a short expanding pulse at the point of impact so a hit
  // lands as a beat rather than an instantaneous change of direction.
  static const double _impactDuration = 0.3;

  /// Closing speed that reads as a full-strength hit. A full-power slide leaves
  /// the hand at roughly 16 units/s, so a head-on strike at speed saturates.
  static const double _impactReferenceSpeed = 12;
  final List<_Impact> _impacts = [];

  /// Where the current shooter starts across the lane (0 = left rail,
  /// 1 = right rail). Reset to centre for every new slide; the below-board
  /// slider drives it.
  double _startNx = 0.5;
  double get startNx => _startNx;

  Offset? _aimStart;
  Offset? _aimNow;

  void Function()? onLaunch;

  /// Puck-on-puck contact, with a 0..1 strength from the closing speed.
  void Function(double strength)? onCollision;
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
      ..onDiscCollision = _handleContact
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
    // Discs are re-seated from state here, so drop the roll baseline — the jump
    // from the old pose to the new one must not be integrated as travel. The
    // accumulated facing itself carries over, so a puck keeps the orientation
    // it came to rest at.
    _lastPos.clear();
    // A fresh match (New game) starts with a clean slate; mid-match rebuilds
    // keep any in-flight fall animating across the settle→rebuild.
    if (state.pucks.isEmpty && state.frame == 0) {
      _falling.clear();
      _fellIds.clear();
      _spin.clear();
      _impacts.clear();
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
        (_spin[d.id] ??= ShuffleboardSlideSpin(d.id))
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
      late final ShuffleboardFallEdge edge;
      late final double along;
      late final double carry;
      late final double spinDir;
      if (overLeft >= overTop && overLeft >= overRight) {
        edge = ShuffleboardFallEdge.left;
        along = n.ny.clamp(0.0, 1.0);
        carry = v.y / tableL;
        spinDir = v.y >= 0 ? 1.0 : -1.0;
      } else if (overRight >= overTop && overRight >= overLeft) {
        edge = ShuffleboardFallEdge.right;
        along = n.ny.clamp(0.0, 1.0);
        carry = v.y / tableL;
        spinDir = v.y >= 0 ? -1.0 : 1.0;
      } else {
        edge = ShuffleboardFallEdge.top;
        along = n.nx.clamp(0.0, 1.0);
        carry = v.x / tableW;
        spinDir = v.x >= 0 ? 1.0 : -1.0;
      }
      // Exit speed perpendicular to the lip, normalized — a puck that dribbles
      // over topples slowly, one that is blasted off launches clear of it.
      final exit = switch (edge) {
        ShuffleboardFallEdge.top || ShuffleboardFallEdge.bottom => (-v.y / tableL).abs(),
        ShuffleboardFallEdge.left || ShuffleboardFallEdge.right => (v.x / tableW).abs(),
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

    final pucks = <ShuffleboardRenderPuck>[];
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
        ShuffleboardRenderPuck(
          nx: n.nx,
          ny: n.ny,
          radiusFrac: puckR / tableW,
          color: style.colorFor(scheme, owner, playerIds),
          score: score,
          isShooter: identical(d, _shooter),
          spin: (_spin[d.id]?.angle ?? 0) + d.angle,
        ),
      );
    }

    ShuffleboardAimView? aim;
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
      aim = ShuffleboardAimView(nx: n.nx, ny: n.ny, dir: dir, power: power);
    }

    final falling = <ShuffleboardFallingPuck>[];
    for (final f in _falling) {
      falling.add(shuffleboardFallFrame(
        edge: f.edge,
        along: f.along,
        carry: f.carry,
        exit: f.exit,
        spinDir: f.spinDir,
        spin0: f.spin0,
        color: f.color,
        radiusFrac: puckR / tableW,
        progress: (f.t / _fallDuration).clamp(0.0, 1.0),
        aspect: tableW / tableL,
      ));
    }

    final impacts = <ShuffleboardImpactRing>[
      for (final i in _impacts)
        ShuffleboardImpactRing(
          nx: i.nx,
          ny: i.ny,
          strength: i.strength,
          t: (i.t / _impactDuration).clamp(0.0, 1.0),
          radiusFrac: puckR / tableW,
        ),
    ];

    paintShuffleboardTable(
      canvas,
      Size(size.x, size.y),
      ShuffleboardView(
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

/// One in-flight off-the-edge fall. Scene-private; the painter gets a computed
/// [ShuffleboardFallingPuck] each frame from [shuffleboardFallFrame].
class _Falling {
  final ShuffleboardFallEdge edge;

  /// Position along the exiting edge (nx for [ShuffleboardFallEdge.top]; ny for the sides).
  final double along;

  /// Normalized velocity component parallel to that edge (carries the disc
  /// along the lip as it drops).
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

/// One live contact pulse (scene-private; the painter gets an [ShuffleboardImpactRing]).
class _Impact {
  final double nx;
  final double ny;
  final double strength;
  double t = 0;

  _Impact({required this.nx, required this.ny, required this.strength});
}

/// A disc's accumulated facing, integrated from how far it has slid.
///
/// A shuffleboard weight is a flat disc: it does not roll like a ball, but it
/// does *turn* as it travels, and its cap markings turning is the difference
/// between a puck that slides and a sprite that is being dragged around. The
/// angle grows with distance travelled over radius (so it is frame-rate and
/// speed independent — the same journey always produces the same turn), scaled
/// by [turnsPerRadius] to keep it a lazy drift rather than a spin.
///
/// Direction is fixed per disc id: two pucks side by side turn opposite ways,
/// which reads as each one having its own bias, exactly like real weights.
class ShuffleboardSlideSpin {
  /// Radians turned per radius travelled.
  static const double turnsPerRadius = 0.16;

  double _angle = 0;
  final double _dir;

  ShuffleboardSlideSpin(String id) : _dir = (id.hashCode & 1) == 0 ? 1.0 : -1.0;

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
const double kShuffleboardFallDuration = 0.62;

/// Fraction of [kShuffleboardFallDuration] spent tipping over the lip before
/// the puck is clear of it and simply falling.
const double _kTipPhase = 0.32;

/// The drawable state of a puck [progress] (0..1) through its fall off [edge].
///
/// Pure, so the fall reads identically in the live scene and in tests. The
/// model is two beats:
///
/// 1. **Tip** — the puck pivots over the lip. It walks outward from just inside
///    the edge to just past it while foreshortening along the axis
///    perpendicular to the lip, and its cylindrical side wall comes into view
///    ([ShuffleboardFallingPuck.rim]) — which is what actually says "tipping" rather than
///    "shrinking".
/// 2. **Fall** — clear of the lip, it drops away from the camera. Because the
///    camera looks down at the table, a falling puck tracks *outward* along the
///    ray it left on while getting smaller, so outward drift and scale are tied
///    together. It keeps the lateral momentum it left with ([carry]), keeps
///    tumbling (the perpendicular squash swings through edge-on and opens back
///    out on the far face), sinks into shadow and fades.
ShuffleboardFallingPuck shuffleboardFallFrame({
  required ShuffleboardFallEdge edge,
  required double along,
  required double carry,
  required double exit,
  required double spinDir,
  required double spin0,
  required Color color,
  required double radiusFrac,
  required double progress,
  double aspect = 1,
}) {
  final p = progress.clamp(0.0, 1.0);
  // Outward displacement, in normalized board units, measured from the lip.
  final tip = (p / _kTipPhase).clamp(0.0, 1.0);
  final fall = p <= _kTipPhase ? 0.0 : (p - _kTipPhase) / (1 - _kTipPhase);
  // Gravity: distance grows with the square of time, and a puck blasted off
  // carries further out before the drop takes over.
  final drop = fall * fall;
  final outward =
      0.012 * tip + (0.075 + 0.055 * exit) * drop + 0.030 * exit * fall;

  // Tumble: the disc pitches over the lip, so the face we see foreshortens to
  // an edge and then opens back out — |cos| of a pitch that keeps turning.
  // Tumbling is constant angular velocity, so the pitch runs on *time*
  // ([fall]), not on the quadratic drop — driving it from the drop left the
  // puck stuck edge-on and invisible through the middle of the animation.
  final pitch = 2.9 * (0.42 * tip + 0.58 * fall);
  final foreshorten = math.max(0.06, math.cos(pitch).abs());
  // The side wall shows most when the face is closest to edge-on.
  final rim = (1 - foreshorten).clamp(0.0, 1.0);

  // Perspective: further away is smaller.
  final scale = 1 / (1 + 1.9 * drop);

  // Lateral momentum keeps carrying it along the lip, bleeding off as it falls.
  final slide = carry * (0.10 * tip + 0.16 * fall);

  // [outward] is measured in lane-width units; on the ends it has to be
  // converted so the puck travels the same number of *pixels* off a short edge
  // as off a long one.
  final outEnd = outward * aspect;

  double nx, ny, sx, sy, rimDx, rimDy;
  switch (edge) {
    case ShuffleboardFallEdge.top:
      nx = along + slide;
      ny = -outEnd;
      sx = 1;
      sy = foreshorten;
      rimDx = 0;
      rimDy = -1;
    case ShuffleboardFallEdge.bottom:
      nx = along + slide;
      ny = 1 + outEnd;
      sx = 1;
      sy = foreshorten;
      rimDx = 0;
      rimDy = 1;
    case ShuffleboardFallEdge.left:
      nx = -outward;
      ny = along + slide;
      sx = foreshorten;
      sy = 1;
      rimDx = -1;
      rimDy = 0;
    case ShuffleboardFallEdge.right:
      nx = 1 + outward;
      ny = along + slide;
      sx = foreshorten;
      sy = 1;
      rimDx = 1;
      rimDy = 0;
  }

  return ShuffleboardFallingPuck(
    nx: nx,
    ny: ny,
    radiusFrac: radiusFrac,
    color: Color.lerp(color, Colors.black, 0.22 * tip + 0.34 * drop)!,
    scale: scale,
    squashX: sx,
    squashY: sy,
    alpha: p < 0.7 ? 1.0 : (1 - (p - 0.7) / 0.3),
    spin: spin0 + spinDir * (0.5 * tip + 2.2 * fall),
    rim: rim,
    rimDx: rimDx,
    rimDy: rimDy,
  );
}

// ---------------------------------------------------------------------------
// Shared table painter — used by the live scene AND by static previews/tests.
// ---------------------------------------------------------------------------

/// Which open edge a disc slid off — drives how its fall tips over the lip.
enum ShuffleboardFallEdge { top, bottom, left, right }

/// A puck to draw, in normalized lane coords.
class ShuffleboardRenderPuck {
  final double nx;
  final double ny;

  /// Radius as a fraction of the lane width.
  final double radiusFrac;
  final Color color;

  /// Scoring band value (0 if not scoring) — drives the highlight ring.
  final int score;
  final bool isShooter;

  /// Accumulated facing in radians (see [ShuffleboardSlideSpin]). The cap markings turn
  /// through it; the body shading does not, since the light does not move.
  final double spin;

  const ShuffleboardRenderPuck({
    required this.nx,
    required this.ny,
    required this.radiusFrac,
    required this.color,
    this.score = 0,
    this.isShooter = false,
    this.spin = 0,
  });
}

/// A short expanding pulse at the point of a puck-on-puck contact.
class ShuffleboardImpactRing {
  final double nx;
  final double ny;

  /// 0..1 closing speed of the hit.
  final double strength;

  /// 0..1 progress through the pulse.
  final double t;

  /// Puck radius as a fraction of the lane width (sets the ring's scale).
  final double radiusFrac;

  const ShuffleboardImpactRing({
    required this.nx,
    required this.ny,
    required this.strength,
    required this.t,
    required this.radiusFrac,
  });
}

/// The aim/power indicator overlay.
class ShuffleboardAimView {
  final double nx;
  final double ny;

  /// Unit launch direction in screen space (y-down).
  final Offset dir;

  /// 0..1 power for the meter.
  final double power;

  const ShuffleboardAimView({
    required this.nx,
    required this.ny,
    required this.dir,
    required this.power,
  });
}

/// A puck mid-fall off the far end — drawn over the lip (outside the lane clip)
/// with a shrink, foreshorten, tumble and fade.
class ShuffleboardFallingPuck {
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

  /// How much of the puck's cylindrical side wall is turned toward the viewer
  /// (0 = flat on, face only; 1 = fully edge-on). Seeing the edge come round is
  /// what reads as *tipping* rather than merely shrinking.
  final double rim;

  /// Unit direction, in screen space, pointing away from the lip it left by —
  /// the side wall is drawn on that side of the face.
  final double rimDx;
  final double rimDy;

  const ShuffleboardFallingPuck({
    required this.nx,
    required this.ny,
    required this.radiusFrac,
    required this.color,
    required this.scale,
    this.squashX = 1,
    required this.squashY,
    required this.alpha,
    required this.spin,
    this.rim = 0,
    this.rimDx = 0,
    this.rimDy = -1,
  });
}

/// Everything one frame of the lane needs.
class ShuffleboardView {
  final List<ShuffleboardRenderPuck> pucks;
  final ShuffleboardAimView? aim;
  final List<ShuffleboardFallingPuck> falling;
  final List<ShuffleboardImpactRing> impacts;

  const ShuffleboardView({
    required this.pucks,
    this.aim,
    this.falling = const [],
    this.impacts = const [],
  });
}

/// The one committed light for this table: a lamp hanging above and to the
/// upper-left. Every bevel, sheen and cast shadow in this file obeys it —
/// highlights sit on the upper-left of a form, shadows fall down-right.
const Alignment _kLight = Alignment(-0.42, -0.58);
const Offset _kShadowDir = Offset(0.42, 0.66);

/// Draws the room, the hardwood table, the maple lane with its painted scoring
/// inlays, the pucks and the aim indicator into [size]. Pure — no Flame or
/// widget state — so a `CustomPainter` can call it for a static snapshot
/// (screenshots/tests) exactly as the live scene does.
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

  final w = size.width;
  final full = Offset.zero & size;

  _paintRoom(canvas, size);

  // --- the table: a solid hardwood box standing on the floor ----------------
  //
  // The far end is deliberately given room above it. Every open lip in this
  // game is a cliff a puck can go over, and the far end is the one players
  // aim at, so the fall has to have somewhere to happen: the table stops short
  // of the top of the frame and the floor shows beyond it. The near end, which
  // is the one walled edge in the sim, runs right to the bottom.
  final tableRect = Rect.fromLTRB(
    w * 0.030,
    w * 0.150,
    size.width - w * 0.030,
    size.height - w * 0.030,
  );
  // Square-ish at the far end (a cut end, flush with the lip), rounded at the
  // near end where the backstop wraps round.
  final tableRR = RRect.fromRectAndCorners(
    tableRect,
    topLeft: Radius.circular(w * 0.012),
    topRight: Radius.circular(w * 0.012),
    bottomLeft: Radius.circular(w * 0.055),
    bottomRight: Radius.circular(w * 0.055),
  );

  // Contact shadow on the floor, thrown down-right by the overhead lamp.
  canvas.drawRRect(
    tableRR.shift(_kShadowDir * (w * 0.035)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.045),
  );
  // The apron's own thickness: a darker copy peeking out below the top face.
  canvas.drawRRect(
    tableRR.shift(Offset(0, w * 0.014)),
    Paint()..color = Color.lerp(frame, Colors.black, 0.62)!,
  );

  // Stained walnut top face.
  canvas.drawRRect(
    tableRR,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(frame, Colors.white, 0.16)!,
          frame,
          Color.lerp(frame, Colors.black, 0.34)!,
        ],
        stops: const [0.0, 0.46, 1.0],
      ).createShader(tableRect),
  );
  _paintApronGrain(canvas, tableRect, frame);
  // Lit upper-left edge / dark lower-right edge of the apron.
  canvas.drawRRect(
    tableRR.deflate(w * 0.004),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, w * 0.005)
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.02),
          Colors.black.withValues(alpha: 0.30),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(tableRect),
  );

  // --- the lane: maple boards let into the frame ---------------------------
  final laneRect = Rect.fromLTRB(
    tableRect.left + w * 0.052,
    tableRect.top + w * 0.014,
    tableRect.right - w * 0.052,
    tableRect.bottom - w * 0.040,
  );
  final laneRR = RRect.fromRectAndCorners(
    laneRect,
    topLeft: Radius.circular(w * 0.005),
    topRight: Radius.circular(w * 0.005),
    bottomLeft: Radius.circular(w * 0.018),
    bottomRight: Radius.circular(w * 0.018),
  );

  // The routed recess the lane sits in: dark all round, deepest down-right.
  canvas.drawRRect(
    laneRR.inflate(w * 0.010).shift(_kShadowDir * (w * 0.006)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.014),
  );

  canvas.save();
  canvas.clipRRect(laneRR);

  double xOf(double nx) => laneRect.left + nx * laneRect.width;
  double yOf(double ny) => laneRect.top + ny * laneRect.height;

  _paintMapleBoards(canvas, laneRect, lane);
  _paintWaxSheen(canvas, laneRect);
  // Markings go on over the wax, not under it — otherwise the sheen washes the
  // scoring lines out and the bands stop reading at a glance.
  _paintScoringInlays(canvas, laneRect, zone, w);
  _paintFoulLine(canvas, laneRect, foul, yOf(ShuffleboardGame.foulLine), w);
  _paintBackstop(canvas, laneRect, frame, yOf(0.955));
  _paintLaneEdgeShading(canvas, laneRect, laneRR, w);

  // Pucks.
  for (final p in view.pucks) {
    _paintPuck(
      canvas,
      Offset(xOf(p.nx), yOf(p.ny)),
      p.radiusFrac * laneRect.width,
      p,
    );
  }

  // Contact pulses, over the pucks so a hit reads even in a cluster.
  for (final i in view.impacts) {
    _paintImpact(
      canvas,
      Offset(xOf(i.nx), yOf(i.ny)),
      i.radiusFrac * laneRect.width,
      i,
    );
  }

  // Aim indicator.
  final aim = view.aim;
  if (aim != null) {
    _paintAim(
        canvas, Offset(xOf(aim.nx), yOf(aim.ny)), aim, laneRect.width, size);
  }

  canvas.restore();

  // The lip: the lane's own edge, catching the lamp on the upper-left.
  canvas.drawRRect(
    laneRR.deflate(0.8),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.005)
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.30),
          Colors.white.withValues(alpha: 0.06),
          Colors.black.withValues(alpha: 0.22),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(laneRect),
  );

  // The far lip itself — the edge everything falls over. Bright cut edge on
  // top, hard shadow dropping away underneath it onto the floor.
  canvas.drawRect(
    Rect.fromLTRB(tableRect.left, tableRect.top - w * 0.028,
        tableRect.right, tableRect.top),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Colors.black.withValues(alpha: 0.55),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTRB(tableRect.left,
          tableRect.top - w * 0.028, tableRect.right, tableRect.top)),
  );
  canvas.drawLine(
    Offset(laneRect.left, laneRect.top + w * 0.002),
    Offset(laneRect.right, laneRect.top + w * 0.002),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.34)
      ..strokeWidth = math.max(1.2, w * 0.005),
  );

  // Room vignette, so the whole thing sits in a space rather than on a page.
  canvas.drawRect(
    full,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.1, -0.20),
        radius: 1.15,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.07),
          Colors.black.withValues(alpha: 0.26),
        ],
        stops: const [0.55, 0.82, 1.0],
      ).createShader(full),
  );

  // Falling pucks — drawn last and OUTSIDE the lane clip so they tumble over
  // the lip and off the table instead of being clipped at the boundary.
  for (final f in view.falling) {
    _paintFallingPuck(
      canvas,
      Offset(xOf(f.nx), yOf(f.ny)),
      f.radiusFrac * laneRect.width,
      f,
    );
  }
}

/// The room the table stands in: a dark stained floor with the pool of light
/// the lamp throws on it, falling off toward the corners.
void _paintRoom(Canvas canvas, Size size) {
  final full = Offset.zero & size;
  const floor = Color(0xFF3B2A1F);
  canvas.drawRect(full, Paint()..color = floor);
  // Floorboards, running across the room so they read as *not* the lane.
  final board = Paint()
    ..color = Colors.black.withValues(alpha: 0.22)
    ..strokeWidth = math.max(0.8, size.width * 0.004);
  final step = size.width * 0.19;
  for (var y = step; y < size.height; y += step) {
    canvas.drawLine(Offset(0, y), Offset(size.width, y), board);
  }
  // Lamp pool, centred a little above and left of the table.
  canvas.drawRect(
    full,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.85),
        radius: 1.25,
        colors: [
          const Color(0xFF8A6244).withValues(alpha: 0.70),
          const Color(0xFF4A3221).withValues(alpha: 0.34),
          Colors.transparent,
        ],
        stops: const [0.0, 0.42, 1.0],
      ).createShader(full),
  );
}

/// Long grain along the apron rails plus mitre lines into the corners, so the
/// frame reads as four pieces of stained hardwood rather than a bevelled box.
void _paintApronGrain(Canvas canvas, Rect t, Color frame) {
  canvas.save();
  canvas.clipRect(t);
  final rnd = math.Random(7);
  final light = Paint()
    ..color = Colors.white.withValues(alpha: 0.045)
    ..strokeWidth = math.max(0.6, t.width * 0.004);
  final dark = Paint()
    ..color = Colors.black.withValues(alpha: 0.16)
    ..strokeWidth = math.max(0.6, t.width * 0.003);
  for (var i = 0; i < 22; i++) {
    final x = t.left + rnd.nextDouble() * t.width;
    canvas.drawLine(
      Offset(x, t.top),
      Offset(x + (rnd.nextDouble() - 0.5) * t.width * 0.03, t.bottom),
      rnd.nextBool() ? light : dark,
    );
  }
  // Mitre joints.
  final mitre = Paint()
    ..color = Colors.black.withValues(alpha: 0.30)
    ..strokeWidth = math.max(0.8, t.width * 0.004);
  final c = t.width * 0.16;
  canvas.drawLine(t.topLeft, t.topLeft + Offset(c, c), mitre);
  canvas.drawLine(t.topRight, t.topRight + Offset(-c, c), mitre);
  canvas.drawLine(t.bottomLeft, t.bottomLeft + Offset(c, -c), mitre);
  canvas.drawLine(t.bottomRight, t.bottomRight + Offset(-c, -c), mitre);
  canvas.restore();
}

/// The playing surface: hard maple boards laid down-lane, each a slightly
/// different cut of timber, separated by real seams with a lit left shoulder.
void _paintMapleBoards(Canvas canvas, Rect lane, Color base) {
  const boards = 7;
  final bw = lane.width / boards;
  // Base wash, cooler and darker toward the far end so the lane has depth.
  canvas.drawRect(
    lane,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(base, const Color(0xFF7C5A33), 0.34)!,
          base,
          Color.lerp(base, Colors.white, 0.05)!,
          Color.lerp(base, const Color(0xFF8A6238), 0.30)!,
        ],
        stops: const [0.0, 0.34, 0.62, 1.0],
      ).createShader(lane),
  );

  for (var i = 0; i < boards; i++) {
    final x0 = lane.left + i * bw;
    final r = Rect.fromLTRB(x0, lane.top, x0 + bw, lane.bottom);
    // Deterministic per-board tone: some boards run pinker, some paler.
    final t = (((i * 37) % 11) / 11.0) - 0.5;
    canvas.drawRect(
      r,
      Paint()
        ..color = (t >= 0
                ? Color.lerp(base, Colors.white, t * 0.13)!
                : Color.lerp(base, const Color(0xFF8E6636), -t * 0.20)!)
            .withValues(alpha: 0.55),
    );
    _paintBoardGrain(canvas, r, i);
    if (i > 0) {
      // Seam: a dark gap with the lamp catching its left shoulder.
      canvas.drawLine(
        Offset(x0, lane.top),
        Offset(x0, lane.bottom),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.34)
          ..strokeWidth = math.max(1.0, lane.width * 0.0035),
      );
      canvas.drawLine(
        Offset(x0 - math.max(1.0, lane.width * 0.0035), lane.top),
        Offset(x0 - math.max(1.0, lane.width * 0.0035), lane.bottom),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.13)
          ..strokeWidth = math.max(0.8, lane.width * 0.0025),
      );
    }
  }
}

/// Figure inside one board: a few wandering grain lines running down-lane.
void _paintBoardGrain(Canvas canvas, Rect b, int seed) {
  final rnd = math.Random(seed * 91 + 3);
  final segments = 7;
  for (var g = 0; g < 5; g++) {
    final x = b.left + (0.12 + 0.76 * rnd.nextDouble()) * b.width;
    final sway = b.width * (0.06 + rnd.nextDouble() * 0.14);
    final path = Path()..moveTo(x, b.top);
    for (var s = 1; s <= segments; s++) {
      final y = b.top + b.height * (s / segments);
      final yPrev = b.top + b.height * ((s - 1) / segments);
      final cx = x + math.sin(s * 1.7 + seed) * sway;
      path.quadraticBezierTo(cx, (y + yPrev) / 2, x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, b.width * (0.02 + rnd.nextDouble() * 0.03))
        ..color = (rnd.nextDouble() < 0.35 ? Colors.white : Colors.black)
            .withValues(alpha: rnd.nextDouble() < 0.35 ? 0.05 : 0.055),
    );
  }
}

/// Scoring zones as painted-and-inlaid lines rather than flat colour bands:
/// a shallow tint, a routed groove, a cream paint line, and the value painted
/// at each side of the lane the way a real table is marked out.
void _paintScoringInlays(Canvas canvas, Rect lane, Color zone, double w) {
  double yOf(double ny) => lane.top + ny * lane.height;
  const cream = Color(0xFFF3E7CC);

  // The tint carries the value: 3 is the richest band, 1 the faintest, and
  // each fades toward its own scoring line so the lane reads as three steps
  // rather than one wash. At the old 0.15/0.11/0.07 the three bands were
  // indistinguishable at phone size — you could only tell them apart by the
  // painted numbers, which is the opposite of how a real table reads.
  final bands = [
    (ShuffleboardGame.zone3Line, '3', 0.34),
    (ShuffleboardGame.zone2Line, '2', 0.21),
    (ShuffleboardGame.zone1Line, '1', 0.10),
  ];
  var prevY = lane.top;
  for (final (line, label, tint) in bands) {
    final bottom = yOf(line);
    final band = Rect.fromLTRB(lane.left, prevY, lane.right, bottom);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            zone.withValues(alpha: tint),
            zone.withValues(alpha: tint * 0.62),
          ],
        ).createShader(band),
    );
    // Routed groove + painted line. The groove sits just below the paint so
    // the line reads as standing proud under a light from above.
    final lw = math.max(1.4, w * 0.0075);
    canvas.drawLine(
      Offset(lane.left, bottom + lw * 0.75),
      Offset(lane.right, bottom + lw * 0.75),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..strokeWidth = lw,
    );
    canvas.drawLine(
      Offset(lane.left, bottom),
      Offset(lane.right, bottom),
      Paint()
        ..color = cream.withValues(alpha: 0.92)
        ..strokeWidth = lw,
    );
    _bandLabel(canvas, Offset(lane.left + lane.width * 0.14,
        (prevY + bottom) / 2), label, lane.width * 0.125);
    _bandLabel(canvas, Offset(lane.right - lane.width * 0.14,
        (prevY + bottom) / 2), label, lane.width * 0.125);
    prevY = bottom;
  }
}

/// The foul line: pucks must cross it to count, so it is the crispest mark on
/// the lane — a deep groove with a hard-edged painted line over it.
void _paintFoulLine(Canvas canvas, Rect lane, Color foul, double y, double w) {
  final lw = math.max(1.6, w * 0.009);
  canvas.drawLine(
    Offset(lane.left, y + lw * 0.8),
    Offset(lane.right, y + lw * 0.8),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.32)
      ..strokeWidth = lw,
  );
  canvas.drawLine(
    Offset(lane.left, y),
    Offset(lane.right, y),
    Paint()
      ..color = foul
      ..strokeWidth = lw,
  );
  canvas.drawLine(
    Offset(lane.left, y - lw * 0.55),
    Offset(lane.right, y - lw * 0.55),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = math.max(0.8, w * 0.003),
  );
}

/// The near backstop — the one walled edge in the sim, so it gets a real piece
/// of raised timber rather than a painted line.
void _paintBackstop(Canvas canvas, Rect lane, Color frame, double y) {
  final r = Rect.fromLTRB(lane.left, y, lane.right, lane.bottom);
  canvas.drawRect(
    r,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(frame, Colors.white, 0.20)!,
          frame,
          Color.lerp(frame, Colors.black, 0.35)!,
        ],
        stops: const [0.0, 0.35, 1.0],
      ).createShader(r),
  );
  canvas.drawLine(
    r.topLeft,
    r.topRight,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.26)
      ..strokeWidth = math.max(1, lane.width * 0.005),
  );
  // The bumper casts a thin shadow up-lane (light is in front of it).
  canvas.drawRect(
    Rect.fromLTRB(r.left, r.top - lane.width * 0.03, r.right, r.top),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Colors.black.withValues(alpha: 0.22),
          Colors.transparent,
        ],
      ).createShader(
          Rect.fromLTRB(r.left, r.top - lane.width * 0.03, r.right, r.top)),
  );
}

/// Wax: a broad specular band running the length of the lane, plus the lamp's
/// own reflection near the far end. Low alpha on purpose — it should register
/// as "this surface is slick", not as a white stripe.
void _paintWaxSheen(Canvas canvas, Rect lane) {
  canvas.drawRect(
    lane,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.085),
          Colors.white.withValues(alpha: 0.035),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.06, 0.30, 0.52, 0.88],
      ).createShader(lane),
  );
  final hot = Rect.fromCenter(
    center: Offset(
        lane.left + lane.width * 0.38, lane.top + lane.height * 0.26),
    width: lane.width * 1.5,
    height: lane.height * 0.75,
  );
  canvas.drawRect(
    lane,
    Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.075),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(hot),
  );
}

/// Occlusion where the lane meets the frame, and the lit shoulder on the side
/// the lamp is on.
void _paintLaneEdgeShading(
    Canvas canvas, Rect lane, RRect laneRR, double w) {
  canvas.drawRRect(
    laneRR.deflate(w * 0.022),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.044
      ..color = Colors.black.withValues(alpha: 0.20)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.020),
  );
  canvas.drawLine(
    Offset(lane.left + w * 0.004, lane.top),
    Offset(lane.left + w * 0.004, lane.bottom),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = math.max(1, w * 0.004),
  );
}

void _paintImpact(Canvas canvas, Offset c, double r, ShuffleboardImpactRing i) {
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
      ..color = Colors.white.withValues(alpha: 0.55 * i.strength * fade),
  );
  if (t < 0.35) {
    canvas.drawCircle(
      c,
      r * 0.7,
      Paint()
        ..color = Colors.white
            .withValues(alpha: 0.22 * i.strength * (1 - t / 0.35))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.4),
    );
  }
}

void _paintFallingPuck(Canvas canvas, Offset c, double r, ShuffleboardFallingPuck f) {
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
    final thick = r * 0.34 * f.rim * f.scale;
    final side = Offset(f.rimDx, f.rimDy) * thick;
    canvas.save();
    canvas.translate(c.dx + side.dx, c.dy + side.dy);
    canvas.scale(sx, sy);
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()..color = Color.lerp(f.color, Colors.black, 0.55)!,
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

void _bandLabel(Canvas canvas, Offset center, String text, double fontSize) {
  void draw(Offset at, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  // Painted-on numerals: a dark impression under a cream stencil.
  draw(center + Offset(0, fontSize * 0.045),
      Colors.black.withValues(alpha: 0.28));
  draw(center, const Color(0xFFF3E7CC).withValues(alpha: 0.80));
}

/// The steel body + coloured cap of one weight, with every marking that should
/// turn as the puck slides drawn through [spin]. Shared by resting and falling
/// pucks so a puck looks like the same object on its way over the lip.
void _paintPuckFace(Canvas canvas, Offset c, double r, Color base, double spin) {
  // Steel body.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = RadialGradient(
        center: _kLight,
        colors: const [
          Color(0xFFF4F6F9),
          Color(0xFFB4BAC4),
          Color(0xFF6A707B),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r)),
  );

  // Knurling on the steel rim — the clearest read of rotation on the puck.
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(spin);
  final tick = Paint()
    ..color = Colors.black.withValues(alpha: 0.22)
    ..strokeWidth = math.max(0.6, r * 0.055)
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 18; i++) {
    final a = i * (math.pi * 2 / 18);
    final ca = math.cos(a), sa = math.sin(a);
    canvas.drawLine(
      Offset(ca * r * 0.81, sa * r * 0.81),
      Offset(ca * r * 0.96, sa * r * 0.96),
      tick,
    );
  }
  canvas.restore();

  // Rim light / rim shade, fixed to the lamp (these must NOT rotate).
  final rimRect = Rect.fromCircle(center: c, radius: r * 0.93);
  canvas.drawArc(
    rimRect,
    math.pi * 1.05,
    math.pi * 0.75,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.11
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.50),
  );
  canvas.drawArc(
    rimRect,
    math.pi * 0.08,
    math.pi * 0.72,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.11
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.30),
  );

  // Coloured cap.
  final capR = r * 0.70;
  canvas.drawCircle(
    c,
    capR,
    Paint()
      ..shader = RadialGradient(
        center: _kLight,
        colors: [
          Color.lerp(base, Colors.white, 0.42)!,
          base,
          Color.lerp(base, Colors.black, 0.38)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: capR)),
  );
  canvas.drawCircle(
    c,
    capR,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.05
      ..color = Colors.black.withValues(alpha: 0.28),
  );

  // Cap markings — the slot and its index notch turn with the puck.
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(spin);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset.zero, width: capR * 1.30, height: capR * 0.20),
      Radius.circular(capR * 0.10),
    ),
    Paint()..color = Colors.black.withValues(alpha: 0.30),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(0, -capR * 0.055),
          width: capR * 1.30,
          height: capR * 0.07),
      Radius.circular(capR * 0.04),
    ),
    Paint()..color = Colors.white.withValues(alpha: 0.22),
  );
  canvas.drawCircle(
    Offset(0, -capR * 0.56),
    capR * 0.13,
    Paint()..color = Colors.black.withValues(alpha: 0.34),
  );
  canvas.restore();

  // Specular hit on the cap, fixed to the lamp.
  canvas.save();
  canvas.translate(c.dx + _kLight.x * capR * 0.55,
      c.dy + _kLight.y * capR * 0.55);
  canvas.rotate(-0.6);
  canvas.drawOval(
    Rect.fromCenter(
        center: Offset.zero, width: capR * 0.66, height: capR * 0.34),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, capR * 0.16),
  );
  canvas.restore();

  // Silhouette.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, r * 0.05)
      ..color = Colors.black.withValues(alpha: 0.35),
  );
}

void _paintPuck(Canvas canvas, Offset c, double r, ShuffleboardRenderPuck p) {
  if (r <= 0.4) return;
  // Contact shadow, thrown down-right by the lamp and tight to the puck — a
  // weight sits ON the wax, it does not hover above it.
  canvas.drawCircle(
    c + _kShadowDir * (r * 0.30),
    r * 0.98,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.34)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.30),
  );
  // Score highlight ring behind scoring pucks.
  if (p.score > 0) {
    canvas.drawCircle(
      c,
      r * 1.30,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.14
        ..color = const Color(0xFFF4B740).withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      c,
      r * 1.30,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.24
        ..color = const Color(0xFFF4B740).withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22),
    );
  }
  // Shooter gets a soft aim halo.
  if (p.isShooter) {
    canvas.drawCircle(
      c,
      r * 1.48,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.09
        ..color = Colors.white.withValues(alpha: 0.5),
    );
  }
  _paintPuckFace(canvas, c, r, p.color, p.spin);
}

void _paintAim(
  Canvas canvas,
  Offset origin,
  ShuffleboardAimView aim,
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
          // The score is the point of the whole screen — it outweighs the name
          // beside it rather than matching it.
          Text(
            '$score',
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
