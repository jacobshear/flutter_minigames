import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigames_core/minigames_core.dart';

import 'sea_battle_game.dart';
import 'sea_battle_style.dart';

/// Animated Sea Battle board wired to a [MatchController].
///
/// Self-contains the GP chrome: maroon felt table, player chips above and
/// below, translucent black pill for outcomes, and — because this is a
/// hidden-information hot-seat game — a handoff cover ("Pass to Player 2")
/// between turns so the incoming player's fleet is never leaked.
///
/// Placement: the acting player sees their own grid with a random fleet;
/// tap a ship to select it, tap it again to rotate, tap open water to move
/// it, or shuffle the whole fleet. Battle: big enemy targeting grid on top,
/// small own-fleet grid below (GP layout). Shots animate as a falling shell
/// with splash/explosion; sounds fire off the animation controller.
class SeaBattleBoard extends StatefulWidget {
  final MatchController<SeaBattleState, SeaBattleMove> controller;
  final SeaBattleStyle style;

  const SeaBattleBoard({
    super.key,
    required this.controller,
    this.style = const SeaBattleStyle(),
  });

  @override
  State<SeaBattleBoard> createState() => _SeaBattleBoardState();
}

class _SeaBattleBoardState extends State<SeaBattleBoard>
    with TickerProviderStateMixin {
  static const _game = SeaBattleGame();
  static const _n = seaBattleBoardSize;

  /// Shot-animation fraction where the shell lands (sound + haptic moment).
  static const double _impactT = 0.38;

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final AnimationController _shotCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
  );
  late final AnimationController _confettiCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  final math.Random _rnd = math.Random();
  StreamSubscription<SeaBattleState>? _sub;

  SeaBattleState? _state;
  GameOutcome? _outcome;

  /// Whose private information (fleet, targeting view) is on screen.
  String _actingPlayer = '';

  /// Hot-seat handoff cover between turns.
  bool _coverVisible = false;

  /// Cover to raise once the current shot animation lands.
  bool _pendingCover = false;

  bool _celebrated = false;
  List<_Confetto> _confetti = const [];

  // Active shot animation.
  int? _shotCell;
  String? _shotTarget;
  bool _shotHit = false;
  bool _shotSunk = false;
  Set<int> _shotHalo = const {};
  bool _impactFired = false;

  // Placement draft (local until committed via PlaceFleetMove).
  List<ShipPlacement>? _draft;
  int? _selectedShip;
  int _shuffles = 0;

  bool get _hotSeat => widget.controller.hotSeat;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.state;
    _state = s;
    if (s != null) {
      _outcome = _game.outcome(s);
      _celebrated = _outcome != null;
      _actingPlayer = _hotSeat
          ? s.currentPlayerId
          : widget.controller.localPlayerId;
    }
    _shotCtrl.addListener(_onShotTick);
    _shotCtrl.addStatusListener(_onShotStatus);
    _entrance.forward();
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void didUpdateWidget(covariant SeaBattleBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    // Rebind to a swapped-in controller (e.g. "New game" reusing this State).
    _sub?.cancel();
    final s = widget.controller.state;
    if (s != null) _resetForNewGame(s);
    _state = s;
    _outcome = s == null ? null : _game.outcome(s);
    _celebrated = _outcome != null;
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _entrance.dispose();
    _shotCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // State stream
  // ---------------------------------------------------------------------------

  void _onState(SeaBattleState next) {
    final style = widget.style;
    final prev = _state;
    final outcome = _game.outcome(next);
    var startedShot = false;

    final isFresh = next.fleets.values.every((f) => f == null) &&
        next.shots.values.every((s) => s.isEmpty);
    if (prev != null &&
        isFresh &&
        (prev.fleets.values.any((f) => f != null) ||
            prev.shots.values.any((s) => s.isNotEmpty))) {
      _resetForNewGame(next);
    } else if (prev != null) {
      final prevPlaced = prev.fleets.values.whereType<List>().length;
      final nextPlaced = next.fleets.values.whereType<List>().length;
      if (nextPlaced > prevPlaced) {
        // A fleet was committed.
        style.sounds.onPlace?.call();
        if (style.haptics) HapticFeedback.lightImpact();
        _draft = null;
        _selectedShip = null;
        if (_hotSeat && next.currentPlayerId != _actingPlayer) {
          _coverVisible = true;
        }
      }

      final shotCell = next.lastShotCell;
      final target = next.lastShotTarget;
      if (shotCell != null && target != null) {
        final prevShots = prev.shots[target] ?? const <int>{};
        final nextShots = next.shots[target] ?? const <int>{};
        if (!prevShots.contains(shotCell) && nextShots.contains(shotCell)) {
          final ship = next.shipAt(target, shotCell);
          _shotCell = shotCell;
          _shotTarget = target;
          _shotHit = ship != null;
          _shotSunk = ship != null && ship.cells.every(nextShots.contains);
          _shotHalo = nextShots.difference(prevShots)..remove(shotCell);
          _impactFired = false;
          _pendingCover = _hotSeat &&
              outcome == null &&
              next.currentPlayerId != _actingPlayer;
          _shotCtrl.forward(from: 0);
          startedShot = true;
        }
      }
    }

    if (outcome != null && !_celebrated && !startedShot) {
      _celebrate(outcome);
    }

    setState(() {
      _state = next;
      _outcome = outcome;
    });
  }

  void _resetForNewGame(SeaBattleState next) {
    _actingPlayer =
        _hotSeat ? next.currentPlayerId : widget.controller.localPlayerId;
    _coverVisible = false;
    _pendingCover = false;
    _celebrated = false;
    _confetti = const [];
    _confettiCtrl.value = 0;
    _shotCtrl.value = 0;
    _shotCell = null;
    _shotTarget = null;
    _shotHalo = const {};
    _draft = null;
    _selectedShip = null;
    _shuffles = 0;
  }

  void _onShotTick() {
    if (_impactFired || _shotCtrl.value < _impactT) return;
    _impactFired = true;
    final style = widget.style;
    if (_shotSunk) {
      style.sounds.onSunk?.call();
      if (style.haptics) HapticFeedback.heavyImpact();
    } else if (_shotHit) {
      style.sounds.onHit?.call();
      if (style.haptics) HapticFeedback.mediumImpact();
    } else {
      style.sounds.onMiss?.call();
      if (style.haptics) HapticFeedback.lightImpact();
    }
  }

  void _onShotStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    setState(() {
      _shotCell = null;
      _shotTarget = null;
      _shotHalo = const {};
      if (_outcome != null && !_celebrated) {
        _celebrate(_outcome!);
      } else if (_pendingCover) {
        _coverVisible = true;
        _pendingCover = false;
      }
    });
  }

  void _celebrate(GameOutcome outcome) {
    _celebrated = true;
    final style = widget.style;
    style.sounds.onWin?.call();
    if (style.haptics) HapticFeedback.heavyImpact();
    if (style.confetti) {
      _confetti = _spawnConfetti();
      _confettiCtrl.forward(from: 0);
    }
  }

  List<_Confetto> _spawnConfetti() {
    final scheme = Theme.of(context).colorScheme;
    final palette = [
      widget.style.resolveHit(scheme),
      widget.style.resolveWater(scheme),
      Colors.white,
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

  // ---------------------------------------------------------------------------
  // Placement interactions
  // ---------------------------------------------------------------------------

  int _draftSeed() =>
      widget.controller.matchId.hashCode ^
      _actingPlayer.hashCode ^
      (_shuffles * 0x9E3779B9);

  void _shuffleDraft() {
    setState(() {
      _shuffles++;
      _draft = SeaBattleGame.randomFleet(_draftSeed());
      _selectedShip = null;
    });
    widget.style.sounds.onPlace?.call();
    if (widget.style.haptics) HapticFeedback.selectionClick();
  }

  void _confirmDraft() {
    final draft = _draft;
    if (draft == null) return;
    widget.controller.submitMove(PlaceFleetMove(List.of(draft)));
  }

  void _onPlacementTap(int cell) {
    final draft = _draft;
    if (draft == null) return;
    final idx = draft.indexWhere((s) => s.cells.contains(cell));
    if (idx >= 0) {
      if (_selectedShip == idx) {
        _tryRotate(idx);
      } else {
        setState(() => _selectedShip = idx);
        if (widget.style.haptics) HapticFeedback.selectionClick();
      }
      return;
    }
    final selected = _selectedShip;
    if (selected != null) _tryMove(selected, cell);
  }

  void _tryRotate(int idx) {
    final draft = _draft!;
    final ship = draft[idx];
    if (ship.length == 1) return; // Rotation is a no-op for 1-cell boats.
    final flipped = !ship.horizontal;
    final candidate = ship.copyWith(
      horizontal: flipped,
      row: flipped ? ship.row : math.min(ship.row, _n - ship.length),
      col: flipped ? math.min(ship.col, _n - ship.length) : ship.col,
    );
    _applyDraftChange(idx, candidate);
  }

  void _tryMove(int idx, int cell) {
    final ship = _draft![idx];
    final row = cell ~/ _n;
    final col = cell % _n;
    final candidate = ship.copyWith(
      row: ship.horizontal ? row : math.min(row, _n - ship.length),
      col: ship.horizontal ? math.min(col, _n - ship.length) : col,
    );
    _applyDraftChange(idx, candidate);
  }

  void _applyDraftChange(int idx, ShipPlacement candidate) {
    final next = List<ShipPlacement>.of(_draft!);
    next[idx] = candidate;
    if (SeaBattleGame.isFleetValid(next)) {
      setState(() => _draft = next);
      widget.style.sounds.onPlace?.call();
      if (widget.style.haptics) HapticFeedback.selectionClick();
    } else {
      widget.style.sounds.onInvalid?.call();
      if (widget.style.haptics) HapticFeedback.selectionClick();
    }
  }

  // ---------------------------------------------------------------------------
  // Battle interactions
  // ---------------------------------------------------------------------------

  void _onTargetTap(int cell) {
    final state = _state;
    if (state == null || _outcome != null) return;
    if (_coverVisible || _shotCtrl.isAnimating) return;
    if (state.currentPlayerId != _actingPlayer) return;
    final target = state.opponentOf(_actingPlayer);
    if ((state.shots[target] ?? const <int>{}).contains(cell)) {
      widget.style.sounds.onInvalid?.call();
      if (widget.style.haptics) HapticFeedback.selectionClick();
      return;
    }
    widget.controller.submitMove(FireMove(cell));
  }

  void _dismissCover() {
    final state = _state;
    if (state == null) return;
    setState(() {
      _actingPlayer = state.currentPlayerId;
      _coverVisible = false;
    });
    if (widget.style.haptics) HapticFeedback.selectionClick();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  String _labelFor(String playerId) {
    final state = _state!;
    return playerId == state.playerIds[0]
        ? widget.style.player1Label
        : widget.style.player2Label;
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

    return AnimatedBuilder(
      animation: Listenable.merge([_entrance, _shotCtrl, _confettiCtrl]),
      builder: (context, _) {
        final enter = Curves.easeOutCubic.transform(_entrance.value);
        final enemy = state.opponentOf(_actingPlayer);

        String? pillMsg;
        if (_outcome != null && !_shotCtrl.isAnimating) {
          pillMsg = _outcome!.isDraw
              ? 'DRAW'
              : '${_labelFor(_outcome!.winnerId!)} wins'.toUpperCase();
        } else if (_shotCtrl.isAnimating && _shotCtrl.value >= _impactT) {
          pillMsg = _shotSunk ? 'SUNK!' : (_shotHit ? 'HIT!' : 'MISS');
        }

        final Widget content;
        if (_coverVisible) {
          content = _HandoffCover(
            label: _labelFor(state.currentPlayerId),
            onReady: _dismissCover,
          );
        } else if (state.phase == SeaBattlePhase.placement &&
            state.fleets[_actingPlayer] == null) {
          _draft ??= SeaBattleGame.randomFleet(_draftSeed());
          content = _buildPlacement(scheme, state);
        } else if (state.phase == SeaBattlePhase.placement) {
          content = _buildWaiting(scheme, state);
        } else {
          content = _buildBattle(scheme, state, enemy);
        }

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
                  label: _labelFor(enemy),
                  accent: style.resolveHit(scheme),
                  active: _outcome == null &&
                      !_coverVisible &&
                      state.currentPlayerId == enemy,
                  winner: _outcome?.winnerId == enemy,
                ),
              ),
              const SizedBox(height: 10),
              Transform.scale(
                scale: 0.94 + 0.06 * enter,
                child: Opacity(
                  opacity: enter.clamp(0.0, 1.0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      content,
                      if (widget.style.confetti && _confetti.isNotEmpty)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: LayoutBuilder(
                              builder: (context, c) => CustomPaint(
                                painter: _ConfettiPainter(
                                  confetti: _confetti,
                                  t: _confettiCtrl.value,
                                  boardSize: c.maxWidth,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
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
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: _PlayerChip(
                  label: _labelFor(_actingPlayer),
                  accent: style.resolveWater(scheme),
                  active: _outcome == null &&
                      !_coverVisible &&
                      state.currentPlayerId == _actingPlayer,
                  winner: _outcome?.winnerId == _actingPlayer,
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

  Widget _buildPlacement(ColorScheme scheme, SeaBattleState state) {
    final draft = _draft!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _gridWidget(
          maxWidth: 340,
          spec: _GridSpec(
            ships: draft,
            shipCells: {for (final s in draft) ...s.cells},
            resolved: const {},
            sunkCells: const {},
            selected: _selectedShip == null ? null : draft[_selectedShip!],
          ),
          onTap: _onPlacementTap,
        ),
        const SizedBox(height: 6),
        const Text(
          'Tap a ship to select — tap again to rotate, tap water to move',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _FeltButton(label: 'Shuffle', onTap: _shuffleDraft),
            const SizedBox(width: 12),
            _FeltButton(
              label: 'Ready',
              fill: const Color(0xFF3E8E5A),
              onTap: _confirmDraft,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWaiting(ColorScheme scheme, SeaBattleState state) {
    final fleet = state.fleets[_actingPlayer] ?? const <ShipPlacement>[];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _gridWidget(
          maxWidth: 340,
          spec: _GridSpec(
            ships: fleet,
            shipCells: state.shipCellsOf(_actingPlayer),
            resolved: const {},
            sunkCells: const {},
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Waiting for the enemy fleet…',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildBattle(
    ColorScheme scheme,
    SeaBattleState state,
    String enemy,
  ) {
    final gameOver = _outcome != null;
    final enemyShots = state.shots[enemy] ?? const <int>{};
    final enemySunk = state.sunkShipsOf(enemy);
    // Hidden until sunk; full reveal when the game ends.
    final enemyVisibleShips =
        gameOver ? (state.fleets[enemy] ?? const <ShipPlacement>[]) : enemySunk;
    final ownShots = state.shots[_actingPlayer] ?? const <int>{};
    final ownFleet = state.fleets[_actingPlayer] ?? const <ShipPlacement>[];

    final animatingOnEnemy = _shotCell != null && _shotTarget == enemy;
    final animatingOnOwn = _shotCell != null && _shotTarget == _actingPlayer;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FleetStatusRow(
          sunkLengths: enemySunk.map((s) => s.length).toList(),
          color: widget.style.resolveMiss(scheme),
        ),
        const SizedBox(height: 8),
        _gridWidget(
          maxWidth: 340,
          spec: _GridSpec(
            ships: enemyVisibleShips,
            shipCells: state.shipCellsOf(enemy),
            resolved: enemyShots,
            sunkCells: {for (final s in enemySunk) ...s.cells},
            shot: animatingOnEnemy
                ? _ShotAnim(
                    cell: _shotCell!,
                    t: _shotCtrl.value,
                    hit: _shotHit,
                    sunk: _shotSunk,
                    halo: _shotHalo,
                  )
                : null,
          ),
          onTap: _onTargetTap,
        ),
        const SizedBox(height: 10),
        _gridWidget(
          maxWidth: 150,
          spec: _GridSpec(
            ships: ownFleet,
            shipCells: state.shipCellsOf(_actingPlayer),
            resolved: ownShots,
            sunkCells: {
              for (final s in state.sunkShipsOf(_actingPlayer)) ...s.cells,
            },
            compact: true,
            shot: animatingOnOwn
                ? _ShotAnim(
                    cell: _shotCell!,
                    t: _shotCtrl.value,
                    hit: _shotHit,
                    sunk: _shotSunk,
                    halo: _shotHalo,
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _gridWidget({
    required double maxWidth,
    required _GridSpec spec,
    void Function(int cell)? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (context, c) {
            final geom = _SeaGeom(c.maxWidth);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: onTap == null
                  ? null
                  : (d) {
                      final cell = geom.hitTest(d.localPosition);
                      if (cell != null) onTap(cell);
                    },
              child: CustomPaint(
                size: Size.square(c.maxWidth),
                painter: _SeaGridPainter(
                  geom: geom,
                  spec: spec,
                  water: style.resolveWater(scheme),
                  gridLine: style.resolveGridLine(scheme),
                  shipColor: style.resolveShip(scheme),
                  hitColor: style.resolveHit(scheme),
                  missColor: style.resolveMiss(scheme),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

class _SeaGeom {
  final double side;
  final double pad;
  final double cell;

  _SeaGeom(this.side)
      : pad = side * 0.045,
        cell = (side - side * 0.09) / seaBattleBoardSize;

  Offset cellCenter(int row, int col) =>
      Offset(pad + (col + 0.5) * cell, pad + (row + 0.5) * cell);

  Rect cellRect(int row, int col) =>
      Rect.fromLTWH(pad + col * cell, pad + row * cell, cell, cell);

  int? hitTest(Offset local) {
    final col = ((local.dx - pad) / cell).floor();
    final row = ((local.dy - pad) / cell).floor();
    if (row < 0 ||
        row >= seaBattleBoardSize ||
        col < 0 ||
        col >= seaBattleBoardSize) {
      return null;
    }
    return row * seaBattleBoardSize + col;
  }
}

// ---------------------------------------------------------------------------
// Materials
//
// One committed light for the whole game: a soft key from the upper left. The
// grids are plotting boards — a painted-steel frame around a recessed chart —
// so the frame's lip is lit up-left while the chart's lip, being below it,
// reverses. Pegs and hulls obey the same key.
// ---------------------------------------------------------------------------

const Offset _kLight = Offset(-0.38, -0.45);

/// Deterministic hash in `[0, 1)` — no `Random` anywhere in painting.
double _noise(int x, int y, int seed) {
  var n = (x * 374761393) ^ (y * 668265263) ^ (seed * 1274126177);
  n = (n ^ (n >> 13)) * 1274126177;
  n = n ^ (n >> 16);
  return (n & 0x3fffffff) / 0x3fffffff;
}

/// Cached chart surface (frame, sea, grid, ruler), keyed on size and palette.
class _Chart {
  final double w;
  final double h;
  final int water;
  final int line;
  final bool compact;
  final ui.Picture picture;

  _Chart(this.w, this.h, this.water, this.line, this.compact, this.picture);

  bool matches(Size s, Color wa, Color l, bool c) =>
      w == s.width &&
      h == s.height &&
      compact == c &&
      // ignore: deprecated_member_use
      water == wa.value &&
      // ignore: deprecated_member_use
      line == l.value;
}

final List<_Chart> _charts = [];

ui.Picture _chartFor(
  Size size,
  _SeaGeom geom,
  Color water,
  Color line,
  bool compact,
) {
  for (final c in _charts) {
    if (c.matches(size, water, line, compact)) return c.picture;
  }
  final recorder = ui.PictureRecorder();
  _paintChart(Canvas(recorder), size, geom, water, line, compact);
  final made = _Chart(
    size.width,
    size.height,
    // ignore: deprecated_member_use
    water.value,
    // ignore: deprecated_member_use
    line.value,
    compact,
    recorder.endRecording(),
  );
  _charts.insert(0, made);
  while (_charts.length > 4) {
    _charts.removeLast().picture.dispose();
  }
  return made.picture;
}

void _paintChart(
  Canvas canvas,
  Size size,
  _SeaGeom geom,
  Color water,
  Color line,
  bool compact,
) {
  final w = size.width;
  final rect = Offset.zero & size;
  final radius = Radius.circular(w * 0.05);
  final slab = RRect.fromRectAndRadius(rect, radius);
  final chart = Rect.fromLTWH(
    geom.pad,
    geom.pad,
    geom.cell * seaBattleBoardSize,
    geom.cell * seaBattleBoardSize,
  );

  // Frame: painted steel a few steps darker and greyer than the sea.
  final frame = Color.lerp(water, const Color(0xFF20303C), 0.62)!;

  // Contact shadow: tight core plus a wide ambient falloff, away from the key.
  canvas.drawRRect(
    slab.shift(Offset(w * 0.010, w * 0.016)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.030),
  );
  canvas.drawRRect(
    slab.shift(Offset(w * 0.003, w * 0.005)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.24)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.008),
  );

  // Frame face, with a brushed grain running across it.
  canvas.save();
  canvas.clipRRect(slab);
  canvas.drawRect(rect, Paint()..color = frame);
  final brush = Paint()..strokeWidth = 0.8;
  final rows = (size.height / 3).ceil();
  for (var y = 0; y < rows; y++) {
    final j = _noise(y, 1, 29);
    brush.color = (j > 0.5 ? Colors.white : Colors.black)
        .withValues(alpha: 0.020 + j * 0.030);
    canvas.drawLine(Offset(0, y * 3.0), Offset(w, y * 3.0 + 0.6), brush);
  }
  canvas.drawRect(
    rect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment(_kLight.dx * 2.2, _kLight.dy * 2.0),
        end: Alignment(-_kLight.dx * 2.2, -_kLight.dy * 2.0),
        colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.0),
          Colors.black.withValues(alpha: 0.18),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect),
  );
  canvas.restore();

  // Frame lip: raised, so lit up-left and shaded down-right.
  canvas.drawRRect(
    slab.deflate(w * 0.004),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.008
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.30),
          Colors.white.withValues(alpha: 0.03),
          Colors.black.withValues(alpha: 0.24),
        ],
      ).createShader(rect),
  );

  // Sea, recessed into the frame.
  canvas.save();
  canvas.clipRect(chart);
  canvas.drawRect(
    chart,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(water, Colors.white, 0.18)!,
          water,
          Color.lerp(water, const Color(0xFF27596F), 0.30)!,
        ],
      ).createShader(chart),
  );

  // Swell: long, low, deterministic wave crests so the sea has surface
  // without competing with the pegs for attention.
  final swell = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final bands = (chart.height / (geom.cell * 0.38)).round().clamp(8, 60);
  for (var i = 0; i < bands; i++) {
    final j = _noise(i, 2, 41);
    final k = _noise(i, 2, 67);
    final y = chart.top + (i + j) / bands * chart.height;
    final amp = geom.cell * (0.05 + j * 0.10);
    swell
      ..strokeWidth = math.max(0.5, geom.cell * (0.02 + k * 0.030))
      ..color = (k > 0.55 ? Colors.white : const Color(0xFF1E5670))
          .withValues(alpha: 0.030 + j * 0.055);
    final path = Path()..moveTo(chart.left, y);
    final segs = 4;
    for (var sIdx = 1; sIdx <= segs; sIdx++) {
      final x = chart.left + chart.width * sIdx / segs;
      final cx = chart.left + chart.width * (sIdx - 0.5) / segs;
      path.quadraticBezierTo(
          cx, y + (sIdx.isEven ? amp : -amp), x, y);
    }
    canvas.drawPath(path, swell);
  }

  // Depth vignette: the chart is a recess, so its walls darken the edges.
  canvas.drawRect(
    chart,
    Paint()
      ..shader = RadialGradient(
        center: Alignment(_kLight.dx * 0.6, _kLight.dy * 0.6),
        radius: 0.95,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.14),
        ],
        stops: const [0.55, 1.0],
      ).createShader(chart),
  );
  canvas.restore();

  // Grid: hairline plotting lines, each with a faint shadow on the key side
  // so they read as scored into the chart rather than drawn over it.
  final lw = math.max(0.7, geom.cell * 0.035);
  final ink = Paint()
    ..color = line
    ..strokeWidth = lw;
  final score = Paint()
    ..color = Colors.black.withValues(alpha: 0.10)
    ..strokeWidth = lw;
  for (var i = 0; i <= seaBattleBoardSize; i++) {
    final d = geom.pad + i * geom.cell;
    canvas.drawLine(Offset(chart.left, d - lw * 0.7),
        Offset(chart.right, d - lw * 0.7), score);
    canvas.drawLine(Offset(d - lw * 0.7, chart.top),
        Offset(d - lw * 0.7, chart.bottom), score);
    canvas.drawLine(Offset(chart.left, d), Offset(chart.right, d), ink);
    canvas.drawLine(Offset(d, chart.top), Offset(d, chart.bottom), ink);
  }

  // The chart sits below the frame face, so its lip reverses the frame's:
  // shadow on the near wall, light catching the far one.
  canvas.drawRect(
    chart.inflate(lw * 1.6),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lw * 3.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.black.withValues(alpha: 0.38),
          Colors.black.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.16),
        ],
      ).createShader(chart),
  );

  // Coordinate ruler stamped into the frame. Skipped on the small own-fleet
  // grid, where there is no room to set it legibly.
  final glyph = geom.pad * 0.52;
  if (!compact && glyph >= 6) {
    for (var i = 0; i < seaBattleBoardSize; i++) {
      _stamp(
        canvas,
        String.fromCharCode(65 + i),
        Offset(chart.left + (i + 0.5) * geom.cell, geom.pad / 2),
        glyph,
      );
      _stamp(
        canvas,
        '${i + 1}',
        Offset(geom.pad / 2, chart.top + (i + 0.5) * geom.cell),
        glyph,
      );
    }
  }
}

/// Draws [text] centred on [at] as a stamped mark on the painted frame: a
/// light offset below the dark glyph, as a struck character would catch a
/// top-left key.
void _stamp(Canvas canvas, String text, Offset at, double size) {
  for (final (dy, color) in [
    (1.0, Colors.white.withValues(alpha: 0.16)),
    (0.0, Colors.black.withValues(alpha: 0.38)),
  ]) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2 - dy));
  }
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

// ---------------------------------------------------------------------------
// Grid painter
// ---------------------------------------------------------------------------

/// Everything one grid needs to paint.
class _GridSpec {
  /// Ships to render as visible hulls.
  final List<ShipPlacement> ships;

  /// All ship cells on this grid (visible or hidden) — classifies hits.
  final Set<int> shipCells;

  /// Resolved cells (fired at or auto-revealed).
  final Set<int> resolved;

  /// Cells belonging to sunk ships (tint hulls darker).
  final Set<int> sunkCells;

  /// Placement-mode selected ship (gold highlight).
  final ShipPlacement? selected;

  /// Active shot overlay, if a shell is mid-flight on this grid.
  final _ShotAnim? shot;

  /// Small own-fleet grid: thinner details.
  final bool compact;

  const _GridSpec({
    required this.ships,
    required this.shipCells,
    required this.resolved,
    required this.sunkCells,
    this.selected,
    this.shot,
    this.compact = false,
  });
}

class _ShotAnim {
  final int cell;
  final double t;
  final bool hit;
  final bool sunk;
  final Set<int> halo;

  const _ShotAnim({
    required this.cell,
    required this.t,
    required this.hit,
    required this.sunk,
    required this.halo,
  });
}

class _SeaGridPainter extends CustomPainter {
  static const double _impactT = _SeaBattleBoardState._impactT;

  final _SeaGeom geom;
  final _GridSpec spec;
  final Color water;
  final Color gridLine;
  final Color shipColor;
  final Color hitColor;
  final Color missColor;

  _SeaGridPainter({
    required this.geom,
    required this.spec,
    required this.water,
    required this.gridLine,
    required this.shipColor,
    required this.hitColor,
    required this.missColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Frame, sea texture, grid and coordinate ruler never move: one cached
    // picture, so only the fleet and the pegs cost anything per frame.
    canvas.drawPicture(
        _chartFor(size, geom, water, gridLine, spec.compact));

    // Ship hulls.
    for (final ship in spec.ships) {
      _paintShip(canvas, ship,
          sunk: ship.cells.every(spec.sunkCells.contains));
    }

    // Selected highlight (placement).
    final selected = spec.selected;
    if (selected != null) {
      final r = _shipRect(selected).inflate(geom.cell * 0.06);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, geom.cell * 0.09)
          ..color = const Color(0xFFF4B740),
      );
    }

    // Pegs & dots for resolved cells. The animating cell (and its reveal
    // halo) pops in at impact instead of being pre-painted.
    final shot = spec.shot;
    final animCell = shot?.cell;
    final animHalo = shot?.halo ?? const <int>{};
    final landed = shot == null || shot.t >= _impactT;
    final settle = shot == null
        ? 1.0
        : Curves.easeOutBack.transform(
            ((shot.t - _impactT) / (1 - _impactT)).clamp(0.0, 1.0),
          );

    for (final cell in spec.resolved) {
      final isAnim = cell == animCell;
      final isHalo = animHalo.contains(cell);
      if ((isAnim || isHalo) && !landed) continue;
      final scale = isAnim ? settle : (isHalo ? settle.clamp(0.0, 1.0) : 1.0);
      final row = cell ~/ seaBattleBoardSize;
      final col = cell % seaBattleBoardSize;
      final c = geom.cellCenter(row, col);
      if (spec.shipCells.contains(cell)) {
        _paintHitPeg(canvas, c, scale);
      } else {
        _paintMissDot(canvas, c, scale);
      }
    }

    // Shot overlay: falling shell before impact, splash/blast after.
    if (shot != null) _paintShot(canvas, shot);
  }

  Rect _shipRect(ShipPlacement ship) {
    final first = geom.cellRect(ship.row, ship.col);
    final lastRow = ship.horizontal ? ship.row : ship.row + ship.length - 1;
    final lastCol = ship.horizontal ? ship.col + ship.length - 1 : ship.col;
    final last = geom.cellRect(lastRow, lastCol);
    return first.expandToInclude(last).deflate(geom.cell * 0.14);
  }

  void _paintShip(Canvas canvas, ShipPlacement ship, {required bool sunk}) {
    final r = _shipRect(ship);
    final rr = RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2));
    final base = sunk
        ? Color.lerp(shipColor, const Color(0xFF23282E), 0.55)!
        : shipColor;

    // Two-part contact shadow, pushed away from the key light.
    canvas.drawRRect(
      rr.shift(Offset(-_kLight.dx * geom.cell * 0.16,
          -_kLight.dy * geom.cell * 0.18)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, geom.cell * 0.16),
    );
    canvas.drawRRect(
      rr.shift(Offset(-_kLight.dx * geom.cell * 0.05,
          -_kLight.dy * geom.cell * 0.06)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.24)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, geom.cell * 0.05),
    );
    // Painted steel: a bright deck edge on the key side, a core shadow across
    // the middle, and a thin bounce off the water on the far side.
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(_kLight.dx * 2.2, _kLight.dy * 2.2),
          end: Alignment(-_kLight.dx * 2.2, -_kLight.dy * 2.2),
          colors: [
            Color.lerp(base, Colors.white, 0.42)!,
            Color.lerp(base, Colors.white, 0.10)!,
            base,
            Color.lerp(base, Colors.black, 0.34)!,
            Color.lerp(base, Colors.white, 0.10)!,
          ],
          stops: const [0.0, 0.24, 0.52, 0.88, 1.0],
        ).createShader(r),
    );
    // Hull seam running the length of the deck.
    canvas.drawLine(
      ship.horizontal
          ? Offset(r.left + r.width * 0.08, r.center.dy)
          : Offset(r.center.dx, r.top + r.height * 0.08),
      ship.horizontal
          ? Offset(r.right - r.width * 0.08, r.center.dy)
          : Offset(r.center.dx, r.bottom - r.height * 0.08),
      Paint()
        ..strokeWidth = math.max(0.6, geom.cell * 0.025)
        ..color = Colors.black.withValues(alpha: 0.16),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, geom.cell * 0.05)
        ..color = Color.lerp(base, Colors.black, 0.45)!
            .withValues(alpha: 0.55),
    );

    // Deck detail: a porthole per cell (skip on the tiny grid).
    if (!spec.compact && ship.length > 1) {
      final paint = Paint()
        ..color = Colors.black.withValues(alpha: sunk ? 0.28 : 0.16);
      for (final cell in ship.cells) {
        final c = geom.cellCenter(
            cell ~/ seaBattleBoardSize, cell % seaBattleBoardSize);
        canvas.drawCircle(c, geom.cell * 0.1, paint);
      }
    }
  }

  void _paintHitPeg(Canvas canvas, Offset c, double scale) {
    final r = geom.cell * (spec.compact ? 0.24 : 0.21) * scale;
    if (r <= 0.2) return;
    // Scorch under the peg.
    canvas.drawCircle(
      c,
      r * 1.55,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28 * scale.clamp(0, 1))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5),
    );
    // Contact shadow: the peg is pushed into the board, so the shadow is
    // tight and sits opposite the key.
    canvas.drawOval(
      Rect.fromCenter(
        center: c.translate(-_kLight.dx * r * 0.55, -_kLight.dy * r * 0.6),
        width: r * 2.0,
        height: r * 1.7,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30 * scale.clamp(0, 1))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.28),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(_kLight.dx * 1.5, _kLight.dy * 1.5),
          radius: 1.05,
          colors: [
            Color.lerp(hitColor, Colors.white, 0.55)!,
            hitColor,
            Color.lerp(hitColor, Colors.black, 0.42)!,
          ],
          stops: const [0.0, 0.58, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Specular bead on the moulded plastic head.
    canvas.drawOval(
      Rect.fromCenter(
        center: c + Offset(_kLight.dx * r * 0.9, _kLight.dy * r * 0.9),
        width: r * 0.60,
        height: r * 0.40,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55 * scale.clamp(0, 1))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.14),
    );
  }

  void _paintMissDot(Canvas canvas, Offset c, double scale) {
    final r = geom.cell * (spec.compact ? 0.13 : 0.11) * scale.clamp(0.0, 1.2);
    if (r <= 0.2) return;
    canvas.drawCircle(
      c.translate(-_kLight.dx * r * 0.7, -_kLight.dy * r * 0.8),
      r * 1.05,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.26)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.4),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(_kLight.dx * 1.4, _kLight.dy * 1.4),
          colors: [
            Colors.white,
            missColor,
            Color.lerp(missColor, const Color(0xFF6E7C88), 0.5)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  void _paintShot(Canvas canvas, _ShotAnim shot) {
    final row = shot.cell ~/ seaBattleBoardSize;
    final col = shot.cell % seaBattleBoardSize;
    final c = geom.cellCenter(row, col);
    final cell = geom.cell;

    if (shot.t < _impactT) {
      // Falling shell: drops in from above, shrinking as it nears the sea.
      final u = Curves.easeIn.transform(shot.t / _impactT);
      final y = -cell * 2.2 * (1 - u);
      final r = cell * (0.30 - 0.12 * u);
      final at = c.translate(0, y);
      canvas.drawCircle(
        c,
        cell * 0.16 * u,
        Paint()..color = Colors.black.withValues(alpha: 0.18 * u),
      );
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            colors: [
              const Color(0xFF5A6470),
              const Color(0xFF2E343B),
            ],
          ).createShader(Rect.fromCircle(center: at, radius: r)),
      );
      return;
    }

    final u = ((shot.t - _impactT) / (1 - _impactT)).clamp(0.0, 1.0);
    final fade = (1 - u).clamp(0.0, 1.0);
    if (shot.hit) {
      // Blast flash + expanding ring + smoke puffs.
      final flash = (1 - u * 1.6).clamp(0.0, 1.0);
      if (flash > 0) {
        canvas.drawCircle(
          c,
          cell * (0.35 + 0.5 * u),
          Paint()
            ..color = const Color(0xFFFFB13D).withValues(alpha: 0.7 * flash)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.25),
        );
      }
      canvas.drawCircle(
        c,
        cell * (0.3 + 0.65 * u),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, cell * 0.09 * fade)
          ..color = hitColor.withValues(alpha: 0.8 * fade),
      );
      // Smoke drifting up.
      final smoke = Paint()
        ..color = Colors.black.withValues(alpha: 0.20 * fade)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.18);
      for (var i = 0; i < 3; i++) {
        final dx = (i - 1) * cell * 0.22;
        canvas.drawCircle(
          c.translate(dx, -cell * (0.25 + 0.6 * u) - i * cell * 0.08),
          cell * (0.14 + 0.10 * u),
          smoke,
        );
      }
      if (shot.sunk) {
        // Extra shockwave for the kill.
        canvas.drawCircle(
          c,
          cell * (0.4 + 1.5 * u),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, cell * 0.06 * fade)
            ..color = const Color(0xFFF4B740).withValues(alpha: 0.75 * fade),
        );
      }
    } else {
      // Splash: two ripple rings + droplets.
      for (final (delay, width) in const [(0.0, 0.09), (0.25, 0.06)]) {
        final v = ((u - delay) / (1 - delay)).clamp(0.0, 1.0);
        if (v <= 0) continue;
        canvas.drawCircle(
          c,
          cell * (0.18 + 0.6 * v),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, cell * width * (1 - v))
            ..color = Colors.white.withValues(alpha: 0.85 * (1 - v)),
        );
      }
      final dropFade = (1 - u * 1.4).clamp(0.0, 1.0);
      if (dropFade > 0) {
        final drop = Paint()..color = Colors.white.withValues(alpha: dropFade);
        for (var i = 0; i < 5; i++) {
          final a = -math.pi / 2 + (i - 2) * 0.55;
          final d = cell * (0.2 + 0.5 * u);
          canvas.drawCircle(
            c + Offset(math.cos(a) * d, math.sin(a) * d + cell * 0.5 * u * u),
            cell * 0.05,
            drop,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_SeaGridPainter old) =>
      old.spec.ships != spec.ships ||
      old.spec.resolved != spec.resolved ||
      old.spec.selected != spec.selected ||
      old.spec.shot?.t != spec.shot?.t ||
      old.spec.shot?.cell != spec.shot?.cell ||
      old.water != water;
}

// ---------------------------------------------------------------------------
// Chrome pieces
// ---------------------------------------------------------------------------

class _PlayerChip extends StatelessWidget {
  final String label;
  final Color accent;
  final bool active;
  final bool winner;

  const _PlayerChip({
    required this.label,
    required this.accent,
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
              border: Border.all(color: Colors.black26, width: 1),
              gradient: RadialGradient(
                center: const Alignment(-0.35, -0.4),
                colors: [
                  Color.lerp(accent, Colors.white, 0.4)!,
                  accent,
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

/// Enemy fleet tracker: one bar per ship, dimmed once sunk.
class _FleetStatusRow extends StatelessWidget {
  final List<int> sunkLengths;
  final Color color;

  const _FleetStatusRow({required this.sunkLengths, required this.color});

  @override
  Widget build(BuildContext context) {
    final remainingSunk = List<int>.of(sunkLengths);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        for (final len in SeaBattleGame.shipLengths)
          Builder(builder: (context) {
            final sunk = remainingSunk.remove(len);
            return Container(
              width: 7.0 * len + 5,
              height: 8,
              decoration: BoxDecoration(
                color: sunk
                    ? Colors.black.withValues(alpha: 0.30)
                    : color.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
      ],
    );
  }
}

class _FeltButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? fill;

  const _FeltButton({required this.label, required this.onTap, this.fill});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: fill ?? Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

/// Pass-and-play privacy cover shown between turns.
class _HandoffCover extends StatelessWidget {
  final String label;
  final VoidCallback onReady;

  const _HandoffCover({required this.label, required this.onReady});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onReady,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF25384C), Color(0xFF17222E)],
              ),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.waves_rounded,
                  color: Colors.white24,
                  size: 44,
                ),
                const SizedBox(height: 14),
                Text(
                  'Pass to $label',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tap when ready',
                  style: TextStyle(
                    color: Colors.white54,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
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
