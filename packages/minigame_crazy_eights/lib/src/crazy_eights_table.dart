import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigames_core/minigames_core.dart';
import 'package:minigames_ui/minigames_ui.dart';

import 'crazy_eights_card_art.dart';
import 'crazy_eights_game.dart';
import 'crazy_eights_style.dart';

/// Animated Crazy 8s card table wired to a [MatchController].
///
/// Self-contains the GP chrome: green felt table, Player 1 / Player 2 chips,
/// face-down stock + face-up discard in the center (with the declared-suit
/// chip when an 8 is live), opponent card backs up top, and the current
/// player's hand fanned along the bottom. Hot-seat matches get an opaque
/// "Pass to Player N" cover between turns so hands are never leaked.
///
/// Juice: deal fan-out, played cards fly to the discard, drawn cards slide
/// off the stock; every sound cue fires from an animation controller.
class CrazyEightsTable extends StatefulWidget {
  final MatchController<CrazyEightsState, CrazyEightsMove> controller;
  final CrazyEightsStyle style;

  const CrazyEightsTable({
    super.key,
    required this.controller,
    this.style = const CrazyEightsStyle(),
  });

  @override
  State<CrazyEightsTable> createState() => _CrazyEightsTableState();
}

// ---------------------------------------------------------------------------
// Table rhythm
//
// Fractions of the table height. Tuned on a 402×798 phone, where the old
// values left two dead bands — one above the piles and one under the fan —
// with the piles marooned in the middle of empty cloth.
// ---------------------------------------------------------------------------

/// Centre of the opponent's card backs.
const double _kOpponentY = 0.175;

/// Centre of the stock + discard.
const double _kPilesY = 0.415;

/// The notice sits in the band between the opponent's hand and the piles.
const double _kNoticeY = 0.265;

/// Seat chip above the fan.
const double _kSeatChipY = 0.605;

/// Where the fan's arc puts the middle card — low, so the hand rests on the
/// bottom rail of the table rather than floating.
const double _kFanY = 0.855;

const List<String> _kSuitNames = ['Spades', 'Hearts', 'Diamonds', 'Clubs'];

/// Cosmetic data for a card flying to the discard pile.
class _PlayAnim {
  final int card;
  final int actor;
  final int prevTop;
  final Offset fromCenter; // fractional (0..1) table coords
  final double fromAngle;

  const _PlayAnim({
    required this.card,
    required this.actor,
    required this.prevTop,
    required this.fromCenter,
    required this.fromAngle,
  });
}

/// Cosmetic data for a card sliding from the stock into a hand.
class _DrawAnim {
  final int card;
  final int actor;

  const _DrawAnim({required this.card, required this.actor});
}

