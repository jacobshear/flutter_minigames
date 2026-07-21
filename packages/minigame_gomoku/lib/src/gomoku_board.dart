import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigames_core/minigames_core.dart';

import 'gomoku_game.dart';
import 'gomoku_style.dart';

/// Animated Gomoku board wired to a [MatchController].
///
/// Self-contains the GP chrome: maroon felt table, Player 1 / Player 2 chips
/// above and below the slab, and a translucent black pill over the board
/// center for outcomes. Juice: stone drop pop, last-move dot, win-line rings,
/// confetti.
class GomokuBoard extends StatefulWidget {
  final MatchController<GomokuState, GomokuMove> controller;
  final GomokuStyle style;

  const GomokuBoard({
    super.key,
    required this.controller,
    this.style = const GomokuStyle(),
  });

  @override
  State<GomokuBoard> createState() => _GomokuBoardState();
}

class _GomokuBoardState extends State<GomokuBoard>
    with TickerProviderStateMixin {
  static const _game = GomokuGame();

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final AnimationController _winCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final AnimationController _confettiCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  /// Per-stone drop progress (0 = above board, 1 = settled).
  final Map<int, AnimationController> _pops = {};

  final math.Random _rnd = math.Random();
  StreamSubscription<GomokuState>? _sub;

  GomokuState? _state;
  GameOutcome? _outcome;
  List<int> _winLine = const [];
  int _lastCount = 0;
  List<_Confetto> _confetti = const [];

  @override
  void initState() {
    super.initState();
    final s = widget.controller.state;
    _state = s;
    if (s != null) {
      _outcome = _game.outcome(s);
      _winLine = _game.winningLine(s);
      _lastCount = s.stoneCount;
      for (var i = 0; i < s.cells.length; i++) {
        if (s.cells[i] != null) _ensurePop(i, animate: false);
      }
      if (_outcome != null) _winCtrl.value = 1;
    }
    _entrance.forward();
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _entrance.dispose();
    _winCtrl.dispose();
    _confettiCtrl.dispose();
    for (final c in _pops.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _ensurePop(int cell, {required bool animate}) {
    if (_pops.containsKey(cell)) {
      if (animate) _pops[cell]!.forward(from: 0);
      return;
    }
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _pops[cell] = ctrl;
    if (animate) {
      ctrl.forward(from: 0);
    } else {
      ctrl.value = 1;
    }
  }

  void _onState(GomokuState state) {
    final style = widget.style;
    final count = state.stoneCount;
    final outcome = _game.outcome(state);

    if (count < _lastCount) {
      // New game.
      for (final c in _pops.values) {
        c.dispose();
      }
      _pops.clear();
      _winCtrl.value = 0;
      _confettiCtrl.value = 0;
      _confetti = const [];
      for (var i = 0; i < state.cells.length; i++) {
        if (state.cells[i] != null) _ensurePop(i, animate: false);
      }
    } else if (count > _lastCount && state.lastCell != null) {
      _ensurePop(state.lastCell!, animate: true);
      style.sounds.onPlace?.call();
      if (style.haptics) HapticFeedback.lightImpact();
    }

    if (outcome != null && _outcome == null) {
      if (outcome.isWin) {
        style.sounds.onWin?.call();
        if (style.haptics) HapticFeedback.heavyImpact();
        _winCtrl.forward(from: 0);
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
      _winLine = _game.winningLine(state);
      _lastCount = count;
    });
  }

  List<_Confetto> _spawnConfetti(GomokuState state, GameOutcome outcome) {
    final scheme = Theme.of(context).colorScheme;
    final winColor = outcome.winnerId == state.blackId
        ? widget.style.resolveBlack(scheme)
        : widget.style.resolveWhite(scheme);
    final palette = [
      winColor,
      widget.style.resolveBlack(scheme),
      widget.style.resolveWhite(scheme),
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

  void _onTapAt(Offset local, _BoardGeom geom, GomokuState state) {
    if (_outcome != null) return;
    final cell = geom.hitTest(local, state.size);
    if (cell == null) return;
    if (state.cells[cell] != null) {
      widget.style.sounds.onInvalid?.call();
      if (widget.style.haptics) HapticFeedback.selectionClick();
      return;
    }
    widget.controller.submitMove(GomokuMove(cell));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final state = _state;
    if (state == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final black = style.resolveBlack(scheme);
    final white = style.resolveWhite(scheme);
    final table = style.resolveTable(scheme);

    return AnimatedBuilder(
      animation: Listenable.merge([
        _entrance,
        _winCtrl,
        _confettiCtrl,
        ..._pops.values,
      ]),
      builder: (context, _) {
        final enter = Curves.easeOutCubic.transform(_entrance.value);

        String? pillMsg;
        if (_outcome != null) {
          pillMsg = _outcome!.isDraw
              ? 'DRAW'
              : (_outcome!.winnerId == state.blackId
                      ? '${style.blackLabel} wins'
                      : '${style.whiteLabel} wins')
                  .toUpperCase();
        }

        final board = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Transform.scale(
            scale: 0.94 + 0.06 * enter,
            child: Opacity(
              opacity: enter.clamp(0.0, 1.0),
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final geom =
                        _BoardGeom(c.maxWidth, state.size);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) =>
                          _onTapAt(d.localPosition, geom, state),
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: Size.square(c.maxWidth),
                            painter: _GomokuPainter(
                              state: state,
                              geom: geom,
                              boardColor: style.resolveBoard(scheme),
                              lineColor: style.resolveLine(scheme),
                              black: black,
                              white: white,
                              pops: {
                                for (final e in _pops.entries)
                                  e.key: e.value.value,
                              },
                              winLine: _winLine.toSet(),
                              winT: Curves.easeOutBack
                                  .transform(_winCtrl.value),
                              gameOver: _outcome != null,
                            ),
                          ),
                          if (style.confetti && _confetti.isNotEmpty)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _ConfettiPainter(
                                    confetti: _confetti,
                                    t: _confettiCtrl.value,
                                    boardSize: c.maxWidth,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );

        // Felt table the slab sits on; opponent chip above, local chip below.
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: RadialGradient(
              center: const Alignment(0, -0.35),
              radius: 1.5,
              colors: [
                Color.lerp(table, Colors.white, 0.07)!,
                table,
                Color.lerp(table, Colors.black, 0.26)!,
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                offset: const Offset(0, 6),
                blurRadius: 18,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _PlayerChip(
                  label: style.whiteLabel,
                  stone: white,
                  stoneEdge: Colors.black26,
                  active: _outcome == null &&
                      state.currentPlayerId == state.whiteId,
                  winner: _outcome?.isWin == true &&
                      _outcome!.winnerId == state.whiteId,
                ),
              ),
              const SizedBox(height: 10),
              Stack(
                alignment: Alignment.center,
                children: [
                  board,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: pillMsg == null
                              ? const SizedBox.shrink()
                              : Container(
                                  key: ValueKey(pillMsg),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black
                                        .withValues(alpha: 0.58),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    pillMsg,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: _PlayerChip(
                  label: style.blackLabel,
                  stone: black,
                  stoneEdge: Colors.white24,
                  active: _outcome == null &&
                      state.currentPlayerId == state.blackId,
                  winner: _outcome?.isWin == true &&
                      _outcome!.winnerId == state.blackId,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

class _BoardGeom {
  final double side;
  final int n;
  final double pad;
  final double spacing;

  _BoardGeom(this.side, this.n)
      : pad = side * 0.055,
        spacing = (side - side * 0.11) / (n - 1);

  Offset center(int row, int col) =>
      Offset(pad + col * spacing, pad + row * spacing);

  /// Nearest intersection to [local], or null outside the grid margin.
  int? hitTest(Offset local, int size) {
    final col = ((local.dx - pad) / spacing).round();
    final row = ((local.dy - pad) / spacing).round();
    if (row < 0 || row >= size || col < 0 || col >= size) return null;
    final c = center(row, col);
    if ((local - c).distance > spacing * 0.72) return null;
    return row * size + col;
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _GomokuPainter extends CustomPainter {
  final GomokuState state;
  final _BoardGeom geom;
  final Color boardColor;
  final Color lineColor;
  final Color black;
  final Color white;
  final Map<int, double> pops;
  final Set<int> winLine;
  final double winT;
  final bool gameOver;

  _GomokuPainter({
    required this.state,
    required this.geom,
    required this.boardColor,
    required this.lineColor,
    required this.black,
    required this.white,
    required this.pops,
    required this.winLine,
    required this.winT,
    required this.gameOver,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = state.size;
    final rect = Offset.zero & size;
    final slab = RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.045));

    // Ground shadow — the pale slab floats just above the felt.
    canvas.drawRRect(
      slab.shift(const Offset(0, 5)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // Sun-bleached birch slab.
    canvas.drawRRect(
      slab,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(boardColor, Colors.white, 0.10)!,
            boardColor,
            Color.lerp(boardColor, Colors.black, 0.08)!,
          ],
        ).createShader(rect),
    );
    // Quiet edge bevel.
    canvas.drawRRect(
      slab.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.18),
    );

    // Grid.
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = math.max(1.0, geom.spacing * 0.04);
    for (var i = 0; i < n; i++) {
      canvas.drawLine(geom.center(i, 0), geom.center(i, n - 1), linePaint);
      canvas.drawLine(geom.center(0, i), geom.center(n - 1, i), linePaint);
    }

    // Star points (hoshi) for the classic 15×15 layout.
    if (n == 15) {
      final star = Paint()..color = lineColor.withValues(alpha: 1);
      for (final (r, c) in const [(3, 3), (3, 11), (7, 7), (11, 3), (11, 11)]) {
        canvas.drawCircle(geom.center(r, c), geom.spacing * 0.11, star);
      }
    }

    // Stones.
    final radius = geom.spacing * 0.47;
    for (var i = 0; i < state.cells.length; i++) {
      final owner = state.cells[i];
      if (owner == null) continue;
      final pop = pops[i] ?? 1.0;
      if (pop <= 0) continue;
      final isBlack = owner == state.blackId;
      final c = geom.center(i ~/ n, i % n);
      // Drop-in: start slightly large and high, settle with a light overshoot.
      final settle = Curves.easeOutBack.transform(pop.clamp(0.0, 1.0));
      final r = radius * (0.6 + 0.4 * settle);
      final lift = (1 - pop) * radius * 0.8;
      final at = c.translate(0, -lift);

      final base = isBlack ? black : white;
      final dim = gameOver && winLine.isNotEmpty && !winLine.contains(i);

      canvas.drawCircle(
        c.translate(0, r * 0.14),
        r * 0.92,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.20 * pop)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22),
      );
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.4),
            colors: [
              Color.lerp(base, Colors.white, isBlack ? 0.32 : 0.6)!,
              base,
              Color.lerp(base, Colors.black, isBlack ? 0.35 : 0.16)!,
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(Rect.fromCircle(center: at, radius: r)),
      );
      if (dim) {
        canvas.drawCircle(
          at,
          r,
          Paint()..color = boardColor.withValues(alpha: 0.38),
        );
      }

      // Last-move dot while the game is live.
      if (!gameOver && i == state.lastCell && pop > 0.9) {
        canvas.drawCircle(
          at,
          r * 0.28,
          Paint()..color = (isBlack ? white : black).withValues(alpha: 0.85),
        );
      }
    }

    // Win-line rings pop in over the five stones.
    if (winLine.isNotEmpty && winT > 0.01) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, radius * 0.22)
        ..color = const Color(0xFFF4B740).withValues(alpha: winT.clamp(0.0, 1.0));
      for (final i in winLine) {
        final c = geom.center(i ~/ n, i % n);
        canvas.drawCircle(c, radius * (0.7 + 0.42 * winT), ring);
      }
    }
  }

  @override
  bool shouldRepaint(_GomokuPainter old) =>
      old.state != state ||
      old.winT != winT ||
      old.gameOver != gameOver ||
      !_mapEquals(old.pops, pops);

  static bool _mapEquals(Map<int, double> a, Map<int, double> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Player chip
// ---------------------------------------------------------------------------

class _PlayerChip extends StatelessWidget {
  final String label;
  final Color stone;
  final Color stoneEdge;
  final bool active;
  final bool winner;

  const _PlayerChip({
    required this.label,
    required this.stone,
    required this.stoneEdge,
    required this.active,
    required this.winner,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: active || winner ? 0.34 : 0.18),
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
              border: Border.all(color: stoneEdge, width: 1),
              gradient: RadialGradient(
                center: const Alignment(-0.35, -0.4),
                colors: [
                  Color.lerp(stone, Colors.white, 0.4)!,
                  stone,
                ],
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
        ],
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
