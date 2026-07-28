import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigames_core/minigames_core.dart';
import 'package:minigames_ui/minigames_ui.dart';

import 'mancala_game.dart';
import 'mancala_marble.dart';
import 'mancala_pile.dart';
import 'mancala_sow.dart';
import 'mancala_style.dart';

/// Vertical 3D Mancala board with arcing marble sow physics.
///
/// Layout (portrait — two columns, sow CCW with flipped column directions):
/// ```
///        [ South store  6 ]   ← after right column tops out at 5
///      7          5
///      8          4
///      9          3
///     10          2
///     11          1
///     12          0
///        [ North store 13 ]   ← after left column bottoms out at 12
/// ```
/// Left (North): play **top → down** 7→12.
/// Right (South): play **bottom → up** 0→5.
/// Opposites share a row (0↔12, …, 5↔7).
class MancalaBoard extends StatefulWidget {
  final MatchController<MancalaState, MancalaMove> controller;
  final MancalaStyle style;

  const MancalaBoard({
    super.key,
    required this.controller,
    this.style = const MancalaStyle(),
  });

  @override
  State<MancalaBoard> createState() => _MancalaBoardState();
}

class _MancalaBoardState extends State<MancalaBoard>
    with TickerProviderStateMixin {
  static const _logic = MancalaGame();

  late AnimationController _entrance;
  late AnimationController _sowCtrl;
  late AnimationController _confettiCtrl;

  final math.Random _rnd = math.Random();
  StreamSubscription<MancalaState>? _sub;

  MancalaState? _state;
  GameOutcome? _outcome;

  /// Pit counts at the start of the active sow (before pickup).
  List<int> _fromPits = const [];
  int? _sowFrom;
  /// Each sow hop: hand travels as a cluster and drops one marble into [toCup].
  List<_HopStep> _hopSteps = const [];
  bool _sowExtra = false;
  bool _sowCapture = false;
  int _sowCaptured = 0;
  bool _sowing = false;

  /// End-of-game sweep: leftover (cup, count) pairs flying into [_sweepStore].
  List<(int, int)> _sweepMoves = const [];
  int _sweepStore = -1;

  /// Animation-driven sound/haptic cues for the active sow (cancel-safe:
  /// they die with the controller instead of firing from stale futures).
  int _dropsFired = 0;
  bool _captureCueFired = false;
  bool _extraCueFired = false;

  /// Outcome that arrived mid-sow; celebrated when the animation lands.
  GameOutcome? _pendingOutcome;

  /// "AGAIN!" is raised after an extra-turn sow. [GameNotice] owns the fade —
  /// it retracts itself via `autoDismiss` and stays down while this flag is
  /// still set, so the highlighted pits are unobstructed for the bonus pick.
  bool _showExtraPill = false;

  List<_Confetto> _confetti = const [];
  _BoardGeom? _geom;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _sowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    // Record the twelve marble pictures now rather than mid-hop.
    primeMarbles();
    _state = widget.controller.state;
    _outcome = _state == null ? null : _logic.outcome(_state!);
    _entrance.forward();
    _sowCtrl.addListener(_onSowTick);
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _entrance.dispose();
    _sowCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  void _onState(MancalaState state) {
    final style = widget.style;
    final outcome = _logic.outcome(state);
    final prev = _state;

    final isNewSow = prev != null &&
        state.lastPath.isNotEmpty &&
        (state.lastPit != prev.lastPit ||
            state.lastPath.join() != prev.lastPath.join() ||
            !_listEq(state.pits, prev.pits));

    if (isNewSow && state.lastPit != null) {
      _fromPits = List<int>.of(prev.pits);
      _sowFrom = state.lastPit;
      final plan = _planSow(
        startPits: _fromPits,
        from: state.lastPit!,
        before: prev,
      );
      _hopSteps = plan.hops;
      _sweepMoves = plan.sweep;
      _sweepStore = plan.sweepStore;
      _sowExtra = state.lastExtraTurn;
      _sowCapture = state.lastWasCapture;
      _sowCaptured = state.lastCaptured;
      _sowing = true;
      _dropsFired = 0;
      _captureCueFired = false;
      _extraCueFired = false;
      _showExtraPill = false;
      // Constant speed: every hop costs the same wall-clock time (no base
      // overhead amortized over hop count — that made short turns feel slow
      // and long turns feel rushed). GP-brisk: stones land in quick
      // succession; long relay chains stay watchable instead of draggy.
      const hopMs = 400; // == _kHopSeconds, the clock the drop is solved for.
      const captureMs = 620;
      const sweepMs = 780;
      final hops = math.max(1, _hopSteps.length);
      final captureBeats = state.lastWasCapture ? 1 : 0;
      final sweepBeats = _sweepMoves.isEmpty ? 0 : 1;
      final ms =
          hops * hopMs + captureBeats * captureMs + sweepBeats * sweepMs;
      _sowCtrl.duration = Duration(milliseconds: ms);
      _sowCtrl.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        setState(() {
          _sowing = false;
          // Raise "AGAIN!". The notice fades itself; the flag is cleared by
          // the next sow, so no timer is needed here.
          if (_sowExtra) _showExtraPill = true;
        });
        final done = _pendingOutcome;
        _pendingOutcome = null;
        if (done != null) _celebrate(state, done);
      });

      style.sounds.onSow?.call();
      if (style.haptics) HapticFeedback.lightImpact();
    }

    if (outcome != null && _outcome == null) {
      if (_sowing) {
        // Hold the fanfare until the last stone (and sweep) actually lands.
        _pendingOutcome = outcome;
      } else {
        _celebrate(state, outcome);
      }
    }

    setState(() {
      _state = state;
      _outcome = outcome;
    });
  }

  void _celebrate(MancalaState state, GameOutcome outcome) {
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

  /// Fire per-stone drop ticks and capture/extra cues off the animation
  /// clock, so cues stay in sync with the visuals and cancel with them.
  void _onSowTick() {
    if (!_sowing || _hopSteps.isEmpty) return;
    final style = widget.style;
    final hopCount = _hopSteps.length;
    final captureBeat = _sowCapture ? 1 : 0;
    final sweepBeat = _sweepMoves.isEmpty ? 0 : 1;
    final totalBeats = hopCount + captureBeat + sweepBeat;
    final pos = _sowCtrl.value * totalBeats;

    while (_dropsFired < hopCount && pos >= _dropsFired + _dropPoint) {
      _dropsFired++;
      style.sounds.onDrop?.call();
      if (style.haptics) HapticFeedback.selectionClick();
    }
    if (_sowCapture && !_captureCueFired && pos >= hopCount + 0.4) {
      _captureCueFired = true;
      style.sounds.onCapture?.call();
      if (style.haptics) HapticFeedback.mediumImpact();
    }
    if (_sowExtra && !_extraCueFired && _sowCtrl.value >= 0.9) {
      _extraCueFired = true;
      style.sounds.onExtraTurn?.call();
      if (style.haptics) HapticFeedback.selectionClick();
    }
  }

  bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<_Confetto> _spawnConfetti(MancalaState state, GameOutcome outcome) {
    final scheme = Theme.of(context).colorScheme;
    final winColor = outcome.winnerId == state.southId
        ? widget.style.resolveSouth(scheme)
        : widget.style.resolveNorth(scheme);
    final palette = [
      winColor,
      widget.style.resolveSeed(scheme),
      const Color(0xFF4FC3F7),
      const Color(0xFFF4B740),
    ];
    return List.generate(32, (i) {
      final angle = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 2.6;
      return _Confetto(
        angle: angle,
        speed: 0.4 + _rnd.nextDouble(),
        size: 0.012 + _rnd.nextDouble() * 0.016,
        color: palette[i % palette.length],
        spin: (_rnd.nextDouble() - 0.5) * 10,
        phase: _rnd.nextDouble() * math.pi,
      );
    });
  }

  void _onTapDown(Offset local) {
    final state = _state;
    final geom = _geom;
    if (state == null || _outcome != null || geom == null || _sowing) return;
    final pit = geom.hitTest(local);
    if (pit == null) return;
    if (!_logic.validateMove(
      state,
      MancalaMove(pit),
      state.currentPlayerId,
    )) {
      // GP-style "nope" on side pits only; stores are inert scenery.
      final isSidePit = pit != MancalaState.southStore &&
          pit != MancalaState.northStore;
      if (isSidePit) {
        widget.style.sounds.onInvalid?.call();
        if (widget.style.haptics) HapticFeedback.lightImpact();
      }
      return;
    }
    widget.controller.submitMove(MancalaMove(pit));
  }

  /// Point within a hop where the front stone crosses the pit mouth. Not a
  /// tuned constant: [SowPhysics.mouthFraction] reports where the simulated
  /// drop actually gets there, so the cue and the visual cannot drift apart.
  static final double _dropPoint = _kSow.mouthFraction(_kHopSeconds);

  /// Replay sow logic to build per-hop hand sizes for stack animation, plus
  /// the end-of-game sweep (leftover stones flying to the store), if any.
  ({List<_HopStep> hops, List<(int, int)> sweep, int sweepStore}) _planSow({
    required List<int> startPits,
    required int from,
    required MancalaState before,
  }) {
    final pits = List<int>.of(startPits);
    final playerId = before.currentPlayerId;
    final ownStore = before.storeOf(playerId);
    final oppStore = before.storeOf(before.opponentOf(playerId));

    final hops = <_HopStep>[];
    var cup = from;
    // Last cup the hand visually departed. When the sow passes the
    // opponent's store, the hop launches from here and arcs straight over
    // the store — the hand never stops at a cup it drops nothing into.
    var prev = from;
    var hand = pits[from];
    pits[from] = 0;
    var safety = 0;

    while (hand > 0 && safety < 256) {
      safety++;
      cup = (cup + 1) % MancalaState.pitCount;
      if (cup == oppStore) continue;
      final fromCup = prev;

      final handFlying = hand;
      pits[cup] += 1;
      hand -= 1;
      final nestIndex = pits[cup] - 1;

      var pickup = false;
      var handAfter = hand;
      if (hand == 0) {
        final isSide = cup != MancalaState.southStore &&
            cup != MancalaState.northStore;
        if (cup == ownStore) {
          // chain ends
        } else if (isSide && pits[cup] >= 2) {
          hand = pits[cup];
          pits[cup] = 0;
          pickup = true;
          handAfter = hand;
        }
      }

      hops.add(
        _HopStep(
          fromCup: fromCup,
          toCup: cup,
          handFlying: handFlying,
          nestIndex: nestIndex,
          pickupAfter: pickup,
          handAfterPickup: handAfter,
        ),
      );
      prev = cup;
    }

    // Capture (mirrors MancalaGame.applyMove) so sweep detection sees the
    // true post-move board.
    if (before.ownsPit(playerId, cup) && pits[cup] == 1) {
      final opp = MancalaState.opposite(cup);
      if (pits[opp] > 0) {
        pits[ownStore] += pits[opp] + 1;
        pits[opp] = 0;
        pits[cup] = 0;
      }
    }

    // End-of-game sweep: one side empty → the other side's leftovers fly
    // into that side's store.
    final southEmpty = pits.sublist(0, 6).every((n) => n == 0);
    final northEmpty = pits.sublist(7, 13).every((n) => n == 0);
    final sweep = <(int, int)>[];
    var sweepStore = -1;
    if (southEmpty && !northEmpty) {
      sweepStore = MancalaState.northStore;
      for (var i = 7; i < 13; i++) {
        if (pits[i] > 0) sweep.add((i, pits[i]));
      }
    } else if (northEmpty && !southEmpty) {
      sweepStore = MancalaState.southStore;
      for (var i = 0; i < 6; i++) {
        if (pits[i] > 0) sweep.add((i, pits[i]));
      }
    }

    return (hops: hops, sweep: sweep, sweepStore: sweepStore);
  }

  /// Build display pit counts + flying hand cluster for the current sow frame.
  _SowFrame _frame(double sowT) {
    final state = _state!;
    if (!_sowing || _sowFrom == null || _hopSteps.isEmpty || sowT >= 1) {
      return _SowFrame(
        pits: List<int>.of(state.pits),
        flyers: const [],
        highlight: -1,
        captureFlash: false,
        // Post-sow "AGAIN!" is timer-driven (_showExtraPill), not sticky.
        extraFlash: false,
      );
    }

    final hops = _hopSteps;
    final hopCount = hops.length;
    final captureBeat = _sowCapture ? 1 : 0;
    final sweepBeat = _sweepMoves.isEmpty ? 0 : 1;
    final totalBeats = hopCount + captureBeat + sweepBeat;
    final pos = sowT.clamp(0.0, 1.0) * totalBeats;
    final maxBeat = totalBeats > 0 ? totalBeats - 1 : 0;
    final beat = pos.floor().clamp(0, maxBeat);
    final localRaw = (pos - beat).clamp(0.0, 1.0);

    final from = _sowFrom!;
    final display = List<int>.of(_fromPits)..[from] = 0;

    // Apply completed deposits only.
    final deposited = pos >= hopCount ? hopCount : beat;
    for (var i = 0; i < deposited; i++) {
      display[hops[i].toCup] += 1;
      // If this hop picked up the stack, empty that cup again.
      if (hops[i].pickupAfter) {
        display[hops[i].toCup] = 0;
      }
    }

    final flyers = <_Flyer>[];
    var highlight = -1;
    var captureFlash = false;

    if (pos < hopCount) {
      final hop = hops[beat];
      highlight = hop.toCup;
      final handN = hop.handFlying;
      final release = _kSow.releaseAt;

      // Cluster offsets for the hand (tight pack in flight).
      final cluster = _handClusterOffsets(handN);

      for (var i = 0; i < handN; i++) {
        // The front stone is the one this hop lets go of.
        final isDropping = i == 0;
        final released = isDropping && localRaw >= release;

        var clusterOff = cluster[i];
        if (!isDropping && localRaw >= release) {
          // The hand closes up around the gap the released stone left.
          final peel = ((localRaw - release) / (1 - release)).clamp(0.0, 1.0);
          final remaining = _handClusterOffsets(handN - 1);
          final ri = i - 1;
          if (ri >= 0 && ri < remaining.length) {
            clusterOff = Offset.lerp(cluster[i], remaining[ri], peel)!;
          }
        }

        flyers.add(
          _Flyer(
            fromCup: hop.fromCup,
            toCup: hop.toCup,
            u: localRaw,
            spec: MarbleSpec.at(
              cup: hop.fromCup,
              slot: i,
              salt: beat * 17,
            ),
            opacity: 1,
            nestIndex: released ? hop.nestIndex : -1,
            clusterOffset: released ? Offset.zero : clusterOff,
            released: released,
            ballistic: true,
          ),
        );
      }
    } else if (_sowCapture && pos < hopCount + captureBeat) {
      final capLocal =
          ((pos - hopCount) / math.max(captureBeat, 1)).clamp(0.0, 1.0);
      final lastCup = hops.isNotEmpty ? hops.last.toCup : from;
      final opp = MancalaState.opposite(lastCup);
      final moverStore = from <= 5
          ? MancalaState.southStore
          : MancalaState.northStore;

      if (capLocal > 0.04) {
        display[lastCup] = 0;
        display[opp] = 0;
      }

      final nCap = _sowCaptured.clamp(1, 12);
      final storeBase = display[moverStore];
      final cluster = _handClusterOffsets(nCap);
      for (var i = 0; i < nCap; i++) {
        final lag = i * 0.05;
        final raw =
            ((capLocal - lag) / math.max(0.5, 1 - lag)).clamp(0.0, 1.0);
        if (raw <= 0) continue;
        final u = _hopCurve(raw);
        final fromCup = i == 0 ? lastCup : opp;
        final squash = raw > 0.8
            ? 1.0 -
                0.15 * math.sin(((raw - 0.8) / 0.2).clamp(0.0, 1.0) * math.pi)
            : 1.0;
        flyers.add(
          _Flyer(
            fromCup: fromCup,
            toCup: moverStore,
            t: u,
            tRaw: raw,
            spec: MarbleSpec.at(
              cup: moverStore,
              slot: storeBase + i,
              salt: fromCup,
            ),
            scaleX: 1.05 / squash,
            scaleY: squash,
            opacity: 1,
            nestIndex: storeBase + i,
            liftMul: 0.68,
            clusterOffset: cluster[i] * (1 - raw),
          ),
        );
      }
      captureFlash = capLocal > 0.4;
      highlight = moverStore;
    } else if (_sweepMoves.isNotEmpty) {
      // Sweep beat: the losing-side board is empty, so the other side's
      // leftovers cascade into their store instead of teleporting.
      // Settle the capture (if any) into the display first.
      if (_sowCapture) {
        final lastCup = hops.isNotEmpty ? hops.last.toCup : from;
        final opp = MancalaState.opposite(lastCup);
        final moverStore = from <= 5
            ? MancalaState.southStore
            : MancalaState.northStore;
        display[moverStore] += display[lastCup] + display[opp];
        display[lastCup] = 0;
        display[opp] = 0;
      }

      final sweepLocal = (pos - hopCount - captureBeat).clamp(0.0, 1.0);
      final store = _sweepStore;
      final storeBase = display[store];
      var idx = 0;
      var cupIdx = 0;
      for (final (cup, count) in _sweepMoves) {
        final cluster = _handClusterOffsets(count);
        final cupLag = (cupIdx * 0.10).clamp(0.0, 0.40);
        var departed = false;
        for (var k = 0; k < count; k++) {
          final lag = (cupLag + k * 0.03).clamp(0.0, 0.55);
          final raw =
              ((sweepLocal - lag) / math.max(0.4, 1 - lag)).clamp(0.0, 1.0);
          final nest = storeBase + idx;
          idx++;
          if (raw <= 0) continue;
          departed = true;
          final squash = raw > 0.8
              ? 1.0 -
                  0.15 *
                      math.sin(((raw - 0.8) / 0.2).clamp(0.0, 1.0) * math.pi)
              : 1.0;
          flyers.add(
            _Flyer(
              fromCup: cup,
              toCup: store,
              t: _hopCurve(raw),
              tRaw: raw,
              spec: MarbleSpec.at(cup: store, slot: nest, salt: cup),
              scaleX: 1.05 / squash,
              scaleY: squash,
              opacity: 1,
              nestIndex: nest,
              liftMul: 0.68,
              clusterOffset: cluster[k] * (1 - raw),
            ),
          );
        }
        if (departed) display[cup] = 0;
        cupIdx++;
      }
      highlight = store;
    }

    if (pos >= totalBeats - 0.002) {
      return _SowFrame(
        pits: List<int>.of(state.pits),
        flyers: const [],
        highlight: -1,
        captureFlash: _sowCapture,
        extraFlash: _sowExtra,
      );
    }

    return _SowFrame(
      pits: display,
      flyers: flyers,
      highlight: highlight,
      captureFlash: captureFlash,
      extraFlash: _sowExtra && sowT > 0.9,
    );
  }

  /// Compact cluster layout for N stones in the flying hand.
  static List<Offset> _handClusterOffsets(int n) {
    if (n <= 0) return const [];
    if (n == 1) return [Offset.zero];
    final out = <Offset>[];
    // Slightly larger spacing so the stack reads while airborne.
    const spacing = 5.5;
    for (var i = 0; i < n; i++) {
      final ang = -math.pi / 2 + i * (2 * math.pi / n);
      final rad = spacing * (0.55 + 0.12 * n.clamp(1, 8));
      out.add(Offset(math.cos(ang) * rad, math.sin(ang) * rad * 0.75));
    }
    return out;
  }

  /// Ease for a single hop: longer apex hang, softer landing.
  static double _hopCurve(double t) {
    final x = t.clamp(0.0, 1.0);
    if (x < 0.40) {
      return 0.5 * Curves.easeOutCubic.transform(x / 0.40);
    }
    return 0.5 + 0.5 * Curves.easeInCubic.transform((x - 0.40) / 0.60);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final state = _state;
    if (state == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final boardColor = style.resolveBoard(scheme);
    final pitColor = style.resolvePit(scheme);
    final south = style.resolveSouth(scheme);
    final north = style.resolveNorth(scheme);

    final legal = (!_sowing && _outcome == null)
        ? _logic.legalPits(state, state.currentPlayerId).toSet()
        : <int>{};

    final table = style.resolveTable(scheme);

    return AnimatedBuilder(
      animation: Listenable.merge([_entrance, _sowCtrl, _confettiCtrl]),
      builder: (context, _) {
        final enter = Curves.easeOutCubic.transform(_entrance.value);
        final frame = _frame(_sowCtrl.value);
        final showOutcome = !_sowing ? _outcome : null;

        // GP-style translucent pill floating over the board center for
        // transient events; turn state lives on the side players.
        String? pillMsg;
        if (showOutcome != null) {
          pillMsg = showOutcome.isDraw
              ? 'DRAW'
              : (showOutcome.winnerId == state.southId
                      ? '${style.southLabel} wins'
                      : '${style.northLabel} wins')
                  .toUpperCase();
        } else if (frame.extraFlash || _showExtraPill) {
          pillMsg = 'AGAIN!';
        }

        final board = ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: Transform.scale(
            scale: 0.94 + 0.06 * enter,
            child: Opacity(
              opacity: enter.clamp(0.0, 1.0),
              child: AspectRatio(
                // Slim GP tray: ~3.1 units wide × ~10.3 tall.
                aspectRatio: 0.31,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final geom = _BoardGeom(Size(c.maxWidth, c.maxHeight));
                    _geom = geom;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _onTapDown(d.localPosition),
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: Size(c.maxWidth, c.maxHeight),
                            painter: _MancalaPainter(
                              pits: frame.pits,
                              geom: geom,
                              boardColor: boardColor,
                              pitColor: pitColor,
                              legal: legal,
                              highlight: frame.highlight,
                              captureFlash: frame.captureFlash,
                              flyers: frame.flyers,
                              tick: _sowCtrl.value,
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

        // Felt table the board sits on.
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _SidePlayer(
                label: style.northLabel,
                score: frame.pits[MancalaState.northStore],
                color: north,
                active: showOutcome == null &&
                    state.currentPlayerId == state.northId,
                winner: showOutcome?.isWin == true &&
                    showOutcome!.winnerId == state.northId,
              ),
              const SizedBox(width: 8),
              Stack(
                alignment: Alignment.center,
                children: [
                  board,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        // Single animating node. "AGAIN!" fires on consecutive
                        // extra turns, so the message genuinely repeats inside
                        // one exit — an AnimatedSwitcher keyed on the text put
                        // two live 'AGAIN!' children in its Stack and threw.
                        // No accent override: the seat colours are dark on the
                        // notice's dark fill, so passing one to say *who* just
                        // erased the underline that says *what*. The side
                        // players already carry the seat.
                        child: GameNotice(
                          message: pillMsg,
                          tone: showOutcome != null
                              ? GameNoticeTone.win
                              : GameNoticeTone.score,
                          strong: showOutcome != null,
                          // Sticky on a result; the extra-turn call retracts
                          // itself, which is what the old _pillTimer did.
                          autoDismiss: showOutcome != null
                              ? null
                              : const Duration(milliseconds: 900),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              _SidePlayer(
                label: style.southLabel,
                score: frame.pits[MancalaState.southStore],
                color: south,
                active: showOutcome == null &&
                    state.currentPlayerId == state.southId,
                winner: showOutcome?.isWin == true &&
                    showOutcome!.winnerId == state.southId,
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

/// Wall clock of a single sow hop, and the physics the drop is solved against.
/// Both live here so the timing the controller schedules and the trajectory the
/// painter draws come from one place.
const double _kHopSeconds = 0.400;
const SowPhysics _kSow = SowPhysics();

/// One hop of a sow: [handFlying] stones leave [fromCup] for [toCup]; one drops.
class _HopStep {
  final int fromCup;
  final int toCup;
  /// Stones in the hand while this hop is airborne (before the drop).
  final int handFlying;
  /// Nest index of the stone deposited into [toCup].
  final int nestIndex;
  /// After the drop, the whole stack at [toCup] was picked up to continue.
  final bool pickupAfter;
  final int handAfterPickup;

  const _HopStep({
    required this.fromCup,
    required this.toCup,
    required this.handFlying,
    required this.nestIndex,
    required this.pickupAfter,
    required this.handAfterPickup,
  });
}

/// A stone in the air.
///
/// Two kinds, deliberately not unified. [ballistic] flyers are the sow itself —
/// the hand and the stone it lets go of, driven by [SowPhysics]. The others are
/// the capture and end-of-game sweeps, which are a flourish rather than a hand
/// sowing, and keep the eased screen arc that suits them.
class _Flyer {
  final int fromCup;
  final int toCup;
  final MarbleSpec spec;
  final double opacity;

  /// Landing slot in the destination pit; -1 while still in the hand.
  final int nestIndex;

  /// Offset within the flying hand cluster (screen px).
  final Offset clusterOffset;

  // --- ballistic sow ---
  final bool ballistic;

  /// 0..1 through the hop.
  final double u;

  /// The hand has opened and this stone is falling.
  final bool released;

  // --- eased arc (capture / sweep) ---
  final double t; // eased along arc 0..1
  final double tRaw; // raw time for squash
  final double scaleX;
  final double scaleY;
  final double liftMul;

  const _Flyer({
    required this.fromCup,
    required this.toCup,
    required this.spec,
    required this.opacity,
    required this.nestIndex,
    this.clusterOffset = Offset.zero,
    this.ballistic = false,
    this.u = 0,
    this.released = false,
    this.t = 0,
    this.tRaw = 0,
    this.scaleX = 1,
    this.scaleY = 1,
    this.liftMul = 0.58,
  });
}

class _SowFrame {
  final List<int> pits;
  final List<_Flyer> flyers;
  final int highlight;
  final bool captureFlash;
  final bool extraFlash;

  const _SowFrame({
    required this.pits,
    required this.flyers,
    required this.highlight,
    required this.captureFlash,
    required this.extraFlash,
  });
}

// ---------------------------------------------------------------------------
// Geometry — vertical board like a real/GP tray stood on end:
// one wood slab, carved wells, fat end-stores, tight land between cups.
// ---------------------------------------------------------------------------

class _BoardGeom {
  final Size size;
  late final Rect tray;
  late final double cornerR;
  late final double pitD;
  late final double land; // wood between cup rims
  late final Rect northStore;
  late final Rect southStore;
  late final List<Rect> cups; // length 14

  _BoardGeom(this.size) {
    // Canvas inset so drop-shadow has room.
    final canvasPad = size.width * 0.03;
    final maxTray = Rect.fromLTWH(
      canvasPad,
      canvasPad * 0.8,
      size.width - canvasPad * 2,
      size.height - canvasPad * 1.6,
    );

    // Unit system tuned to GP proportions: slim board, fat pits, thin rails
    // with plain numerals sitting on them (no badge chips).
    const sideRailU = 0.44;
    const endRailU = 0.34;
    const landU = 0.24;
    const storeU = 0.95;
    const bridgeU = 0.24;
    const colLandU = 0.22;
    // height: 2*endRail + 2*store + 2*bridge + 6*pit + 5*land
    const hU = 2 * endRailU + 2 * storeU + 2 * bridgeU + 6 + 5 * landU;
    // width: 2*sideRail + 2*pit + colLand
    const wU = 2 * sideRailU + 2 + colLandU;

    pitD = math.min(maxTray.width / wU, maxTray.height / hU);
    land = pitD * landU;
    final sideRail = pitD * sideRailU;
    final endRail = pitD * endRailU;
    final storeH = pitD * storeU;
    final bridge = pitD * bridgeU;
    final colLand = pitD * colLandU;

    final contentW = 2 * sideRail + 2 * pitD + colLand;
    final contentH =
        2 * endRail + 2 * storeH + 2 * bridge + 6 * pitD + 5 * land;

    // Center content block in canvas.
    final origin = Offset(
      maxTray.left + (maxTray.width - contentW) / 2,
      maxTray.top + (maxTray.height - contentH) / 2,
    );
    tray = Rect.fromLTWH(origin.dx, origin.dy, contentW, contentH);
    // Gently rounded corners (GP board is a slab, not a stadium).
    cornerR = contentW * 0.13;

    final pairW = 2 * pitD + colLand;
    final storeW = pairW; // stores align with the pit pair
    final storeX = tray.left + sideRail;
    final pitsX = tray.left + sideRail;

    // Flipped column directions reverse which store belongs on which end:
    // CCW path is 0↑…5 → south store → 7↓…12 → north store → 0.
    // So south store sits at the TOP (exit of right column), north at BOTTOM.
    southStore = Rect.fromLTWH(
      storeX,
      tray.top + endRail,
      storeW,
      storeH,
    );
    northStore = Rect.fromLTWH(
      storeX,
      tray.bottom - endRail - storeH,
      storeW,
      storeH,
    );

    final fieldTop = southStore.bottom + bridge;
    final lx = pitsX;
    final rx = pitsX + pitD + colLand;

    cups = List<Rect>.filled(14, Rect.zero);
    cups[MancalaState.northStore] = northStore;
    cups[MancalaState.southStore] = southStore;

    // Left North top→down 7..12; right South bottom→up (visual 5..0).
    for (var i = 0; i < 6; i++) {
      final y = fieldTop + i * (pitD + land);
      cups[7 + i] = Rect.fromLTWH(lx, y, pitD, pitD);
      cups[5 - i] = Rect.fromLTWH(rx, y, pitD, pitD);
    }
  }

  Offset center(int cup) => cups[cup].center;

  int? hitTest(Offset p) {
    for (var i = 0; i < 6; i++) {
      if (cups[i].inflate(pitD * 0.12).contains(p)) return i;
      if (cups[7 + i].inflate(pitD * 0.12).contains(p)) return 7 + i;
    }
    if (northStore.inflate(2).contains(p)) return MancalaState.northStore;
    if (southStore.inflate(2).contains(p)) return MancalaState.southStore;
    return null;
  }

  /// Arc position from cup A → B at t∈[0,1], with height proportional to distance.
  Offset arc(int from, int to, double t) {
    final a = center(from);
    final b = center(to);
    final mid = Offset.lerp(a, b, t)!;
    final dist = (b - a).distance;
    final lift = dist * 0.48 * math.sin(math.pi * t.clamp(0.0, 1.0));
    return Offset(mid.dx, mid.dy - lift);
  }
}

// ---------------------------------------------------------------------------
// Materials
//
// One committed light for the whole board: a soft key from the upper left.
// Raised forms get their highlight up-left and cast down-right; the carved
// wells reverse both, so their shadow pools under the top-left rim and the
// light catches the far bottom-right lip.
// ---------------------------------------------------------------------------

/// The board and the marbles must obey the *same* light or neither reads as
/// solid, so this is [kBoardLight] — the direction the sphere shader evaluates
/// against — rather than a second, independently tuned number.
const Offset _kLight = kBoardLight;

/// Deterministic hash in `[0, 1)` — the grain and nap must be identical on
/// every rebuild, so nothing in painting uses `Random`.
double _noise(int x, int y, int seed) {
  var n = (x * 374761393) ^ (y * 668265263) ^ (seed * 1274126177);
  n = (n ^ (n >> 13)) * 1274126177;
  n = n ^ (n >> 16);
  return (n & 0x3fffffff) / 0x3fffffff;
}

/// The rounded rect of a side pit's scoop.
RRect _pitWellRRect(Rect rect) {
  final r = rect.shortestSide / 2;
  return RRect.fromRectAndRadius(
    Rect.fromCenter(center: rect.center, width: r * 2, height: r * 1.92),
    Radius.circular(r),
  );
}

/// The rounded rect of an end store's scoop.
RRect _storeWellRRect(Rect rect) => RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.shortestSide * 0.48),
    );

/// Cached carved slab (grain, wells, rims), keyed on size and palette.
class _Tray {
  final double w;
  final double h;
  final int board;
  final int pit;
  final ui.Picture picture;

  _Tray(this.w, this.h, this.board, this.pit, this.picture);

  bool matches(Size s, Color b, Color p) =>
      w == s.width &&
      h == s.height &&
      // ignore: deprecated_member_use
      board == b.value &&
      // ignore: deprecated_member_use
      pit == p.value;
}

final List<_Tray> _trays = [];

ui.Picture _trayFor(Size size, _BoardGeom geom, Color board, Color pit) {
  for (final t in _trays) {
    if (t.matches(size, board, pit)) return t.picture;
  }
  final recorder = ui.PictureRecorder();
  _paintTray(Canvas(recorder), geom, board, pit);
  final made = _Tray(
    size.width,
    size.height,
    // ignore: deprecated_member_use
    board.value,
    // ignore: deprecated_member_use
    pit.value,
    recorder.endRecording(),
  );
  _trays.insert(0, made);
  while (_trays.length > 3) {
    _trays.removeLast().picture.dispose();
  }
  return made.picture;
}

/// A single piece of carved hardwood: the slab with its thickness and grain,
/// then every well scooped out of it.
void _paintTray(Canvas canvas, _BoardGeom geom, Color board, Color pit) {
  final tray = geom.tray;
  final edge = tray.width * 0.075;
  final radius = Radius.circular(geom.cornerR);
  final top = RRect.fromRectAndRadius(tray, radius);
  final sideFace = RRect.fromRectAndRadius(
    Rect.fromLTWH(tray.left, tray.top + edge, tray.width, tray.height),
    radius,
  );
  final edgeWood = Color.lerp(board, const Color(0xFF6B4A22), 0.46)!;

  // Contact shadow: tight dark core at the seam plus a wide ambient falloff,
  // both pushed away from the key light.
  canvas.drawRRect(
    sideFace.shift(Offset(tray.width * 0.020, tray.width * 0.030)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.30)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, tray.width * 0.055),
  );
  canvas.drawRRect(
    sideFace.shift(Offset(tray.width * 0.008, tray.width * 0.012)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.26)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, tray.width * 0.016),
  );

  // Side face — the board's thickness.
  canvas.drawRRect(
    sideFace,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [edgeWood, Color.lerp(edgeWood, Colors.black, 0.40)!],
      ).createShader(sideFace.outerRect),
  );

  // Top face.
  canvas.save();
  canvas.clipRRect(top);
  canvas.drawRect(tray, Paint()..color = board);

  // Broad growth bands drifting across the grain.
  for (var i = 0; i < 16; i++) {
    final j = _noise(i, 3, 11);
    final x = tray.left + (i / 16) * tray.width + (j - 0.5) * tray.width * 0.03;
    final w = tray.width * (0.03 + j * 0.07);
    final d = (_noise(i, 3, 23) - 0.5) * 0.10;
    canvas.drawRect(
      Rect.fromLTWH(x, tray.top, w, tray.height),
      Paint()
        ..color = (d < 0
                ? Color.lerp(board, Colors.white, -d)!
                : Color.lerp(board, const Color(0xFF6B4A22), d)!)
            .withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, tray.width * 0.03),
    );
  }

  // Fine fibres running the length of the slab.
  final fibre = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final count = (tray.width / 2.6).round().clamp(30, 140);
  for (var i = 0; i < count; i++) {
    final j = _noise(i, 5, 37);
    final k = _noise(i, 5, 53);
    final x = tray.left + ((i + j) / count) * tray.width;
    final bend = (k - 0.5) * tray.width * 0.05;
    fibre
      ..strokeWidth = 0.5 + j * 0.9
      ..color = (k > 0.6
              ? Color.lerp(board, const Color(0xFF4A3315), 0.42)!
              : Color.lerp(board, Colors.white, 0.30)!)
          .withValues(alpha: 0.04 + j * 0.07);
    canvas.drawPath(
      Path()
        ..moveTo(x, tray.top)
        ..quadraticBezierTo(
            x + bend, tray.center.dy, x + bend * 0.3, tray.bottom),
      fibre,
    );
  }

  // Key-light wash across the face.
  canvas.drawRect(
    tray,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment(_kLight.dx * 2.2, _kLight.dy * 2.0),
        end: Alignment(-_kLight.dx * 2.2, -_kLight.dy * 2.0),
        colors: [
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.0),
          Colors.black.withValues(alpha: 0.16),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(tray),
  );
  canvas.restore();

  // Chamfer: lit lip up-left, dark lip down-right.
  canvas.drawRRect(
    top.deflate(tray.width * 0.006),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = tray.width * 0.012
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.36),
          Colors.white.withValues(alpha: 0.04),
          Colors.black.withValues(alpha: 0.20),
        ],
      ).createShader(tray),
  );

  // Wells, scooped out of the same stock.
  for (var i = 0; i < 6; i++) {
    _paintCarvedWell(canvas, _pitWellRRect(geom.cups[i]), geom, board, pit);
    _paintCarvedWell(canvas, _pitWellRRect(geom.cups[7 + i]), geom, board, pit);
  }
  _paintCarvedWell(
      canvas, _storeWellRRect(geom.northStore), geom, board, pit);
  _paintCarvedWell(
      canvas, _storeWellRRect(geom.southStore), geom, board, pit);
}

/// A scoop routed into the slab. Depth comes from three stacked cues: the
/// occluded wall under the top-left rim, the lit far wall at bottom-right,
/// and a rim that is dark where it is undercut and bright where it catches
/// the key.
void _paintCarvedWell(
  Canvas canvas,
  RRect well,
  _BoardGeom geom,
  Color board,
  Color pit,
) {
  final rect = well.outerRect;
  final lip = math.max(1.2, geom.pitD * 0.05);

  // Cast shadow of the rim onto the wood just outside the well, opposite the
  // key — a routed edge throws a little shade of its own.
  canvas.drawRRect(
    well.shift(Offset(-_kLight.dx * lip * 0.8, -_kLight.dy * lip * 0.8)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.10)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, lip * 1.2),
  );

  // Scoop floor: same wood, one step cooler, dark under the near wall.
  canvas.drawRRect(
    well,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment(_kLight.dx * 1.6, _kLight.dy * 1.6),
        end: Alignment(-_kLight.dx * 1.6, -_kLight.dy * 1.6),
        colors: [
          Color.lerp(pit, const Color(0xFF4A3315), 0.42)!,
          Color.lerp(pit, const Color(0xFF6B573A), 0.14)!,
          pit,
          Color.lerp(pit, Colors.white, 0.22)!,
        ],
        stops: const [0.0, 0.34, 0.72, 1.0],
      ).createShader(rect),
  );

  canvas.save();
  canvas.clipRRect(well);
  // Occlusion pooling against the near wall.
  canvas.drawOval(
    Rect.fromLTWH(
      rect.left - rect.width * 0.14,
      rect.top - rect.height * 0.40,
      rect.width * 1.28,
      rect.height * 0.72,
    ),
    Paint()
      ..color = const Color(0xFF3A2A14).withValues(alpha: 0.34)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, lip * 2.6),
  );
  // Light climbing the far wall.
  canvas.drawOval(
    Rect.fromLTWH(
      rect.left + rect.width * 0.06,
      rect.bottom - rect.height * 0.26,
      rect.width * 0.88,
      rect.height * 0.36,
    ),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.26)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, lip * 2.0),
  );
  canvas.restore();

  // Rim: undercut and dark on the key side, catching light on the far side.
  canvas.drawRRect(
    well,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lip * 0.75
      ..shader = LinearGradient(
        begin: Alignment(_kLight.dx * 1.6, _kLight.dy * 1.6),
        end: Alignment(-_kLight.dx * 1.6, -_kLight.dy * 1.6),
        colors: [
          const Color(0xFF4A3315).withValues(alpha: 0.42),
          const Color(0xFF6B573A).withValues(alpha: 0.14),
          Colors.white.withValues(alpha: 0.34),
        ],
      ).createShader(rect),
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
// Painter
// ---------------------------------------------------------------------------

class _MancalaPainter extends CustomPainter {
  final List<int> pits;
  final _BoardGeom geom;
  final Color boardColor;
  final Color pitColor;
  final Set<int> legal;
  final int highlight;
  final bool captureFlash;
  final List<_Flyer> flyers;
  final double tick;

  _MancalaPainter({
    required this.pits,
    required this.geom,
    required this.boardColor,
    required this.pitColor,
    required this.legal,
    required this.highlight,
    required this.captureFlash,
    required this.flyers,
    required this.tick,
  });

  double get _baseMarbleR => geom.pitD * 0.145;

  @override
  void paint(Canvas canvas, Size size) {
    // The carved slab never moves: grain, wells and rims come from one cached
    // picture, leaving only the state rings and the stones per frame.
    canvas.drawPicture(_trayFor(size, geom, boardColor, pitColor));
    for (var i = 0; i < 6; i++) {
      _paintWellRing(canvas, _pitWellRRect(geom.cups[i]),
          hi: highlight == i, legal: legal.contains(i));
      _paintWellRing(canvas, _pitWellRRect(geom.cups[7 + i]),
          hi: highlight == 7 + i, legal: legal.contains(7 + i));
    }
    for (final cup in const [
      MancalaState.northStore,
      MancalaState.southStore,
    ]) {
      _paintWellRing(canvas, _storeWellRRect(geom.cups[cup]),
          hi: highlight == cup, legal: false);
    }
    for (var i = 0; i < 14; i++) {
      _paintMarblesInCup(canvas, i, pits[i]);
    }
    // Count badges after stones so they stay readable.
    for (var i = 0; i < 14; i++) {
      _paintCountBadge(canvas, i, pits[i]);
    }
    for (final f in flyers) {
      if (f.ballistic) {
        _paintSownStone(canvas, f);
      } else {
        _paintArcedStone(canvas, f);
      }
    }
  }

  /// A stone in the hand, or falling out of it into a pit.
  ///
  /// The hand's travel is an eased carry — a hand is not a projectile. The
  /// moment it opens, the stone becomes one: position, altitude and the frame
  /// it enters the pit all come from the simulation in [dropFor].
  void _paintSownStone(Canvas canvas, _Flyer f) {
    final pitD = geom.pitD;
    final origin = geom.center(f.fromCup);
    final to = (geom.center(f.toCup) - origin) / pitD;

    late Offset ground;
    late double height;
    var r = _baseMarbleR * f.spec.sizeMul;

    if (f.released && f.nestIndex >= 0) {
      final total = math.max(pits[f.toCup], f.nestIndex) + 1;
      final slot = _nestSlot(f.toCup, f.nestIndex, total);
      final drop = dropFor(
        from: Offset.zero,
        to: to,
        rest: (slot.centre - origin) / pitD,
        hopSeconds: _kHopSeconds,
        physics: _kSow,
      );
      final t = (f.u - _kSow.releaseAt) * _kHopSeconds;
      ground = origin + drop.groundAt(t) * pitD;
      height = drop.heightAt(t) * pitD;
      // Ease into the slot's pile scale as it settles, so it does not pop.
      final k = (t / math.max(drop.totalTime, 1e-3)).clamp(0.0, 1.0);
      r *= 1.0 + (slot.scale - 1.0) * k;
    } else {
      ground = origin +
          handGroundAt(Offset.zero, to, f.u, _kSow) * pitD +
          Offset(f.clusterOffset.dx, 0);
      height = handHeightAt(f.u, _kSow) * pitD - f.clusterOffset.dy;
    }

    // The cast shadow tracks the stone's real altitude: tight and dark on the
    // floor, wide and faint at carry height.
    final lift = (height / (pitD * _kSow.handHeight)).clamp(0.0, 1.4);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          ground.dx - _kLight.dx * r * 0.4,
          ground.dy + r * 0.42,
        ),
        width: r * (1.5 + 0.9 * lift),
        height: r * (0.48 + 0.30 * lift),
      ),
      Paint()
        ..color = Colors.black
            .withValues(alpha: (0.34 - 0.18 * lift) * f.opacity)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, r * (0.18 + 0.5 * lift)),
    );

    paintMarble(
      canvas,
      Offset(ground.dx, ground.dy - height),
      r,
      f.spec,
      opacity: f.opacity,
    );
  }

  /// Capture and end-of-game sweeps: an eased screen arc into the store.
  void _paintArcedStone(Canvas canvas, _Flyer f) {
    final r0 = _baseMarbleR * f.spec.sizeMul;
    final start = geom.center(f.fromCup);
    final end = f.nestIndex >= 0
        ? _nestSlot(
            f.toCup,
            f.nestIndex,
            math.max(pits[f.toCup], f.nestIndex) + 1,
          ).centre
        : geom.center(f.toCup);
    final mid = Offset.lerp(start, end, f.t)!;
    final dist = (end - start).distance;
    final lift = dist * f.liftMul * math.sin(math.pi * f.tRaw.clamp(0.0, 1.0));
    final cluster = f.clusterOffset * 0.35;
    final p = Offset(mid.dx + cluster.dx, mid.dy - lift + cluster.dy);
    final shadowY = 2.5 + 11 * math.sin(math.pi * f.tRaw.clamp(0.0, 1.0));
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.scale(f.scaleX, f.scaleY);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, r0 * 0.55 + shadowY * 0.15),
        width: r0 * 1.7,
        height: r0 * 0.55,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20 * f.opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r0 * 0.45),
    );
    paintMarble(canvas, Offset.zero, r0, f.spec, opacity: f.opacity);
    canvas.restore();
  }

  /// The well a pile occupies, in the ellipse [pileLayout] packs into.
  ({Offset centre, double rx, double ry}) _well(int cup) {
    final rect = geom.cups[cup];
    final isStore =
        cup == MancalaState.southStore || cup == MancalaState.northStore;
    return (
      centre: rect.center,
      rx: isStore ? rect.width * 0.38 : rect.shortestSide * 0.40,
      ry: isStore ? rect.height * 0.36 : rect.shortestSide * 0.40,
    );
  }

  PileLayout _pile(int cup, int count) {
    final w = _well(cup);
    return pileLayout(
      count: count,
      centre: w.centre,
      wellRx: w.rx,
      wellRy: w.ry,
      marbleR: _baseMarbleR,
      seed: cup * 19,
    );
  }

  PileSlot _nestSlot(int cup, int index, int total) {
    final pile = _pile(cup, math.max(total, index + 1));
    if (pile.slots.isEmpty) {
      return PileSlot(
        centre: geom.cups[cup].center,
        scale: 1,
        nearness: 0.5,
        course: 0,
        occlusion: 0,
        occlusionFrom: Offset.zero,
      );
    }
    return pile.slots[index.clamp(0, pile.slots.length - 1)];
  }

  /// Just the state ring on a well rim; everything else is in the cached
  /// picture. Kept quiet on purpose — GP shows nothing, hot-seat needs a hint.
  void _paintWellRing(
    Canvas canvas,
    RRect well, {
    required bool hi,
    required bool legal,
  }) {
    if (!hi && !legal) return;
    final lip = math.max(1.2, geom.pitD * 0.05);
    canvas.drawRRect(
      well.inflate(lip * 0.3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hi ? lip * 1.0 : lip * 0.7
        ..color = const Color(0xFF8B6F47).withValues(alpha: hi ? 0.85 : 0.42),
    );
  }

  void _paintMarblesInCup(Canvas canvas, int cup, int count) {
    if (count <= 0) return;
    final isStore =
        cup == MancalaState.southStore || cup == MancalaState.northStore;
    final show = count.clamp(1, isStore ? 20 : 10);
    final pile = _pile(cup, show);
    if (pile.slots.isEmpty) return;

    // 1 — the pile's own shade pooled on the scoop floor. One soft mass, not
    // a shadow per stone: a heap of stones darkens the wood as one object.
    final well = _well(cup);
    canvas.save();
    canvas.clipRRect(
      isStore
          ? _storeWellRRect(geom.cups[cup])
          : _pitWellRRect(geom.cups[cup]),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: well.centre +
            Offset(-_kLight.dx * _baseMarbleR * 0.5, _baseMarbleR * 0.55),
        width: well.rx * (1.1 + 0.5 * (show / 6).clamp(0.0, 1.0)),
        height: well.ry * (0.9 + 0.5 * (show / 6).clamp(0.0, 1.0)),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, _baseMarbleR * 0.9),
    );

    // 2 — crevice occlusion where stones touch. Drawn under the stones so it
    // only survives in the gaps, which is exactly where a real pile is darkest
    // and what stops the heap reading as overlapping cutouts.
    for (final c in pile.contacts) {
      canvas.drawCircle(
        c.at,
        c.radius,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.42 * c.strength)
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, c.radius * 0.55),
      );
    }
    canvas.restore();

    // 3 — the stones themselves, far wall of the scoop first.
    for (final i in pile.order) {
      final slot = pile.slots[i];
      final spec = MarbleSpec.at(cup: cup, slot: i);
      final r = _baseMarbleR * spec.sizeMul * slot.scale;

      // Contact shadow: a tight dark core where the stone meets what is under
      // it, softening outward. Stones riding a course cast onto the stones
      // below rather than the wood, so theirs is tighter and darker.
      final tight = slot.course > 0 ? 0.34 : 0.26;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(
            slot.centre.dx - _kLight.dx * r * 0.26,
            slot.centre.dy + r * (slot.course > 0 ? 0.62 : 0.48),
          ),
          width: r * 1.42,
          height: r * 0.46,
        ),
        Paint()
          ..color = Colors.black.withValues(alpha: tight)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.20),
      );

      paintMarble(
        canvas,
        slot.centre,
        r,
        spec,
        occlusion: slot.occlusion,
        occlusionFrom: slot.occlusionFrom,
      );
    }

    // Overflow count is handled by the side badge, not an overlay on stones.
  }

  /// Plain GP-style numeral sitting directly on the wood rail — no chip.
  void _paintCountBadge(Canvas canvas, int cup, int count) {
    final rect = geom.cups[cup];
    final isStore =
        cup == MancalaState.southStore || cup == MancalaState.northStore;
    final isNorthCol = cup >= 7 && cup <= 12;
    final isSouthCol = cup >= 0 && cup <= 5;
    final fontSize = geom.pitD * (isStore ? 0.30 : 0.28);

    // Side pits: mid-rail beside the cup. Stores: tucked into the board
    // corner GP-style (top store → top-right, bottom store → bottom-left).
    late Offset anchor;
    if (isStore) {
      if (cup == MancalaState.southStore) {
        anchor = Offset(
          rect.right - fontSize * 0.7,
          (geom.tray.top + rect.top) / 2,
        );
      } else {
        anchor = Offset(
          rect.left + fontSize * 0.7,
          (rect.bottom + geom.tray.bottom) / 2,
        );
      }
    } else if (isNorthCol) {
      anchor = Offset((geom.tray.left + rect.left) / 2, rect.center.dy);
    } else if (isSouthCol) {
      anchor = Offset((rect.right + geom.tray.right) / 2, rect.center.dy);
    } else {
      anchor = rect.center;
    }

    final tp = TextPainter(
      text: TextSpan(
        text: '$count',
        style: TextStyle(
          color: count == 0
              ? const Color(0xFF6B5D45).withValues(alpha: 0.40)
              : const Color(0xFF6B5D45).withValues(alpha: 0.88),
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    tp.paint(
      canvas,
      Offset(anchor.dx - tp.width / 2, anchor.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(_MancalaPainter old) =>
      old.pits != pits ||
      old.highlight != highlight ||
      old.captureFlash != captureFlash ||
      old.legal != legal ||
      old.flyers != flyers ||
      old.tick != tick ||
      old.boardColor != boardColor;
}

// ---------------------------------------------------------------------------
// Side players
// ---------------------------------------------------------------------------

class _SidePlayer extends StatelessWidget {
  final String label;
  final int score;
  final Color color;
  final bool active;
  final bool winner;

  const _SidePlayer({
    required this.label,
    required this.score,
    required this.color,
    required this.active,
    required this.winner,
  });

  @override
  Widget build(BuildContext context) {
    final lit = active || winner;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: lit ? 1.0 : 0.55,
      child: SizedBox(
        width: 58,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.3),
                  colors: [Color.lerp(color, Colors.white, 0.35)!, color],
                ),
                border: Border.all(
                  color: winner
                      ? const Color(0xFFF4B740)
                      : (active ? Colors.white70 : Colors.white24),
                  width: winner || active ? 2.5 : 1.5,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.22),
                          blurRadius: 10,
                        ),
                      ]
                    : const [],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontWeight: FontWeight.w800,
                fontSize: 11,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$score',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
          ],
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
    const gravity = 2.2;
    final fade = t < 0.8 ? 1.0 : (1 - (t - 0.8) / 0.2);
    for (final c in confetti) {
      final dx = math.cos(c.angle) * c.speed * t;
      final dy = math.sin(c.angle) * c.speed * t + 0.5 * gravity * t * t;
      final p = o + Offset(dx, dy) * boardSize * 0.45;
      final dim = c.size * boardSize;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(c.spin * t + c.phase);
      canvas.drawCircle(
        Offset.zero,
        dim * 0.5,
        Paint()..color = c.color.withValues(alpha: 0.9 * fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
