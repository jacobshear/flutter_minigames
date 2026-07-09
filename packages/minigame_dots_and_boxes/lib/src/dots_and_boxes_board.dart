import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigames_core/minigames_core.dart';

import 'dots_and_boxes_game.dart';
import 'dots_and_boxes_style.dart';

/// Animated Dots and Boxes board wired to a [MatchController].
///
/// Juice: free edges glow on hover, claimed edges stroke in with a squash,
/// completed boxes pop + fill in the scorer's colour, "Again!" flashes on
/// extra turns, scores live in the banner, confetti on win.
class DotsAndBoxesBoard extends StatefulWidget {
  final MatchController<DotsAndBoxesState, DotsAndBoxesMove> controller;
  final DotsAndBoxesStyle style;

  const DotsAndBoxesBoard({
    super.key,
    required this.controller,
    this.style = const DotsAndBoxesStyle(),
  });

  @override
  State<DotsAndBoxesBoard> createState() => _DotsAndBoxesBoardState();
}

class _DotsAndBoxesBoardState extends State<DotsAndBoxesBoard>
    with TickerProviderStateMixin {
  static const _gameLogic = DotsAndBoxesGame(); // only for outcome helpers

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final AnimationController _againCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _confettiCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  final Map<String, AnimationController> _edgeCtrls = {};
  final Map<int, AnimationController> _boxCtrls = {};

  final math.Random _rnd = math.Random();
  StreamSubscription<DotsAndBoxesState>? _sub;

  DotsAndBoxesState? _state;
  GameOutcome? _outcome;
  int _lastClaimedEdges = 0;
  int _lastBoxCount = 0;
  bool _showAgain = false;
  List<_Confetto> _confetti = const [];
  Offset _confettiOrigin = const Offset(0.5, 0.5);

  // Hover target: 'h:$i' or 'v:$i'
  String? _hoverKey;

  @override
  void initState() {
    super.initState();
    _state = widget.controller.state;
    _outcome = _state == null ? null : _gameLogic.outcome(_state!);
    _lastClaimedEdges = _claimedCount(_state);
    _lastBoxCount = _state?.boxes.where((b) => b != null).length ?? 0;
    // Seed existing edges/boxes as fully animated (resume).
    final s = _state;
    if (s != null) {
      for (var i = 0; i < s.hCount; i++) {
        if (s.hEdges[i] != null) _ensureEdge('h:$i', animate: false);
      }
      for (var i = 0; i < s.vCount; i++) {
        if (s.vEdges[i] != null) _ensureEdge('v:$i', animate: false);
      }
      for (var i = 0; i < s.boxCount; i++) {
        if (s.boxes[i] != null) _ensureBox(i, animate: false);
      }
    }
    _entrance.forward();
    _sub = widget.controller.stateStream.listen(_onState);
  }

  int _claimedCount(DotsAndBoxesState? s) {
    if (s == null) return 0;
    return s.hEdges.where((e) => e != null).length +
        s.vEdges.where((e) => e != null).length;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _entrance.dispose();
    _againCtrl.dispose();
    _confettiCtrl.dispose();
    for (final c in _edgeCtrls.values) {
      c.dispose();
    }
    for (final c in _boxCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _ensureEdge(String key, {required bool animate}) {
    if (_edgeCtrls.containsKey(key)) return;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _edgeCtrls[key] = ctrl;
    if (animate) {
      ctrl.forward();
    } else {
      ctrl.value = 1;
    }
  }

  void _ensureBox(int index, {required bool animate}) {
    if (_boxCtrls.containsKey(index)) return;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _boxCtrls[index] = ctrl;
    if (animate) {
      ctrl.forward();
    } else {
      ctrl.value = 1;
    }
  }

  void _onState(DotsAndBoxesState state) {
    final style = widget.style;
    final claimed = _claimedCount(state);
    final boxCount = state.boxes.where((b) => b != null).length;
    final outcome = _gameLogic.outcome(state);

    if (claimed > _lastClaimedEdges &&
        state.lastWasHorizontal != null &&
        state.lastEdgeIndex != null) {
      final key =
          state.lastWasHorizontal! ? 'h:${state.lastEdgeIndex}' : 'v:${state.lastEdgeIndex}';
      _ensureEdge(key, animate: true);
      if (style.haptics) HapticFeedback.lightImpact();
      style.sounds.onClaim?.call();
    }

    if (boxCount > _lastBoxCount) {
      for (final bi in state.lastCompletedBoxes) {
        _ensureBox(bi, animate: true);
      }
      if (style.haptics) {
        HapticFeedback.mediumImpact();
        if (state.lastCompletedBoxes.length > 1) {
          Future.delayed(const Duration(milliseconds: 60), () {
            if (mounted) HapticFeedback.heavyImpact();
          });
        }
      }
      style.sounds.onBox?.call(state.lastCompletedBoxes.length);
      if (state.lastKeptTurn && outcome == null) {
        style.sounds.onExtraTurn?.call();
        setState(() => _showAgain = true);
        _againCtrl.forward(from: 0).whenComplete(() {
          if (mounted) setState(() => _showAgain = false);
        });
      }
    }

    if (claimed < _lastClaimedEdges) {
      // New game
      for (final c in _edgeCtrls.values) {
        c.dispose();
      }
      for (final c in _boxCtrls.values) {
        c.dispose();
      }
      _edgeCtrls.clear();
      _boxCtrls.clear();
      _confettiCtrl.value = 0;
      _confetti = const [];
      _showAgain = false;
      _hoverKey = null;
    }

    if (outcome != null && _outcome == null) {
      if (outcome.isWin) {
        style.sounds.onWin?.call();
        if (style.haptics) {
          HapticFeedback.heavyImpact();
          Future.delayed(const Duration(milliseconds: 90), () {
            if (mounted) HapticFeedback.mediumImpact();
          });
        }
        if (style.confetti) {
          _confettiOrigin = const Offset(0.5, 0.45);
          _confetti = _spawnConfetti(state, outcome);
          _confettiCtrl.forward(from: 0);
        }
      } else {
        style.sounds.onDraw?.call();
        if (style.haptics) HapticFeedback.mediumImpact();
      }
    }

    setState(() {
      _state = state;
      _outcome = outcome;
      _lastClaimedEdges = claimed;
      _lastBoxCount = boxCount;
    });
  }

  List<_Confetto> _spawnConfetti(DotsAndBoxesState state, GameOutcome outcome) {
    final scheme = Theme.of(context).colorScheme;
    final winnerIsP0 =
        outcome.winnerId != null && state.playerIds.indexOf(outcome.winnerId!) == 0;
    final palette = <Color>[
      widget.style.resolveP0(scheme),
      widget.style.resolveP1(scheme),
      const Color(0xFFF4B740),
      Colors.white,
      winnerIsP0
          ? widget.style.resolveP0(scheme)
          : widget.style.resolveP1(scheme),
    ];
    return List<_Confetto>.generate(40, (i) {
      final angle = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 2.8;
      return _Confetto(
        angle: angle,
        speed: 0.5 + _rnd.nextDouble() * 1.0,
        size: 0.015 + _rnd.nextDouble() * 0.02,
        color: palette[i % palette.length],
        spin: (_rnd.nextDouble() - 0.5) * 12,
        phase: _rnd.nextDouble() * math.pi,
        round: _rnd.nextBool(),
      );
    });
  }

  void _claim(bool horizontal, int index) {
    if (_outcome != null) return;
    widget.controller.submitMove(
      DotsAndBoxesMove(horizontal: horizontal, index: index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final state = _state;
    if (state == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final p0 = style.resolveP0(scheme);
    final p1 = style.resolveP1(scheme);
    final freeEdge = style.resolveFreeEdge(scheme);
    final dotColor = style.resolveDot(scheme);
    final boardColor = style.resolveBoard(scheme);
    final n = state.n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusBanner(
          state: state,
          outcome: _outcome,
          p0: p0,
          p1: p1,
          showAgain: _showAgain,
          againT: _againCtrl.value,
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.maxWidth;
                return AnimatedBuilder(
                  animation: Listenable.merge([
                    _entrance,
                    _againCtrl,
                    _confettiCtrl,
                    ..._edgeCtrls.values,
                    ..._boxCtrls.values,
                  ]),
                  builder: (context, _) {
                    final enter =
                        Curves.easeOutCubic.transform(_entrance.value);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Transform.scale(
                          scale: 0.94 + 0.06 * enter,
                          child: Opacity(
                            opacity: enter.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: boardColor,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 28,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                              padding: EdgeInsets.all(size * 0.06),
                              child: CustomPaint(
                                painter: _GridPainter(
                                  state: state,
                                  p0: p0,
                                  p1: p1,
                                  freeEdge: freeEdge,
                                  dotColor: dotColor,
                                  hoverKey: _outcome == null ? _hoverKey : null,
                                  edgeProgress: {
                                    for (final e in _edgeCtrls.entries)
                                      e.key: e.value.value,
                                  },
                                  boxProgress: {
                                    for (final e in _boxCtrls.entries)
                                      e.key: e.value.value,
                                  },
                                  gameOver: _outcome != null,
                                ),
                                child: _EdgeHitLayer(
                                  n: n,
                                  gameOver: _outcome != null,
                                  state: state,
                                  onHover: (k) => setState(() => _hoverKey = k),
                                  onClaim: _claim,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (style.confetti && _confetti.isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _ConfettiPainter(
                                  confetti: _confetti,
                                  origin: _confettiOrigin,
                                  t: _confettiCtrl.value,
                                  boardSize: size,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status banner + scores
// ---------------------------------------------------------------------------

class _StatusBanner extends StatelessWidget {
  final DotsAndBoxesState state;
  final GameOutcome? outcome;
  final Color p0;
  final Color p1;
  final bool showAgain;
  final double againT;

  const _StatusBanner({
    required this.state,
    required this.outcome,
    required this.p0,
    required this.p1,
    required this.showAgain,
    required this.againT,
  });

  @override
  Widget build(BuildContext context) {
    // Prefer ambient theme, but force a bold game-y weight for scores/turn.
    final textStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        );
    final a = state.playerIds[0];
    final b = state.playerIds[1];
    final sa = state.scoreFor(a);
    final sb = state.scoreFor(b);

    Widget center;
    if (outcome == null) {
      if (showAgain) {
        final t = Curves.easeOutBack.transform(againT.clamp(0.0, 1.0));
        final color = state.playerIds.indexOf(state.currentPlayerId) == 0
            ? p0
            : p1;
        center = Opacity(
          key: const ValueKey('again'),
          opacity: (1.0 - (againT - 0.7).clamp(0.0, 0.3) / 0.3).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.85 + 0.2 * t,
            child: Text(
              'Again!',
              style: textStyle?.copyWith(color: color, fontSize: 26),
            ),
          ),
        );
      } else {
        final isP0 = state.playerIds.indexOf(state.currentPlayerId) == 0;
        final color = isP0 ? p0 : p1;
        center = Row(
          key: ValueKey('turn-${state.currentPlayerId}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(color: color, size: 14, breathe: true),
            const SizedBox(width: 10),
            Text('to claim', style: textStyle),
          ],
        );
      }
    } else if (outcome!.isDraw) {
      final ink = Theme.of(context).colorScheme.onSurface;
      center = _ResultPill(
        key: const ValueKey('draw'),
        color: ink,
        child: Text(
          'Dead heat',
          style: textStyle?.copyWith(color: ink, fontSize: 18),
        ),
      );
    } else {
      final isP0 = state.playerIds.indexOf(outcome!.winnerId!) == 0;
      final color = isP0 ? p0 : p1;
      center = _ResultPill(
        key: const ValueKey('win'),
        color: color,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(color: color, size: 16),
            const SizedBox(width: 10),
            Text(
              isP0 ? 'P1 wins' : 'P2 wins',
              style: textStyle?.copyWith(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    final winnerIsP0 =
        outcome?.isWin == true && state.playerIds.indexOf(outcome!.winnerId!) == 0;
    final winnerIsP1 =
        outcome?.isWin == true && state.playerIds.indexOf(outcome!.winnerId!) == 1;

    return Row(
      children: [
        _ScoreChip(
          label: 'P1',
          score: sa,
          color: p0,
          active: outcome == null && state.currentPlayerId == a,
          winner: winnerIsP0,
        ),
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            height: outcome != null ? 52 : 40,
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutBack,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.86, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: center,
            ),
          ),
        ),
        _ScoreChip(
          label: 'P2',
          score: sb,
          color: p1,
          active: outcome == null && state.currentPlayerId == b,
          winner: winnerIsP1,
        ),
      ],
    );
  }
}

class _ResultPill extends StatelessWidget {
  final Color color;
  final Widget child;

  const _ResultPill({super.key, required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            offset: const Offset(0, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ScoreChip extends StatelessWidget {
  final String label;
  final int score;
  final Color color;
  final bool active;
  final bool winner;

  const _ScoreChip({
    required this.label,
    required this.score,
    required this.color,
    required this.active,
    this.winner = false,
  });

  @override
  Widget build(BuildContext context) {
    final emphasize = active || winner;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: EdgeInsets.symmetric(
        horizontal: winner ? 14 : 12,
        vertical: winner ? 10 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: winner ? 0.28 : (active ? 0.18 : 0.10)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: winner ? 0.95 : (active ? 0.7 : 0.35)),
          width: emphasize ? 2.5 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: winner ? 0.16 : 0.08),
            offset: Offset(0, winner ? 4 : 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            winner ? '$label · win' : label,
            style: TextStyle(
              color: color.withValues(alpha: 0.9),
              fontWeight: FontWeight.w700,
              fontSize: winner ? 12 : 13,
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: child,
            ),
            child: Text(
              '$score',
              key: ValueKey('$score-$winner'),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: winner ? 20 : 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final Color color;
  final double size;
  final bool breathe;

  const _Dot({required this.color, required this.size, this.breathe = false});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.breathe) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = widget.breathe ? Curves.easeInOut.transform(_c.value) : 0.0;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.35 * t),
                blurRadius: 8 + 4 * t,
                spreadRadius: t,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Hit layer — fat invisible targets for edges
// ---------------------------------------------------------------------------

class _EdgeHitLayer extends StatelessWidget {
  final int n;
  final bool gameOver;
  final DotsAndBoxesState state;
  final ValueChanged<String?> onHover;
  final void Function(bool horizontal, int index) onClaim;

  const _EdgeHitLayer({
    required this.n,
    required this.gameOver,
    required this.state,
    required this.onHover,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final step = w / n; // square grid
        final hitThick = step * 0.28;

        return Stack(
          children: [
            // Horizontal edges
            for (var r = 0; r <= n; r++)
              for (var c = 0; c < n; c++)
                if (state.hEdges[r * n + c] == null && !gameOver)
                  Positioned(
                    left: c * step,
                    top: r * step - hitThick / 2,
                    width: step,
                    height: hitThick,
                    child: _EdgeSensor(
                      edgeKey: 'h:${r * n + c}',
                      onHover: onHover,
                      onTap: () => onClaim(true, r * n + c),
                    ),
                  ),
            // Vertical edges
            for (var r = 0; r < n; r++)
              for (var c = 0; c <= n; c++)
                if (state.vEdges[r * (n + 1) + c] == null && !gameOver)
                  Positioned(
                    left: c * step - hitThick / 2,
                    top: r * step,
                    width: hitThick,
                    height: step,
                    child: _EdgeSensor(
                      edgeKey: 'v:${r * (n + 1) + c}',
                      onHover: onHover,
                      onTap: () => onClaim(false, r * (n + 1) + c),
                    ),
                  ),
          ],
        );
      },
    );
  }
}

class _EdgeSensor extends StatelessWidget {
  final String edgeKey;
  final ValueChanged<String?> onHover;
  final VoidCallback onTap;

  const _EdgeSensor({
    required this.edgeKey,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(edgeKey),
      onExit: (_) => onHover(null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onHover(edgeKey),
        onTapCancel: () => onHover(null),
        onTap: onTap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grid painter
// ---------------------------------------------------------------------------

class _GridPainter extends CustomPainter {
  final DotsAndBoxesState state;
  final Color p0;
  final Color p1;
  final Color freeEdge;
  final Color dotColor;
  final String? hoverKey;
  final Map<String, double> edgeProgress;
  final Map<int, double> boxProgress;
  final bool gameOver;

  _GridPainter({
    required this.state,
    required this.p0,
    required this.p1,
    required this.freeEdge,
    required this.dotColor,
    required this.hoverKey,
    required this.edgeProgress,
    required this.boxProgress,
    required this.gameOver,
  });

  Color _playerColor(String? id) {
    if (id == null) return freeEdge;
    return state.playerIds.indexOf(id) == 0 ? p0 : p1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = state.n;
    final step = size.width / n;
    final stroke = size.width * 0.028;
    final dotR = size.width * 0.028;

    // Boxes (under edges)
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final bi = r * n + c;
        final owner = state.boxes[bi];
        if (owner == null) continue;
        final t = Curves.easeOutBack.transform(
          (boxProgress[bi] ?? 1.0).clamp(0.0, 1.0),
        );
        final color = _playerColor(owner);
        final cx = (c + 0.5) * step;
        final cy = (r + 0.5) * step;
        final half = step * 0.42 * t;
        final rect = Rect.fromCenter(
          center: Offset(cx, cy),
          width: half * 2,
          height: half * 2,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(step * 0.12)),
          Paint()..color = color.withValues(alpha: 0.22 + 0.2 * t),
        );
        // Monogram
        final tp = TextPainter(
          text: TextSpan(
            text: state.playerIds.indexOf(owner) == 0 ? '1' : '2',
            style: TextStyle(
              color: color.withValues(alpha: 0.85 * t),
              fontWeight: FontWeight.w800,
              fontSize: step * 0.28,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(cx - tp.width / 2, cy - tp.height / 2),
        );
      }
    }

    // Free edge guides (very subtle grid)
    final guide = Paint()
      ..color = freeEdge
      ..strokeWidth = stroke * 0.55
      ..strokeCap = StrokeCap.round;
    for (var r = 0; r <= n; r++) {
      for (var c = 0; c < n; c++) {
        if (state.hEdges[r * n + c] != null) continue;
        final a = Offset(c * step, r * step);
        final b = Offset((c + 1) * step, r * step);
        canvas.drawLine(a, b, guide);
      }
    }
    for (var r = 0; r < n; r++) {
      for (var c = 0; c <= n; c++) {
        if (state.vEdges[r * (n + 1) + c] != null) continue;
        final a = Offset(c * step, r * step);
        final b = Offset(c * step, (r + 1) * step);
        canvas.drawLine(a, b, guide);
      }
    }

    // Hover ghost
    if (hoverKey != null && !gameOver) {
      final parts = hoverKey!.split(':');
      final isH = parts[0] == 'h';
      final idx = int.parse(parts[1]);
      final ghostColor = _playerColor(state.currentPlayerId)
          .withValues(alpha: 0.45);
      final paint = Paint()
        ..color = ghostColor
        ..strokeWidth = stroke * 1.15
        ..strokeCap = StrokeCap.round;
      if (isH) {
        final r = idx ~/ n;
        final c = idx % n;
        canvas.drawLine(
          Offset(c * step, r * step),
          Offset((c + 1) * step, r * step),
          paint,
        );
      } else {
        final r = idx ~/ (n + 1);
        final c = idx % (n + 1);
        canvas.drawLine(
          Offset(c * step, r * step),
          Offset(c * step, (r + 1) * step),
          paint,
        );
      }
    }

    // Claimed edges (stroke-in)
    for (var r = 0; r <= n; r++) {
      for (var c = 0; c < n; c++) {
        final idx = r * n + c;
        final owner = state.hEdges[idx];
        if (owner == null) continue;
        final t = Curves.easeOutCubic
            .transform((edgeProgress['h:$idx'] ?? 1.0).clamp(0.0, 1.0));
        final a = Offset(c * step, r * step);
        final b = Offset((c + 1) * step, r * step);
        final end = Offset.lerp(a, b, t)!;
        canvas.drawLine(
          a,
          end,
          Paint()
            ..color = _playerColor(owner)
            ..strokeWidth = stroke * (0.9 + 0.25 * t)
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    for (var r = 0; r < n; r++) {
      for (var c = 0; c <= n; c++) {
        final idx = r * (n + 1) + c;
        final owner = state.vEdges[idx];
        if (owner == null) continue;
        final t = Curves.easeOutCubic
            .transform((edgeProgress['v:$idx'] ?? 1.0).clamp(0.0, 1.0));
        final a = Offset(c * step, r * step);
        final b = Offset(c * step, (r + 1) * step);
        final end = Offset.lerp(a, b, t)!;
        canvas.drawLine(
          a,
          end,
          Paint()
            ..color = _playerColor(owner)
            ..strokeWidth = stroke * (0.9 + 0.25 * t)
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Dots on top
    for (var r = 0; r <= n; r++) {
      for (var c = 0; c <= n; c++) {
        final o = Offset(c * step, r * step);
        canvas.drawCircle(
          o,
          dotR,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          o,
          dotR * 0.78,
          Paint()..color = dotColor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => true;
}

// ---------------------------------------------------------------------------
// Confetti
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
  final Offset origin;
  final double t;
  final double boardSize;

  _ConfettiPainter({
    required this.confetti,
    required this.origin,
    required this.t,
    required this.boardSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final o = Offset(origin.dx * size.width, origin.dy * size.height);
    const gravity = 2.5;
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
            Rect.fromCenter(center: Offset.zero, width: dim, height: dim * 0.55),
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
