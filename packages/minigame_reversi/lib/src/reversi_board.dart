import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Picture, PictureRecorder;

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
        // 8×8 reads huge at the shared 400 cap used by sparser boards —
        // keep classic rules, just give the green tray less screen real estate.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 312),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth;
        // A rail of stock around a recessed baize field — the frame is part of
        // the board's width, so the cells start at [rail].
        final rail = side * 0.045;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(side * 0.05),
            boxShadow: [
              // Light is upper-left everywhere on this board, so the board's
              // own shadow falls down and slightly right.
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: side * 0.055,
                offset: Offset(side * 0.008, side * 0.030),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _TablePainter(
                    boardColor: boardColor,
                    gridColor: gridColor,
                    rail: rail,
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(rail),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: ReversiState.size,
                    ),
                    itemCount: ReversiState.cellCount,
                    itemBuilder: (context, i) {
                      final owner = state.cells[i];
                      final isLegal = legal.contains(i);
                      final flipT =
                          flipCtrls[i]?.value ?? (owner == null ? 0.0 : 1.0);
                      // Squash to nothing at the half-way point, then grow the
                      // new face back — the disc is turning over on its edge.
                      final squash =
                          flipT < 0.5 ? (1 - flipT * 2) : ((flipT - 0.5) * 2);
                      final discColor = owner == null
                          ? null
                          : (owner == state.darkId ? dark : light);

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: (!gameOver && (isLegal || owner == null))
                            ? () {
                                if (isLegal) onTap(i);
                              }
                            : null,
                        child: owner != null
                            ? CustomPaint(
                                painter: _DiscPainter(
                                  color: discColor!,
                                  other: owner == state.darkId ? light : dark,
                                  squash: squash.clamp(0.0, 1.0),
                                ),
                              )
                            : (isLegal && !gameOver
                                ? Center(
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: hintColor,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.30),
                                            blurRadius: 2,
                                            offset: const Offset(0.5, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : null),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Rail, baize and engraved grid — everything on the table that never moves.
/// Recorded once into a [ui.Picture]; the nap texture alone is a few thousand
/// draw calls and this widget repaints on every flip.
class _TablePainter extends CustomPainter {
  final Color boardColor;
  final Color gridColor;
  final double rail;

  _TablePainter({
    required this.boardColor,
    required this.gridColor,
    required this.rail,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPicture(_tableFor(size, boardColor, gridColor, rail));
  }

  @override
  bool shouldRepaint(_TablePainter old) =>
      old.boardColor != boardColor ||
      old.gridColor != gridColor ||
      old.rail != rail;
}

/// Deterministic 0..1 value hash — procedural nap and grain with no assets,
/// stable across rebuilds so the cached picture never shimmers.
double _hash2(int x, int y) {
  var h = x * 374761393 + y * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0;
}

void _paintTable(
  Canvas canvas,
  Size size,
  Color boardColor,
  Color gridColor,
  double rail,
) {
  final side = size.width;
  final outer =
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(side * 0.05));
  canvas.save();
  canvas.clipRRect(outer);

  // Rail: dark stock, four lengths mitred at the corners. Grain runs *along*
  // each length — drawing it in both directions everywhere would give the
  // frame a plaid weave instead of wood.
  const railBase = Color(0xFF4A3421);
  canvas.drawRect(Offset.zero & size, Paint()..color = railBase);
  final grainPaint = Paint()..strokeWidth = math.max(0.7, side * 0.0045);
  void grain(Rect r, {required bool horizontal, int seed = 0}) {
    canvas.save();
    canvas.clipRect(r);
    final span = horizontal ? r.height : r.width;
    final lines = (span / math.max(1.6, side * 0.006)).round().clamp(4, 40);
    for (var i = 0; i < lines; i++) {
      final h = _hash2(seed, i);
      grainPaint.color = (h < 0.5 ? Colors.black : Colors.white)
          .withValues(alpha: 0.04 + 0.10 * (h - 0.5).abs() * 2);
      final t = (i + 0.5) / lines;
      if (horizontal) {
        final y = r.top + t * r.height;
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grainPaint);
      } else {
        final x = r.left + t * r.width;
        canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), grainPaint);
      }
    }
    canvas.restore();
  }

  grain(Rect.fromLTWH(0, 0, side, rail), horizontal: true, seed: 1);
  grain(Rect.fromLTWH(0, size.height - rail, side, rail),
      horizontal: true, seed: 2);
  grain(Rect.fromLTWH(0, 0, rail, size.height), horizontal: false, seed: 3);
  grain(Rect.fromLTWH(side - rail, 0, rail, size.height),
      horizontal: false, seed: 4);
  // Mitres.
  final mitre = Paint()
    ..strokeWidth = side * 0.003
    ..color = Colors.black.withValues(alpha: 0.35);
  canvas.drawLine(Offset.zero, Offset(rail, rail), mitre);
  canvas.drawLine(Offset(side, 0), Offset(side - rail, rail), mitre);
  canvas.drawLine(
      Offset(0, size.height), Offset(rail, size.height - rail), mitre);
  canvas.drawLine(Offset(side, size.height),
      Offset(side - rail, size.height - rail), mitre);

  // Baize.
  final field = Rect.fromLTWH(
    rail,
    rail,
    side - rail * 2,
    size.height - rail * 2,
  );
  canvas.drawRect(
    field,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(boardColor, Colors.white, 0.10)!,
          boardColor,
          Color.lerp(boardColor, Colors.black, 0.16)!,
        ],
      ).createShader(field),
  );

  // Nap: a dense, very low-contrast fleck so the cloth isn't a flat fill.
  canvas.save();
  canvas.clipRect(field);
  final fleck = Paint();
  final n = (side / 3.4).round().clamp(40, 130);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      final h = _hash2(i, j);
      if (h < 0.48) continue;
      fleck.color = (h > 0.74 ? Colors.white : Colors.black)
          .withValues(alpha: 0.028 + 0.052 * (h - 0.48) / 0.52);
      canvas.drawCircle(
        Offset(
          field.left + (i + _hash2(i, j + 23)) / n * field.width,
          field.top + (j + _hash2(i + 61, j)) / n * field.height,
        ),
        side * (0.0014 + 0.0014 * _hash2(j, i)),
        fleck,
      );
    }
  }

  // Engraved grid: a scored line with a lit lip below and right of it.
  final cell = field.width / ReversiState.size;
  final score = Paint()
    ..strokeWidth = math.max(1.0, cell * 0.045)
    ..color = Color.alphaBlend(gridColor, Colors.transparent)
        .withValues(alpha: math.max(gridColor.a, 0.34));
  final lip = Paint()
    ..strokeWidth = math.max(0.6, cell * 0.026)
    ..color = Colors.white.withValues(alpha: 0.10);
  for (var i = 1; i < ReversiState.size; i++) {
    final x = field.left + i * cell;
    final y = field.top + i * cell;
    canvas.drawLine(Offset(x, field.top), Offset(x, field.bottom), score);
    canvas.drawLine(Offset(x + score.strokeWidth, field.top),
        Offset(x + score.strokeWidth, field.bottom), lip);
    canvas.drawLine(Offset(field.left, y), Offset(field.right, y), score);
    canvas.drawLine(Offset(field.left, y + score.strokeWidth),
        Offset(field.right, y + score.strokeWidth), lip);
  }

  // Star points at the 2/6 intersections — the guide dots every real othello
  // board has, and a free legibility win for judging distance to a corner.
  for (final (r, c) in const [(2, 2), (2, 6), (6, 2), (6, 6)]) {
    final p = Offset(field.left + c * cell, field.top + r * cell);
    canvas.drawCircle(
      p.translate(cell * 0.02, cell * 0.03),
      cell * 0.085,
      Paint()..color = Colors.white.withValues(alpha: 0.16),
    );
    canvas.drawCircle(
      p,
      cell * 0.085,
      Paint()..color = Colors.black.withValues(alpha: 0.34),
    );
  }

  // Field is sunk below the rail.
  canvas.drawRect(
    field,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rail * 0.55
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.black.withValues(alpha: 0.44),
          Colors.black.withValues(alpha: 0.12),
          Colors.white.withValues(alpha: 0.10),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(field),
  );
  canvas.restore();

  // One light across the whole board.
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-1, -1.3),
        end: const Alignment(0.7, 1),
        colors: [
          Colors.white.withValues(alpha: 0.11),
          Colors.white.withValues(alpha: 0.0),
          Colors.black.withValues(alpha: 0.14),
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(Offset.zero & size),
  );
  canvas.drawRRect(
    outer.deflate(side * 0.004),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.008
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.26),
          Colors.white.withValues(alpha: 0.02),
          Colors.black.withValues(alpha: 0.42),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Offset.zero & size),
  );
  canvas.restore();
}

