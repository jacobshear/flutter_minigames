import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/src/core/core.dart';

import 'filler_game.dart';
import 'filler_style.dart';

/// Animated Filler board wired to a [MatchController].
///
/// Self-contains the GP chrome: maroon felt table, score chips for both
/// players (Player 2 top-right, Player 1 bottom-left — matching the start
/// corners), the 6 color swatches under the grid, and a translucent black
/// pill over the board center for outcomes. Juice: territory recolor sweep,
/// capture wavefront pops staggered outward ring by ring (animation-driven
/// sound cues), confetti on win.
class FillerBoard extends StatefulWidget {
  final MatchController<FillerState, FillerMove> controller;
  final FillerStyle style;

  const FillerBoard({
    super.key,
    required this.controller,
    this.style = const FillerStyle(),
  });

  @override
  State<FillerBoard> createState() => _FillerBoardState();
}

class _FillerBoardState extends State<FillerBoard>
    with TickerProviderStateMixin {
  static const _game = FillerGame();

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  late final AnimationController _captureCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final AnimationController _confettiCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  final math.Random _rnd = math.Random();
  StreamSubscription<FillerState>? _sub;

  FillerState? _state;
  GameOutcome? _outcome;

  /// State before the currently-animating move (recolor source colors).
  FillerState? _prevState;

  /// Captured cell → wavefront ring (1-based BFS depth from old territory).
  Map<int, int> _captureRing = const {};
  int _maxRing = 0;
  int _moverIndex = -1;
  bool _animating = false;

  /// Animation-driven capture cues (cancel-safe: they die with the
  /// controller instead of firing from stale futures).
  int _ringsFired = 0;

  /// Outcome that arrived mid-capture; celebrated when the wave lands.
  GameOutcome? _pendingOutcome;

  List<_Confetto> _confetti = const [];

  @override
  void initState() {
    super.initState();
    final s = widget.controller.state;
    _state = s;
    _outcome = s == null ? null : _game.outcome(s);
    _entrance.forward();
    _captureCtrl.addListener(_onCaptureTick);
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _entrance.dispose();
    _captureCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  static int _totalOwned(FillerState s) =>
      FillerState.cellCount - s.unownedCount;

  void _onState(FillerState next) {
    final prev = _state;
    final outcome = _game.outcome(next);

    if (prev != null && _totalOwned(next) < _totalOwned(prev)) {
      // New game.
      _captureCtrl.stop();
      _captureCtrl.value = 0;
      _animating = false;
      _prevState = null;
      _captureRing = const {};
      _maxRing = 0;
      _pendingOutcome = null;
      _confetti = const [];
      _confettiCtrl.value = 0;
    } else if (prev != null && next.turnIndex != prev.turnIndex) {
      _startCaptureAnimation(prev, next);
    }

    if (outcome != null && _outcome == null) {
      if (_animating) {
        // Hold the fanfare until the wave actually lands.
        _pendingOutcome = outcome;
      } else {
        _celebrate(next, outcome);
      }
    }

    setState(() {
      _state = next;
      _outcome = outcome;
    });
  }

  void _startCaptureAnimation(FillerState prev, FillerState next) {
    final style = widget.style;
    final mover = prev.turnIndex;

    final captured = <int>{
      for (var i = 0; i < FillerState.cellCount; i++)
        if (prev.owners[i] == -1 && next.owners[i] == mover) i,
    };

    // BFS rings outward from the old territory through the captured set —
    // the flood-fill wavefront.
    final ring = <int, int>{};
    var frontier = <int>{
      for (var i = 0; i < FillerState.cellCount; i++)
        if (prev.owners[i] == mover) i,
    };
    var depth = 0;
    while (captured.isNotEmpty && frontier.isNotEmpty) {
      depth++;
      final nextFrontier = <int>{};
      for (final cell in frontier) {
        for (final n in FillerState.neighborsOf(cell)) {
          if (captured.remove(n)) {
            ring[n] = depth;
            nextFrontier.add(n);
          }
        }
      }
      frontier = nextFrontier;
    }

    _prevState = prev;
    _moverIndex = mover;
    _captureRing = ring;
    _maxRing = depth == 0 ? 0 : ring.values.fold(0, math.max);
    _animating = true;
    _ringsFired = 0;

    const recolorMs = 190;
    const ringMs = 105;
    _captureCtrl.duration =
        Duration(milliseconds: recolorMs + _maxRing * ringMs);
    _captureCtrl.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _animating = false;
        _prevState = null;
        _captureRing = const {};
        _maxRing = 0;
      });
      final done = _pendingOutcome;
      _pendingOutcome = null;
      if (done != null && _state != null) _celebrate(_state!, done);
    });

    style.sounds.onPick?.call();
    if (style.haptics) HapticFeedback.lightImpact();
  }

  /// Fire one capture cue per wavefront ring, off the animation clock.
  void _onCaptureTick() {
    if (!_animating || _maxRing == 0) return;
    final style = widget.style;
    final pos = _captureCtrl.value * (1 + _maxRing);
    while (_ringsFired < _maxRing && pos >= _ringsFired + 1 + 0.25) {
      _ringsFired++;
      style.sounds.onCapture?.call();
      if (style.haptics) HapticFeedback.selectionClick();
    }
  }

  void _celebrate(FillerState state, GameOutcome outcome) {
    final style = widget.style;
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

  List<_Confetto> _spawnConfetti(FillerState state, GameOutcome outcome) {
    final winnerIndex = outcome.winnerId == state.playerIds[0] ? 0 : 1;
    final palette = [
      widget.style.cellColors[state.colorOfIndex(winnerIndex)],
      const Color(0xFFF4B740),
      Colors.white,
      widget.style.cellColors[(state.colorOfIndex(winnerIndex) + 3) % 6],
    ];
    return List.generate(34, (i) {
      final angle = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 2.7;
      return _Confetto(
        angle: angle,
        speed: 0.45 + _rnd.nextDouble(),
        size: 0.013 + _rnd.nextDouble() * 0.018,
        color: palette[i % palette.length],
        spin: (_rnd.nextDouble() - 0.5) * 11,
        phase: _rnd.nextDouble() * math.pi,
      );
    });
  }

  void _onSwatchTap(int color) {
    final state = _state;
    if (state == null || _outcome != null || _animating) return;
    if (!_game.validateMove(state, FillerMove(color), state.currentPlayerId)) {
      widget.style.sounds.onInvalid?.call();
      if (widget.style.haptics) HapticFeedback.lightImpact();
      return;
    }
    widget.controller.submitMove(FillerMove(color));
  }

  /// Per-cell display for the current animation frame.
  _GridFrame _frame(double t) {
    final state = _state!;
    final colors = widget.style.cellColors;

    if (!_animating || _prevState == null) {
      return _GridFrame(
        colors: [for (final c in state.cells) colors[c]],
        popScale: null,
        flash: null,
      );
    }

    final prev = _prevState!;
    final beats = 1 + _maxRing;
    final pos = t.clamp(0.0, 1.0) * beats;
    final recolorT = Curves.easeOutCubic.transform(pos.clamp(0.0, 1.0));

    final display = List<Color>.filled(FillerState.cellCount, Colors.black);
    List<double>? popScale;
    List<double>? flash;
    for (var i = 0; i < FillerState.cellCount; i++) {
      if (prev.owners[i] == _moverIndex) {
        // Old territory sweeps from its old color to the picked one.
        display[i] = Color.lerp(
          colors[prev.cells[i]],
          colors[state.cells[i]],
          recolorT,
        )!;
      } else {
        display[i] = colors[state.cells[i]];
      }
      final ring = _captureRing[i];
      if (ring != null) {
        // Pop when this cell's ring beat starts: scale overshoot + flash.
        final u = (pos - ring).clamp(0.0, 1.0);
        if (u > 0) {
          final bump = math.sin(math.pi * (u * 1.35).clamp(0.0, 1.0));
          (popScale ??= List<double>.filled(FillerState.cellCount, 1))[i] =
              1 + 0.16 * bump;
          (flash ??= List<double>.filled(FillerState.cellCount, 0))[i] =
              0.38 * bump;
        }
      }
    }
    return _GridFrame(colors: display, popScale: popScale, flash: flash);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final state = _state;
    if (state == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final table = style.resolveTable(scheme);
    final slab = style.resolveSlab(scheme);

    return AnimatedBuilder(
      animation: Listenable.merge([_entrance, _captureCtrl, _confettiCtrl]),
      builder: (context, _) {
        final enter = Curves.easeOutCubic.transform(_entrance.value);
        final frame = _frame(_captureCtrl.value);
        final showOutcome = !_animating ? _outcome : null;

        String? pillMsg;
        if (showOutcome != null) {
          pillMsg = showOutcome.isDraw
              ? 'DRAW'
              : (showOutcome.winnerId == state.playerIds[0]
                      ? '${style.p1Label} wins'
                      : '${style.p2Label} wins')
                  .toUpperCase();
        }

        final ownColor = state.colorOfIndex(state.turnIndex);
        final oppColor = state.colorOfIndex(1 - state.turnIndex);

        final grid = AspectRatio(
          aspectRatio: FillerState.cols / FillerState.rows,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.34),
                  offset: const Offset(0, 6),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _TrayPainter(slab)),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _FillerGridPainter(frame: frame),
                    ),
                  ),
                  if (style.confetti && _confetti.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _ConfettiPainter(
                            confetti: _confetti,
                            t: _confettiCtrl.value,
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: pillMsg == null
                              ? const SizedBox.shrink(
                                  key: ValueKey('pill-empty'))
                              : Container(
                                  key: ValueKey(pillMsg),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.58),
                                    borderRadius: BorderRadius.circular(10),
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
            ),
          ),
        );

        // Felt table the grid + swatches sit on. Player 2's chip hugs the
        // top-right, Player 1's the bottom-left — mirroring the start corners.
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Transform.scale(
                  scale: 0.94 + 0.06 * enter,
                  child: Opacity(
                    opacity: enter.clamp(0.0, 1.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: _PlayerChip(
                            label: style.p2Label,
                            score: state.scoreOfIndex(1),
                            color: style.cellColors[state.colorOfIndex(1)],
                            active: showOutcome == null && state.turnIndex == 1,
                            winner: showOutcome?.isWin == true &&
                                showOutcome!.winnerId == state.playerIds[1],
                          ),
                        ),
                        const SizedBox(height: 10),
                        grid,
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _PlayerChip(
                            label: style.p1Label,
                            score: state.scoreOfIndex(0),
                            color: style.cellColors[state.colorOfIndex(0)],
                            active: showOutcome == null && state.turnIndex == 0,
                            winner: showOutcome?.isWin == true &&
                                showOutcome!.winnerId == state.playerIds[0],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            for (var c = 0;
                                c < FillerState.colorCount;
                                c++) ...[
                              if (c > 0) const SizedBox(width: 8),
                              Expanded(
                                child: _Swatch(
                                  key: ValueKey('filler_swatch_$c'),
                                  color: style.cellColors[c],
                                  enabled: _outcome == null &&
                                      c != ownColor &&
                                      c != oppColor,
                                  onTap: () => _onSwatchTap(c),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GridFrame {
  final List<Color> colors;
  final List<double>? popScale;
  final List<double>? flash;

  const _GridFrame({
    required this.colors,
    required this.popScale,
    required this.flash,
  });
}

// ---------------------------------------------------------------------------
// Materials
//
// One committed light: a soft key from the upper left. Filler is the one game
// here where colour identity is the whole read, so the tile material is built
// only from *neutral* light — a white lift up-left and a black fall down-right,
// identical for every colour. Hue and saturation are never touched, so no two
// palette colours can drift toward each other.
// ---------------------------------------------------------------------------

const Offset _kLight = Offset(-0.38, -0.45);

/// Deterministic hash in `[0, 1)` — no `Random` anywhere in painting.
double _noise(int x, int y, int seed) {
  var n = (x * 374761393) ^ (y * 668265263) ^ (seed * 1274126177);
  n = (n ^ (n >> 13)) * 1274126177;
  n = n ^ (n >> 16);
  return (n & 0x3fffffff) / 0x3fffffff;
}

/// Body and bevel shaders for one tile size + colour, built in tile-local
/// coordinates so the grid painter can reuse six of them per frame instead of
/// allocating a shader per cell.
class _TileMaterial {
  final ui.Shader body;
  final ui.Shader bevel;

  const _TileMaterial(this.body, this.bevel);
}

final Map<int, _TileMaterial> _tileMaterials = {};

_TileMaterial _tileMaterialFor(double w, double h, Color color) {
  // ignore: deprecated_member_use
  final key = Object.hash(w.round(), h.round(), color.value);
  final cached = _tileMaterials[key];
  if (cached != null) return cached;
  final local = Rect.fromLTWH(0, 0, w, h);
  final made = _TileMaterial(
    // Matte moulded tile: a shallow neutral ramp, brightest at the key corner.
    LinearGradient(
      begin: Alignment(_kLight.dx * 2.4, _kLight.dy * 2.2),
      end: Alignment(-_kLight.dx * 2.4, -_kLight.dy * 2.2),
      colors: [
        Color.lerp(color, Colors.white, 0.13)!,
        color,
        Color.lerp(color, Colors.black, 0.15)!,
      ],
      stops: const [0.0, 0.52, 1.0],
    ).createShader(local),
    // Moulded lip: lit where the key strikes it, shaded on the far side.
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: 0.34),
        Colors.white.withValues(alpha: 0.05),
        Colors.black.withValues(alpha: 0.22),
      ],
    ).createShader(local),
  );
  if (_tileMaterials.length > 24) _tileMaterials.clear();
  _tileMaterials[key] = made;
  return made;
}

class _FillerGridPainter extends CustomPainter {
  final _GridFrame frame;

  _FillerGridPainter({required this.frame});

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / FillerState.cols;
    final cellH = size.height / FillerState.rows;
    final gap = math.min(cellW, cellH) * 0.085;
    final tw = cellW - gap;
    final th = cellH - gap;
    final radius = Radius.circular(math.min(cellW, cellH) * 0.22);
    final local = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, tw, th), radius);
    final lip = math.max(0.7, math.min(tw, th) * 0.055);
    final bodyPaint = Paint();
    final bevelPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lip;
    final flashPaint = Paint();
    final shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.32);
    final drop = Offset(-_kLight.dx * lip * 1.6, -_kLight.dy * lip * 1.6);

    for (var i = 0; i < FillerState.cellCount; i++) {
      final r = FillerState.rowOf(i);
      final c = FillerState.colOf(i);
      final scale = frame.popScale?[i] ?? 1;
      final color = frame.colors[i];
      final mat = _tileMaterialFor(tw, th, color);

      canvas.save();
      canvas.translate(c * cellW + gap / 2, r * cellH + gap / 2);
      if (scale != 1) {
        canvas.translate(tw / 2, th / 2);
        canvas.scale(scale);
        canvas.translate(-tw / 2, -th / 2);
      }
      // Contact shadow onto the tray, pushed away from the key.
      canvas.drawRRect(local.shift(drop), shadowPaint);
      bodyPaint.shader = mat.body;
      canvas.drawRRect(local, bodyPaint);
      bevelPaint.shader = mat.bevel;
      canvas.drawRRect(local.deflate(lip / 2), bevelPaint);
      final flash = frame.flash?[i] ?? 0;
      if (flash > 0) {
        flashPaint.color = Colors.white.withValues(alpha: flash);
        canvas.drawRRect(local, flashPaint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_FillerGridPainter oldDelegate) => true;
}

/// The recessed tray the tiles sit in: a machined dark panel with a lip that
/// is shaded where the key strikes it and lit on the far side, because the
/// well is *below* the surrounding frame.
class _TrayPainter extends CustomPainter {
  final Color slab;

  const _TrayPainter(this.slab);

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Rect.fromLTWH(-9, -9, size.width + 18, size.height + 18);
    final frame = RRect.fromRectAndRadius(outer, const Radius.circular(16));
    canvas.drawRRect(
      frame,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(slab, Colors.white, 0.16)!,
            slab,
            Color.lerp(slab, Colors.black, 0.45)!,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(outer),
    );
    // Outer lip of the frame: lit up-left, dark down-right.
    canvas.drawRRect(
      frame.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.02),
            Colors.black.withValues(alpha: 0.35),
          ],
        ).createShader(outer),
    );
    // The playfield is routed into the frame, so its lip reverses.
    final well = Rect.fromLTWH(-3, -3, size.width + 6, size.height + 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(well, const Radius.circular(10)),
      Paint()..color = Color.lerp(slab, Colors.black, 0.30)!,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(well, const Radius.circular(10)).deflate(1.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withValues(alpha: 0.55),
            Colors.black.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0.10),
          ],
        ).createShader(well),
    );
  }

  @override
  bool shouldRepaint(_TrayPainter old) => old.slab != slab;
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

