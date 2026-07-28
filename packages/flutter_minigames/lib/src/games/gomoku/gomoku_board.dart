import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/src/core/core.dart';

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
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                offset: const Offset(0, 6),
                blurRadius: 18,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: CustomPaint(
              painter: _FeltPainter(table),
              child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                              ? const SizedBox.shrink(key: ValueKey('pill-empty'))
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
              ),
            ),
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

    // Slab, grain, edge and grid never move: one cached drawPicture.
    canvas.drawPicture(_gobanFor(size, geom, n, boardColor, lineColor));

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

      _paintStone(canvas, c, at, r, base, isBlack, pop);

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
// Materials
//
// One committed light for the whole game: a soft key from the upper left,
// slightly in front. Every highlight sits at (-0.38, -0.45) of a form, every
// cast shadow falls down and to the right, and every carved inset reverses
// both. Nothing here depends on frame state, so the board surface is recorded
// once into a Picture and replayed.
// ---------------------------------------------------------------------------

/// Light direction as a unit-ish offset (points from the surface toward the
/// key light). Used to place highlights and to offset cast shadows.
const Offset _kLight = Offset(-0.38, -0.45);

/// Deterministic hash in `[0, 1)` — the grain and nap must be identical on
/// every rebuild, so no `Random` is used anywhere in painting.
double _noise(int x, int y, int seed) {
  var n = (x * 374761393) ^ (y * 668265263) ^ (seed * 1274126177);
  n = (n ^ (n >> 13)) * 1274126177;
  n = n ^ (n >> 16);
  return (n & 0x3fffffff) / 0x3fffffff;
}

/// Draws quarter-sawn wood into [r]: a cross-grain tonal wash, broad growth
/// bands, and fine fibre streaks — all running along [vertical].
void _paintWoodGrain(
  Canvas canvas,
  Rect r,
  Color base,
  int seed, {
  bool vertical = true,
}) {
  final long = vertical ? r.height : r.width;
  final across = vertical ? r.width : r.height;

  // Broad growth bands: slow tonal drift across the grain.
  const bands = 22;
  for (var i = 0; i < bands; i++) {
    final t = i / bands;
    final j = _noise(i, seed, 11);
    final w = across * (0.02 + j * 0.05);
    final x = r.left + t * across + (j - 0.5) * across * 0.02;
    final dark = (_noise(i, seed, 23) - 0.5) * 0.085;
    final paint = Paint()
      ..color = (dark < 0
              ? Color.lerp(base, Colors.white, -dark)!
              : Color.lerp(base, const Color(0xFF4A331C), dark)!)
          .withValues(alpha: 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, across * 0.018);
    canvas.drawRect(
      vertical
          ? Rect.fromLTWH(x, r.top, w, r.height)
          : Rect.fromLTWH(r.left, r.top + t * across, r.width, w),
      paint,
    );
  }

  // Fine fibres: thin, slightly wandering lines the length of the board.
  final fibre = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final count = (across / 2.2).round().clamp(40, 220);
  for (var i = 0; i < count; i++) {
    final j = _noise(i, seed, 37);
    final k = _noise(i, seed, 53);
    final pos = r.left + (i / count) * across + (j - 0.5) * 3;
    final wobble = (k - 0.5) * across * 0.012;
    final dark = k > 0.62;
    fibre
      ..strokeWidth = 0.5 + j * 0.9
      ..color = (dark
              ? Color.lerp(base, const Color(0xFF3D2A15), 0.35)!
              : Color.lerp(base, Colors.white, 0.30)!)
          .withValues(alpha: 0.06 + j * 0.10);
    final path = Path();
    if (vertical) {
      path.moveTo(pos, r.top);
      path.quadraticBezierTo(
          pos + wobble, r.top + long * 0.5, pos + wobble * 0.3, r.bottom);
    } else {
      final y = r.top + (i / count) * across + (j - 0.5) * 3;
      path.moveTo(r.left, y);
      path.quadraticBezierTo(
          r.left + long * 0.5, y + wobble, r.right, y + wobble * 0.3);
    }
    canvas.drawPath(path, fibre);
  }
}