class _TableCache {
  final double w;
  final int board;
  final int grid;
  final double rail;
  final ui.Picture picture;
  const _TableCache(this.w, this.board, this.grid, this.rail, this.picture);
}

/// Two slots: board and preview can be on screen at once at different sizes.
final List<_TableCache> _tables = [];

ui.Picture _tableFor(Size size, Color board, Color grid, double rail) {
  for (final t in _tables) {
    if (t.w == size.width &&
        t.board == board.toARGB32() &&
        t.grid == grid.toARGB32() &&
        t.rail == rail) {
      return t.picture;
    }
  }
  final recorder = ui.PictureRecorder();
  _paintTable(Canvas(recorder), size, board, grid, rail);
  final made = _TableCache(size.width, board.toARGB32(), grid.toARGB32(), rail,
      recorder.endRecording());
  _tables.insert(0, made);
  while (_tables.length > 2) {
    _tables.removeLast().picture.dispose();
  }
  return made.picture;
}

/// A two-sided othello disc, seen edge-on as it turns.
///
/// [squash] is 1 face-on and 0 exactly on edge. Because the disc has real
/// thickness, at low squash you see the milled rim band rather than the face —
/// which is what sells the flip. The rim is a blend of both players' colours,
/// as it is on a moulded two-tone counter.
class _DiscPainter extends CustomPainter {
  final Color color;
  final Color other;
  final double squash;