class _CrazyEightsTableState extends State<CrazyEightsTable>
    with TickerProviderStateMixin {
  static const _game = CrazyEightsGame();

  // Built in initState, never as `late final x = AnimationController(...)`:
  // a field initialiser that first runs during dispose() looks up a
  // deactivated element's ancestor and throws.
  late final AnimationController _entrance;
  late final AnimationController _fly;
  late final AnimationController _drawFly;
  late final AnimationController _confettiCtrl;

  StreamSubscription<CrazyEightsState>? _sub;

  /// The transient line over the table — what just happened, not what is.
  /// [GameNotice] owns its own dismissal, so nothing here runs a timer.
  String? _notice;
  GameNoticeTone _noticeTone = GameNoticeTone.info;

  /// Bumped on every raise, and handed to [GameNotice] as its token. Without
  /// it the notice keys on the text alone, so jabbing the same illegal card
  /// twice would shake once — the second refusal is a distinct event that
  /// happens to use the same sentence.
  int _noticeSeq = 0;

  /// How long a transient line stays up. [GameNotice] owns the countdown and
  /// keeps an auto-dismissed message down while the caller is still holding
  /// it, so this table runs no timer of its own.
  static const Duration _kNoticeLife = Duration(milliseconds: 2400);

  void _raiseNotice(String message, GameNoticeTone tone) {
    _notice = message;
    _noticeTone = tone;
    _noticeSeq++;
  }

  CrazyEightsState? _shown;
  GameOutcome? _outcome;

  /// Seat rendered at the bottom (whose cards are face up).
  int _bottomSeat = 0;

  _PlayAnim? _playAnim;
  _DrawAnim? _drawAnim;

  bool _coverShown = false;

  /// The 8 waiting on a declared suit, or null.
  int? _pickerCard;

  final math.Random _rnd = math.Random();
  List<_Confetto> _confetti = const [];

  bool get _hotSeat => widget.controller.hotSeat;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _fly = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _drawFly = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    final s = widget.controller.state;
    if (s != null) {
      _shown = s;
      _outcome = _game.outcome(s);
      _bottomSeat = _hotSeat
          ? s.currentIndex
          : math.max(0, s.seatOf(widget.controller.localPlayerId));
    }
    _entrance.addStatusListener(_onEntranceStatus);
    _fly.addStatusListener(_onFlyStatus);
    _drawFly.addStatusListener(_onDrawStatus);
    _entrance.forward();
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _entrance.dispose();
    _fly.dispose();
    _drawFly.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // State + animation orchestration
  // ---------------------------------------------------------------------------

  void _onState(CrazyEightsState next) {
    final prev = _shown;
    // A newer state always wins: finish cosmetic animations silently.
    if (_fly.isAnimating) {
      _fly.stop();
      _playAnim = null;
    }
    if (_drawFly.isAnimating) {
      _drawFly.stop();
      _drawAnim = null;
    }

    final outcome = _game.outcome(next);
    final style = widget.style;

    if (prev != null) {
      _noteEvent(next);
      switch (next.lastAction) {
        case CrazyEightsAction.play:
          final actor = next.lastActor!;
          final card = next.lastCard!;
          final idx = prev.hands[actor].indexOf(card);
          _playAnim = _PlayAnim(
            card: card,
            actor: actor,
            prevTop: prev.topCard,
            fromCenter: actor == _bottomSeat
                ? const Offset(0.5, 0.86)
                : const Offset(0.5, 0.14),
            fromAngle: actor == _bottomSeat && idx >= 0
                ? _fanAngle(idx, prev.hands[actor].length)
                : 0,
          );
          _fly.forward(from: 0);
        case CrazyEightsAction.draw:
          _drawAnim = _DrawAnim(card: next.lastCard!, actor: next.lastActor!);
          _drawFly.forward(from: 0);
        case CrazyEightsAction.pass:
          style.sounds.onPass?.call();
          if (style.haptics) HapticFeedback.selectionClick();
          if (outcome == null) {
            _maybeCover(next);
          } else {
            _fireOutcome(outcome);
          }
        case CrazyEightsAction.deal:
          break;
      }
    }

    setState(() {
      _shown = next;
      _outcome = outcome;
      _pickerCard = null;
    });
  }

  /// Narrate the turn. Only the beats a player cannot read off the table get a
  /// line: a wild 8 changing the suit under everyone, and a forced pass. A
  /// draw is already a card sliding off the stock, so it stays silent.
  void _noteEvent(CrazyEightsState next) {
    // Every new state either says something or clears the slate. Holding a
    // stale sentence would also stop the identical one being announced again
    // later, since a notice will not re-present a message it already
    // dismissed while the caller keeps handing it back.
    _notice = null;
    final actor = next.lastActor;
    if (actor == null) return;
    final who = actor == _bottomSeat ? 'You' : widget.style.seatLabel(actor);
    switch (next.lastAction) {
      case CrazyEightsAction.play:
        final suit = next.declaredSuit;
        if (suit != null) {
          _raiseNotice(
            '$who ${actor == _bottomSeat ? 'call' : 'calls'} '
                '${_kSuitNames[suit].toLowerCase()}',
            GameNoticeTone.score,
          );
        }
      case CrazyEightsAction.pass:
        _raiseNotice(
          '$who ${actor == _bottomSeat ? 'pass' : 'passes'} — nothing to play',
          GameNoticeTone.warn,
        );
      case CrazyEightsAction.draw:
      case CrazyEightsAction.deal:
        break;
    }
  }

  /// A refusal the player caused. Same single node as every other notice, so
  /// a repeated refusal can never collide with its own exit.
  void _refuse(String message) {
    setState(() => _raiseNotice(message, GameNoticeTone.warn));
    widget.style.sounds.onInvalid?.call();
    if (widget.style.haptics) HapticFeedback.selectionClick();
  }

  void _onEntranceStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    widget.style.sounds.onDeal?.call();
    if (widget.style.haptics) HapticFeedback.lightImpact();
  }

  void _onFlyStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final style = widget.style;
    style.sounds.onPlay?.call();
    if (style.haptics) HapticFeedback.lightImpact();
    setState(() => _playAnim = null);
    final outcome = _outcome;
    if (outcome != null) {
      _fireOutcome(outcome);
    } else {
      final s = _shown;
      if (s != null) _maybeCover(s);
    }
  }

  void _onDrawStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    widget.style.sounds.onDraw?.call();
    if (widget.style.haptics) HapticFeedback.selectionClick();
    setState(() => _drawAnim = null);
  }

  void _fireOutcome(GameOutcome outcome) {
    final style = widget.style;
    if (outcome.isWin) {
      style.sounds.onWin?.call();
      if (style.haptics) HapticFeedback.heavyImpact();
      if (style.confetti) {
        _confetti = _spawnConfetti();
        _confettiCtrl.forward(from: 0);
      }
    } else {
      style.sounds.onGameDraw?.call();
      if (style.haptics) HapticFeedback.mediumImpact();
    }
    setState(() {});
  }

  void _maybeCover(CrazyEightsState s) {
    if (!_hotSeat || !widget.style.handoffCover) {
      if (!_hotSeat) return;
      // No cover requested — flip the visible seat immediately.
      setState(() => _bottomSeat = s.currentIndex);
      return;
    }
    if (s.currentIndex != _bottomSeat) {
      setState(() => _coverShown = true);
    }
  }

  void _dismissCover() {
    final s = _shown;
    if (s == null) return;
    setState(() {
      _bottomSeat = s.currentIndex;
      _coverShown = false;
    });
    if (widget.style.haptics) HapticFeedback.selectionClick();
  }

  // ---------------------------------------------------------------------------
  // Input
  // ---------------------------------------------------------------------------

  bool get _bottomActs =>
      _outcome == null &&
      !_coverShown &&
      _shown != null &&
      _shown!.currentIndex == _bottomSeat &&
      widget.controller.canActLocally;

  void _tapHandCard(int card) {
    final s = _shown;
    if (s == null || !_bottomActs || _fly.isAnimating) return;
    if (!_game.isPlayable(s, card)) {
      // The pill under the discard already says what *will* go, so the
      // refusal only has to say no.
      _refuse('That one will not go there');
      return;
    }
    if (CrazyEightsCards.isEight(card)) {
      setState(() => _pickerCard = card);
      return;
    }
    widget.controller.submitMove(CrazyEightsMove.play(card));
  }

  void _pickSuit(int suit) {
    final card = _pickerCard;
    if (card == null) return;
    setState(() => _pickerCard = null);
    widget.controller.submitMove(
      CrazyEightsMove.play(card, declaredSuit: suit),
    );
  }

  void _tapStock() {
    final s = _shown;
    if (s == null || !_bottomActs) return;
    if (s.stock.isEmpty) {
      _refuse('The stock is empty');
      return;
    }
    widget.controller.submitMove(const CrazyEightsMove.draw());
  }

  void _tapPass() {
    if (!_bottomActs) return;
    widget.controller.submitMove(const CrazyEightsMove.pass());
  }

  // ---------------------------------------------------------------------------
  // Fan geometry (fractions of the table size; converted per-build)
  // ---------------------------------------------------------------------------

  /// Width-agnostic approximation (used for fly-animation start poses).
  double _fanAngle(int i, int n) {
    if (n <= 1) return 0;
    final spread = math.min(0.9, (n - 1) * 0.13);
    return (i - (n - 1) / 2) * (spread / (n - 1));
  }

  ({Offset center, double angle}) _fanSlot(
    int i,
    int n,
    Size size,
    double cardH,
  ) {
    final r = size.height * 0.58;
    // The fan hangs off a pivot below the table. Sitting it low uses the strip
    // of felt a phone leaves under the hand — the fan floating mid-table with
    // dead cloth beneath it was the worst of this layout's empty bands.
    // Cap the spread so edge cards stay inside the table width.
    final maxHalf = math.min(
      0.46,
      math.asin(math.min(1.0, size.width * 0.33 / r)),
    );
    final step = n <= 1 ? 0.0 : math.min(0.13, 2 * maxHalf / (n - 1));
    final a = (i - (n - 1) / 2) * step;
    final pivot =
        Offset(size.width / 2, size.height * _kFanY - cardH * 0.25 + r);
    return (
      center: pivot + Offset(math.sin(a) * r, -math.cos(a) * r),
      angle: a,
    );
  }

  Offset _stockCenter(Size size, double cardW) =>
      Offset(size.width / 2 - cardW * 0.72, size.height * _kPilesY);

  Offset _discardCenter(Size size, double cardW) =>
      Offset(size.width / 2 + cardW * 0.72, size.height * _kPilesY);

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final table = style.resolveTable(scheme);
    final state = _shown;

    return Container(
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
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        // Table rail: the cloth is stretched over a rim, so the perimeter
        // catches the key up-left and falls away down-right.
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
      painter: _BaizePainter(table),
      child: state == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, c) {
                final size = Size(c.maxWidth, c.maxHeight);
                return AnimatedBuilder(
                  animation: Listenable.merge(
                    [_entrance, _fly, _drawFly, _confettiCtrl],
                  ),
                  builder: (context, _) => _buildTable(size, state),
                );
              },
            ),
      ),
    );
  }

  Widget _buildTable(Size size, CrazyEightsState state) {
    final style = widget.style;
    final cardH = (size.height * 0.185).clamp(64.0, 116.0);
    final cardW = cardH / 1.4;
    final topSeat = 1 - _bottomSeat;

    final children = <Widget>[
      _buildCenterWell(size, cardW),
      ..._buildOpponentRow(size, state, topSeat, cardW * 0.72),
      ..._buildCenterPiles(size, state, cardW),
      ..._buildFan(size, state, cardW, cardH),
      if (_playAnim != null) _buildFlyingPlay(size, cardW, cardH),
      if (_drawAnim != null) _buildFlyingDraw(size, state, cardW, cardH),
      _buildChips(size, state, topSeat),
      if (_passAvailable(state)) _buildPassButton(size),
      if (style.confetti && _confetti.isNotEmpty && _confettiCtrl.value > 0)
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ConfettiPainter(
                confetti: _confetti,
                t: _confettiCtrl.value,
                extent: size.shortestSide,
              ),
            ),
          ),
        ),
      _buildNotice(size, state),
      if (_pickerCard != null) _buildSuitPicker(size),
      if (_coverShown) _buildHandoffCover(state),
    ];

    return Stack(children: children);
  }

  /// The inset well the two piles sit in. A card table has a play area, and
  /// painting one stops the middle of the felt reading as an empty gap between
  /// the opponent's hand and yours.
  Widget _buildCenterWell(Size size, double cardW) {
    final cardH = cardW * 1.4;
    final cy = size.height * _kPilesY;
    final halfW = cardW * 0.72 + cardW / 2 + 18;
    return Positioned(
      left: size.width / 2 - halfW,
      top: cy - cardH / 2 - 20,
      width: halfW * 2,
      height: cardH + 40,
      child: IgnorePointer(
        child: CustomPaint(painter: const _WellPainter()),
      ),
    );
  }

  // -- opponent -------------------------------------------------------------

  List<Widget> _buildOpponentRow(
    Size size,
    CrazyEightsState state,
    int topSeat,
    double backW,
  ) {
    var count = state.hands[topSeat].length;
    // While a draw by the top seat animates, the new card is still in flight.
    if (_drawAnim != null && _drawAnim!.actor == topSeat) count -= 1;
    count = math.max(0, count);
    final rowY = size.height * _kOpponentY;
    final maxSpan = size.width * 0.62;
    final spacing =
        count <= 1 ? 0.0 : math.min(backW * 0.42, maxSpan / (count - 1));
    final enter = Curves.easeOutCubic.transform(
      ((_entrance.value - 0.1) / 0.5).clamp(0.0, 1.0),
    );

    final widgets = <Widget>[];
    for (var i = 0; i < count; i++) {
      final x = size.width / 2 + (i - (count - 1) / 2) * spacing;
      final start = Offset(size.width / 2, size.height * _kPilesY);
      final end = Offset(x, rowY);
      final stagger = count <= 1
          ? enter
          : Curves.easeOutCubic.transform(
              ((enter * count) - i).clamp(0.0, 1.0),
            );
      final at = Offset.lerp(start, end, stagger)!;
      if (stagger <= 0.01) continue;
      widgets.add(Positioned(
        left: at.dx - backW / 2,
        top: at.dy - backW * 0.7,
        child: PlayingCardView(
          card: null,
          faceUp: false,
          width: backW,
          shadow: false,
        ),
      ));
    }
    return widgets;
  }

  // -- center piles ---------------------------------------------------------

  List<Widget> _buildCenterPiles(
    Size size,
    CrazyEightsState state,
    double cardW,
  ) {
    final cardH = cardW * 1.4;
    final stockC = _stockCenter(size, cardW);
    final discardC = _discardCenter(size, cardW);
    final enter = Curves.easeOutCubic.transform(
      ((_entrance.value - 0.55) / 0.45).clamp(0.0, 1.0),
    );

    final widgets = <Widget>[
      // Empty stock well.
      Positioned(
        left: stockC.dx - cardW / 2,
        top: stockC.dy - cardH / 2,
        child: Container(
          width: cardW,
          height: cardH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(cardW * 0.13),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.5,
            ),
          ),
        ),
      ),
    ];

    // Stock stack (up to 3 offset backs).
    if (state.stock.isNotEmpty) {
      final layers = math.min(3, state.stock.length);
      for (var i = 0; i < layers; i++) {
        final off = (layers - 1 - i) * 2.0;
        widgets.add(Positioned(
          left: stockC.dx - cardW / 2 - off,
          top: stockC.dy - cardH / 2 - off,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: i == layers - 1 ? _tapStock : null,
            child: PlayingCardView(
              card: null,
              faceUp: false,
              width: cardW,
              shadow: i == 0,
            ),
          ),
        ));
      }
    }

    // Discard pile: during a play animation the previous top stays visible.
    final topCard =
        _playAnim != null ? _playAnim!.prevTop : state.topCard;
    // The declared suit paints onto the wild 8 itself, so the pile carries the
    // live colour even before the eye reaches the badge.
    final declared = state.declaredSuit;
    widgets.add(Positioned(
      left: discardC.dx - cardW / 2,
      top: discardC.dy - cardH / 2,
      child: Transform.scale(
        scale: 0.85 + 0.15 * enter,
        child: Opacity(
          opacity: enter.clamp(0.0, 1.0),
          child: PlayingCardView(
            card: topCard,
            width: cardW,
            declaredSuit: _playAnim == null ? declared : null,
          ),
        ),
      ),
    ));

    // Declared-suit chip when an 8 is live.
    if (declared != null && _playAnim == null) {
      final chipR = cardW * 0.30;
      widgets.add(Positioned(
        left: discardC.dx + cardW * 0.42,
        top: discardC.dy - cardH / 2 - chipR * 0.4,
        child: SizedBox(
          width: chipR * 2,
          height: chipR * 2,
          child: CustomPaint(painter: _SuitBadgePainter(suit: declared)),
        ),
      ));
    }

    // Captions under the two piles. Static facts about the table, so pills —
    // and the right-hand one is the single most useful sentence in Crazy 8s:
    // what will actually go down next.
    final active = state.activeSuit;
    final topRank = CrazyEightsCards.rankLabels[
        CrazyEightsCards.rankOf(state.topCard)];
    widgets.add(Positioned(
      left: stockC.dx - cardW * 0.9,
      top: stockC.dy + cardH / 2 + 9,
      width: cardW * 1.8,
      child: Center(
        child: GamePill(
          text: state.stock.isEmpty ? 'Stock out' : '${state.stock.length} left',
        ),
      ),
    ));
    widgets.add(Positioned(
      left: discardC.dx - cardW * 1.05,
      top: discardC.dy + cardH / 2 + 9,
      width: cardW * 2.1,
      child: Center(
        child: GamePill(
          text: active == null
              ? 'Anything goes'
              : '${_kSuitNames[active]} or $topRank',
          strong: true,
          accent: active == null
              ? null
              : CrazyEightsCardArt.suitColor(active),
        ),
      ),
    ));

    return widgets;
  }

  // -- bottom fan -----------------------------------------------------------

  List<Widget> _buildFan(
    Size size,
    CrazyEightsState state,
    double cardW,
    double cardH,
  ) {
    final hand = List<int>.of(state.hands[_bottomSeat]);
    // A card mid-draw hasn't visually reached the hand yet.
    if (_drawAnim != null && _drawAnim!.actor == _bottomSeat) {
      hand.remove(_drawAnim!.card);
    }
    final n = hand.length;
    final acting = _bottomActs;
    final deckC = Offset(size.width / 2, size.height * _kPilesY);

    final widgets = <Widget>[];
    for (var i = 0; i < n; i++) {
      final card = hand[i];
      final slot = _fanSlot(i, n, size, cardH);
      final playable = acting && _game.isPlayable(state, card);
      var center = slot.center;
      if (playable) {
        center += Offset(math.sin(slot.angle), -math.cos(slot.angle)) * 12;
      }
      // Deal-in stagger.
      final stagger = Curves.easeOutCubic.transform(
        ((_entrance.value * (n + 2)) - i).clamp(0.0, 1.0),
      );
      if (stagger <= 0.01) continue;
      final at = Offset.lerp(deckC, center, stagger)!;
      final angle = slot.angle * stagger;

      widgets.add(Positioned(
        left: at.dx - cardW / 2,
        top: at.dy - cardH / 2,
        child: Transform.rotate(
          angle: angle,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _tapHandCard(card),
            child: PlayingCardView(
              card: card,
              width: cardW,
              highlighted: playable,
            ),
          ),
        ),
      ));
    }
    return widgets;
  }

  // -- flying cards ---------------------------------------------------------

  Widget _buildFlyingPlay(Size size, double cardW, double cardH) {
    final anim = _playAnim!;
    final t = Curves.easeInOutCubic.transform(_fly.value);
    final from = Offset(
      anim.fromCenter.dx * size.width +
          math.sin(anim.fromAngle) * size.height * 0.1,
      anim.fromCenter.dy * size.height,
    );
    final to = _discardCenter(size, cardW);
    final at = Offset.lerp(from, to, t)!;
    final angle = anim.fromAngle * (1 - t);
    final scale = 1.0 + 0.12 * math.sin(t * math.pi);
    return Positioned(
      left: at.dx - cardW / 2,
      top: at.dy - cardH / 2,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scale: scale,
            child: PlayingCardView(card: anim.card, width: cardW),
          ),
        ),
      ),
    );
  }

  Widget _buildFlyingDraw(
    Size size,
    CrazyEightsState state,
    double cardW,
    double cardH,
  ) {
    final anim = _drawAnim!;
    final t = Curves.easeOutCubic.transform(_drawFly.value);
    final from = _stockCenter(size, cardW);
    final toBottom = anim.actor == _bottomSeat;
    final Offset to;
    double angle;
    if (toBottom) {
      final hand = state.hands[_bottomSeat];
      final idx = math.max(0, hand.indexOf(anim.card));
      final slot = _fanSlot(idx, hand.length, size, cardH);
      to = slot.center;
      angle = slot.angle * t;
    } else {
      to = Offset(size.width / 2, size.height * _kOpponentY);
      angle = 0;
    }
    final at = Offset.lerp(from, to, t)!;
    return Positioned(
      left: at.dx - cardW / 2,
      top: at.dy - cardH / 2,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: angle,
          // Own draws show the face as the card arrives; opponent draws stay
          // hidden.
          child: PlayingCardView(
            card: toBottom ? anim.card : null,
            faceUp: toBottom && t > 0.5,
            width: cardW,
          ),
        ),
      ),
    );
  }

  // -- chrome ---------------------------------------------------------------

  Widget _buildChips(Size size, CrazyEightsState state, int topSeat) {
    final style = widget.style;
    Widget chip(int seat) => _PlayerChip(
          label: style.seatLabel(seat),
          cardCount: state.hands[seat].length,
          active: _outcome == null && state.currentIndex == seat,
          winner: _outcome?.isWin == true &&
              _outcome!.winnerId == state.playerIds[seat],
        );
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(left: 12, top: 12, child: chip(topSeat)),
            // Above the fan so the hand never buries it, and on the opposite
            // side from the opponent's — the two chips read as two seats
            // rather than as a left-hand column.
            Positioned(
              right: 12,
              top: size.height * _kSeatChipY,
              child: chip(_bottomSeat),
            ),
          ],
        ),
      ),
    );
  }

  bool _passAvailable(CrazyEightsState state) =>
      _bottomActs && _game.mustPass(state);

  Widget _buildPassButton(Size size) {
    return Positioned(
      left: 0,
      right: 0,
      top: size.height * _kSeatChipY - 46,
      child: Center(
        child: GestureDetector(
          onTap: _tapPass,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'PASS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The one animating message node on the table.
  ///
  /// This used to be an [AnimatedSwitcher] keyed on the message, which keeps
  /// the outgoing child mounted beside the incoming one: two consecutive
  /// passes — or a message repeating across the empty state — collided with
  /// their own still-animating corpse and threw "Duplicate keys found".
  /// [GameNotice] animates a single node and queues instead.
  Widget _buildNotice(Size size, CrazyEightsState state) {
    final outcome = _outcome;
    String? msg = _notice;
    var tone = _noticeTone;
    if (outcome != null) {
      tone = GameNoticeTone.win;
      if (outcome.isDraw) {
        msg = 'Draw — equal points';
      } else {
        final seat = state.playerIds.indexOf(outcome.winnerId!);
        final label = widget.style.seatLabel(seat);
        msg = state.hands[seat].isEmpty
            ? '$label wins'
            : '$label wins — fewer points';
      }
    }
    // The endgame line stays; everything else retracts on its own so the
    // table is not left carrying a stale sentence.
    return Positioned(
      left: 16,
      right: 16,
      top: outcome != null
          ? size.height * 0.44
          : size.height * _kNoticeY,
      child: IgnorePointer(
        child: Center(
          child: GameNotice(
            message: msg,
            tone: tone,
            strong: outcome != null,
            autoDismiss: outcome == null ? _kNoticeLife : null,
            // The endgame line is a state, not an occurrence, so it carries no
            // token — nothing should re-fire it.
            token: outcome == null ? _noticeSeq : null,
          ),
        ),
      ),
    );
  }

  Widget _buildSuitPicker(Size size) {
    final d = math.min(52.0, size.width * 0.13);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _pickerCard = null),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GamePill(text: 'Choose a suit', strong: true),
                const SizedBox(height: 14),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var suit = 0; suit < 4; suit++) ...[
                      if (suit > 0) const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => _pickSuit(suit),
                        child: SizedBox(
                          width: d,
                          height: d,
                          child: CustomPaint(
                            painter: _SuitBadgePainter(suit: suit),
                          ),
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
    );
  }

  Widget _buildHandoffCover(CrazyEightsState state) {
    final scheme = Theme.of(context).colorScheme;
    final table = widget.style.resolveTable(scheme);
    final label = widget.style.seatLabel(state.currentIndex);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismissCover,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.3),
              radius: 1.4,
              colors: [
                Color.lerp(table, Colors.black, 0.25)!,
                Color.lerp(table, Colors.black, 0.55)!,
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.swap_vert_rounded,
                  color: Colors.white70,
                  size: 42,
                ),
                const SizedBox(height: 12),
                Text(
                  'Pass to $label',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap to continue',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_Confetto> _spawnConfetti() {
    const palette = [
      CrazyEightsCardArt.spadeBlue,
      CrazyEightsCardArt.heartRed,
      CrazyEightsCardArt.diamondAmber,
      CrazyEightsCardArt.clubGreen,
      Color(0xFFFFFFFF),
    ];
    return List.generate(36, (i) {
      final angle = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 2.8;
      return _Confetto(
        angle: angle,
        speed: 0.45 + _rnd.nextDouble(),
        size: 0.02 + _rnd.nextDouble() * 0.026,
        color: palette[i % palette.length],
        spin: (_rnd.nextDouble() - 0.5) * 12,
        phase: _rnd.nextDouble() * math.pi,
        round: _rnd.nextBool(),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Small painters + chip
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Baize table
//
// One committed light for the game: a soft key from the upper left. The cloth
// carries a directional nap, and the table falls away into shadow at the far
// bottom-right corner.
// ---------------------------------------------------------------------------

const Offset _kLight = Offset(-0.38, -0.45);

/// Deterministic hash in `[0, 1)` — no `Random` anywhere in painting.
double _noise(int x, int y, int seed) {
  var n = (x * 374761393) ^ (y * 668265263) ^ (seed * 1274126177);
  n = (n ^ (n >> 13)) * 1274126177;
  n = n ^ (n >> 16);
  return (n & 0x3fffffff) / 0x3fffffff;
}

class _BaizeCache {
  final double w;
  final double h;
  final int felt;
  final ui.Picture picture;

  _BaizeCache(this.w, this.h, this.felt, this.picture);

  bool matches(Size s, Color f) =>
      w == s.width &&
      h == s.height &&
      // ignore: deprecated_member_use
      felt == f.value;
}

final List<_BaizeCache> _baizes = [];

/// Green baize with a nap: every fibre leans the same way, so the cloth has a
/// direction the way a real card table does. Recorded once per size + colour.
class _BaizePainter extends CustomPainter {
  final Color felt;

  const _BaizePainter(this.felt);

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in _baizes) {
      if (b.matches(size, felt)) {
        canvas.drawPicture(b.picture);
        return;
      }
    }
    final recorder = ui.PictureRecorder();
    _record(Canvas(recorder), size);
    final made = _BaizeCache(
      size.width,
      size.height,
      // ignore: deprecated_member_use
      felt.value,
      recorder.endRecording(),
    );
    _baizes.insert(0, made);
    while (_baizes.length > 3) {
      _baizes.removeLast().picture.dispose();
    }
    canvas.drawPicture(made.picture);
  }

  void _record(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(_kLight.dx * 0.9, _kLight.dy * 0.9),
          radius: 1.30,
          colors: [
            Color.lerp(felt, Colors.white, 0.13)!,
            felt,
            Color.lerp(felt, Colors.black, 0.42)!,
          ],
          stops: const [0.0, 0.40, 1.0],
        ).createShader(rect),
    );

    // Nap: short fibres all leaning away from the key, dense enough to read as
    // cloth and faint enough never to compete with the cards.
    final nap = Paint()
      ..strokeWidth = 0.85
      ..strokeCap = StrokeCap.round;
    final cols = (size.width / 4).ceil();
    final rows = (size.height / 4).ceil();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final j = _noise(x, y, 7);
        if (j < 0.40) continue;
        final k = _noise(x, y, 19);
        nap.color = (j > 0.74 ? Colors.white : Colors.black)
            .withValues(alpha: 0.014 + k * 0.022);
        final px = x * 4.0 + k * 4;
        final py = y * 4.0 + j * 4;
        canvas.drawLine(Offset(px, py), Offset(px + 1.5 + k, py + 0.9), nap);
      }
    }

    // Worn sheen where hands rest and cards are dealt, at the table centre.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.46),
        width: size.width * 1.05,
        height: size.height * 0.42,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.035)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, size.shortestSide * 0.14),
    );
  }

  @override
  bool shouldRepaint(_BaizePainter old) => old.felt != felt;
}