/// Cached goban surface, keyed on size and palette.
class _Goban {
  final double w;
  final double h;
  final int board;
  final int line;
  final int n;
  final ui.Picture picture;

  _Goban(this.w, this.h, this.board, this.line, this.n, this.picture);

  bool matches(Size s, int cells, Color b, Color l) =>
      w == s.width &&
      h == s.height &&
      n == cells &&
      // ignore: deprecated_member_use
      board == b.value &&
      // ignore: deprecated_member_use
      line == l.value;
}

final List<_Goban> _gobans = [];

ui.Picture _gobanFor(
  Size size,
  _BoardGeom geom,
  int n,
  Color board,
  Color line,
) {
  for (final g in _gobans) {
    if (g.matches(size, n, board, line)) return g.picture;
  }
  final recorder = ui.PictureRecorder();
  _paintGoban(Canvas(recorder), size, geom, n, board, line);
  final made = _Goban(
    size.width,
    size.height,
    // ignore: deprecated_member_use
    board.value,
    // ignore: deprecated_member_use
    line.value,
    n,
    recorder.endRecording(),
  );
  _gobans.insert(0, made);
  while (_gobans.length > 3) {
    _gobans.removeLast().picture.dispose();
  }
  return made.picture;
}

void _paintGoban(
  Canvas canvas,
  Size size,
  _BoardGeom geom,
  int n,
  Color board,
  Color line,
) {
  final w = size.width;
  final thickness = w * 0.030;
  final radius = Radius.circular(w * 0.030);
  final topRect = Rect.fromLTWH(0, 0, w, size.height - thickness);
  final top = RRect.fromRectAndRadius(topRect, radius);
  final sideRect = Rect.fromLTWH(0, thickness * 0.4, w, size.height - thickness * 0.4);
  final side = RRect.fromRectAndRadius(sideRect, radius);

  final edgeWood = Color.lerp(board, const Color(0xFF6B4A22), 0.42)!;

  // Feet: two blocks the slab stands on, so it reads as an object on a table.
  final footY = size.height - thickness * 0.15;
  for (final fx in [w * 0.17, w * 0.83]) {
    final foot = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(fx, footY), width: w * 0.14, height: thickness * 1.5),
      Radius.circular(thickness * 0.35),
    );
    canvas.drawRRect(
      foot.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.012),
    );
    canvas.drawRRect(
      foot,
      Paint()..color = Color.lerp(edgeWood, Colors.black, 0.35)!,
    );
  }

  // Contact shadow: tight and dark where the slab meets the felt, then a wide
  // soft ambient falloff down-right of the key light.
  canvas.drawRRect(
    side.shift(Offset(w * 0.010, w * 0.016)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.30)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.030),
  );
  canvas.drawRRect(
    side.shift(Offset(w * 0.004, w * 0.006)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.26)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.008),
  );

  // Side face — the board's thickness, in shadow under a top-left key.
  canvas.drawRRect(
    side,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          edgeWood,
          Color.lerp(edgeWood, Colors.black, 0.34)!,
        ],
      ).createShader(sideRect),
  );

  // Top face.
  canvas.save();
  canvas.clipRRect(top);
  canvas.drawRect(topRect, Paint()..color = board);
  _paintWoodGrain(canvas, topRect, board, 3);
  // Key-light wash: brighter toward the upper left, falling away bottom right.
  canvas.drawRect(
    topRect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment(_kLight.dx * 2.2, _kLight.dy * 2.0),
        end: Alignment(-_kLight.dx * 2.2, -_kLight.dy * 2.0),
        colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.0),
          Colors.black.withValues(alpha: 0.10),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(topRect),
  );
  canvas.restore();

  // Chamfer: lit on the top-left lip, dark on the bottom-right lip.
  canvas.drawRRect(
    top.deflate(w * 0.004),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.008
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.34),
          Colors.white.withValues(alpha: 0.04),
          Colors.black.withValues(alpha: 0.16),
        ],
      ).createShader(topRect),
  );

  // Grid: ink lines sit *in* the wood, so each gets a hairline of light on the
  // side away from the key — the trace of a scored, filled line.
  final lw = math.max(0.9, geom.spacing * 0.035);
  final ink = Paint()
    ..color = line
    ..strokeWidth = lw
    ..strokeCap = StrokeCap.square;
  final glint = Paint()
    ..color = Colors.white.withValues(alpha: 0.13)
    ..strokeWidth = lw * 0.6
    ..strokeCap = StrokeCap.square;
  for (var i = 0; i < n; i++) {
    final hA = geom.center(i, 0);
    final hB = geom.center(i, n - 1);
    final vA = geom.center(0, i);
    final vB = geom.center(n - 1, i);
    canvas.drawLine(hA.translate(0, lw * 0.8), hB.translate(0, lw * 0.8), glint);
    canvas.drawLine(vA.translate(lw * 0.8, 0), vB.translate(lw * 0.8, 0), glint);
    canvas.drawLine(hA, hB, ink);
    canvas.drawLine(vA, vB, ink);
  }
  // Border line of a goban is heavier than the interior grid.
  canvas.drawRect(
    Rect.fromPoints(geom.center(0, 0), geom.center(n - 1, n - 1)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lw * 1.7
      ..color = line,
  );

  // Star points (hoshi) for the classic 15×15 layout.
  if (n == 15) {
    for (final (r, c) in const [(3, 3), (3, 11), (7, 7), (11, 3), (11, 11)]) {
      final at = geom.center(r, c);
      final sr = geom.spacing * 0.115;
      canvas.drawCircle(
        at.translate(lw * 0.7, lw * 0.7),
        sr,
        Paint()..color = Colors.white.withValues(alpha: 0.20),
      );
      canvas.drawCircle(at, sr, Paint()..color = line);
    }
  }
}