  const _DiscPainter({
    required this.color,
    required this.other,
    required this.squash,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide * 0.40;
    final thickness = r * 0.22;
    // The rim hangs below the face, so lift the face by half the thickness to
    // keep the whole piece optically centred in its square.
    final c = Offset(size.width / 2, size.height / 2 - thickness * 0.5);
    final ry = r * squash;

    // Contact shadow on the cloth, tight and down-right.
    canvas.drawOval(
      Rect.fromCenter(
        center: c.translate(r * 0.10, r * 0.20 + thickness * 0.5),
        width: r * 2.0,
        height: math.max(r * 0.30, ry * 1.7),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.32)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.14),
    );

    // Rim band: the disc's edge, always visible under the face and dominant
    // when the disc is on edge.
    final rimColor = Color.lerp(color, other, 0.5)!;
    final rim = Path()
      ..addOval(Rect.fromCenter(
          center: c, width: r * 2, height: math.max(ry * 2, r * 0.06)))
      ..addOval(Rect.fromCenter(
          center: c.translate(0, thickness),
          width: r * 2,
          height: math.max(ry * 2, r * 0.06)))
      ..addRect(Rect.fromLTWH(c.dx - r, c.dy, r * 2, thickness));
    canvas.drawPath(
      rim,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(rimColor, Colors.white, 0.24)!,
            Color.lerp(rimColor, Colors.black, 0.42)!,
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Face.
    final face = Rect.fromCenter(center: c, width: r * 2, height: ry * 2);
    if (ry > 0.4) {
      canvas.drawOval(
        face,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.38, -0.45),
            radius: 1.05,
            colors: [
              Color.lerp(color, Colors.white, 0.34)!,
              color,
              Color.lerp(color, Colors.black, 0.24)!,
            ],
            stops: const [0.0, 0.52, 1.0],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      // Chamfer where the face rolls into the rim.
      canvas.drawOval(
        Rect.fromCenter(
            center: c, width: r * 1.94, height: math.max(ry * 1.94, 1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.07
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.32),
              Colors.white.withValues(alpha: 0.02),
              Colors.black.withValues(alpha: 0.30),
            ],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      // Specular, squashed with the face so it turns with the disc.
      canvas.save();
      canvas.clipPath(Path()..addOval(face));
      canvas.drawOval(
        Rect.fromCenter(
          center: c.translate(-r * 0.34, -ry * 0.42),
          width: r * 0.76,
          height: ry * 0.52,
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.30)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.13),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_DiscPainter old) =>
      old.color != color || old.other != other || old.squash != squash;
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
