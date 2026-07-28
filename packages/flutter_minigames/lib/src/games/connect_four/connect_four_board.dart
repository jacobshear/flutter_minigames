import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Picture, PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/src/core/core.dart';

import 'connect_four_game.dart';
import 'connect_four_style.dart';

/// Animated Connect Four board wired to a [MatchController].
///
/// Toy-quality juice:
/// - Discs fall **behind** a punched plastic faceplate (path-difference holes)
/// - Gravity ease-in + impact bounce; longer falls take longer
/// - Column press + ghost disc in the top rail
/// - Win pulse on the four, glow line, confetti, escalating haptics
///
/// Brand comes from [ConnectFourStyle] (palette / sounds / confetti).
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
    duration: const Duration(milliseconds: 780),
  );
  late final AnimationController _winPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final AnimationController _confettiCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1650),
  );

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

  int _dropDurationMs(int dropRows) => (260 + dropRows * 85).clamp(280, 780);

  void _ensureDropCtrl(String key, {required bool animate, int dropRows = 3}) {
    if (_dropCtrls.containsKey(key)) return;
    final ms = animate ? _dropDurationMs(dropRows) : 1;
    final ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: ms),
    );
    // Gravity → impact squash → settle.
    final anim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.05)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 80,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.05, end: 0.96)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.96, end: 1.0)
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
      final dropRows = ConnectFourState.rows - row;
      _ensureDropCtrl('$col,$row', animate: true, dropRows: dropRows);

      final landMs = (_dropDurationMs(dropRows) * 0.80).round();
      if (style.haptics) {
        HapticFeedback.selectionClick();
        Future.delayed(Duration(milliseconds: landMs), () {
          if (!mounted) return;
          HapticFeedback.mediumImpact();
          style.sounds.onDrop?.call(dropRows);
        });
      } else {
        Future.delayed(Duration(milliseconds: landMs), () {
          if (mounted) style.sounds.onDrop?.call(dropRows);
        });
      }
    }

    if (filled < _lastFilled) {
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
    // Let the landing disc settle before the celebration.
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      widget.style.sounds.onWin?.call();
      if (widget.style.haptics) {
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 90), () {
          if (mounted) HapticFeedback.mediumImpact();
        });
      }
      final line = _winLine;
      if (line != null && line.isNotEmpty) {
        var sumC = 0.0, sumR = 0.0;
        for (final i in line) {
          sumC += (i % ConnectFourState.cols + 0.5) / ConnectFourState.cols;
          sumR += (i ~/ ConnectFourState.cols + 0.5) / ConnectFourState.rows;
        }
        _confettiOrigin = Offset(
          sumC / line.length,
          1.0 - (sumR / line.length),
        );
      }
      if (widget.style.confetti) {
        setState(() {
          _confetti = _spawnConfetti();
        });
        _confettiCtrl.forward(from: 0);
      }
    });
  }

  List<_Confetto> _spawnConfetti() {
    final scheme = Theme.of(context).colorScheme;
    final palette = <Color>[
      widget.style.resolveP0(scheme),
      widget.style.resolveP1(scheme),
      const Color(0xFFF4B740),
      const Color(0xFFFFF3E0),
      Colors.white,
    ];
    return List<_Confetto>.generate(48, (i) {
      final angle = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 2.9;
      return _Confetto(
        angle: angle,
        speed: 0.48 + _rnd.nextDouble() * 1.05,
        size: 0.014 + _rnd.nextDouble() * 0.022,
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
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: AspectRatio(
            aspectRatio: 7 / 6.7,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final cell = w / ConnectFourState.cols;
                final boardH = cell * ConnectFourState.rows;
                final topRail = constraints.maxHeight - boardH;
                final pad = cell * 0.07;

                return AnimatedBuilder(
                  animation: Listenable.merge([
                    _entrance,
                    _winPulse,
                    _confettiCtrl,
                    ..._dropCtrls.values,
                  ]),
                  builder: (context, _) {
                    final enter = Curves.easeOutCubic.transform(
                      _entrance.value,
                    );
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Ghost disc in the top rail.
                        if (!gameOver && _hoverCol != null)
                          Positioned(
                            left: _hoverCol! * cell + pad * 0.3,
                            top: math.max(0.0, topRail * 0.08),
                            width: cell - pad * 0.6,
                            height: cell - pad * 0.6,
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: 0.42,
                                child: _Disc(
                                  color: state.isPlayer0Turn ? p0 : p1,
                                  progress: 1,
                                ),
                              ),
                            ),
                          ),
                        // Board: back well → discs → punched face → hits.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: boardH,
                          child: Transform.translate(
                            offset: Offset(0, (1 - enter) * 32),
                            child: Opacity(
                              opacity: enter.clamp(0.0, 1.0),
                              child: _ToyBoard(
                                cell: cell,
                                pad: pad,
                                state: state,
                                p0: p0,
                                p1: p1,
                                boardColor: boardColor,
                                holeColor: holeColor,
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
                        // Win line sits on top of the face (celebratory).
                        if (_winLine != null)
                          Positioned(
                            left: pad,
                            right: pad,
                            bottom: pad,
                            height: boardH - pad * 2,
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _WinLinePainter(
                                  line: _winLine!,
                                  color: winnerIsP0 == true ? p0 : p1,
                                  pulse: _winPulse.value,
                                  cell: (w - pad * 2) / ConnectFourState.cols,
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
                                    (topRail + _confettiOrigin.dy * boardH) /
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
// Toy board: back well + discs (behind) + punched plastic face + hit columns
// ---------------------------------------------------------------------------

class _ToyBoard extends StatelessWidget {
  final double cell;
  final double pad;
  final ConnectFourState state;
  final Color p0;
  final Color p1;
  final Color boardColor;
  final Color holeColor;
  final Set<int> winSet;
  final bool gameOver;
  final double winPulse;
  final Map<String, Animation<double>> dropAnims;
  final int? hoverCol;
  final ValueChanged<int?> onHover;
  final ValueChanged<int> onTap;

  const _ToyBoard({
    required this.cell,
    required this.pad,
    required this.state,
    required this.p0,
    required this.p1,
    required this.boardColor,
    required this.holeColor,
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
    final radius = cell * 0.28;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          // One light, one shadow direction: the toy is lit from the upper
          // left, so its shadow falls down and slightly right.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.26),
            blurRadius: 26,
            offset: const Offset(3, 14),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 5,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      // Don't clip — falling discs start above the frame.
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1) Back well (visible through the punched holes) — a real cavity
          //    with column slots, not a flat gradient.
          Positioned.fill(
            child: CustomPaint(
              painter: _WellPainter(
                holeColor: holeColor,
                pad: pad,
                radius: radius,
              ),
            ),
          ),
          // 2) Discs — behind the faceplate so they fall "into" the toy.
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: CustomPaint(
                painter: _DiscsPainter(
                  state: state,
                  p0: p0,
                  p1: p1,
                  winSet: winSet,
                  gameOver: gameOver,
                  winPulse: winPulse,
                  dropAnims: dropAnims,
                ),
              ),
            ),
          ),
          // 3) Plastic face with circular cutouts.
          Positioned.fill(
            child: CustomPaint(
              painter: _FaceplatePainter(
                boardColor: boardColor,
                pad: pad,
                radius: radius,
              ),
            ),
          ),
          // 4) Column interaction layer.
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: Row(
                children: [
                  for (var col = 0; col < ConnectFourState.cols; col++)
                    Expanded(
                      child: _ColumnSensor(
                        col: col,
                        open: state.dropRow(col) != null && !gameOver,
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
          ),
        ],
      ),
    );
  }
}

/// Renders every disc in absolute board coordinates (row 0 = bottom).
class _DiscsPainter extends CustomPainter {
  final ConnectFourState state;
  final Color p0;
  final Color p1;
  final Set<int> winSet;
  final bool gameOver;
  final double winPulse;
  final Map<String, Animation<double>> dropAnims;

  _DiscsPainter({
    required this.state,
    required this.p0,
    required this.p1,
    required this.winSet,
    required this.gameOver,
    required this.winPulse,
    required this.dropAnims,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / ConnectFourState.cols;
    final cellH = size.height / ConnectFourState.rows;
    final discR = math.min(cellW, cellH) * 0.42;

    for (var col = 0; col < ConnectFourState.cols; col++) {
      for (var row = 0; row < ConnectFourState.rows; row++) {
        final index = row * ConnectFourState.cols + col;
        final owner = state.cells[index];
        if (owner == null) continue;

        final key = '$col,$row';
        final t = dropAnims[key]?.value ?? 1.0;
        final isP0 = state.playerIds.indexOf(owner) == 0;
        final color = isP0 ? p0 : p1;
        final isWin = winSet.contains(index);
        final dimmed = gameOver && !isWin;

        // visualRow: 0 at top of canvas.
        final visualRow = ConnectFourState.rows - 1 - row;
        final restY = (visualRow + 0.5) * cellH;
        // Start above the board so the fall is visible through several holes.
        final startY = -cellH * (0.6 + (ConnectFourState.rows - row) * 0.85);
        // [t] already encodes gravity + bounce overshoot (0 → 1.05 → 0.96 → 1).
        final drawY = startY + (restY - startY) * t;

        final cx = (col + 0.5) * cellW;
        final scale =
            t > 1 ? 1.0 + (t - 1) * 0.1 : 0.9 + 0.1 * t.clamp(0.0, 1.0);

        canvas.save();
        canvas.translate(cx, drawY);
        canvas.scale(scale);
        final discColor = dimmed
            ? Color.lerp(color, const Color(0xFFF7F0E4), 0.55)!
                .withValues(alpha: 0.45)
            : color;
        _paintDisc(
          canvas,
          discR,
          discColor,
          winGlow: isWin ? 0.28 + 0.4 * winPulse : 0,
        );
        canvas.restore();
      }
    }
  }

  void _paintDisc(Canvas canvas, double r, Color color,
          {required double winGlow}) =>
      paintCheckerDisc(canvas, Offset.zero, r, color, winGlow: winGlow);

  @override
  bool shouldRepaint(_DiscsPainter old) => true; // driven by drop anims
}

/// One translucent-plastic checker, lit from the upper left.
///
/// The read we're after is a moulded acrylic counter sitting *inside* a slot:
/// a contact shadow on the back wall behind it, a saturated rim where the light
/// passes through the thick edge, the moulded concentric ring real counters
/// have, and a single specular highlight up-left. Every offset here points
/// down-right for shadow / up-left for light — the board and faceplate agree.
void paintCheckerDisc(
  Canvas canvas,
  Offset c,
  double r,
  Color color, {
  double winGlow = 0,
}) {
  if (winGlow > 0) {
    canvas.drawCircle(
      c,
      r * 1.2,
      Paint()
        ..color = color.withValues(alpha: winGlow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5),
    );
  }

  // Cast shadow onto the back wall of the well.
  canvas.drawCircle(
    c.translate(r * 0.10, r * 0.14),
    r * 0.99,
    Paint()
      ..color = const Color(0x5C000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.16),
  );

  final rect = Rect.fromCircle(center: c, radius: r);

  // Body. Translucent plastic is lightest where it is thinnest and where the
  // light enters, and glows a little on the far side from transmitted light —
  // hence the second, weaker lift at the lower right rather than a flat falloff.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.38, -0.45),
        radius: 1.05,
        colors: [
          Color.lerp(color, Colors.white, 0.52)!,
          Color.lerp(color, Colors.white, 0.10)!,
          color,
          Color.lerp(color, Colors.black, 0.30)!,
        ],
        stops: const [0.0, 0.36, 0.68, 1.0],
      ).createShader(rect),
  );

  // Transmitted light bleeding through the thick lower-right edge.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.55, 0.62),
        radius: 0.62,
        colors: [
          Color.lerp(color, Colors.white, 0.30)!.withValues(alpha: 0.55),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(rect),
  );

  // Edge: dark seat where it meets the slot, bright arc where light grazes it.
  canvas.drawCircle(
    c,
    r * 0.965,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.09
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.06),
          Colors.black.withValues(alpha: 0.30),
          Colors.white.withValues(alpha: 0.10),
        ],
        stops: const [0.0, 0.16, 0.42, 0.72, 1.0],
        transform: const GradientRotation(-math.pi * 0.85),
      ).createShader(rect),
  );

  // Moulded concentric ring — the detail that makes it a counter, not a dot.
  canvas.drawCircle(
    c.translate(-r * 0.02, -r * 0.02),
    r * 0.62,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.055
      ..color = Colors.black.withValues(alpha: 0.16),
  );
  canvas.drawCircle(
    c.translate(-r * 0.035, -r * 0.045),
    r * 0.62,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.045
      ..color = Colors.white.withValues(alpha: 0.26),
  );

  // Specular.
  canvas.save();
  canvas.clipPath(Path()..addOval(rect));
  canvas.drawOval(
    Rect.fromCenter(
      center: c.translate(-r * 0.34, -r * 0.40),
      width: r * 0.78,
      height: r * 0.56,
    ),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.46)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.14),
  );
  canvas.restore();
}

/// Geometry shared by the well and the faceplate — they must agree exactly or
/// the holes stop lining up with the recesses behind them.
({Rect inner, double cellW, double cellH, double holeR}) _holeGeometry(
  Size size,
  double pad,
) {
  final inner = Rect.fromLTWH(
    pad,
    pad,
    size.width - pad * 2,
    size.height - pad * 2,
  );
  final cellW = inner.width / ConnectFourState.cols;
  final cellH = inner.height / ConnectFourState.rows;
  return (
    inner: inner,
    cellW: cellW,
    cellH: cellH,
    // Hole slightly smaller than disc so pieces sit "inside" the toy.
    holeR: math.min(cellW, cellH) * 0.40,
  );
}

/// The cavity behind the faceplate. Only the discs of it visible through the
/// cutouts matter, so the detail is spent there: each empty slot gets a real
/// inner bevel (dark on the light side, lifted opposite) so it reads as a hole
/// punched through plastic rather than a printed grey circle.
class _WellPainter extends CustomPainter {
  final Color holeColor;
  final double pad;
  final double radius;

  _WellPainter({
    required this.holeColor,
    required this.pad,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPicture(_wellFor(size, holeColor, pad, radius));
  }

  @override
  bool shouldRepaint(_WellPainter old) =>
      old.holeColor != holeColor || old.pad != pad || old.radius != radius;
}

void _paintWell(
  Canvas canvas,
  Size size,
  Color holeColor,
  double pad,
  double radius,
) {
  final rr = RRect.fromRectAndRadius(
    Offset.zero & size,
    Radius.circular(radius),
  );
  canvas.save();
  canvas.clipRRect(rr);
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(holeColor, Colors.black, 0.10)!,
          Color.lerp(holeColor, Colors.black, 0.22)!,
        ],
      ).createShader(Offset.zero & size),
  );

  final g = _holeGeometry(size, pad);
  final floor = Color.lerp(holeColor, Colors.white, 0.06)!;
  final deep = Color.lerp(holeColor, Colors.black, 0.24)!;

  for (var col = 0; col < ConnectFourState.cols; col++) {
    for (var visualRow = 0; visualRow < ConnectFourState.rows; visualRow++) {
      final c = Offset(
        g.inner.left + (col + 0.5) * g.cellW,
        g.inner.top + (visualRow + 0.5) * g.cellH,
      );
      final rect = Rect.fromCircle(center: c, radius: g.holeR);
      // Slot floor, brighter at the lower right where the light lands after
      // it clears the rim.
      canvas.drawCircle(
        c,
        g.holeR,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [deep, floor],
          ).createShader(rect),
      );
      // Rim shadow cast down onto the floor from the upper-left lip.
      canvas.drawCircle(
        c.translate(-g.holeR * 0.10, -g.holeR * 0.13),
        g.holeR * 0.94,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = g.holeR * 0.26
          ..color = Colors.black.withValues(alpha: 0.20)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, g.holeR * 0.16),
      );
    }
  }
  canvas.restore();
}