/// Slate (black) and clamshell (white) stones: a domed body under the key
/// light, a soft rim bounce opposite it, and a two-part contact shadow so the
/// stone reads as resting on the wood rather than pasted onto it.
void _paintStone(
  Canvas canvas,
  Offset seat,
  Offset at,
  double r,
  Color base,
  bool isBlack,
  double pop,
) {
  final rect = Rect.fromCircle(center: at, radius: r);

  // Contact shadow: a tight dark core right under the stone plus a wider,
  // softer ambient blur, both pushed away from the key light.
  final drop = Offset(-_kLight.dx * r * 0.30, -_kLight.dy * r * 0.34);
  canvas.drawOval(
    Rect.fromCenter(
      center: seat + drop * 1.5,
      width: r * 2.0,
      height: r * 1.55,
    ),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.20 * pop)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.34),
  );
  canvas.drawOval(
    Rect.fromCenter(
      center: seat + drop * 0.55,
      width: r * 1.82,
      height: r * 1.5,
    ),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.26 * pop)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.10),
  );

  // Body.
  canvas.drawCircle(
    at,
    r,
    Paint()
      ..shader = RadialGradient(
        center: Alignment(_kLight.dx * 1.5, _kLight.dy * 1.5),
        radius: 1.05,
        colors: isBlack
            ? [
                Color.lerp(base, Colors.white, 0.30)!,
                Color.lerp(base, Colors.white, 0.06)!,
                base,
                Color.lerp(base, Colors.black, 0.55)!,
              ]
            : [
                Colors.white,
                Color.lerp(base, Colors.white, 0.55)!,
                base,
                Color.lerp(base, const Color(0xFF8A7A5E), 0.34)!,
              ],
        stops: const [0.0, 0.30, 0.66, 1.0],
      ).createShader(rect),
  );

  if (!isBlack) {
    // Clamshell: faint concentric growth arcs, off-centre like the real thing.
    final shell = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF9A8763).withValues(alpha: 0.085)
      ..strokeWidth = math.max(0.4, r * 0.035);
    for (var i = 1; i <= 2; i++) {
      canvas.drawArc(
        Rect.fromCircle(
          center: at.translate(r * 0.16, r * 0.10),
          radius: r * (0.30 + i * 0.20),
        ),
        math.pi * 0.55,
        math.pi * 1.25,
        false,
        shell,
      );
    }
  }

  // Rim bounce: a crescent of light on the shaded side, from the table.
  canvas.drawArc(
    rect.deflate(r * 0.05),
    math.pi * 0.10,
    math.pi * 0.80,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.10
      ..color =
          Colors.white.withValues(alpha: isBlack ? 0.14 : 0.16),
  );

  // Specular: a soft bloom with a small hot core, both on the key side.
  final specAt = at + Offset(_kLight.dx * r * 0.95, _kLight.dy * r * 0.95);
  canvas.save();
  canvas.clipPath(Path()..addOval(rect));
  canvas.drawOval(
    Rect.fromCenter(
      center: specAt,
      width: r * (isBlack ? 0.78 : 1.02),
      height: r * (isBlack ? 0.52 : 0.72),
    ),
    Paint()
      ..color = Colors.white.withValues(alpha: isBlack ? 0.30 : 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.20),
  );
  canvas.drawOval(
    Rect.fromCenter(
      center: specAt,
      width: r * 0.34,
      height: r * 0.20,
    ),
    Paint()
      ..color = Colors.white.withValues(alpha: isBlack ? 0.70 : 0.85)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.06),
  );
  canvas.restore();

  // Edge seat: darkens the very rim so the silhouette doesn't fray.
  canvas.drawCircle(
    at,
    r - r * 0.02,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.05
      ..color = Colors.black.withValues(alpha: isBlack ? 0.30 : 0.14),
  );
}

