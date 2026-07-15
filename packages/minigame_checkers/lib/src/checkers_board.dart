import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigames_core/minigames_core.dart';

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
      final hit = legal
          .where((m) => m.from == _selected && m.to == cell)
          .toList();
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white24, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 2,
            offset: const Offset(0, 1),
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: darkSquare.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth;
          final cell = side / CheckersState.size;
          return Stack(
            children: [
              // Squares
              for (var i = 0; i < CheckersState.cellCount; i++)
                _square(i, cell),
              // Captured fade
              if (animCaptured != null && moveT < 1)
                _capturedGhost(animCaptured!, cell, moveT),
              // Static pieces (skip destination while the mover is in flight).
              for (var i = 0; i < CheckersState.cellCount; i++)
                if (state.cells[i] != null &&
                    !(moveT < 1 && i == animTo))
                  _pieceAt(i, cell, scale: 1),
              // Moving piece
              if (animFrom != null &&
                  animTo != null &&
                  moveT < 1 &&
                  state.cells[animTo!] != null)
                _movingPiece(cell),
              // Hit targets
              for (var i = 0; i < CheckersState.cellCount; i++)
                Positioned(
                  left: (i % CheckersState.size) * cell,
                  top: (i ~/ CheckersState.size) * cell,
                  width: cell,
                  height: cell,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: gameOver ? null : () => onTap(i),
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _square(int i, double cell) {
    final (r, c) = CheckersState.rc(i);
    final dark = CheckersState.isDarkSquare(r, c);
    final isSel = selected == i;
    final isTarget = targets.contains(i);
    final canPick = selectable.contains(i) && selected == null;

    return Positioned(
      left: c * cell,
      top: r * cell,
      width: cell,
      height: cell,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? darkSquare : lightSquare,
          border: isSel
              ? Border.all(color: selectColor, width: 2.5)
              : null,
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
            : (canPick
                ? Center(
                    child: Container(
                      width: cell * 0.12,
                      height: cell * 0.12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selectColor.withValues(alpha: 0.35),
                      ),
                    ),
                  )
                : null),
      ),
    );
  }

  Widget _pieceAt(int i, double cell, {required double scale}) {
    final (r, c) = CheckersState.rc(i);
    final owner = state.cells[i]!;
    final color = owner == state.darkId ? darkPiece : lightPiece;
    final king = state.isKing[i];
    return Positioned(
      left: c * cell,
      top: r * cell,
      width: cell,
      height: cell,
      child: Center(
        child: Transform.scale(
          scale: scale * (selected == i ? 1.06 : 1.0),
          child: _Man(color: color, size: cell * 0.78, isKing: king),
        ),
      ),
    );
  }

  Widget _movingPiece(double cell) {
    final (fr, fc) = CheckersState.rc(animFrom!);
    final (tr, tc) = CheckersState.rc(animTo!);
    final x = (fc + (tc - fc) * moveT) * cell;
    final y = (fr + (tr - fr) * moveT) * cell;
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
      child: Center(
        child: Transform.scale(
          scale: 1.0 + (isJump ? 0.08 * math.sin(moveT * math.pi) : 0),
          child: _Man(
            color: color,
            size: cell * 0.78,
            isKing: showKing || king,
          ),
        ),
      ),
    );
  }

  Widget _capturedGhost(int i, double cell, double t) {
    final (r, c) = CheckersState.rc(i);
    // Fade + shrink the captured piece (color from opponent of mover).
    final mover = state.cells[animTo!];
    if (mover == null) return const SizedBox.shrink();
    final victimColor =
        mover == state.darkId ? lightPiece : darkPiece;
    final p = Curves.easeIn.transform(t);
    return Positioned(
      left: c * cell,
      top: r * cell,
      width: cell,
      height: cell,
      child: Opacity(
        opacity: (1 - p).clamp(0.0, 1.0),
        child: Center(
          child: Transform.scale(
            scale: 1 - 0.5 * p,
            child: _Man(
              color: victimColor,
              size: cell * 0.78,
              isKing: false,
            ),
          ),
        ),
      ),
    );
  }
}

class _Man extends StatelessWidget {
  final Color color;
  final double size;
  final bool isKing;

  const _Man({
    required this.color,
    required this.size,
    required this.isKing,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.35, -0.4),
            colors: [
              Color.lerp(color, Colors.white, 0.28)!,
              color,
              Color.lerp(color, Colors.black, 0.25)!,
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.2),
            width: size * 0.04,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: size * 0.08,
              offset: Offset(0, size * 0.06),
            ),
          ],
        ),
        child: isKing
            ? Center(
                child: Icon(
                  Icons.workspace_premium_rounded,
                  size: size * 0.48,
                  color: const Color(0xFFFFD54F),
                ),
              )
            : Center(
                child: Container(
                  width: size * 0.38,
                  height: size * 0.38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                      width: size * 0.05,
                    ),
                  ),
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