/// Plastic face with circular holes punched out so discs show through.
class _FaceplatePainter extends CustomPainter {
  final Color boardColor;
  final double pad;
  final double radius;

  _FaceplatePainter({
    required this.boardColor,
    required this.pad,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPicture(_faceFor(size, boardColor, pad, radius));
  }

  @override
  bool shouldRepaint(_FaceplatePainter old) =>
      old.boardColor != boardColor || old.pad != pad || old.radius != radius;
}

void _paintFaceplate(
  Canvas canvas,
  Size size,
  Color boardColor,
  double pad,
  double radius,
) {
  final outer = RRect.fromRectAndRadius(
    Offset.zero & size,
    Radius.circular(radius),
  );
  final facePath = Path()..addRRect(outer);
  final g = _holeGeometry(size, pad);

  final holes = Path();
  for (var col = 0; col < ConnectFourState.cols; col++) {
    for (var visualRow = 0; visualRow < ConnectFourState.rows; visualRow++) {
      final cx = g.inner.left + (col + 0.5) * g.cellW;
      final cy = g.inner.top + (visualRow + 0.5) * g.cellH;
      holes.addOval(
        Rect.fromCircle(center: Offset(cx, cy), radius: g.holeR),
      );
    }
  }

  final punched = Path.combine(PathOperation.difference, facePath, holes);

  // Plastic body gradient.
  canvas.drawPath(
    punched,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(boardColor, Colors.white, 0.13)!,
          boardColor,
          Color.lerp(boardColor, Colors.black, 0.24)!,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Offset.zero & size),
  );