// ---------------------------------------------------------------------------
// Felt table
// ---------------------------------------------------------------------------

class _FeltCache {
  final double w;
  final double h;
  final int felt;
  final ui.Picture picture;

  _FeltCache(this.w, this.h, this.felt, this.picture);

  bool matches(Size s, Color f) =>
      w == s.width &&
      h == s.height &&
      // ignore: deprecated_member_use
      felt == f.value;
}

final List<_FeltCache> _felts = [];

/// Napped felt: a lit wash from the key, a dense deterministic speckle for the
/// fibre, and a vignette that seats the panel in the surrounding dark.
class _FeltPainter extends CustomPainter {
  final Color felt;

  const _FeltPainter(this.felt);

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in _felts) {
      if (f.matches(size, felt)) {
        canvas.drawPicture(f.picture);
        return;
      }
    }
    final recorder = ui.PictureRecorder();
    _record(Canvas(recorder), size);
    final made = _FeltCache(
      size.width,
      size.height,
      // ignore: deprecated_member_use
      felt.value,
      recorder.endRecording(),
    );
    _felts.insert(0, made);
    while (_felts.length > 3) {
      _felts.removeLast().picture.dispose();
    }
    canvas.drawPicture(made.picture);
  }

  void _record(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(_kLight.dx, _kLight.dy),
          radius: 1.35,
          colors: [
            Color.lerp(felt, Colors.white, 0.10)!,
            felt,
            Color.lerp(felt, Colors.black, 0.34)!,
          ],
          stops: const [0.0, 0.42, 1.0],
        ).createShader(rect),
    );

    // Nap: short fibres all leaning the same way, so the felt has a direction.
    final nap = Paint()
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    final cols = (size.width / 5).ceil();
    final rows = (size.height / 5).ceil();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final j = _noise(x, y, 7);
        if (j < 0.45) continue;
        final k = _noise(x, y, 19);
        final px = x * 5.0 + k * 5;
        final py = y * 5.0 + j * 5;
        nap.color = (j > 0.78 ? Colors.white : Colors.black)
            .withValues(alpha: 0.012 + k * 0.016);
        canvas.drawLine(
            Offset(px, py), Offset(px + 1.6 + k, py + 0.8), nap);
      }
    }
  }

  @override
  bool shouldRepaint(_FeltPainter old) => old.felt != felt;
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