/// The play area: a shallow well pressed into the cloth. The rim catches the
/// key from the upper left and the inside sits a shade darker, so the two
/// piles read as sitting *in* the table rather than floating over it.
class _WellPainter extends CustomPainter {
  const _WellPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(size.height * 0.16));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.17),
            Colors.black.withValues(alpha: 0.07),
          ],
        ).createShader(rect),
    );
    // Lit rim along the bottom edge, shadowed along the top: the read of a
    // recess rather than a raised panel.
    canvas.drawRRect(
      rrect.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.09),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_WellPainter old) => false;
}

/// A suit as a solid disc in that suit's colour with a white pip — the same
/// colour language the cards use, so the picker teaches the mapping.
class _SuitBadgePainter extends CustomPainter {
  final int suit;

  _SuitBadgePainter({required this.suit});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    canvas.drawCircle(
      c + Offset(0, size.width * 0.045),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.06),
    );
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      r - size.width * 0.075,
      Paint()..color = CrazyEightsCardArt.suitColor(suit),
    );
    final inset = size.width * 0.29;
    CrazyEightsCardArt.paintSuitOnColor(
      canvas,
      Rect.fromLTRB(
        inset,
        inset,
        size.width - inset,
        size.height - inset,
      ),
      suit,
      keylineAlpha: 0.25,
    );
  }

  @override
  bool shouldRepaint(_SuitBadgePainter old) => old.suit != suit;
}

class _PlayerChip extends StatelessWidget {
  final String label;
  final int cardCount;
  final bool active;
  final bool winner;

  const _PlayerChip({
    required this.label,
    required this.cardCount,
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
            width: 12,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2.5),
              border: Border.all(color: Colors.black26, width: 0.8),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$label · $cardCount',
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
  final double extent;

  _ConfettiPainter({
    required this.confetti,
    required this.t,
    required this.extent,
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
      final pos = o + Offset(dx * extent, dy * extent);
      final paint = Paint()
        ..color = c.color.withValues(alpha: fade.clamp(0.0, 1.0));
      final dim = c.size * extent;
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(c.phase + c.spin * t);
      if (c.round) {
        canvas.drawCircle(Offset.zero, dim * 0.5, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: dim,
              height: dim * 0.55,
            ),
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
