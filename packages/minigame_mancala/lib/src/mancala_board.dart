import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigames_core/minigames_core.dart';

import 'mancala_game.dart';
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

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  late final AnimationController _sowCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final AnimationController _confettiCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

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

  /// "AGAIN!" pill lingers briefly after an extra-turn sow, then fades so
  /// the highlighted pits are unobstructed for the bonus pick.
  bool _showExtraPill = false;
  Timer? _pillTimer;

  List<_Confetto> _confetti = const [];
  _BoardGeom? _geom;

  @override
  void initState() {
    super.initState();
    _state = widget.controller.state;
    _outcome = _state == null ? null : _logic.outcome(_state!);
    _entrance.forward();
    _sowCtrl.addListener(_onSowTick);
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pillTimer?.cancel();
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
      _pillTimer?.cancel();
      _showExtraPill = false;
      // Constant speed: every hop costs the same wall-clock time (no base
      // overhead amortized over hop count — that made short turns feel slow
      // and long turns feel rushed). GP-brisk: stones land in quick
      // succession; long relay chains stay watchable instead of draggy.
      const hopMs = 400;
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
          // Flash "AGAIN!" briefly, then fade so the highlighted pits are
          // clear for the bonus pick.
          if (_sowExtra) {
            _showExtraPill = true;
            _pillTimer?.cancel();
            _pillTimer = Timer(const Duration(milliseconds: 900), () {
              if (mounted) setState(() => _showExtraPill = false);
            });
          }
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

  /// Point within a hop where the front stone lands in its cup.
  static const double _dropPoint = 0.72;

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
    final local = _hopCurve(localRaw);

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
      const dropT = _dropPoint; // when the front marble peels into the pit

      // Cluster offsets for the hand (tight pack in flight).
      final cluster = _handClusterOffsets(handN);

      for (var i = 0; i < handN; i++) {
        final isDropping = i == 0; // front stone drops this hop
        final staysInHand = !isDropping || localRaw < dropT;

        // Dropping marble peels toward nest late in the hop.
        double t = local;
        double tRaw = localRaw;
        var nest = -1;
        var toCup = hop.toCup;
        var fromCup = hop.fromCup;
        var clusterOff = cluster[i];
        var opacity = 1.0;
        var scaleX = 1.0;
        var scaleY = 1.0;

        if (isDropping && localRaw >= dropT) {
          // Peel-off: remaining motion is into the nest.
          final peel = ((localRaw - dropT) / (1 - dropT)).clamp(0.0, 1.0);
          t = _hopCurve(dropT + peel * (1 - dropT));
          tRaw = localRaw;
          nest = hop.nestIndex;
          // Shrink cluster offset to nest.
          clusterOff = Offset.lerp(cluster[i], Offset.zero, peel)!;
          final squash = 1.0 -
              0.16 * math.sin(peel.clamp(0.0, 1.0) * math.pi);
          scaleX = 1.05 / squash;
          scaleY = squash;
        } else if (!isDropping) {
          // Rest of hand continues as a unit; slight lag by index.
          final lag = (i * 0.012).clamp(0.0, 0.08);
          final raw = ((localRaw - lag) / (1 - lag)).clamp(0.0, 1.0);
          t = _hopCurve(raw);
          tRaw = raw;
          nest = -1; // stays mid-air / follows arc end without depositing
          // After drop point, hand shrinks toward center (one less stone).
          if (localRaw >= dropT) {
            final peel = ((localRaw - dropT) / (1 - dropT)).clamp(0.0, 1.0);
            final remaining = _handClusterOffsets(handN - 1);
            final ri = i - 1;
            if (ri >= 0 && ri < remaining.length) {
              clusterOff = Offset.lerp(cluster[i], remaining[ri], peel)!;
            }
          }
        }

        // Specs stable for hand members.
        final spec = _MarbleSpec.at(
          cup: hop.fromCup,
          slot: i,
          salt: beat * 17,
        );

        flyers.add(
          _Flyer(
            fromCup: fromCup,
            toCup: toCup,
            t: t,
            tRaw: tRaw,
            spec: spec,
            scaleX: scaleX * (1.0 + 0.06 * math.sin(math.pi * tRaw)),
            scaleY: scaleY * (1.0 + 0.06 * math.sin(math.pi * tRaw)),
            opacity: opacity,
            nestIndex: nest,
            liftMul: 0.58,
            clusterOffset: clusterOff,
            isDropping: isDropping && localRaw >= dropT,
          ),
        );

        // Suppress unused warning if staysInHand needed later.
        assert(staysInHand || isDropping);
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
            spec: _MarbleSpec.at(
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
            isDropping: true,
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
              spec: _MarbleSpec.at(cup: store, slot: nest, salt: cup),
              scaleX: 1.05 / squash,
              scaleY: squash,
              opacity: 1,
              nestIndex: nest,
              liftMul: 0.68,
              clusterOffset: cluster[k] * (1 - raw),
              isDropping: true,
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
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
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
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Glossy glass marbles — white / black / blue (GP palette), near-round
// ---------------------------------------------------------------------------

enum _PebbleColor { white, black, blue }

class _MarbleSpec {
  final _PebbleColor color;
  final double sizeMul;
  /// Horizontal scale (ellipse).
  final double squashX;
  /// Vertical scale (ellipse).
  final double squashY;
  /// Rotation of the oval (radians).
  final double rotation;
  final int seed;

  const _MarbleSpec({
    required this.color,
    required this.sizeMul,
    required this.squashX,
    required this.squashY,
    required this.rotation,
    required this.seed,
  });

  /// Body color — glass-bead reads on pale wood: cool silvery white,
  /// charcoal black, medium azure blue.
  Color get base => switch (color) {
        _PebbleColor.white => const Color(0xFFEDEDE8),
        _PebbleColor.black => const Color(0xFF45454B),
        _PebbleColor.blue => const Color(0xFF4C7FD9),
      };

  Color get shade => switch (color) {
        _PebbleColor.white => const Color(0xFFA5A099),
        _PebbleColor.black => const Color(0xFF1E1E22),
        _PebbleColor.blue => const Color(0xFF23477F),
      };

  Color get hi => switch (color) {
        _PebbleColor.white => const Color(0xFFFFFFFF),
        _PebbleColor.black => const Color(0xFF94949C),
        _PebbleColor.blue => const Color(0xFFBBD4F8),
      };

  /// Stable pebble for a cup slot. Color is interleaved across cups so both
  /// board sides get an even white/black/blue mix (not hash clumps).
  factory _MarbleSpec.at({
    required int cup,
    required int slot,
    int salt = 0,
  }) {
    // Coprime steps: within a cup and across neighboring cups, colors cycle.
    final color = _PebbleColor.values[(cup * 2 + slot * 5 + salt) % 3];

    // Shape variety from a mixed seed (independent of color index).
    // GP marbles are near-perfect spheres — only a whisper of squash.
    var s = (cup * 73856093) ^ (slot * 19349663) ^ (salt * 83492791);
    s &= 0x7fffffff;
    s ^= s >> 13;
    final sizeMul = 0.92 + ((s >> 3) % 9) * 0.015;
    final shapeRoll = (s >> 5) % 4;
    final (sx, sy) = switch (shapeRoll) {
      0 => (1.05, 0.95),
      1 => (0.96, 1.04),
      2 => (1.07, 0.94),
      _ => (1.0, 1.0),
    };
    final rotation = (((s >> 8) % 17) - 8) * 0.04;
    return _MarbleSpec(
      color: color,
      sizeMul: sizeMul,
      squashX: sx,
      squashY: sy,
      rotation: rotation,
      seed: s,
    );
  }
}

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

class _Flyer {
  final int fromCup;
  final int toCup;
  final double t; // eased along arc 0..1
  final double tRaw; // raw hop time for squash
  final _MarbleSpec spec;
  final double scaleX;
  final double scaleY;
  final double opacity;
  /// Landing nest when [isDropping]; -1 means stays in the hand cluster.
  final int nestIndex;
  final double liftMul;
  /// Offset within the flying hand cluster (screen-ish units).
  final Offset clusterOffset;
  final bool isDropping;

  const _Flyer({
    required this.fromCup,
    required this.toCup,
    required this.t,
    required this.tRaw,
    required this.spec,
    required this.scaleX,
    required this.scaleY,
    required this.opacity,
    required this.nestIndex,
    required this.liftMul,
    this.clusterOffset = Offset.zero,
    this.isDropping = false,
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

/// Pack [count] marble centers inside an elliptical well ([wellRx] × [wellRy])
/// with simple collision resolution. Stores pass a wide ellipse so stones
/// spread along the oval instead of bunching in a center circle.
List<Offset> _packNests({
  required int count,
  required Offset center,
  required double wellRx,
  required double wellRy,
  required double marbleR,
  required int cupSeed,
}) {
  if (count <= 0) return const [];
  final nestY = wellRy * 0.08;
  final c = center + Offset(0, nestY);
  if (count == 1) return [c];

  final maxRx = math.max(1.0, wellRx - marbleR * 1.2);
  final maxRy = math.max(1.0, wellRy - marbleR * 1.2);
  final out = <Offset>[];
  // Golden-angle spiral seed, then push-apart iterations.
  for (var i = 0; i < count; i++) {
    final ang = i * 2.399963 + cupSeed * 0.17;
    final frac = math.sqrt((i + 0.35) / count);
    out.add(c +
        Offset(
          math.cos(ang) * maxRx * frac,
          math.sin(ang) * maxRy * frac * 0.9,
        ));
  }

  final minDist = marbleR * 2.08;
  for (var iter = 0; iter < 12; iter++) {
    for (var i = 0; i < out.length; i++) {
      for (var j = i + 1; j < out.length; j++) {
        var d = out[j] - out[i];
        var dist = d.distance;
        if (dist < 1e-5) {
          d = Offset(minDist * 0.5, 0);
          dist = d.distance;
        }
        if (dist < minDist) {
          final push = d / dist * (minDist - dist) * 0.52;
          out[i] = out[i] - push;
          out[j] = out[j] + push;
        }
      }
      // Clamp into the elliptical bowl.
      final fromC = out[i] - c;
      final q = Offset(fromC.dx / maxRx, fromC.dy / maxRy);
      if (q.distance > 1 && q.distance > 1e-5) {
        out[i] = c +
            Offset(
              q.dx / q.distance * maxRx,
              q.dy / q.distance * maxRy,
            );
      }
    }
  }
  return out;
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
    _paintTray(canvas);
    _paintStoreWell(canvas, geom.northStore, MancalaState.northStore);
    _paintStoreWell(canvas, geom.southStore, MancalaState.southStore);
    for (var i = 0; i < 6; i++) {
      _paintPitWell(canvas, geom.cups[i], i);
      _paintPitWell(canvas, geom.cups[7 + i], 7 + i);
    }
    for (var i = 0; i < 14; i++) {
      _paintMarblesInCup(canvas, i, pits[i]);
    }
    // Count badges after stones so they stay readable.
    for (var i = 0; i < 14; i++) {
      _paintCountBadge(canvas, i, pits[i]);
    }
    // Flying hand: cluster rides the arc; dropping stone peels into nest.
    for (final f in flyers) {
      final r0 = _baseMarbleR * f.spec.sizeMul;
      final start = geom.center(f.fromCup);
      final end = f.isDropping && f.nestIndex >= 0
          ? _nestPoint(
              f.toCup,
              f.nestIndex,
              math.max(pits[f.toCup], f.nestIndex) + 1,
            )
          : geom.center(f.toCup);
      final mid = Offset.lerp(start, end, f.t)!;
      final dist = (end - start).distance;
      final lift =
          dist * f.liftMul * math.sin(math.pi * f.tRaw.clamp(0.0, 1.0));
      // Cluster offset in flight; shrink toward path for droppers.
      final cluster = f.clusterOffset * (f.isDropping ? 0.35 : 1.0);
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
      _paintMarble3d(canvas, Offset.zero, r0, f.spec, opacity: f.opacity);
      canvas.restore();
    }
  }

  Offset _nestPoint(int cup, int index, int total) {
    final rect = geom.cups[cup];
    final isStore =
        cup == MancalaState.southStore || cup == MancalaState.northStore;
    final nests = _packNests(
      count: math.max(total, index + 1),
      center: rect.center,
      wellRx: isStore ? rect.width * 0.36 : rect.shortestSide * 0.40,
      wellRy: isStore ? rect.height * 0.34 : rect.shortestSide * 0.40,
      marbleR: _baseMarbleR,
      cupSeed: cup * 19,
    );
    if (nests.isEmpty) return rect.center;
    return nests[index.clamp(0, nests.length - 1)];
  }

  void _paintTray(Canvas canvas) {
    final tray = geom.tray;
    final r = RRect.fromRectAndRadius(tray, Radius.circular(geom.cornerR));

    // Ground shadow — soft and close; the pale slab floats just above the felt.
    canvas.drawRRect(
      r.shift(const Offset(0, 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
    );

    // Pale birch slab — stronger corner-to-corner drift for definition.
    final woodTop = Color.lerp(boardColor, Colors.white, 0.26)!;
    final woodMid = boardColor;
    final woodBot = Color.lerp(boardColor, const Color(0xFF7A6647), 0.24)!;
    canvas.drawRRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [woodTop, woodMid, woodBot],
          stops: const [0.0, 0.48, 1.0],
        ).createShader(tray),
    );

    // Plank tone bands — broad soft vertical stripes of warmer wood.
    final band = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    band.color = const Color(0xFF8A7350).withValues(alpha: 0.06);
    canvas.drawRect(
      Rect.fromLTWH(
        tray.left + tray.width * 0.28,
        tray.top,
        tray.width * 0.17,
        tray.height,
      ),
      band,
    );
    band.color = const Color(0xFF8A7350).withValues(alpha: 0.045);
    canvas.drawRect(
      Rect.fromLTWH(
        tray.left + tray.width * 0.64,
        tray.top,
        tray.width * 0.12,
        tray.height,
      ),
      band,
    );

    // Sun-bleached worn patches so the face isn't a uniform fill.
    final patch = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    patch.color = Colors.white.withValues(alpha: 0.10);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          tray.center.dx - tray.width * 0.16,
          tray.top + tray.height * 0.20,
        ),
        width: tray.width * 0.72,
        height: tray.height * 0.16,
      ),
      patch,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          tray.center.dx + tray.width * 0.14,
          tray.bottom - tray.height * 0.24,
        ),
        width: tray.width * 0.66,
        height: tray.height * 0.14,
      ),
      patch,
    );

    // Long-grain: wavy bezier streaks with varied weight — real figure,
    // not ruler lines.
    final grain = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final x = tray.left + tray.width * (0.09 + i * 0.075);
      final bend = (((i * 37) % 11) - 5) * tray.width * 0.008;
      final heavy = i % 3 == 0;
      grain.color = const Color(0xFF8A7350)
          .withValues(alpha: heavy ? 0.10 : (i.isEven ? 0.06 : 0.04));
      grain.strokeWidth = heavy ? 1.5 : 1.0;
      final path = Path()
        ..moveTo(x, tray.top + tray.height * 0.03)
        ..quadraticBezierTo(
          x + bend,
          tray.top + tray.height * 0.5,
          x + bend * 0.35,
          tray.bottom - tray.height * 0.03,
        );
      canvas.drawPath(path, grain);
    }

    // Edge bevel: firmer dark outline + brighter inner top light so the
    // slab reads as a cut piece of wood, not a flat sticker.
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, geom.pitD * 0.042)
        ..color = const Color(0xFF5E4C32).withValues(alpha: 0.40),
    );
    canvas.drawRRect(
      r.deflate(math.max(1.2, geom.pitD * 0.034)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, geom.pitD * 0.026)
        ..color = Colors.white.withValues(alpha: 0.42),
    );
  }

  /// Elongated end-store carved into the slab (GP/real: fat oval at each end).
  void _paintStoreWell(Canvas canvas, Rect rect, int cup) {
    final rr = RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.shortestSide * 0.48),
    );
    final hi = highlight == cup || (captureFlash && cup == highlight);
    _paintCarvedWell(canvas, rr, hi: hi, legal: false);
  }

  /// Round side-pit carved into the slab.
  void _paintPitWell(Canvas canvas, Rect rect, int cup) {
    final r = rect.shortestSide / 2;
    final c = rect.center;
    // Slight vertical squash so wells sit “into” the board face.
    final well = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: c,
        width: r * 2,
        height: r * 1.92,
      ),
      Radius.circular(r),
    );
    _paintCarvedWell(
      canvas,
      well,
      hi: highlight == cup,
      legal: legal.contains(cup),
    );
  }

  /// Shallow scoop pressed into the same pale wood (GP read) — the depth cue
  /// is an inner top shadow + bottom lip light, not a dark bowl.
  void _paintCarvedWell(
    Canvas canvas,
    RRect well, {
    required bool hi,
    required bool legal,
  }) {
    final rect = well.outerRect;
    final lip = math.max(1.2, geom.pitD * 0.05);

    // Scoop base: darker toward the top wall, lighter at the bottom lip
    // (light from above on a shallow depression).
    canvas.drawRRect(
      well,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(pitColor, const Color(0xFF6B573A), 0.30)!,
            pitColor,
            Color.lerp(pitColor, Colors.white, 0.16)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    // Gentle floor shading so the middle reads deepest.
    canvas.drawRRect(
      well.deflate(lip),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.05),
          radius: 0.9,
          colors: [
            Colors.black.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const [0.0, 0.85],
        ).createShader(rect),
    );

    // Inner top shadow + bottom inner light — the strongest depth cues.
    canvas.save();
    canvas.clipRRect(well);
    canvas.drawOval(
      Rect.fromLTWH(
        rect.left - rect.width * 0.10,
        rect.top - rect.height * 0.34,
        rect.width * 1.20,
        rect.height * 0.55,
      ),
      Paint()
        ..color = const Color(0xFF4A3B24).withValues(alpha: 0.26)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, lip * 2.2),
    );
    canvas.drawOval(
      Rect.fromLTWH(
        rect.left + rect.width * 0.08,
        rect.bottom - rect.height * 0.22,
        rect.width * 0.84,
        rect.height * 0.30,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.20)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, lip * 1.8),
    );
    canvas.restore();

    // Rim: hairline dark crest above, light catch below (pressed-in edge).
    canvas.drawRRect(
      well,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lip * 0.6
        ..shader = SweepGradient(
          center: Alignment.center,
          colors: [
            Colors.white.withValues(alpha: 0.20),
            const Color(0xFF6B573A).withValues(alpha: 0.10),
            const Color(0xFF6B573A).withValues(alpha: 0.26),
            const Color(0xFF6B573A).withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.16),
          ],
          stops: const [0.0, 0.2, 0.5, 0.75, 1.0],
        ).createShader(rect),
    );

    // Selection / legal cue: quiet wood-toned ring on the rim (GP shows
    // nothing; hot-seat needs a hint, so keep it barely-there).
    if (hi || legal) {
      canvas.drawRRect(
        well.inflate(lip * 0.3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hi ? lip * 1.0 : lip * 0.7
          ..color = const Color(0xFF8B6F47)
              .withValues(alpha: hi ? 0.85 : 0.42),
      );
    }
  }

  void _paintMarblesInCup(Canvas canvas, int cup, int count) {
    if (count <= 0) return;
    final rect = geom.cups[cup];
    final isStore =
        cup == MancalaState.southStore || cup == MancalaState.northStore;
    final show = count.clamp(1, isStore ? 20 : 10);
    final nests = _packNests(
      count: show,
      center: rect.center,
      wellRx: isStore ? rect.width * 0.36 : rect.shortestSide * 0.40,
      wellRy: isStore ? rect.height * 0.34 : rect.shortestSide * 0.40,
      marbleR: _baseMarbleR,
      cupSeed: cup * 19,
    );

    for (var i = 0; i < nests.length; i++) {
      final spec = _MarbleSpec.at(cup: cup, slot: i);
      final r = _baseMarbleR * spec.sizeMul;
      final pos = nests[i];
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(pos.dx, pos.dy + r * 0.48),
          width: r * 1.55,
          height: r * 0.52,
        ),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.22)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.35),
      );
      _paintMarble3d(canvas, pos, r, spec);
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

  /// Smooth glossy pebble: perfect rounded oval with readable lighting.
  void _paintMarble3d(
    Canvas canvas,
    Offset c,
    double r,
    _MarbleSpec spec, {
    double opacity = 1,
  }) {
    if (r < 0.5 || opacity <= 0.01) return;
    final isWhite = spec.color == _PebbleColor.white;
    final isBlack = spec.color == _PebbleColor.black;

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(spec.rotation);
    canvas.scale(spec.squashX, spec.squashY);

    final oval = Rect.fromCircle(center: Offset.zero, radius: r);

    // Soft contact rim — quiet on pale wood; the drop shadow separates stones.
    canvas.drawOval(
      oval.inflate(r * 0.06),
      Paint()
        ..color = Colors.white.withValues(
          alpha: (isBlack ? 0.10 : (isWhite ? 0.04 : 0.06)) * opacity,
        ),
    );

    // Body volume — more stops so whites show form, not a flat blob.
    canvas.drawOval(
      oval,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.40, -0.45),
          radius: 1.15,
          colors: [
            spec.hi.withValues(alpha: opacity),
            Color.lerp(spec.hi, spec.base, 0.45)!.withValues(alpha: opacity),
            spec.base.withValues(alpha: opacity),
            Color.lerp(spec.base, spec.shade, 0.55)!.withValues(alpha: opacity),
            spec.shade.withValues(alpha: opacity),
          ],
          stops: const [0.0, 0.22, 0.48, 0.78, 1.0],
        ).createShader(oval),
    );

    // Environment-ish cool reflection strip (reads on white/grey especially).
    final envAlpha = isWhite
        ? 0.28
        : isBlack
            ? 0.12
            : 0.18;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(r * 0.18, r * 0.05),
        width: r * 0.55,
        height: r * 0.70,
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF8EADCF).withValues(alpha: envAlpha * opacity),
            const Color(0xFF8EADCF).withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCenter(
            center: Offset(r * 0.18, r * 0.05),
            width: r * 0.55,
            height: r * 0.70,
          ),
        ),
    );

    // Warm bounce from the wood board (grounds white stones).
    final woodAlpha = isWhite ? 0.22 : (isBlack ? 0.08 : 0.10);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(r * 0.05, r * 0.38),
        width: r * 1.15,
        height: r * 0.55,
      ),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.bottomCenter,
          radius: 1.0,
          colors: [
            const Color(0xFFC4A574).withValues(alpha: woodAlpha * opacity),
            const Color(0xFFC4A574).withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCenter(
            center: Offset(r * 0.05, r * 0.38),
            width: r * 1.15,
            height: r * 0.55,
          ),
        ),
    );

    // Broad primary sheen.
    final sheenA = isWhite ? 0.72 : (isBlack ? 0.45 : 0.58);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * 0.24, -r * 0.32),
        width: r * 0.78,
        height: r * 0.50,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: sheenA * opacity),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCenter(
            center: Offset(-r * 0.24, -r * 0.32),
            width: r * 0.78,
            height: r * 0.50,
          ),
        ),
    );

    // Tight specular.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * 0.30, -r * 0.36),
        width: r * 0.30,
        height: r * 0.22,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.92 * opacity),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCenter(
            center: Offset(-r * 0.30, -r * 0.36),
            width: r * 0.30,
            height: r * 0.22,
          ),
        ),
    );

    // Secondary glint (opposite side).
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(r * 0.32, r * 0.18),
        width: r * 0.22,
        height: r * 0.14,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: (isWhite ? 0.35 : 0.22) * opacity),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCenter(
            center: Offset(r * 0.32, r * 0.18),
            width: r * 0.22,
            height: r * 0.14,
          ),
        ),
    );

    // Bottom rim light.
    canvas.drawArc(
      oval.deflate(r * 0.06),
      0.4,
      math.pi * 0.9,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.08
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(
          alpha: (isBlack ? 0.22 : (isWhite ? 0.28 : 0.14)) * opacity,
        ),
    );

    // Silhouette — a whisper; GP marbles have no drawn outline, shadow and
    // shading do the separating.
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.7, r * 0.045)
        ..color = Colors.black.withValues(
          alpha: (isWhite ? 0.10 : (isBlack ? 0.14 : 0.12)) * opacity,
        ),
    );

    canvas.restore();
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