  canvas.save();
  canvas.clipPath(punched);

  // Injection-moulded texture: a very fine flake so the plastic isn't a pure
  // vector fill, plus a broad sheen band raking across from the light.
  final flake = Paint();
  final n = (size.width / 7).round().clamp(20, 80);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      final h = _hash2(i, j);
      if (h < 0.90) continue;
      flake.color = (h > 0.955 ? Colors.white : Colors.black)
          .withValues(alpha: 0.020 + 0.030 * (h - 0.90) / 0.10);
      canvas.drawCircle(
        Offset(
          (i + _hash2(i, j + 41)) / n * size.width,
          (j + _hash2(i + 17, j)) / n * size.height,
        ),
        size.width * 0.0016,
        flake,
      );
    }
  }
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-1, -1.2),
        end: const Alignment(0.4, 1),
        colors: [
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.0),
          Colors.black.withValues(alpha: 0.12),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Offset.zero & size),
  );

  // Frame thickness: the toy is a slab, so the bottom and right edges show a
  // darker side wall and the top-left edge catches a bright bevel.
  canvas.drawRRect(
    outer.deflate(size.width * 0.004),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.009
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.50),
          Colors.white.withValues(alpha: 0.06),
          Colors.black.withValues(alpha: 0.34),
        ],
        stops: const [0.0, 0.42, 1.0],
      ).createShader(Offset.zero & size),
  );
  canvas.drawRect(
    Rect.fromLTRB(0, size.height - pad * 0.55, size.width, size.height),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.0),
          Colors.black.withValues(alpha: 0.26),
        ],
      ).createShader(
        Rect.fromLTRB(0, size.height - pad * 0.55, size.width, size.height),
      ),
  );
  canvas.restore();

  // Drop slots along the top rail — the mouths you actually post a disc into.
  // Cheap detail, but it explains the whole toy: you can see where discs go in.
  for (var col = 0; col < ConnectFourState.cols; col++) {
    final cx = g.inner.left + (col + 0.5) * g.cellW;
    final slot = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, pad * 0.5),
        width: g.holeR * 1.55,
        height: pad * 0.62,
      ),
      Radius.circular(pad * 0.31),
    );
    canvas.drawRRect(
      slot,
      Paint()..color = Colors.black.withValues(alpha: 0.30),
    );
    canvas.drawRRect(
      slot.shift(Offset(0, pad * 0.10)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = pad * 0.12
        ..color = Colors.white.withValues(alpha: 0.16),
    );
  }

  // Hole rims — a punched cutout, so the bevel runs opposite to a raised edge:
  // shadowed lip on the light side, lit lip on the far side.
  for (var col = 0; col < ConnectFourState.cols; col++) {
    for (var visualRow = 0; visualRow < ConnectFourState.rows; visualRow++) {
      final c = Offset(
        g.inner.left + (col + 0.5) * g.cellW,
        g.inner.top + (visualRow + 0.5) * g.cellH,
      );
      final rect = Rect.fromCircle(center: c, radius: g.holeR * 1.06);
      canvas.drawCircle(
        c,
        g.holeR * 1.06,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = g.holeR * 0.15
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black.withValues(alpha: 0.34),
              Colors.black.withValues(alpha: 0.05),
              Colors.white.withValues(alpha: 0.34),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(rect),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Static-layer cache
// ---------------------------------------------------------------------------

/// Deterministic 0..1 value hash — procedural texture with no assets, and
/// stable across rebuilds so a cached picture never shimmers.
double _hash2(int x, int y) {
  var h = x * 374761393 + y * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0;
}

class _Layer {
  final double w;
  final double h;
  final int color;
  final double pad;
  final bool face;
  final ui.Picture picture;
  const _Layer(this.w, this.h, this.color, this.pad, this.face, this.picture);

  bool matches(Size s, Color c, double p, bool isFace) =>
      w == s.width &&
      h == s.height &&
      color == c.toARGB32() &&
      pad == p &&
      face == isFace;
}

/// Board and preview can be on screen at once at different sizes, so keep a few
/// slots rather than a single one that would thrash every frame.
final List<_Layer> _layers = [];

ui.Picture _layerFor(
  Size size,
  Color color,
  double pad,
  double radius,
  bool face,
) {
  for (final l in _layers) {
    if (l.matches(size, color, pad, face)) return l.picture;
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (face) {
    _paintFaceplate(canvas, size, color, pad, radius);
  } else {
    _paintWell(canvas, size, color, pad, radius);
  }
  final made = _Layer(size.width, size.height, color.toARGB32(), pad, face,
      recorder.endRecording());
  _layers.insert(0, made);
  while (_layers.length > 4) {
    _layers.removeLast().picture.dispose();
  }
  return made.picture;
}

ui.Picture _faceFor(Size size, Color c, double pad, double radius) =>
    _layerFor(size, c, pad, radius, true);

ui.Picture _wellFor(Size size, Color c, double pad, double radius) =>
    _layerFor(size, c, pad, radius, false);

class _ColumnSensor extends StatefulWidget {
  final int col;
  final bool open;
  final bool hovered;
  final VoidCallback onHoverEnter;
  final VoidCallback onHoverExit;
  final VoidCallback onTap;

  const _ColumnSensor({
    required this.col,
    required this.open,
    required this.hovered,
    required this.onHoverEnter,
    required this.onHoverExit,
    required this.onTap,
  });

  @override
  State<_ColumnSensor> createState() => _ColumnSensorState();
}

class _ColumnSensorState extends State<_ColumnSensor> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final open = widget.open;
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: (_pressed || widget.hovered) && open
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.transparent,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small disc widgets (banner / ghost)
// ---------------------------------------------------------------------------

class _Disc extends StatelessWidget {
  final Color color;
  final double progress;

  const _Disc({
    required this.color,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SingleDiscPainter(color: color, progress: progress),
    );
  }
}

class _SingleDiscPainter extends CustomPainter {
  final Color color;
  final double progress;

  _SingleDiscPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.46 * progress.clamp(0.15, 1.0);
    paintCheckerDisc(canvas, c, r, color);
  }

  @override
  bool shouldRepaint(_SingleDiscPainter old) =>
      old.color != color || old.progress != progress;
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
      final ink = Theme.of(context).colorScheme.onSurface;
      content = _ResultPill(
        key: const ValueKey('draw'),
        color: ink,
        child: Text(
          'Dead heat',
          style: textStyle?.copyWith(color: ink, fontSize: 20),
        ),
      );
    } else {
      final isP0 = winnerIsP0 == true;
      final color = isP0 ? p0 : p1;
      content = _ResultPill(
        key: const ValueKey('win'),
        color: color,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MiniDisc(color: color, size: 28, glow: 0.35),
            const SizedBox(width: 12),
            Text(
              isP0 ? 'P1 wins' : 'P2 wins',
              style: textStyle?.copyWith(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    final isResult = outcome != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      height: isResult ? 56 : 40,
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.86, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: content,
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
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
          child: _MiniDisc(color: widget.color, size: 22, glow: 0.35 * t),
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
// Win line + confetti
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
    final alpha = 0.5 + 0.35 * pulse;

    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color.withValues(alpha: alpha * 0.55)
        ..strokeWidth = cell * 0.22
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.08),
    );
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = cell * 0.1
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_WinLinePainter old) =>
      old.pulse != pulse || old.line != line || old.color != color;
}

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