/// Napped felt: a lit wash from the key, a deterministic fibre speckle, and a
/// vignette that seats the panel in the surrounding dark.
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
        nap.color = (j > 0.78 ? Colors.white : Colors.black)
            .withValues(alpha: 0.012 + k * 0.016);
        final px = x * 5.0 + k * 5;
        final py = y * 5.0 + j * 5;
        canvas.drawLine(Offset(px, py), Offset(px + 1.6 + k, py + 0.8), nap);
      }
    }
  }

  @override
  bool shouldRepaint(_FeltPainter old) => old.felt != felt;
}

/// GP-style score chip: territory-color dot, name, big count.
class _PlayerChip extends StatelessWidget {
  final String label;
  final int score;
  final Color color;
  final bool active;
  final bool winner;

  const _PlayerChip({
    required this.label,
    required this.score,
    required this.color,
    required this.active,
    required this.winner,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: active ? 0.38 : 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: winner
              ? const Color(0xFFF4B740)
              : Colors.white.withValues(alpha: active ? 0.65 : 0.14),
          width: winner ? 2 : 1.4,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: active ? 1 : 0.72),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$score',
            style: TextStyle(
              color: Colors.white.withValues(alpha: active ? 1 : 0.8),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatefulWidget {
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _Swatch({
    super.key,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_Swatch> createState() => _SwatchState();
}

class _SwatchState extends State<_Swatch> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed && widget.enabled ? 0.90 : (widget.enabled ? 1 : 0.86),
        duration: const Duration(milliseconds: 120),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: widget.enabled ? 1 : 0.26,
          child: AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              // Same moulded-tile material as the grid, so the swatches read
              // as the pieces you are about to place rather than flat chips.
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(_kLight.dx * 2.4, _kLight.dy * 2.2),
                  end: Alignment(-_kLight.dx * 2.4, -_kLight.dy * 2.2),
                  colors: [
                    Color.lerp(widget.color, Colors.white, 0.13)!,
                    widget.color,
                    Color.lerp(widget.color, Colors.black, 0.15)!,
                  ],
                  stops: const [0.0, 0.52, 1.0],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(
                    alpha: widget.enabled ? 0.34 : 0.08,
                  ),
                  width: 1.6,
                ),
                boxShadow: widget.enabled
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.32),
                          offset: const Offset(2, 3),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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

  _ConfettiPainter({required this.confetti, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final origin = Offset(size.width / 2, size.height * 0.55);
    final travel = size.shortestSide;
    final paint = Paint();
    for (final c in confetti) {
      final dist = c.speed * travel * Curves.easeOutCubic.transform(t);
      final gravity = 0.55 * travel * t * t;
      final p = origin +
          Offset(
            math.cos(c.angle) * dist,
            math.sin(c.angle) * dist + gravity,
          );
      paint.color = c.color.withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(c.phase + c.spin * t);
      final s = c.size * travel;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: s * 1.6, height: s),
          Radius.circular(s * 0.3),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => true;
}
