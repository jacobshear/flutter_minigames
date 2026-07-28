import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Picture, PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/src/core/core.dart';

import 'checkers_game.dart';
import 'checkers_style.dart';

/// Animated checkers board wired to a [MatchController].
///
/// Tap a piece to select, then a highlighted square to move. Legal targets
/// light up; captures animate the victim out; kings get a crown flash.
class CheckersBoard extends StatefulWidget {
  final MatchController<CheckersState, CheckersMove> controller;
  final CheckersStyle style;

  const CheckersBoard({
    super.key,
    required this.controller,
    this.style = const CheckersStyle(),
  });

  @override
  State<CheckersBoard> createState() => _CheckersBoardState();
}

class _CheckersBoardState extends State<CheckersBoard>
    with TickerProviderStateMixin {
  static const _game = CheckersGame();

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final AnimationController _moveCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final AnimationController _confettiCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  final math.Random _rnd = math.Random();
  StreamSubscription<CheckersState>? _sub;

  CheckersState? _state;
  GameOutcome? _outcome;
  int? _selected;
  int? _animFrom;
  int? _animTo;
  int? _animCaptured;
  bool _animKing = false;
  List<_Confetto> _confetti = const [];

  @override
  void initState() {
    super.initState();
    _state = widget.controller.state;
    _outcome = _state == null ? null : _game.outcome(_state!);
    _entrance.forward();
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _entrance.dispose();
    _moveCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  void _onState(CheckersState state) {
    final style = widget.style;
    final outcome = _game.outcome(state);
    final prev = _state;

    if (prev != null &&
        state.lastFrom != null &&
        state.lastTo != null &&
        (state.lastFrom != prev.lastFrom || state.lastTo != prev.lastTo)) {
      _animFrom = state.lastFrom;
      _animTo = state.lastTo;
      _animCaptured = state.lastCaptured;
      _animKing = state.lastBecameKing;
      _moveCtrl.forward(from: 0);

      if (state.lastCaptured != null) {
        style.sounds.onCapture?.call();
        if (style.haptics) HapticFeedback.mediumImpact();
      } else {
        style.sounds.onMove?.call();
        if (style.haptics) HapticFeedback.lightImpact();
      }
      if (state.lastBecameKing) {
        style.sounds.onKing?.call();
        if (style.haptics) HapticFeedback.selectionClick();
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

    // New game reset
    final filled = state.cells.where((c) => c != null).length;
    final prevFilled = prev?.cells.where((c) => c != null).length ?? 0;
    if (filled > prevFilled + 4) {
      _confettiCtrl.value = 0;
      _confetti = const [];
      _selected = null;
    }

    setState(() {
      _state = state;
      _outcome = outcome;
      // Auto-select multi-jump piece.
      if (state.mustContinueFrom != null) {
        _selected = state.mustContinueFrom;
      } else if (_selected != null &&
          (state.cells[_selected!] != state.currentPlayerId ||
              outcome != null)) {
        _selected = null;
      }
    });
  }

  List<_Confetto> _spawnConfetti(CheckersState state, GameOutcome outcome) {
    final scheme = Theme.of(context).colorScheme;
    final winColor = outcome.winnerId == state.darkId
        ? widget.style.resolveDarkPiece(scheme)
        : widget.style.resolveLightPiece(scheme);
    final palette = [
      winColor,
      widget.style.resolveDarkPiece(scheme),
      widget.style.resolveLightPiece(scheme),
      const Color(0xFFF4B740),
    ];
    return List.generate(32, (i) {
      final angle = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 2.6;
      return _Confetto(
        angle: angle,
        speed: 0.4 + _rnd.nextDouble(),
        size: 0.012 + _rnd.nextDouble() * 0.018,
        color: palette[i % palette.length],
        spin: (_rnd.nextDouble() - 0.5) * 10,
        phase: _rnd.nextDouble() * math.pi,
      );
    });
  }

  void _onTapCell(int cell) {
    final state = _state;
    if (state == null || _outcome != null) return;
    final style = widget.style;
    final player = state.currentPlayerId;
    final legal = _game.legalMoves(state, player);

    // Mid multi-jump: only destinations from locked piece.
    if (state.mustContinueFrom != null) {
      final hit = legal.where((m) => m.to == cell).toList();
      if (hit.isEmpty) return;
      widget.controller.submitMove(hit.first);
      return;
    }

    if (state.cells[cell] == player) {
      // Toggle select (only if piece has any legal move).
      final can = legal.any((m) => m.from == cell);
      if (!can) {
        style.sounds.onSelect?.call();
        return;
      }
      setState(() => _selected = _selected == cell ? null : cell);
      style.sounds.onSelect?.call();
      if (style.haptics) HapticFeedback.selectionClick();
      return;
    }

    if (_selected != null) {
      final hit =
          legal.where((m) => m.from == _selected && m.to == cell).toList();
      if (hit.isEmpty) {
        setState(() => _selected = null);
        return;
      }
      final move = hit.first;
      setState(() => _selected = null);
      widget.controller.submitMove(move);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final state = _state;
    if (state == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final darkP = style.resolveDarkPiece(scheme);
    final lightP = style.resolveLightPiece(scheme);
    final darkSq = style.resolveDarkSquare(scheme);
    final lightSq = style.resolveLightSquare(scheme);
    final selectC = style.resolveSelect(scheme);
    final hintC = style.resolveHint(scheme);

    final legal = _outcome == null
        ? _game.legalMoves(state, state.currentPlayerId)
        : const <CheckersMove>[];
    final targets = _selected == null
        ? <int>{}
        : legal.where((m) => m.from == _selected).map((m) => m.to).toSet();
    final selectable = legal.map((m) => m.from).toSet();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusBanner(
          state: state,
          outcome: _outcome,
          dark: darkP,
          light: lightP,
        ),
        const SizedBox(height: 10),
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
                    _moveCtrl,
                    _confettiCtrl,
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
                              darkPiece: darkP,
                              lightPiece: lightP,
                              darkSquare: darkSq,
                              lightSquare: lightSq,
                              selectColor: selectC,
                              hintColor: hintC,
                              selected: _selected,
                              targets: targets,
                              selectable: selectable,
                              moveT: Curves.easeInOutCubic
                                  .transform(_moveCtrl.value),
                              animFrom: _animFrom,
                              animTo: _animTo,
                              animCaptured: _animCaptured,
                              animKing: _animKing,
                              gameOver: _outcome != null,
                              onTap: _onTapCell,
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
  final CheckersState state;
  final GameOutcome? outcome;
  final Color dark;
  final Color light;

  const _StatusBanner({
    required this.state,
    required this.outcome,
    required this.dark,
    required this.light,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        );
    final sd = state.pieceCount(state.darkId);
    final sl = state.pieceCount(state.lightId);

    Widget center;
    if (outcome == null) {
      final isDark = state.currentPlayerId == state.darkId;
      final label = state.mustContinueFrom != null ? 'jump again' : 'to play';
      center = Row(
        key: ValueKey('turn-${state.currentPlayerId}-$label'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniMan(color: isDark ? dark : light, size: 16),
          const SizedBox(width: 8),
          Text(label, style: textStyle),
        ],
      );
    } else if (outcome!.isDraw) {
      center = Text('Draw', key: const ValueKey('draw'), style: textStyle);
    } else {
      final isDark = outcome!.winnerId == state.darkId;
      center = Row(
        key: const ValueKey('win'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniMan(color: isDark ? dark : light, size: 18),
          const SizedBox(width: 8),
          Text(
            isDark ? 'Dark wins' : 'Red wins',
            style: textStyle,
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
                duration: const Duration(milliseconds: 240),
                child: center,
              ),
            ),
          ),
        ),
        _ScoreChip(
          label: 'Red',
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
    final fg = onDark ? Colors.white : Colors.white;
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
              color: fg.withValues(alpha: 0.9),
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

class _MiniMan extends StatelessWidget {
  final Color color;
  final double size;
  const _MiniMan({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    // Same material and light direction as the board pieces, just small enough
    // that the lathe grooves would only add noise.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.40, -0.45),
          radius: 1.05,
          colors: [
            Color.lerp(color, Colors.white, 0.34)!,
            color,
            Color.lerp(color, Colors.black, 0.28)!,
          ],
          stops: const [0.0, 0.52, 1.0],
        ),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.22),
          width: size * 0.055,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.26),
            blurRadius: size * 0.16,
            offset: Offset(size * 0.03, size * 0.09),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Board
// ---------------------------------------------------------------------------

class _BoardGrid extends StatelessWidget {
  final CheckersState state;
  final Color darkPiece;
  final Color lightPiece;
  final Color darkSquare;
  final Color lightSquare;
  final Color selectColor;
  final Color hintColor;
  final int? selected;
  final Set<int> targets;
  final Set<int> selectable;
  final double moveT;
  final int? animFrom;
  final int? animTo;
  final int? animCaptured;
  final bool animKing;
  final bool gameOver;
  final ValueChanged<int> onTap;

  const _BoardGrid({
    required this.state,
    required this.darkPiece,
    required this.lightPiece,
    required this.darkSquare,
    required this.lightSquare,
    required this.selectColor,
    required this.hintColor,
    required this.selected,
    required this.targets,
    required this.selectable,
    required this.moveT,
    required this.animFrom,
    required this.animTo,
    required this.animCaptured,
    required this.animKing,
    required this.gameOver,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth;
        // The board is a real object: a mitred wooden frame around an inlaid
        // playfield. The frame eats into the widget rather than sitting outside
        // it, so the squares (and therefore every piece position) start at
        // [frame], not at zero.
        final frame = side * 0.042;
        final cell = (side - frame * 2) / CheckersState.size;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(side * 0.045),
            boxShadow: [
              // Contact shadow, offset down-right to agree with a light that
              // comes from the upper left everywhere else on this board.
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: side * 0.05,
                offset: Offset(side * 0.008, side * 0.028),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Frame + inlaid squares + engraved seams, all static.
              Positioned.fill(
                child: CustomPaint(
                  painter: _WoodBoardPainter(
                    darkSquare: darkSquare,
                    lightSquare: lightSquare,
                    frame: frame,
                  ),
                ),
              ),
              // State-dependent square marks.
              for (var i = 0; i < CheckersState.cellCount; i++)
                if (selected == i ||
                    targets.contains(i) ||
                    (selectable.contains(i) && selected == null))
                  _squareMark(i, cell, frame),
              // Captured fade
              if (animCaptured != null && moveT < 1)
                _capturedGhost(animCaptured!, cell, frame, moveT),
              // Static pieces (skip destination while the mover is in flight).
              for (var i = 0; i < CheckersState.cellCount; i++)
                if (state.cells[i] != null && !(moveT < 1 && i == animTo))
                  _pieceAt(i, cell, frame, scale: 1),
              // Moving piece
              if (animFrom != null &&
                  animTo != null &&
                  moveT < 1 &&
                  state.cells[animTo!] != null)
                _movingPiece(cell, frame),
              // Hit targets
              for (var i = 0; i < CheckersState.cellCount; i++)
                Positioned(
                  left: frame + (i % CheckersState.size) * cell,
                  top: frame + (i ~/ CheckersState.size) * cell,
                  width: cell,
                  height: cell,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: gameOver ? null : () => onTap(i),
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _squareMark(int i, double cell, double frame) {
    final (r, c) = CheckersState.rc(i);
    final isSel = selected == i;
    final isTarget = targets.contains(i);

    return Positioned(
      left: frame + c * cell,
      top: frame + r * cell,
      width: cell,
      height: cell,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: isSel
                ? Border.all(color: selectColor, width: cell * 0.075)
                : null,
            color: isSel ? selectColor.withValues(alpha: 0.14) : null,
          ),
          child: isTarget
              ? Center(
                  child: Container(
                    width: cell * 0.28,
                    height: cell * 0.28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hintColor,
                      border: Border.all(
                        color: selectColor.withValues(alpha: 0.7),
                        width: 1.5,
                      ),
                    ),
                  ),
                )
              : (isSel
                  ? null
                  : Center(
                      child: Container(
                        width: cell * 0.12,
                        height: cell * 0.12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selectColor.withValues(alpha: 0.35),
                        ),
                      ),
                    )),
        ),
      ),
    );
  }

  Widget _pieceAt(int i, double cell, double frame, {required double scale}) {
    final (r, c) = CheckersState.rc(i);
    final owner = state.cells[i]!;
    final color = owner == state.darkId ? darkPiece : lightPiece;
    final king = state.isKing[i];
    return Positioned(
      left: frame + c * cell,
      top: frame + r * cell,
      width: cell,
      height: cell,
      child: IgnorePointer(
        child: Center(
          child: Transform.scale(
            scale: scale * (selected == i ? 1.06 : 1.0),
            child: _Man(color: color, size: cell * 0.80, isKing: king),
          ),
        ),
      ),
    );
  }

  Widget _movingPiece(double cell, double frame) {
    final (fr, fc) = CheckersState.rc(animFrom!);
    final (tr, tc) = CheckersState.rc(animTo!);
    final x = frame + (fc + (tc - fc) * moveT) * cell;
    final y = frame + (fr + (tr - fr) * moveT) * cell;
    // Arc lift on jumps.
    final isJump = (tr - fr).abs() == 2;
    final lift = isJump ? math.sin(moveT * math.pi) * cell * 0.35 : 0.0;
    final owner = state.cells[animTo!]!;
    final color = owner == state.darkId ? darkPiece : lightPiece;
    final king = state.isKing[animTo!] && !animKing
        ? true
        : (state.isKing[animTo!] && moveT > 0.85);
    final showKing = state.isKing[animTo!] || (animKing && moveT > 0.7);
    return Positioned(
      left: x,
      top: y - lift,
      width: cell,
      height: cell,
      child: IgnorePointer(
        child: Center(
          child: Transform.scale(
            scale: 1.0 + (isJump ? 0.08 * math.sin(moveT * math.pi) : 0),
            child: _Man(
              color: color,
              size: cell * 0.80,
              isKing: showKing || king,
              // Lifted off the board mid-jump, so the shadow drops away.
              lift: lift / cell,
            ),
          ),
        ),
      ),
    );
  }

  Widget _capturedGhost(int i, double cell, double frame, double t) {
    final (r, c) = CheckersState.rc(i);
    // Fade + shrink the captured piece (color from opponent of mover).
    final mover = state.cells[animTo!];
    if (mover == null) return const SizedBox.shrink();
    final victimColor = mover == state.darkId ? lightPiece : darkPiece;
    final p = Curves.easeIn.transform(t);
    return Positioned(
      left: frame + c * cell,
      top: frame + r * cell,
      width: cell,
      height: cell,
      child: IgnorePointer(
        child: Opacity(
          opacity: (1 - p).clamp(0.0, 1.0),
          child: Center(
            child: Transform.scale(
              scale: 1 - 0.5 * p,
              child: _Man(
                color: victimColor,
                size: cell * 0.80,
                isKing: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wooden board
// ---------------------------------------------------------------------------

/// Frame, inlaid squares and engraved seams. Entirely static, so it is recorded
/// once into a [ui.Picture] keyed by size and palette — the per-frame cost of
/// 64 grain-textured squares would otherwise land on every move animation.
class _WoodBoardPainter extends CustomPainter {
  final Color darkSquare;
  final Color lightSquare;
  final double frame;

  _WoodBoardPainter({
    required this.darkSquare,
    required this.lightSquare,
    required this.frame,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPicture(_boardFor(size, darkSquare, lightSquare, frame));
  }

  @override
  bool shouldRepaint(_WoodBoardPainter old) =>
      old.darkSquare != darkSquare ||
      old.lightSquare != lightSquare ||
      old.frame != frame;
}

/// Deterministic 0..1 value hash — procedural grain with no assets, stable
/// across rebuilds so the cached picture never shimmers.
double _hash2(int x, int y) {
  var h = x * 374761393 + y * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0;
}

/// Wood grain: long, low-contrast bands running along [horizontal], with the
/// band spacing jittered by the deterministic hash so no two squares repeat.
void _paintGrain(
  Canvas canvas,
  Rect rect,
  Color base,
  int seed, {
  required bool horizontal,
  double strength = 1.0,
}) {
  final span = horizontal ? rect.height : rect.width;
  // Wide, soft bands. Tight high-contrast lines turn wood into corduroy — the
  // grain has to be felt more than seen at phone size.
  final lines = (span / 3.4).round().clamp(4, 30);
  final paint = Paint()..strokeWidth = span / lines * 1.05;
  for (var i = 0; i < lines; i++) {
    final h = _hash2(seed, i);
    final tone = (h - 0.5) * 0.075 * strength;
    paint.color =
        (tone < 0 ? Colors.black : Colors.white).withValues(alpha: tone.abs());
    final t = (i + 0.5) / lines;
    if (horizontal) {
      final y = rect.top + t * rect.height;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    } else {
      final x = rect.left + t * rect.width;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
    }
  }
  // A couple of darker figure lines per square — grain isn't uniform.
  final figure = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = span * 0.012
    ..color = Colors.black.withValues(alpha: 0.055 * strength);
  for (var k = 0; k < 2; k++) {
    final t = 0.2 + 0.6 * _hash2(seed + 700, k);
    final path = Path();
    const steps = 6;
    for (var s = 0; s <= steps; s++) {
      final u = s / steps;
      final wobble = (_hash2(seed + k * 31, s) - 0.5) * 0.06;
      final p = horizontal
          ? Offset(
              rect.left + u * rect.width, rect.top + (t + wobble) * rect.height)
          : Offset(rect.left + (t + wobble) * rect.width,
              rect.top + u * rect.height);
      s == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, figure);
  }
}

void _paintWoodBoard(
  Canvas canvas,
  Size size,
  Color darkSquare,
  Color lightSquare,
  double frame,
) {
  final side = size.width;
  final radius = Radius.circular(side * 0.045);
  final outer = RRect.fromRectAndRadius(Offset.zero & size, radius);
  canvas.save();
  canvas.clipRRect(outer);

  // Frame: a darker, warmer stock than the dark squares, grain running around
  // the border rather than across it (mitred stock, like a real board).
  final frameBase = Color.lerp(darkSquare, Colors.black, 0.34)!;
  canvas.drawRect(Offset.zero & size, Paint()..color = frameBase);
  _paintGrain(canvas, Rect.fromLTWH(0, 0, side, frame * 1.4), frameBase, 11,
      horizontal: true);
  _paintGrain(
      canvas,
      Rect.fromLTWH(0, size.height - frame * 1.4, side, frame * 1.4),
      frameBase,
      12,
      horizontal: true);
  _paintGrain(
      canvas, Rect.fromLTWH(0, 0, frame * 1.4, size.height), frameBase, 13,
      horizontal: false);
  _paintGrain(
      canvas,
      Rect.fromLTWH(size.width - frame * 1.4, 0, frame * 1.4, size.height),
      frameBase,
      14,
      horizontal: false);

  // Mitre lines from each corner — the giveaway that this is four pieces of
  // stock, not a printed border.
  final mitre = Paint()
    ..strokeWidth = side * 0.003
    ..color = Colors.black.withValues(alpha: 0.30);
  canvas.drawLine(Offset.zero, Offset(frame, frame), mitre);
  canvas.drawLine(Offset(side, 0), Offset(side - frame, frame), mitre);
  canvas.drawLine(
      Offset(0, size.height), Offset(frame, size.height - frame), mitre);
  canvas.drawLine(Offset(side, size.height),
      Offset(side - frame, size.height - frame), mitre);

  // Playfield, recessed into the frame.
  final field = Rect.fromLTWH(
    frame,
    frame,
    side - frame * 2,
    size.height - frame * 2,
  );
  final cell = field.width / CheckersState.size;
  for (var r = 0; r < CheckersState.size; r++) {
    for (var c = 0; c < CheckersState.size; c++) {
      final dark = CheckersState.isDarkSquare(r, c);
      final rect = Rect.fromLTWH(
        field.left + c * cell,
        field.top + r * cell,
        cell,
        cell,
      );
      // Each square is a separate piece of stock, so its base tone drifts a
      // little — identical fills are the tell that this is a printed board.
      final drift = (_hash2(r + 40, c + 40) - 0.5) * 0.06;
      canvas.drawRect(
        rect,
        Paint()
          ..color = Color.lerp(
            dark ? darkSquare : lightSquare,
            drift < 0 ? Colors.black : Colors.white,
            drift.abs(),
          )!,
      );
      // Alternating grain direction — inlaid squares are cut from a board and
      // laid quarter-turned, which is most of why a real board reads as wood.
      _paintGrain(
        canvas,
        rect,
        dark ? darkSquare : lightSquare,
        r * 8 + c,
        horizontal: (r + c).isEven,
        strength: dark ? 1.15 : 0.85,
      );
    }
  }

  // Engraved seams between squares: a hairline shadow with a lit lip below it.
  final seam = Paint()
    ..strokeWidth = math.max(0.6, cell * 0.012)
    ..color = Colors.black.withValues(alpha: 0.22);
  final seamLip = Paint()
    ..strokeWidth = math.max(0.5, cell * 0.010)
    ..color = Colors.white.withValues(alpha: 0.16);
  for (var i = 1; i < CheckersState.size; i++) {
    final x = field.left + i * cell;
    final y = field.top + i * cell;
    canvas.drawLine(Offset(x, field.top), Offset(x, field.bottom), seam);
    canvas.drawLine(Offset(x + seam.strokeWidth, field.top),
        Offset(x + seam.strokeWidth, field.bottom), seamLip);
    canvas.drawLine(Offset(field.left, y), Offset(field.right, y), seam);
    canvas.drawLine(Offset(field.left, y + seam.strokeWidth),
        Offset(field.right, y + seam.strokeWidth), seamLip);
  }

  // Playfield sits below the frame: shadow on the upper-left inner wall, lit
  // lip on the lower-right — the frame's inside edge catching the light.
  canvas.drawRect(
    field,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = frame * 0.5
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.black.withValues(alpha: 0.42),
          Colors.black.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.16),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(field),
  );

  // Global sheen and vignette so the whole board shares one light.
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-1, -1.3),
        end: const Alignment(0.7, 1),
        colors: [
          Colors.white.withValues(alpha: 0.13),
          Colors.white.withValues(alpha: 0.0),
          Colors.black.withValues(alpha: 0.13),
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(Offset.zero & size),
  );

  // Outer edge bevel.
  canvas.drawRRect(
    outer.deflate(side * 0.004),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.008
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.30),
          Colors.white.withValues(alpha: 0.02),
          Colors.black.withValues(alpha: 0.40),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Offset.zero & size),
  );
  canvas.restore();
}

class _BoardCache {
  final double w;
  final int dark;
  final int light;
  final double frame;
  final ui.Picture picture;
  const _BoardCache(this.w, this.dark, this.light, this.frame, this.picture);
}

/// Two slots: the live board and a preview can be on screen at different sizes.
final List<_BoardCache> _boards = [];

ui.Picture _boardFor(Size size, Color dark, Color light, double frame) {
  for (final b in _boards) {
    if (b.w == size.width &&
        b.dark == dark.toARGB32() &&
        b.light == light.toARGB32() &&
        b.frame == frame) {
      return b.picture;
    }
  }
  final recorder = ui.PictureRecorder();
  _paintWoodBoard(Canvas(recorder), size, dark, light, frame);
  final made = _BoardCache(size.width, dark.toARGB32(), light.toARGB32(), frame,
      recorder.endRecording());
  _boards.insert(0, made);
  while (_boards.length > 2) {
    _boards.removeLast().picture.dispose();
  }
  return made.picture;
}

/// A turned checker: a short cylinder with a milled (knurled) edge, concentric
/// lathe grooves on the top face, and a contact shadow on the board.
///
/// A king is a second man stacked on the first — the way you actually crown a
/// piece — rather than a badge printed on a single disc. That reads instantly at
/// phone size from the doubled side wall alone, before you can see any emblem.
class _Man extends StatelessWidget {
  final Color color;
  final double size;
  final bool isKing;

  /// How far the piece is lifted off the board, in cell fractions. Used to
  /// float the contact shadow away mid-jump instead of dragging it along.
  final double lift;

  const _Man({
    required this.color,
    required this.size,
    required this.isKing,
    this.lift = 0,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size * 1.16, // room for the stack + side wall
        child: CustomPaint(
          painter: _ManPainter(color: color, isKing: isKing, lift: lift),
        ),
      );
}

class _ManPainter extends CustomPainter {
  final Color color;
  final bool isKing;
  final double lift;

  const _ManPainter({
    required this.color,
    required this.isKing,
    required this.lift,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final wall = r * 0.30; // cylinder height, drawn as a downward offset
    final base = Offset(r, size.height - r - wall * (isKing ? 2.5 : 0.9));

    // Contact shadow. Lifting the piece pushes the shadow away and softens it.
    final l = lift.clamp(0.0, 1.0);
    canvas.drawOval(
      Rect.fromCenter(
        center:
            base.translate(r * (0.14 + 0.5 * l), wall + r * (0.30 + 0.7 * l)),
        width: r * (1.95 - 0.25 * l),
        height: r * (0.62 - 0.10 * l),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.34 * (1 - 0.45 * l))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * (0.16 + 0.30 * l)),
    );

    if (isKing) {
      // The lower man of the stack sits deeper in shadow — the upper piece is
      // between it and the light — which is what makes the doubled height read
      // as two pieces rather than one thick one.
      _cylinder(canvas, base.translate(0, wall * 1.45), r, wall, shade: 0.22);
    }
    _cylinder(canvas, base, r, wall, top: true);
  }

  /// One disc: side wall, milled edge, top face, lathe grooves, specular.
  void _cylinder(
    Canvas canvas,
    Offset c,
    double r,
    double wall, {
    bool top = false,
    double shade = 0,
  }) {
    final body = Color.lerp(color, Colors.black, shade)!;
    final dark = Color.lerp(body, Colors.black, 0.46)!;
    final mid = Color.lerp(body, Colors.black, 0.20)!;

    // Side wall — the whole reason the piece has volume.
    final wallRect = Rect.fromCircle(center: c.translate(0, wall), radius: r);
    canvas.drawCircle(
      c.translate(0, wall),
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [mid, dark],
        ).createShader(wallRect),
    );
    // Milling: fine vertical ticks around the visible arc of the wall.
    canvas.save();
    canvas.clipPath(
      Path()
        ..addOval(wallRect)
        ..addOval(Rect.fromCircle(center: c, radius: r))
        ..fillType = PathFillType.evenOdd,
    );
    final tick = Paint()..strokeWidth = math.max(0.5, r * 0.045);
    for (var i = 0; i < 40; i++) {
      final a = math.pi * (i / 40);
      final h = _hash2(i, 3);
      // Brighter where the light rakes across the knurl, dark on the far side.
      final lit = (math.cos(a - math.pi * 0.25) + 1) / 2;
      tick.color = Colors.white.withValues(alpha: 0.05 + 0.16 * lit * h);
      final x = c.dx + math.cos(a) * r * 0.985;
      canvas.drawLine(
        Offset(x, c.dy),
        Offset(x, c.dy + wall * 1.2),
        tick,
      );
    }
    canvas.restore();

    // Top face.
    final faceRect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.40, -0.45),
          radius: 1.05,
          colors: [
            Color.lerp(body, Colors.white, 0.34)!,
            body,
            Color.lerp(body, Colors.black, 0.22)!,
          ],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(faceRect),
    );
    // Chamfer between face and wall.
    canvas.drawCircle(
      c,
      r * 0.975,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.075
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.38),
            Colors.white.withValues(alpha: 0.02),
            Colors.black.withValues(alpha: 0.34),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(faceRect),
    );

    // Lathe grooves — the turned-on-a-lathe read.
    for (final (rf, a) in const [(0.74, 0.18), (0.60, 0.13), (0.34, 0.10)]) {
      canvas.drawCircle(
        c,
        r * rf,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.035
          ..color = Colors.black.withValues(alpha: a),
      );
      canvas.drawCircle(
        c.translate(-r * 0.012, -r * 0.016),
        r * rf,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.028
          ..color = Colors.white.withValues(alpha: a * 1.25),
      );
    }

    // A crown only on the upper disc of a king, small and inlaid.
    if (top && isKing) {
      _crown(canvas, c, r * 0.34);
    }

    // Specular.
    canvas.save();
    canvas.clipPath(Path()..addOval(faceRect));
    canvas.drawOval(
      Rect.fromCenter(
        center: c.translate(-r * 0.36, -r * 0.42),
        width: r * 0.80,
        height: r * 0.52,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.26)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.16),
    );
    canvas.restore();
  }

  void _crown(Canvas canvas, Offset c, double s) {
    final path = Path()
      ..moveTo(c.dx - s, c.dy + s * 0.62)
      ..lineTo(c.dx - s * 0.82, c.dy - s * 0.72)
      ..lineTo(c.dx - s * 0.34, c.dy - s * 0.02)
      ..lineTo(c.dx, c.dy - s * 0.92)
      ..lineTo(c.dx + s * 0.34, c.dy - s * 0.02)
      ..lineTo(c.dx + s * 0.82, c.dy - s * 0.72)
      ..lineTo(c.dx + s, c.dy + s * 0.62)
      ..close();
    canvas.drawPath(
      path.shift(Offset(s * 0.10, s * 0.13)),
      Paint()..color = Colors.black.withValues(alpha: 0.38),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE9A3), Color(0xFFE0A93B)],
        ).createShader(Rect.fromCenter(center: c, width: s * 2, height: s * 2)),
    );
  }

  @override
  bool shouldRepaint(_ManPainter old) =>
      old.color != color || old.isKing != isKing || old.lift != lift;
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

  const _Confetto({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.spin,
    required this.phase,
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
      final p = o + Offset(dx, dy) * boardSize * 0.55;
      final dim = c.size * boardSize;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(c.spin * t + c.phase);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: dim, height: dim * 0.55),
          Radius.circular(dim * 0.15),
        ),
        Paint()..color = c.color.withValues(alpha: 0.9 * fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
