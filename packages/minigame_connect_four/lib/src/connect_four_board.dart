import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigames_core/minigames_core.dart';

import 'connect_four_game.dart';
import 'connect_four_style.dart';

/// Animated Connect Four board wired to a [MatchController].
///
/// Juice (all free for every host):
/// - Column press dips; a translucent ghost disc previews the drop target
/// - Discs fall with ease-in gravity + a soft bounce on impact
/// - Landing haptics scale with drop height; win escalates further
/// - Winning four pulse + glow line; losers dim; confetti burst
/// - Living turn banner with a breathing disc
///
/// Brand (palette, sounds, confetti on/off) comes from [ConnectFourStyle].
class ConnectFourBoard extends StatefulWidget {
  final MatchController<ConnectFourState, ConnectFourMove> controller;
  final ConnectFourStyle style;

  const ConnectFourBoard({
    super.key,
    required this.controller,
    this.style = const ConnectFourStyle(),
  });

  @override
  State<ConnectFourBoard> createState() => _ConnectFourBoardState();
}

class _ConnectFourBoardState extends State<ConnectFourBoard>
    with TickerProviderStateMixin {
  static const _game = ConnectFourGame();

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );
  late final AnimationController _winPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final AnimationController _confettiCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// One controller per disc key (`"$col,$row"`) for drop animation.
  final Map<String, AnimationController> _dropCtrls = {};
  final Map<String, Animation<double>> _dropAnims = {};

  final math.Random _rnd = math.Random();
  StreamSubscription<ConnectFourState>? _sub;

  ConnectFourState? _state;
  GameOutcome? _outcome;
  List<int>? _winLine;
  int _lastFilled = 0;
  int? _hoverCol;
  List<_Confetto> _confetti = const [];
  Offset _confettiOrigin = const Offset(0.5, 0.5);

  @override
  void initState() {
    super.initState();
    _state = widget.controller.state;
    _lastFilled = _state?.filledCount ?? 0;
    _outcome = _state == null ? null : _game.outcome(_state!);
    // Seed already-placed discs as fully landed (resume / hot restart).
    final s = _state;
    if (s != null) {
      for (var i = 0; i < s.cells.length; i++) {
        if (s.cells[i] != null) {
          final col = i % ConnectFourState.cols;
          final row = i ~/ ConnectFourState.cols;
          _ensureDropCtrl('$col,$row', animate: false);
        }
      }
    }
    _entrance.forward();
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _entrance.dispose();
    _winPulse.dispose();
    _confettiCtrl.dispose();
    for (final c in _dropCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _ensureDropCtrl(String key, {required bool animate, int dropRows = 3}) {
    if (_dropCtrls.containsKey(key)) return;
    final ms = animate ? (280 + dropRows * 70).clamp(280, 700) : 1;
    final ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: ms),
    );
    // Gravity ease-in then soft overshoot bounce.
    final anim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.06)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 78,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.06, end: 0.97)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.97, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 10,
      ),
    ]).animate(ctrl);
    _dropCtrls[key] = ctrl;
    _dropAnims[key] = anim;
    if (animate) {
      ctrl.forward();
    } else {
      ctrl.value = 1;
    }
  }

  void _onState(ConnectFourState state) {
    final filled = state.filledCount;
    final outcome = _game.outcome(state);
    final style = widget.style;

    if (filled > _lastFilled &&
        state.lastCol != null &&
        state.lastRow != null) {
      final col = state.lastCol!;
      final row = state.lastRow!;
      final key = '$col,$row';
      // Drop distance from top of board (rows above the landing slot).
      final dropRows = ConnectFourState.rows - row;
      _ensureDropCtrl(key, animate: true, dropRows: dropRows);

      if (style.haptics) {
        HapticFeedback.lightImpact();
        // Impact when the disc would land.
        final landMs = (280 + dropRows * 70).clamp(280, 700) * 0.78;
        Future.delayed(Duration(milliseconds: landMs.round()), () {
          if (!mounted) return;
          HapticFeedback.mediumImpact();
          style.sounds.onDrop?.call();
        });
      } else {
        style.sounds.onDrop?.call();
      }
    }

    if (filled < _lastFilled) {
      // New game — wipe animation state.
      for (final c in _dropCtrls.values) {
        c.dispose();
      }
      _dropCtrls.clear();
      _dropAnims.clear();
      _confettiCtrl.value = 0;
      _winLine = null;
      _confetti = const [];
      _hoverCol = null;
    }

    if (outcome != null && _outcome == null) {
      if (outcome.isWin) {
        _winLine = _game.winningLine(state);
        _startWinEffects(state);
      } else {
        if (style.haptics) HapticFeedback.mediumImpact();
        style.sounds.onDraw?.call();
      }
    }
    if (outcome == null) _winLine = null;

    setState(() {
      _state = state;
      _outcome = outcome;
      _lastFilled = filled;
    });
  }

  void _startWinEffects(ConnectFourState state) {
    widget.style.sounds.onWin?.call();
    if (widget.style.haptics) {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 90), () {
        if (mounted) HapticFeedback.mediumImpact();
      });
    }
    final line = _winLine;
    if (line != null && line.isNotEmpty) {
      // Midpoint of winning discs in board fraction coords (col 0 left, row 0 bottom).
      var sumC = 0.0, sumR = 0.0;
      for (final i in line) {
        sumC += (i % ConnectFourState.cols + 0.5) / ConnectFourState.cols;
        sumR += (i ~/ ConnectFourState.cols + 0.5) / ConnectFourState.rows;
      }
      // Flip Y: board paints row 0 at the bottom.
      _confettiOrigin = Offset(
        sumC / line.length,
        1.0 - (sumR / line.length),
      );
    }
    if (widget.style.confetti) {
      _confetti = _spawnConfetti();
      _confettiCtrl.forward(from: 0);
    }
  }

  List<_Confetto> _spawnConfetti() {
    final scheme = Theme.of(context).colorScheme;
    final palette = <Color>[
      widget.style.resolveP0(scheme),
      widget.style.resolveP1(scheme),
      const Color(0xFFF4B740),
      const Color(0xFFFFF3E0),
    ];
    return List<_Confetto>.generate(42, (i) {
      final angle = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 2.8;
      return _Confetto(
        angle: angle,
        speed: 0.5 + _rnd.nextDouble() * 1.0,
        size: 0.016 + _rnd.nextDouble() * 0.02,
        color: palette[i % palette.length],
        spin: (_rnd.nextDouble() - 0.5) * 14,
        phase: _rnd.nextDouble() * math.pi,
        round: _rnd.nextBool(),
      );
    });
  }

  void _onColumnTap(int col) {
    final state = _state;
    if (state == null || _outcome != null) return;
    if (state.dropRow(col) == null) {
      if (widget.style.haptics) HapticFeedback.selectionClick();
      widget.style.sounds.onInvalid?.call();
      return;
    }
    widget.controller.submitMove(ConnectFourMove(col));
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
    final boardColor = style.resolveBoard(scheme);
    final holeColor = style.resolveHole(scheme);
    final winSet = _winLine?.toSet() ?? const <int>{};
    final gameOver = _outcome != null;
    final winnerIsP0 = _outcome?.isWin == true
        ? state.playerIds.indexOf(_outcome!.winnerId!) == 0
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusBanner(
          state: state,
          outcome: _outcome,
          winnerIsP0: winnerIsP0,
          p0: p0,
          p1: p1,
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: AspectRatio(
            // 7 cols × ~6.4 rows (ghost rail on top).
            aspectRatio: 7 / 6.55,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final cell = w / ConnectFourState.cols;
                final boardH = cell * ConnectFourState.rows;
                final topRail = constraints.maxHeight - boardH;

                return AnimatedBuilder(
                  animation: Listenable.merge([
                    _entrance,
                    _winPulse,
                    _confettiCtrl,
                    ..._dropCtrls.values,
                  ]),
                  builder: (context, _) {
                    return Stack(
                      // Drops start above the frame; never clip mid-flight.
                      clipBehavior: Clip.none,
                      children: [
                        // Ghost / hover disc in the top rail.
                        if (!gameOver && _hoverCol != null)
                          Positioned(
                            left: _hoverCol! * cell,
                            top: topRail * 0.12,
                            width: cell,
                            height: cell,
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: 0.38,
                                child: _Disc(
                                  color: state.isPlayer0Turn ? p0 : p1,
                                  progress: 1,
                                ),
                              ),
                            ),
                          ),
                        // Plastic frame + holes + discs.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: boardH,
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              (1 - Curves.easeOutCubic.transform(
                                    _entrance.value,
                                  )) *
                                  28,
                            ),
                            child: Opacity(
                              opacity: Curves.easeOut
                                  .transform(_entrance.value)
                                  .clamp(0.0, 1.0),
                              child: _BoardFrame(
                                boardColor: boardColor,
                                holeColor: holeColor,
                                cell: cell,
                                state: state,
                                p0: p0,
                                p1: p1,
                                winSet: winSet,
                                gameOver: gameOver,
                                winPulse: _winPulse.value,
                                dropAnims: _dropAnims,
                                hoverCol: gameOver ? null : _hoverCol,
                                onHover: (c) => setState(() => _hoverCol = c),
                                onTap: _onColumnTap,
                              ),
                            ),
                          ),
                        ),
                        // Win line glow across the four.
                        if (_winLine != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: boardH,
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _WinLinePainter(
                                  line: _winLine!,
                                  color: winnerIsP0 == true ? p0 : p1,
                                  pulse: _winPulse.value,
                                  cell: cell,
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
                                  origin: Offset(
                                    _confettiOrigin.dx,
                                    // Origin is relative to full widget;
                                    // map board-local origin into full height.
                                    (topRail +
                                            _confettiOrigin.dy * boardH) /
                                        constraints.maxHeight,
                                  ),
                                  t: _confettiCtrl.value,
                                  boardSize: w,
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
// Status banner
// ---------------------------------------------------------------------------

class _StatusBanner extends StatelessWidget {
  final ConnectFourState state;
  final GameOutcome? outcome;
  final bool? winnerIsP0;
  final Color p0;
  final Color p1;

  const _StatusBanner({
    required this.state,
    required this.outcome,
    required this.winnerIsP0,
    required this.p0,
    required this.p1,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        );

    final Widget content;
    if (outcome == null) {
      final isP0 = state.isPlayer0Turn;
      final color = isP0 ? p0 : p1;
      content = Row(
        key: ValueKey('turn-${state.currentPlayerId}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _BreathingDisc(color: color),
          const SizedBox(width: 12),
          Text('to drop', style: textStyle),
        ],
      );
    } else if (outcome!.isDraw) {
      content = Text(
        'Dead heat',
        key: const ValueKey('draw'),
        style: textStyle,
      );
    } else {
      final color = winnerIsP0 == true ? p0 : p1;
      content = Row(
        key: const ValueKey('win'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniDisc(color: color, size: 26),
          const SizedBox(width: 10),
          Text('wins', style: textStyle?.copyWith(color: color)),
        ],
      );
    }

    return SizedBox(
      height: 40,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.35),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: content,
      ),
    );
  }
}

class _BreathingDisc extends StatefulWidget {
  final Color color;
  const _BreathingDisc({required this.color});

  @override
  State<_BreathingDisc> createState() => _BreathingDiscState();
}

class _BreathingDiscState extends State<_BreathingDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

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
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.scale(
          scale: 0.92 + 0.1 * t,
          child: _MiniDisc(
            color: widget.color,
            size: 22,
            glow: 0.35 * t,
          ),
        );
      },
    );
  }
}

