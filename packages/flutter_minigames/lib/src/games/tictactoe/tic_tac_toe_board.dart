import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Picture, PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/src/core/core.dart';

import 'tic_tac_toe_game.dart';
import 'tic_tac_toe_marks.dart';
import 'tic_tac_toe_style.dart';

/// A fully animated tic-tac-toe board wired to a [MatchController].
///
/// All the "juice" lives here so every host gets it for free: the grid draws
/// itself on load, marks stroke in with a squash, pressing an empty cell shows
/// a ghost of your mark, and a win draws the winning line, pops the winning
/// cells, dims the rest, bursts confetti, escalates haptics, and fires optional
/// [TicTacToeStyle.sounds]. Colours come from [TicTacToeStyle] / the ambient
/// [ColorScheme]; the motion is universal.
class TicTacToeBoard extends StatefulWidget {
  final MatchController<TicTacToeState, TicTacToeMove> controller;
  final TicTacToeStyle style;

  const TicTacToeBoard({
    super.key,
    required this.controller,
    this.style = const TicTacToeStyle(),
  });

  @override
  State<TicTacToeBoard> createState() => _TicTacToeBoardState();
}

class _TicTacToeBoardState extends State<TicTacToeBoard>
    with TickerProviderStateMixin {
  static const _game = TicTacToeGame();

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _winLineCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final AnimationController _confettiCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  final math.Random _rnd = math.Random();
  StreamSubscription<TicTacToeState>? _sub;

  TicTacToeState? _state;
  GameOutcome? _outcome;
  List<int>? _winLine;
  int _lastFilled = 0;
  List<_Confetto> _confetti = const [];
  Offset _confettiOrigin = const Offset(0.5, 0.5);

  @override
  void initState() {
    super.initState();
    _state = widget.controller.state;
    _lastFilled = _state?.filledCount ?? 0;
    _outcome = _state == null ? null : _game.outcome(_state!);
    _entrance.forward();
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _entrance.dispose();
    _winLineCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  void _onState(TicTacToeState state) {
    final filled = state.filledCount;
    final outcome = _game.outcome(state);
    final style = widget.style;

    if (filled > _lastFilled) {
      if (style.haptics) HapticFeedback.lightImpact();
      // Fire place sound slightly into the stroke so it lands with the mark.
      Future.delayed(const Duration(milliseconds: 70), () {
        if (mounted) style.sounds.onPlace?.call();
      });
    }
    if (filled < _lastFilled) {
      // New game — clear win effects.
      _winLineCtrl.value = 0;
      _confettiCtrl.value = 0;
      _winLine = null;
      _confetti = const [];
    }
    if (outcome != null && _outcome == null) {
      if (outcome.isWin) {
        _winLine = _findWinLine(state);
        _startWinEffects(state);
      } else {
        // Draw.
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

  List<int>? _findWinLine(TicTacToeState state) {
    for (final line in TicTacToeGame.winningLines) {
      final a = state.cells[line[0]];
      if (a != null &&
          a == state.cells[line[1]] &&
          a == state.cells[line[2]]) {
        return line;
      }
    }
    return null;
  }

  void _startWinEffects(TicTacToeState state) {
    widget.style.sounds.onWin?.call();
    if (widget.style.haptics) {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 90), () {
        if (mounted) HapticFeedback.mediumImpact();
      });
    }
    final line = _winLine;
    if (line != null) {
      _confettiOrigin = Offset(
        ((line.first % 3 + line.last % 3) / 2 + 0.5) / 3,
        ((line.first ~/ 3 + line.last ~/ 3) / 2 + 0.5) / 3,
      );
    }
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) _winLineCtrl.forward(from: 0);
    });
    if (widget.style.confetti) {
      _confetti = _spawnConfetti();
      _confettiCtrl.forward(from: 0);
    }
  }

  List<_Confetto> _spawnConfetti() {
    final scheme = Theme.of(context).colorScheme;
    final palette = <Color>[
      widget.style.resolveX(scheme),
      widget.style.resolveO(scheme),
      const Color(0xFFF4B740),
      const Color(0xFFFFF3E0),
    ];
    return List<_Confetto>.generate(36, (i) {
      final angle = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 2.5;
      return _Confetto(
        angle: angle,
        speed: 0.55 + _rnd.nextDouble() * 0.95,
        size: 0.018 + _rnd.nextDouble() * 0.022,
        color: palette[i % palette.length],
        spin: (_rnd.nextDouble() - 0.5) * 12,
        phase: _rnd.nextDouble() * math.pi,
        round: _rnd.nextBool(),
      );
    });
  }

  bool? _markIsX(TicTacToeState state, int i) {
    final id = state.cells[i];
    if (id == null) return null;
    return state.playerIds.indexOf(id) == 0;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final state = _state;
    if (state == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final xColor = style.resolveX(scheme);
    final oColor = style.resolveO(scheme);
    final currentIsX = state.playerIds.indexOf(state.currentPlayerId) == 0;
    final winSet = _winLine?.toSet() ?? const <int>{};
    final gameOver = _outcome != null;
    final winnerIsX = _winLine == null
        ? null
        : state.playerIds.indexOf(state.cells[_winLine!.first]!) == 0;
    final winColor = style.winLineColor ?? (winnerIsX == true ? xColor : oColor);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusBanner(
          state: state,
          outcome: _outcome,
          winnerIsX: winnerIsX,
          xColor: xColor,
          oColor: oColor,
        ),
        const SizedBox(height: 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.maxWidth;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _entrance,
                        builder: (_, __) => CustomPaint(
                          painter: _GridPainter(
                            color: style.resolveGrid(scheme),
                            progress: _entrance.value,
                            brightness: scheme.brightness,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: GridView.count(
                        crossAxisCount: 3,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (var i = 0; i < 9; i++)
                            _Cell(
                              markIsX: _markIsX(state, i),
                              currentIsX: currentIsX,
                              xColor: xColor,
                              oColor: oColor,
                              winning: winSet.contains(i),
                              dimmed: gameOver && !winSet.contains(i),
                              enabled: !gameOver && state.cells[i] == null,
                              onTap: () => widget.controller
                                  .submitMove(TicTacToeMove(i)),
                            ),
                        ],
                      ),
                    ),
                    if (_winLine != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _winLineCtrl,
                            builder: (_, __) => CustomPaint(
                              painter: _WinLinePainter(
                                line: _winLine!,
                                color: winColor,
                                progress: _winLineCtrl.value,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (style.confetti && _confetti.isNotEmpty)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _confettiCtrl,
                            builder: (_, __) => CustomPaint(
                              painter: _ConfettiPainter(
                                confetti: _confetti,
                                origin: _confettiOrigin,
                                t: _confettiCtrl.value,
                                boardSize: size,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
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
  final TicTacToeState state;
  final GameOutcome? outcome;
  final bool? winnerIsX;
  final Color xColor;
  final Color oColor;

  const _StatusBanner({
    required this.state,
    required this.outcome,
    required this.winnerIsX,
    required this.xColor,
    required this.oColor,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        );

    final Widget content;
    if (outcome == null) {
      final isX = state.playerIds.indexOf(state.currentPlayerId) == 0;
      final color = isX ? xColor : oColor;
      content = Row(
        key: ValueKey('turn-${state.currentPlayerId}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _BreathingDot(color: color),
          const SizedBox(width: 10),
          TicTacToeGlyph(isX: isX, color: color, size: 22),
          const SizedBox(width: 8),
          Text('to move', style: textStyle),
        ],
      );
    } else if (outcome!.isDraw) {
      content = _ResultPill(
        key: const ValueKey('draw'),
        color: Theme.of(context).colorScheme.onSurface,
        child: Text(
          'Dead heat',
          style: textStyle?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 20,
          ),
        ),
      );
    } else {
      final isX = winnerIsX == true;
      final color = isX ? xColor : oColor;
      content = _ResultPill(
        key: const ValueKey('win'),
        color: color,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TicTacToeGlyph(isX: isX, color: color, size: 28),
            const SizedBox(width: 10),
            Text(
              isX ? 'X wins' : 'O wins',
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

/// Big coloured pill so the winner is obvious under confetti.
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

class _BreathingDot extends StatefulWidget {
  final Color color;
  const _BreathingDot({required this.color});

  @override
  State<_BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<_BreathingDot>
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
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.55 + 0.45 * t),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.35 * t),
                blurRadius: 8 + 6 * t,
                spreadRadius: 1 + t,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Cell
// ---------------------------------------------------------------------------

class _Cell extends StatefulWidget {
  final bool? markIsX;
  final bool currentIsX;
  final Color xColor;
  final Color oColor;
  final bool winning;
  final bool dimmed;
  final bool enabled;
  final VoidCallback onTap;

  const _Cell({
    required this.markIsX,
    required this.currentIsX,
    required this.xColor,
    required this.oColor,
    required this.winning,
    required this.dimmed,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> with TickerProviderStateMixin {
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 440),
  );
  late final AnimationController _win = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    if (widget.markIsX != null) _appear.value = 1;
    if (widget.winning) _win.value = 1;
  }

  @override
  void didUpdateWidget(_Cell old) {
    super.didUpdateWidget(old);
    if (old.markIsX == null && widget.markIsX != null) {
      _appear.forward(from: 0);
    } else if (old.markIsX != null && widget.markIsX == null) {
      _appear.value = 0;
    }
    if (!old.winning && widget.winning) {
      _win.forward(from: 0);
    } else if (old.winning && !widget.winning) {
      _win.value = 0;
    }
  }

  @override
  void dispose() {
    _appear.dispose();
    _win.dispose();
    super.dispose();
  }

  Color get _markColor =>
      (widget.markIsX ?? widget.currentIsX) ? widget.xColor : widget.oColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel:
          widget.enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 340),
        opacity: widget.dimmed ? 0.28 : 1,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          scale: _pressed ? 0.92 : 1,
          child: AnimatedBuilder(
            animation: Listenable.merge([_appear, _win]),
            builder: (context, _) {
              final appear = _appear.value;
              final markScale =
                  0.4 + 0.6 * Curves.easeOutBack.transform(appear);
              final winPop = Curves.easeOutBack.transform(_win.value);
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (widget.winning)
                    Padding(
                      padding: const EdgeInsets.all(9),
                      child: Transform.scale(
                        scale: 0.7 + 0.3 * winPop,
                        child: Opacity(
                          opacity: _win.value.clamp(0.0, 1.0) * 0.9,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _markColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  if (widget.markIsX != null)
                    Transform.scale(
                      scale: markScale,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: MarkPainter(
                          isX: widget.markIsX!,
                          color: _markColor,
                          progress: appear,
                        ),
                      ),
                    )
                  else if (_pressed)
                    Opacity(
                      opacity: 0.18,
                      child: Transform.scale(
                        scale: 0.84,
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: MarkPainter(
                            isX: widget.currentIsX,
                            color: _markColor,
                            progress: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

/// The board: a milled stone slab with routed grid channels.
///
/// Light comes from the upper left and every element agrees with it — the slab
/// bevel, the recessed playfield, the channel lips, and (in [MarkPainter]) the
/// inlaid marks. The slab itself is expensive (procedural grain speckle) but
/// completely static, so it is recorded once into a [ui.Picture] keyed by size
/// and palette; only the animated channels are drawn per frame.
class _GridPainter extends CustomPainter {
  final Color color;
  final double progress;
  final Brightness brightness;

  _GridPainter({
    required this.color,
    required this.progress,
    required this.brightness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final pal = _StonePalette.of(brightness);
    canvas.drawPicture(_slabFor(size, pal));

    final third = s / 3;
    final half = s * 0.895 / 2; // channels run wall to wall inside the field
    final mid = s / 2;

    final vt = Curves.easeOutCubic.transform((progress / 0.75).clamp(0.0, 1.0));
    final ht = Curves.easeOutCubic
        .transform(((progress - 0.25) / 0.75).clamp(0.0, 1.0));

    final w = s * 0.017;
    // A routed channel reads as walls *inside* one trough width: the darkest
    // point is the floor, the wall facing the light is shadowed (it faces away
    // from it once you tip into the groove) and the far wall catches a bead.
    // Everything is drawn within ±w/2 — push the lips outside that and the
    // groove flips into a raised bar with a white outline.
    final trough = Paint()
      ..color = pal.channel
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final core = Paint()
      ..color = pal.channelShade
      ..strokeWidth = w * 0.44
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final lipDark = Paint()
      ..color = pal.channelShade.withValues(alpha: 0.60)
      ..strokeWidth = w * 0.26
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final lipLight = Paint()
      ..color = pal.channelLight.withValues(alpha: 0.55)
      ..strokeWidth = w * 0.24
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final off = w * 0.34;

    void channel(Offset a, Offset b, bool vertical) {
      final d = vertical ? Offset(off, 0) : Offset(0, off);
      canvas.drawLine(a, b, trough);
      canvas.drawLine(a, b, core);
      canvas.drawLine(a - d, b - d, lipDark);
      canvas.drawLine(a + d, b + d, lipLight);
    }

    for (final x in [third, third * 2]) {
      if (vt <= 0) continue;
      channel(Offset(x, mid - half * vt), Offset(x, mid + half * vt), true);
    }
    for (final y in [third, third * 2]) {
      if (ht <= 0) continue;
      channel(Offset(mid - half * ht, y), Offset(mid + half * ht, y), false);
    }

    // The host's grid colour still gets a say: a faint tint down each channel
    // so a branded palette reads on the board, not only on the marks.
    if (color.a > 0) {
      final tint = Paint()
        ..color = color.withValues(alpha: 0.07)
        ..strokeWidth = w * 0.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (final x in [third, third * 2]) {
        if (vt <= 0) continue;
        canvas.drawLine(
            Offset(x, mid - half * vt), Offset(x, mid + half * vt), tint);
      }
      for (final y in [third, third * 2]) {
        if (ht <= 0) continue;
        canvas.drawLine(
            Offset(mid - half * ht, y), Offset(mid + half * ht, y), tint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.brightness != brightness;
}

// ---------------------------------------------------------------------------
// Stone slab: palette, procedural grain, cached picture
// ---------------------------------------------------------------------------

/// Everything the slab needs, resolved once per brightness. Deliberately not
/// derived from [ColorScheme]: the board is a physical object with its own
/// material, and the host brands the marks, not the rock.
class _StonePalette {
  final Color top; // lit face, upper-left
  final Color bottom; // shaded face, lower-right
  final Color field; // recessed playfield
  final Color rimLight;
  final Color rimShade;
  final Color channel;
  final Color channelShade;
  final Color channelLight;
  final Color grain;
  final int key;

  const _StonePalette({
    required this.top,
    required this.bottom,
    required this.field,
    required this.rimLight,
    required this.rimShade,
    required this.channel,
    required this.channelShade,
    required this.channelLight,
    required this.grain,
    required this.key,
  });

  static const _light = _StonePalette(
    top: Color(0xFFF0EBE1),
    bottom: Color(0xFFD5CDBE),
    field: Color(0xFFE6E0D3),
    rimLight: Color(0xB3FFFFFF),
    rimShade: Color(0x3D000000),
    channel: Color(0xFFA79C88),
    channelShade: Color(0xFF7C7160),
    channelLight: Color(0xE6FFFFFF),
    grain: Color(0xFF6B6353),
    key: 1,
  );

  static const _dark = _StonePalette(
    top: Color(0xFF3B3F45),
    bottom: Color(0xFF23262A),
    field: Color(0xFF2E3237),
    rimLight: Color(0x33FFFFFF),
    rimShade: Color(0x66000000),
    channel: Color(0xFF15171A),
    channelShade: Color(0xFF0C0D0F),
    channelLight: Color(0x40FFFFFF),
    grain: Color(0xFF9AA3AD),
    key: 2,
  );

  static _StonePalette of(Brightness b) =>
      b == Brightness.dark ? _dark : _light;
}

/// Deterministic 0..1 value hash — procedural grain with no assets and no
/// per-frame randomness (the slab must be byte-identical between rebuilds or
/// the cache would flicker).
double _hash2(int x, int y) {
  var h = x * 374761393 + y * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0;
}

class _Slab {
  final double w;
  final int key;
  final ui.Picture picture;
  const _Slab(this.w, this.key, this.picture);
}

final List<_Slab> _slabs = [];

ui.Picture _slabFor(Size size, _StonePalette pal) {
  for (final s in _slabs) {
    if (s.w == size.width && s.key == pal.key) return s.picture;
  }
  final recorder = ui.PictureRecorder();
  _paintSlab(Canvas(recorder), size, pal);
  final made = _Slab(size.width, pal.key, recorder.endRecording());
  _slabs.insert(0, made);
  while (_slabs.length > 3) {
    _slabs.removeLast().picture.dispose();
  }
  return made.picture;
}

void _paintSlab(Canvas canvas, Size size, _StonePalette pal) {
  final s = size.width;
  final body = Rect.fromLTWH(s * 0.012, 0, s - s * 0.024, s - s * 0.03);
  final rr = RRect.fromRectAndRadius(body, Radius.circular(s * 0.075));

  // Contact shadow — the slab is lying on the panel, not floating over it.
  canvas.drawRRect(
    rr.shift(Offset(s * 0.004, s * 0.020)),
    Paint()
      ..color = const Color(0x2E000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.022),
  );

  // Slab face, lit from the upper left.
  canvas.drawRRect(
    rr,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [pal.top, pal.bottom],
      ).createShader(body),
  );

  // Grain: sparse speckle plus a few longer flecks, clipped to the slab.
  canvas.save();
  canvas.clipRRect(rr);
  final grain = Paint();
  final cells = (s / 5).round().clamp(20, 90);
  for (var i = 0; i < cells; i++) {
    for (var j = 0; j < cells; j++) {
      final h = _hash2(i, j);
      if (h < 0.86) continue;
      final x = body.left + (i + _hash2(i, j + 91)) / cells * body.width;
      final y = body.top + (j + _hash2(i + 57, j)) / cells * body.height;
      grain.color = pal.grain.withValues(alpha: 0.03 + 0.07 * (h - 0.86) / 0.14);
      canvas.drawCircle(Offset(x, y), s * (0.0012 + 0.0022 * h), grain);
    }
  }
  // A wide, very soft sheen sweeping from the light.
  canvas.drawRect(
    body,
    Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-1, -1.4),
        end: const Alignment(0.6, 1),
        colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(body),
  );
  canvas.restore();

  // Recessed playfield: darker floor, shadowed upper-left wall, lit lower-right.
  final field = body.deflate(s * 0.035);
  final fieldRR = RRect.fromRectAndRadius(field, Radius.circular(s * 0.05));
  canvas.drawRRect(fieldRR, Paint()..color = pal.field);
  canvas.save();
  canvas.clipRRect(fieldRR);
  canvas.drawRRect(
    fieldRR.shift(Offset(s * 0.008, s * 0.010)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.014
      ..color = pal.rimShade
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.008),
  );
  canvas.drawRRect(
    fieldRR.shift(Offset(-s * 0.008, -s * 0.010)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.010
      ..color = pal.rimLight
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.007),
  );
  canvas.restore();

  // Outer edge: bright along the lit rim, dark along the shaded one.
  canvas.drawRRect(
    rr.deflate(s * 0.0035),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.006
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [pal.rimLight, pal.rimShade],
        stops: const [0.15, 0.85],
      ).createShader(body),
  );
}

class _WinLinePainter extends CustomPainter {
  final List<int> line;
  final Color color;
  final double progress;

  _WinLinePainter({
    required this.line,
    required this.color,
    required this.progress,
  });

  Offset _center(int i, double s) {
    final third = s / 3;
    return Offset((i % 3 + 0.5) * third, (i ~/ 3 + 0.5) * third);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final s = size.width;
    final a = _center(line.first, s);
    final b = _center(line.last, s);
    final dir = b - a;
    final unit = dir / dir.distance;
    final start = a - unit * (s * 0.03);
    final fullEnd = b + unit * (s * 0.03);
    final end =
        Offset.lerp(start, fullEnd, Curves.easeOutCubic.transform(progress))!;

    final glow = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03);
    final stroke = Paint()
      ..color = color
      ..strokeWidth = s * 0.034
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start, end, glow);
    canvas.drawLine(start, end, stroke);
  }

  @override
  bool shouldRepaint(_WinLinePainter old) =>
      old.progress != progress || old.line != line || old.color != color;
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
  final Offset origin; // fractional 0..1
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
    final s = boardSize;
    final o = Offset(origin.dx * s, origin.dy * s);
    const gravity = 2.4;
    final fade = t < 0.8 ? 1.0 : (1 - (t - 0.8) / 0.2);

    for (final c in confetti) {
      final dx = math.cos(c.angle) * c.speed * t;
      final dy = math.sin(c.angle) * c.speed * t + 0.5 * gravity * t * t;
      final pos = o + Offset(dx * s, dy * s);
      final paint = Paint()
        ..color = c.color.withValues(alpha: fade.clamp(0.0, 1.0));
      final dim = c.size * s;

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(c.phase + c.spin * t);
      if (c.round) {
        canvas.drawCircle(Offset.zero, dim * 0.5, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: dim, height: dim * 0.6),
            Radius.circular(dim * 0.15),
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
