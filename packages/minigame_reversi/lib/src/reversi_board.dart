import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigames_core/minigames_core.dart';

import 'reversi_game.dart';
import 'reversi_style.dart';

/// Animated Reversi board wired to a [MatchController].
///
/// Juice: legal-move dots, place squash, staggered Y-axis flips, score chips,
/// pass toast, confetti on win. Auto-submits a pass when the local seat must.
class ReversiBoard extends StatefulWidget {
  final MatchController<ReversiState, ReversiMove> controller;
  final ReversiStyle style;

  const ReversiBoard({
    super.key,
    required this.controller,
    this.style = const ReversiStyle(),
  });

  @override
  State<ReversiBoard> createState() => _ReversiBoardState();
}

class _ReversiBoardState extends State<ReversiBoard>
    with TickerProviderStateMixin {
  static const _game = ReversiGame();

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final AnimationController _confettiCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _passToast = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// Per-cell flip progress 0=start color, 1=end color (Y scale through 0).
  final Map<int, AnimationController> _flipCtrls = {};

  final math.Random _rnd = math.Random();
  StreamSubscription<ReversiState>? _sub;

  ReversiState? _state;
  GameOutcome? _outcome;
  int _lastFilled = 4;
  bool _passing = false;
  List<_Confetto> _confetti = const [];

  @override
  void initState() {
    super.initState();
    _state = widget.controller.state;
    _outcome = _state == null ? null : _game.outcome(_state!);
    _lastFilled = _state?.cells.where((c) => c != null).length ?? 4;
    // Seed existing discs as fully settled.
    final s = _state;
    if (s != null) {
      for (var i = 0; i < s.cells.length; i++) {
        if (s.cells[i] != null) _ensureFlip(i, animate: false);
      }
    }
    _entrance.forward();
    _sub = widget.controller.stateStream.listen(_onState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoPass());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _entrance.dispose();
    _confettiCtrl.dispose();
    _passToast.dispose();
    for (final c in _flipCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _ensureFlip(int cell, {required bool animate}) {
    if (_flipCtrls.containsKey(cell)) {
      if (animate) {
        _flipCtrls[cell]!.forward(from: 0);
      }
      return;
    }
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _flipCtrls[cell] = ctrl;
    if (animate) {
      ctrl.forward(from: 0);
    } else {
      ctrl.value = 1;
    }
  }

  void _onState(ReversiState state) {
    final style = widget.style;
    final filled = state.cells.where((c) => c != null).length;
    final outcome = _game.outcome(state);

    if (state.lastWasPass) {
      style.sounds.onPass?.call();
      if (style.haptics) HapticFeedback.selectionClick();
      _passToast.forward(from: 0);
    } else if (filled > _lastFilled && state.lastCell != null) {
      _ensureFlip(state.lastCell!, animate: true);
      if (style.haptics) HapticFeedback.lightImpact();
      style.sounds.onPlace?.call();

      // Stagger flips.
      final flips = state.lastFlipped;
      if (flips.isNotEmpty) {
        style.sounds.onFlip?.call(flips.length);
        for (var i = 0; i < flips.length; i++) {
          final cell = flips[i];
          Future.delayed(Duration(milliseconds: 40 + i * 35), () {
            if (!mounted) return;
            _ensureFlip(cell, animate: true);
            if (style.haptics && i % 2 == 0) {
              HapticFeedback.selectionClick();
            }
            setState(() {});
          });
        }
      }
    }

    if (filled < _lastFilled) {
      // New game
      for (final c in _flipCtrls.values) {
        c.dispose();
      }
      _flipCtrls.clear();
      _confettiCtrl.value = 0;
      _confetti = const [];
      for (var i = 0; i < state.cells.length; i++) {
        if (state.cells[i] != null) _ensureFlip(i, animate: false);
      }
    }

    if (outcome != null && _outcome == null) {
      if (outcome.isWin) {
        style.sounds.onWin?.call();
        if (style.haptics) HapticFeedback.heavyImpact();
        if (style.confetti) {
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
      _lastFilled = filled;
      _passing = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoPass());
  }

  Future<void> _maybeAutoPass() async {
    final state = _state;
    if (state == null || _outcome != null || _passing) return;
    if (!_game.mustPass(state, state.currentPlayerId)) return;
    // Hot-seat: always auto-pass. Networked: only if it's "local" seat —
    // MatchController already gates; pass is legal for current player.
    if (!widget.controller.canActLocally && !widget.controller.hotSeat) {
      // Still current player on this client only acts.
      if (widget.controller.localPlayerId != state.currentPlayerId) return;
    }
    _passing = true;
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    await widget.controller.submitMove(const ReversiMove.pass());
  }

  List<_Confetto> _spawnConfetti(ReversiState state, GameOutcome outcome) {
    final scheme = Theme.of(context).colorScheme;
    final winColor = outcome.winnerId == state.darkId
        ? widget.style.resolveDark(scheme)
        : widget.style.resolveLight(scheme);
    final palette = [
      winColor,
      widget.style.resolveDark(scheme),
      widget.style.resolveLight(scheme),
      const Color(0xFFF4B740),
    ];
    return List.generate(36, (i) {
      final angle = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 2.8;
      return _Confetto(
        angle: angle,
        speed: 0.45 + _rnd.nextDouble(),
        size: 0.014 + _rnd.nextDouble() * 0.02,
        color: palette[i % palette.length],
        spin: (_rnd.nextDouble() - 0.5) * 12,
        phase: _rnd.nextDouble() * math.pi,
        round: _rnd.nextBool(),
      );
    });
  }

  void _onTap(int cell) {
    if (_outcome != null || _passing) return;
    widget.controller.submitMove(ReversiMove(cell));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final state = _state;
    if (state == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final dark = style.resolveDark(scheme);
    final light = style.resolveLight(scheme);
    final boardColor = style.resolveBoard(scheme);
    final legal = style.showLegalMoves && _outcome == null
        ? _game.legalMoves(state, state.currentPlayerId).toSet()
        : const <int>{};
    final winnerIsDark = _outcome?.isWin == true &&
        _outcome!.winnerId == state.darkId;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusBanner(
          state: state,
          outcome: _outcome,
          dark: dark,
          light: light,
          passToast: _passToast.value,
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = constraints.maxWidth;
                return AnimatedBuilder(
                  animation: Listenable.merge([
                    _entrance,
                    _confettiCtrl,
                    _passToast,
                    ..._flipCtrls.values,
                  ]),
                  builder: (context, _) {
                    final enter =
                        Curves.easeOutCubic.transform(_entrance.value);
                    return Stack(
                      children: [
                        Transform.scale(
                          scale: 0.94 + 0.06 * enter,
                          child: Opacity(
                            opacity: enter.clamp(0.0, 1.0),
                            child: _BoardGrid(
                              state: state,
                              dark: dark,
                              light: light,
                              boardColor: boardColor,
                              gridColor: style.resolveGrid(scheme),
                              hintColor: style.resolveHint(scheme),
                              legal: legal,
                              flipCtrls: _flipCtrls,
                              gameOver: _outcome != null,
                              winnerIsDark: winnerIsDark,
                              onTap: _onTap,
                            ),
                          ),
                        ),
                        if (style.confetti && _confetti.isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _ConfettiPainter(
                                  confetti: _confetti,
                                  t: _confettiCtrl.value,
                                  boardSize: side,
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
// Banner
// ---------------------------------------------------------------------------

class _StatusBanner extends StatelessWidget {
  final ReversiState state;
  final GameOutcome? outcome;
  final Color dark;
  final Color light;
  final double passToast;

  const _StatusBanner({
    required this.state,
    required this.outcome,
    required this.dark,
    required this.light,
    required this.passToast,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        );
    final sd = state.scoreFor(state.darkId);
    final sl = state.scoreFor(state.lightId);

    Widget center;
    if (outcome == null) {
      if (passToast > 0 && passToast < 1) {
        final fade = passToast < 0.2
            ? passToast / 0.2
            : (passToast > 0.75 ? (1 - passToast) / 0.25 : 1.0);
        center = Opacity(
          key: const ValueKey('pass'),
          opacity: fade.clamp(0.0, 1.0),
          child: Text('Pass', style: textStyle),
        );
      } else {
        final isDark = state.currentPlayerId == state.darkId;
        center = Row(
          key: ValueKey('turn-${state.currentPlayerId}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            _MiniDisc(color: isDark ? dark : light, size: 18),
            const SizedBox(width: 8),
            Text('to play', style: textStyle),
          ],
        );
      }
    } else if (outcome!.isDraw) {
      center = Text('Dead heat', key: const ValueKey('draw'), style: textStyle);
    } else {
      final isDark = outcome!.winnerId == state.darkId;
      final color = isDark ? dark : light;
      center = Row(
        key: const ValueKey('win'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniDisc(color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            isDark ? 'Dark wins' : 'Light wins',
            style: textStyle?.copyWith(
              color: isDark ? dark : Colors.black87,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        _ScoreChip(
          label: 'Dark',
          score: sd,
          color: dark,
          active: outcome == null && state.currentPlayerId == state.darkId,
          winner: outcome?.isWin == true && outcome!.winnerId == state.darkId,
        ),
        Expanded(
          child: SizedBox(
            height: 40,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: center,
              ),
            ),
          ),
        ),
        _ScoreChip(
          label: 'Light',
          score: sl,
          color: light,
          active: outcome == null && state.currentPlayerId == state.lightId,
          winner: outcome?.isWin == true && outcome!.winnerId == state.lightId,
          onDark: false,
        ),
      ],
    );
  }
}

class _ScoreChip extends StatelessWidget {
  final String label;
  final int score;
  final Color color;
  final bool active;
  final bool winner;
  final bool onDark;

  const _ScoreChip({
    required this.label,
    required this.score,
    required this.color,
    required this.active,
    this.winner = false,
    this.onDark = true,
  });

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : Colors.black87;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: winner
              ? const Color(0xFFF4B740)
              : (active ? Colors.white54 : Colors.black12),
          width: winner || active ? 2 : 1,
        ),
        boxShadow: [
          if (active || winner)
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: fg.withValues(alpha: 0.85),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$score',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniDisc extends StatelessWidget {
  final Color color;
  final double size;
  const _MiniDisc({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.black26, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Board grid
// ---------------------------------------------------------------------------

class _BoardGrid extends StatelessWidget {
  final ReversiState state;
  final Color dark;
  final Color light;
  final Color boardColor;
  final Color gridColor;
  final Color hintColor;
  final Set<int> legal;
  final Map<int, AnimationController> flipCtrls;
  final bool gameOver;
  final bool winnerIsDark;
  final ValueChanged<int> onTap;

  const _BoardGrid({
    required this.state,
    required this.dark,
    required this.light,
    required this.boardColor,
    required this.gridColor,
    required this.hintColor,
    required this.legal,
    required this.flipCtrls,
    required this.gameOver,
    required this.winnerIsDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(boardColor, Colors.white, 0.12)!,
            boardColor,
            Color.lerp(boardColor, Colors.black, 0.12)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: boardColor.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: ReversiState.size,
        ),
        itemCount: ReversiState.cellCount,
        itemBuilder: (context, i) {
          final owner = state.cells[i];
          final isLegal = legal.contains(i);
          final flipT = flipCtrls[i]?.value ?? (owner == null ? 0.0 : 1.0);
          // At flip mid-point (0.5) scale Y → 0; color is new color after 0.5.
          final scaleY = flipT < 0.5
              ? (1 - flipT * 2)
              : ((flipT - 0.5) * 2);
          final showDark = owner == null
              ? true
              : (owner == state.darkId);
          // During flip from light→dark: first half still light, second dark.
          // We always paint the *current* owner; flip anim is squash only after
          // state already updated — so mid-flip we squash then grow new color.
          final discColor = owner == null
              ? null
              : (showDark ? dark : light);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: (!gameOver && (isLegal || owner == null))
                ? () {
                    if (isLegal) onTap(i);
                  }
                : null,
            child: CustomPaint(
              painter: _CellPainter(gridColor: gridColor),
              child: Center(
                child: owner != null
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.diagonal3Values(1.0, scaleY.clamp(0.05, 1.0), 1.0),
                        child: _Disc(color: discColor!),
                      )
                    : (isLegal && !gameOver
                        ? Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hintColor,
                            ),
                          )
                        : null),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CellPainter extends CustomPainter {
  final Color gridColor;
  _CellPainter({required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = gridColor,
    );
  }

  @override
  bool shouldRepaint(_CellPainter old) => old.gridColor != gridColor;
}

class _Disc extends StatelessWidget {
  final Color color;
  const _Disc({required this.color});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.35, -0.4),
              colors: [
                Color.lerp(color, Colors.white, 0.35)!,
                color,
                Color.lerp(color, Colors.black, 0.2)!,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 3,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