class _MiniDisc extends StatelessWidget {
  final Color color;
  final double size;
  final double glow;

  const _MiniDisc({
    required this.color,
    required this.size,
    this.glow = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 0.95,
          colors: [
            Color.lerp(color, Colors.white, 0.35)!,
            color,
            Color.lerp(color, Colors.black, 0.18)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          if (glow > 0)
            BoxShadow(
              color: color.withValues(alpha: glow),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 3,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Board frame (plastic shell + interactive columns)
// ---------------------------------------------------------------------------

class _BoardFrame extends StatelessWidget {
  final Color boardColor;
  final Color holeColor;
  final double cell;
  final ConnectFourState state;
  final Color p0;
  final Color p1;
  final Set<int> winSet;
  final bool gameOver;
  final double winPulse;
  final Map<String, Animation<double>> dropAnims;
  final int? hoverCol;
  final ValueChanged<int?> onHover;
  final ValueChanged<int> onTap;

  const _BoardFrame({
    required this.boardColor,
    required this.holeColor,
    required this.cell,
    required this.state,
    required this.p0,
    required this.p1,
    required this.winSet,
    required this.gameOver,
    required this.winPulse,
    required this.dropAnims,
    required this.hoverCol,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pad = cell * 0.08;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cell * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(boardColor, Colors.white, 0.12)!,
            boardColor,
            Color.lerp(boardColor, Colors.black, 0.18)!,
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: boardColor.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(pad),
        // Discs animate in from above the frame — don't clip the drop.
        child: Row(
          children: [
            for (var col = 0; col < ConnectFourState.cols; col++)
              Expanded(
                child: _ColumnHitTarget(
                  col: col,
                  cell: cell,
                  pad: pad,
                  state: state,
                  p0: p0,
                  p1: p1,
                  holeColor: holeColor,
                  boardColor: boardColor,
                  winSet: winSet,
                  gameOver: gameOver,
                  winPulse: winPulse,
                  dropAnims: dropAnims,
                  hovered: hoverCol == col,
                  onHoverEnter: () => onHover(col),
                  onHoverExit: () {
                    if (hoverCol == col) onHover(null);
                  },
                  onTap: () => onTap(col),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ColumnHitTarget extends StatefulWidget {
  final int col;
  final double cell;
  final double pad;
  final ConnectFourState state;
  final Color p0;
  final Color p1;
  final Color holeColor;
  final Color boardColor;
  final Set<int> winSet;
  final bool gameOver;
  final double winPulse;
  final Map<String, Animation<double>> dropAnims;
  final bool hovered;
  final VoidCallback onHoverEnter;
  final VoidCallback onHoverExit;
  final VoidCallback onTap;

  const _ColumnHitTarget({
    required this.col,
    required this.cell,
    required this.pad,
    required this.state,
    required this.p0,
    required this.p1,
    required this.holeColor,
    required this.boardColor,
    required this.winSet,
    required this.gameOver,
    required this.winPulse,
    required this.dropAnims,
    required this.hovered,
    required this.onHoverEnter,
    required this.onHoverExit,
    required this.onTap,
  });

  @override
  State<_ColumnHitTarget> createState() => _ColumnHitTargetState();
}

class _ColumnHitTargetState extends State<_ColumnHitTarget> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final open = widget.state.dropRow(widget.col) != null && !widget.gameOver;

    return MouseRegion(
      onEnter: open ? (_) => widget.onHoverEnter() : null,
      onExit: open
          ? (_) {
              widget.onHoverExit();
              setState(() => _pressed = false);
            }
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: open
            ? (_) {
                setState(() => _pressed = true);
                widget.onHoverEnter();
              }
            : null,
        onTapUp: open ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: open
            ? () {
                setState(() => _pressed = false);
                widget.onHoverExit();
              }
            : null,
        onTap: open ? widget.onTap : null,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: const Duration(milliseconds: 100),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if ((_pressed || widget.hovered) && open)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.cell * 0.2),
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              Column(
                children: [
                  // Top row is visual top = game row (rows-1).
                  for (var visualRow = 0;
                      visualRow < ConnectFourState.rows;
                      visualRow++)
                    Expanded(
                      child: _buildSlot(
                        gameRow: ConnectFourState.rows - 1 - visualRow,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlot({required int gameRow}) {
    final index = gameRow * ConnectFourState.cols + widget.col;
    final owner = widget.state.cells[index];
    final key = '${widget.col},$gameRow';
    final dropT = widget.dropAnims[key]?.value ?? (owner == null ? 0.0 : 1.0);
    final isWin = widget.winSet.contains(index);
    final dimmed = widget.gameOver && !isWin && owner != null;

    Color? discColor;
    if (owner != null) {
      final isP0 = widget.state.playerIds.indexOf(owner) == 0;
      discColor = isP0 ? widget.p0 : widget.p1;
    }

    return Padding(
      padding: EdgeInsets.all(widget.cell * 0.06),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 340),
        opacity: dimmed ? 0.28 : 1,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            // Hole well (recessed).
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.holeColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                    spreadRadius: -1,
                  ),
                ],
              ),
            ),
            // Disc (animated Y from above the slot).
            if (discColor != null)
              Transform.translate(
                offset: Offset(
                  0,
                  // Start above the full board so long drops feel real.
                  -widget.cell *
                      (ConnectFourState.rows - gameRow) *
                      (1 - dropT.clamp(0.0, 1.2)),
                ),
                child: Transform.scale(
                  scale: dropT > 1
                      ? 1.0 + (dropT - 1) * 0.04
                      : 0.92 + 0.08 * dropT.clamp(0.0, 1.0),
                  child: _Disc(
                    color: discColor,
                    progress: dropT.clamp(0.0, 1.0),
                    winGlow: isWin ? 0.25 + 0.35 * widget.winPulse : 0,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  final Color color;
  final double progress;
  final double winGlow;

  const _Disc({
    required this.color,
    required this.progress,
    this.winGlow = 0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DiscPainter(
        color: color,
        progress: progress,
        winGlow: winGlow,
      ),
    );
  }
}

class _DiscPainter extends CustomPainter {
  final Color color;
  final double progress;
  final double winGlow;

  _DiscPainter({
    required this.color,
    required this.progress,
    required this.winGlow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.46 * progress.clamp(0.15, 1.0);

    if (winGlow > 0) {
      canvas.drawCircle(
        c,
        r * 1.15,
        Paint()
          ..color = color.withValues(alpha: winGlow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.45),
      );
    }

    final rect = Rect.fromCircle(center: c, radius: r);
    final base = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        radius: 0.95,
        colors: [
          Color.lerp(color, Colors.white, 0.42)!,
          color,
          Color.lerp(color, Colors.black, 0.22)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawCircle(c, r, base);

    // Inner rim for plastic depth.
    canvas.drawCircle(
      c,
      r * 0.78,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..color = Colors.white.withValues(alpha: 0.18),
    );

    // Specular highlight.
    final hi = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.45, -0.55),
        radius: 0.55,
        colors: [
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c.translate(-r * 0.12, -r * 0.15), r * 0.42, hi);
  }

  @override
  bool shouldRepaint(_DiscPainter old) =>
      old.color != color ||
      old.progress != progress ||
      old.winGlow != winGlow;
}

// ---------------------------------------------------------------------------
// Win line
// ---------------------------------------------------------------------------

class _WinLinePainter extends CustomPainter {
  final List<int> line;
  final Color color;
  final double pulse;
  final double cell;

  _WinLinePainter({
    required this.line,
    required this.color,
    required this.pulse,
    required this.cell,
  });

  Offset _center(int index) {
    final col = index % ConnectFourState.cols;
    final gameRow = index ~/ ConnectFourState.cols;
    final visualRow = ConnectFourState.rows - 1 - gameRow;
    return Offset((col + 0.5) * cell, (visualRow + 0.5) * cell);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (line.length < 2) return;
    final a = _center(line.first);
    final b = _center(line.last);
    final alpha = 0.45 + 0.35 * pulse;

    final glow = Paint()
      ..color = color.withValues(alpha: alpha * 0.55)
      ..strokeWidth = cell * 0.22
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.08);
    final stroke = Paint()
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = cell * 0.1
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(a, b, glow);
    canvas.drawLine(a, b, stroke);
  }

  @override
  bool shouldRepaint(_WinLinePainter old) =>
      old.pulse != pulse || old.line != line || old.color != color;
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
  final Offset origin; // fractional 0..1 of the full paint area
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
    const gravity = 2.6;
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
