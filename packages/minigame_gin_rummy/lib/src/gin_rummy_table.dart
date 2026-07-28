import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigames_cards/minigames_cards.dart';
import 'package:minigames_ui/minigames_ui.dart';
import 'package:minigames_core/minigames_core.dart';

import 'gin_rummy_game.dart';
import 'gin_rummy_meld.dart';
import 'gin_rummy_style.dart';

/// The Gin Rummy card table, wired to a [MatchController].
///
/// The whole readability problem in gin is "what is melded and what is
/// deadwood", so the hand is a board at the bottom of the table: a header strip
/// carrying the live deadwood count, then melds in their own tinted trays — a
/// run and a set are told apart by colour, label *and* mark — then loose
/// deadwood in a tray of its own. A player can see their hand's shape without
/// sorting anything by hand.
///
/// Every position on the table comes from [_Geom], which is a pure function of
/// the box size and the hand's composition. Two consequences worth keeping:
/// the whole bottom block is anchored to the bottom edge (so a short hand does
/// not leave a band of bare felt under it), and the flying cards read their
/// endpoints from the same source the static layout does, so a card can never
/// land somewhere its destination is not.
///
/// Hot-seat matches get an opaque handoff cover between turns — hands are
/// hidden information and a shared phone must not leak them.
class GinRummyTable extends StatefulWidget {
  final MatchController<GinRummyState, GinRummyMove> controller;
  final GinRummyStyle style;

  const GinRummyTable({
    super.key,
    required this.controller,
    this.style = const GinRummyStyle(),
  });

  @override
  State<GinRummyTable> createState() => _GinRummyTableState();
}

class _GinRummyTableState extends State<GinRummyTable>
    with TickerProviderStateMixin {
  late final GinRummyGame _game = _resolveGame();

  AnimationController? _entrance;
  AnimationController? _pulse;
  AnimationController? _flight;
  AnimationController? _reveal;

  StreamSubscription<GinRummyState>? _sub;

  GinRummyState? _shown;
  GameOutcome? _outcome;

  /// Seat whose cards are face up at the bottom.
  int _bottomSeat = 0;

  /// Card the player has picked up but not yet committed to discarding.
  PlayingCard? _selected;

  bool _coverShown = false;

  /// The handoff cover is owed but a card is still in the air. Dropping the
  /// cover the instant the turn passes would hide the discard landing, which
  /// is the one animation that tells the next player what just happened.
  bool _coverPending = false;

  /// The card currently in the air, or null. Endpoints are resolved at paint
  /// time from [_Geom]; this only carries what moved and which way.
  _Flight? _inAir;

  /// Cached split of the bottom seat's hand — recomputed only on state change.
  HandAnalysis _analysis = const HandAnalysis(
    melds: [],
    deadwood: [],
    deadwoodValue: 0,
  );

  GinRummyGame _resolveGame() {
    final g = widget.controller.game;
    return g is GinRummyGame ? g : const GinRummyGame();
  }

  bool get _hotSeat => widget.controller.hotSeat;

  int get _knockThreshold => _game.rules.knockThreshold;

  @override
  void initState() {
    super.initState();
    // Every controller is built here, never in a field initialiser: a `late
    // final` one runs during dispose() and throws on the deactivated element.
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addStatusListener(_onEntranceStatus);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _flight = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addStatusListener(_onFlightStatus);
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );

    final s = widget.controller.state;
    if (s != null) {
      _shown = s;
      _outcome = _game.outcome(s);
      _bottomSeat = _hotSeat
          ? s.currentIndex
          : math.max(0, s.seatOf(widget.controller.localPlayerId));
      _analysis = s.analysisFor(_bottomSeat);
      if (_isSummary(s)) _reveal!.value = 1;
    }
    _entrance!.forward();
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _entrance?.dispose();
    _pulse?.dispose();
    _flight?.dispose();
    _reveal?.dispose();
    super.dispose();
  }

  static bool _isSummary(GinRummyState s) =>
      s.phase == GinRummyPhase.handOver || s.phase == GinRummyPhase.matchOver;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  void _onState(GinRummyState next) {
    final prev = _shown;
    final sounds = widget.style.sounds;
    final outcome = _game.outcome(next);
    _Flight? flight;

    if (prev != null) {
      switch (next.lastAction) {
        case GinRummyAction.drawStock:
          sounds.onDrawStock?.call();
          _haptic(HapticFeedback.selectionClick);
          flight = _Flight.draw(next, from: _FlightEnd.stock);
        case GinRummyAction.takeUpcard:
        case GinRummyAction.drawDiscard:
          sounds.onTakeDiscard?.call();
          _haptic(HapticFeedback.selectionClick);
          flight = _Flight.draw(next, from: _FlightEnd.discard);
        case GinRummyAction.passUpcard:
          sounds.onPassUpcard?.call();
        case GinRummyAction.discard:
          sounds.onDiscard?.call();
          _haptic(HapticFeedback.lightImpact);
          flight = _Flight.discard(next);
        case GinRummyAction.layOff:
          sounds.onLayOff?.call();
          _haptic(HapticFeedback.selectionClick);
        case GinRummyAction.knock:
          sounds.onKnock?.call();
          _haptic(HapticFeedback.mediumImpact);
          flight = _Flight.discard(next);
        case GinRummyAction.gin:
          sounds.onGin?.call();
          _haptic(HapticFeedback.heavyImpact);
          flight = _Flight.discard(next);
        case GinRummyAction.handScored:
          final result = next.result;
          if (result != null && result.cancelled) {
            sounds.onDraw?.call();
          } else if (result != null && result.gin) {
            sounds.onGin?.call();
          } else {
            sounds.onKnock?.call();
          }
          _haptic(HapticFeedback.mediumImpact);
        case GinRummyAction.newHand:
          _entrance?.forward(from: 0);
        case GinRummyAction.deal:
          break;
      }
    }

    if (outcome != null && _outcome == null) {
      if (outcome.isDraw) {
        sounds.onDraw?.call();
      } else {
        sounds.onWin?.call();
      }
      _haptic(HapticFeedback.heavyImpact);
    }

    // The knock reveal is a real screen change, so it gets its own entrance
    // rather than snapping into place.
    if (_isSummary(next)) {
      if (prev == null || !_isSummary(prev)) _reveal?.forward(from: 0);
    } else {
      _reveal?.value = 0;
    }

    setState(() {
      _shown = next;
      _outcome = outcome;
      _selected = null;
      _inAir = flight;
      _refreshSeat(next);
    });
    if (flight != null) _flight?.forward(from: 0);
  }

  /// The discard pile takes the hit when a card actually lands on it, not on a
  /// timer.
  void _onFlightStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final landed = _inAir;
    if (landed != null && landed.toDiscardPile) _pulse?.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _inAir = null;
      if (_coverPending) {
        _coverPending = false;
        _coverShown = true;
      }
    });
  }

  /// Decide who is looking at the phone, and cover the hand if it changed.
  void _refreshSeat(GinRummyState s) {
    final hidden = !_isSummary(s);
    if (!_hotSeat || !hidden) {
      if (!hidden) {
        // Everything is face up in a summary; keep the seat we were on.
        _analysis = s.analysisFor(_bottomSeat);
        return;
      }
      _bottomSeat = _hotSeat ? s.currentIndex : _bottomSeat;
      _analysis = s.analysisFor(_bottomSeat);
      return;
    }
    if (s.currentIndex != _bottomSeat) {
      if (!widget.style.handoffCover) {
        _bottomSeat = s.currentIndex;
      } else if (_inAir != null) {
        _coverPending = true;
      } else {
        _coverShown = true;
      }
    }
    _analysis = s.analysisFor(_bottomSeat);
  }

  void _dismissCover() {
    final s = _shown;
    if (s == null) return;
    setState(() {
      _bottomSeat = s.currentIndex;
      _analysis = s.analysisFor(_bottomSeat);
      _coverShown = false;
      _coverPending = false;
      _selected = null;
    });
    _haptic(HapticFeedback.selectionClick);
  }

  void _onEntranceStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    widget.style.sounds.onDeal?.call();
    _haptic(HapticFeedback.lightImpact);
  }

  void _haptic(void Function() fire) {
    if (widget.style.haptics) fire();
  }

  void _invalid() {
    widget.style.sounds.onInvalid?.call();
    _haptic(HapticFeedback.selectionClick);
  }

  // ---------------------------------------------------------------------------
  // Input
  // ---------------------------------------------------------------------------

  /// Whether the seat at the bottom of the screen may act right now.
  bool get _bottomActs {
    final s = _shown;
    return s != null &&
        !_coverShown &&
        s.phase != GinRummyPhase.matchOver &&
        s.currentIndex == _bottomSeat &&
        widget.controller.canActLocally;
  }

  void _submit(GinRummyMove move) {
    widget.controller.submitMove(move);
  }

  void _tapStock() {
    final s = _shown;
    if (s == null || !_bottomActs) return;
    if (s.phase != GinRummyPhase.draw || s.stock.isEmpty) {
      _invalid();
      return;
    }
    _submit(const GinRummyMove.drawStock());
  }

  void _tapDiscardPile() {
    final s = _shown;
    if (s == null || !_bottomActs) return;
    if (s.phase == GinRummyPhase.upcardOffer) {
      _submit(const GinRummyMove.takeUpcard());
      return;
    }
    if (s.phase != GinRummyPhase.draw ||
        s.mustDrawFromStock ||
        s.discard.isEmpty) {
      _invalid();
      return;
    }
    _submit(const GinRummyMove.drawDiscard());
  }

  void _tapHandCard(PlayingCard card) {
    final s = _shown;
    if (s == null || !_bottomActs) return;

    if (s.phase == GinRummyPhase.layOff) {
      final knock = s.knock!;
      final target = GinRummyMelds.layOffTarget(knock.knockerMelds, card);
      if (target < 0 || !knock.defenderDeadwood.contains(card)) {
        _invalid();
        return;
      }
      _submit(GinRummyMove.layOff(card, target));
      return;
    }

    if (s.phase != GinRummyPhase.discard) {
      _invalid();
      return;
    }
    if (card == s.blockedDiscard) {
      // The card you just took off the pile cannot go straight back.
      _invalid();
      return;
    }
    setState(() => _selected = _selected == card ? null : card);
    _haptic(HapticFeedback.selectionClick);
  }

  void _confirmDiscard({required bool knock}) {
    final card = _selected;
    if (card == null || !_bottomActs) return;
    setState(() => _selected = null);
    _submit(GinRummyMove.discard(card, knock: knock));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final table = widget.style.resolveTable(scheme);
    final state = _shown;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            offset: const Offset(0, 8),
            blurRadius: 22,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The felt never animates, so it is rastered once behind everything
          // instead of being repainted under every card that moves.
          RepaintBoundary(
            child: CustomPaint(
              painter: _FeltPainter(table),
              isComplex: true,
              willChange: false,
            ),
          ),
          if (state == null)
            const Center(child: CircularProgressIndicator())
          else
            LayoutBuilder(
              builder: (context, c) => AnimatedBuilder(
                animation:
                    Listenable.merge([_entrance, _pulse, _flight, _reveal]),
                builder: (context, _) => _buildTable(
                  Size(c.maxWidth, c.maxHeight),
                  state,
                ),
              ),
            ),
        ],
      ),
    );
  }

  _Geom _geomFor(Size size, GinRummyState s) {
    final showingBar = _bottomActs &&
        (s.phase == GinRummyPhase.discard ||
            s.phase == GinRummyPhase.layOff ||
            s.phase == GinRummyPhase.upcardOffer);
    return _Geom(
      size: size,
      meldCards: _analysis.melds.fold<int>(0, (n, m) => n + m.length),
      meldGroups: _analysis.melds.length,
      deadCards: _analysis.deadwood.length,
      actionBar: showingBar,
    );
  }

  Widget _buildTable(Size size, GinRummyState s) {
    // A finished hand is a different screen, not an overlay: the table's own
    // cards showing through a scrim would only compete with the accounting.
    if (_isSummary(s)) {
      return Stack(children: [_buildSummary(size, s)]);
    }
    final g = _geomFor(size, s);
    return Stack(
      children: [
        _buildOpponentRow(g, s),
        _buildSeatChips(g, s),
        if (s.phase == GinRummyPhase.layOff)
          _buildKnockerMelds(g, s)
        else
          _buildCenter(g, s),
        _buildStatus(g, s),
        ..._buildHand(g, s),
        if (_bottomActs && s.phase == GinRummyPhase.discard)
          _buildActionBar(g, s),
        if (_bottomActs && s.phase == GinRummyPhase.layOff) _buildLayoffBar(g),
        if (_bottomActs && s.phase == GinRummyPhase.upcardOffer)
          _buildOfferBar(g),
        ..._buildFlight(g),
        if (_coverShown) _buildHandoffCover(s),
      ],
    );
  }

  // -- opponent --------------------------------------------------------------

  Widget _buildOpponentRow(_Geom g, GinRummyState s) {
    final topSeat = 1 - _bottomSeat;
    var count = s.hands[topSeat].length;
    final air = _inAir;
    // A card on its way to the opponent must not also be sitting in their fan.
    if (air != null && air.landsWithOpponent(_bottomSeat)) count -= 1;
    final backW = g.backW;
    final maxSpan = g.size.width * 0.66;
    final step = count <= 1
        ? 0.0
        : math.min(backW * 0.58, (maxSpan - backW) / (count - 1));
    final enter = Curves.easeOutCubic.transform(
      (_entrance!.value / 0.6).clamp(0.0, 1.0),
    );

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            for (var i = 0; i < count; i++)
              Positioned(
                left: g.size.width / 2 -
                    (backW + step * (count - 1)) / 2 +
                    i * step,
                top: g.opponentTop - (1 - enter) * g.size.height * 0.12,
                child: Opacity(
                  opacity: enter,
                  child: CardView(
                    card: null,
                    faceUp: false,
                    width: backW,
                    style: widget.style.cards,
                    shadow: i == count - 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeatChips(_Geom g, GinRummyState s) {
    final topSeat = 1 - _bottomSeat;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              left: 10,
              top: 9,
              child: _SeatChip(
                label: widget.style.seatLabel(topSeat),
                score: s.scores[topSeat],
                cards: s.hands[topSeat].length,
                target: _game.rules.targetScore,
                active: s.currentIndex == topSeat && _outcome == null,
              ),
            ),
            // Both scoreboards live at the top: the mid-table band belongs to
            // the piles, the status line and the action buttons.
            Positioned(
              right: 10,
              top: 9,
              child: _SeatChip(
                label: widget.style.seatLabel(_bottomSeat),
                score: s.scores[_bottomSeat],
                cards: s.hands[_bottomSeat].length,
                target: _game.rules.targetScore,
                active: s.currentIndex == _bottomSeat && _outcome == null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- centre piles ----------------------------------------------------------

  Widget _buildCenter(_Geom g, GinRummyState s) {
    final cardW = g.pileW;
    final cardH = g.pileH;
    final stockC = g.stockCentre;
    final discardC = g.discardCentre;
    final enter = Curves.easeOutCubic.transform(
      ((_entrance!.value - 0.35) / 0.65).clamp(0.0, 1.0),
    );
    // The pile takes the impact: a quick squash that settles, not a bounce.
    final hit = _pulse?.value ?? 0;
    final squashX = 1 + 0.13 * math.sin(hit * math.pi) * (1 - hit);
    final squashY = 1 - 0.09 * math.sin(hit * math.pi) * (1 - hit);

    final canTakeDiscard = _bottomActs &&
        (s.phase == GinRummyPhase.upcardOffer ||
            (s.phase == GinRummyPhase.draw && !s.mustDrawFromStock));
    final canTakeStock = _bottomActs && s.phase == GinRummyPhase.draw;
    final air = _inAir;
    final hideUpcard = air != null && air.toDiscardPile;

    final children = <Widget>[
      Positioned(
        left: stockC.dx - cardW / 2,
        top: stockC.dy - cardH / 2,
        child: _PileWell(width: cardW, height: cardH),
      ),
      Positioned(
        left: discardC.dx - cardW / 2,
        top: discardC.dy - cardH / 2,
        child: _PileWell(width: cardW, height: cardH),
      ),
    ];

    if (s.stock.isNotEmpty) {
      // A visible edge stack, so a shrinking stock reads as a thinning pile.
      final layers = math.min(4, s.stock.length);
      for (var i = 0; i < layers; i++) {
        final off = (layers - 1 - i) * 2.2;
        children.add(Positioned(
          left: stockC.dx - cardW / 2 - off * 0.6,
          top: stockC.dy - cardH / 2 - off,
          child: Opacity(
            opacity: enter,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: i == layers - 1 ? _tapStock : null,
              child: CardView(
                card: null,
                faceUp: false,
                width: cardW,
                style: widget.style.cards,
                shadow: i == 0,
                highlight: i == layers - 1 && canTakeStock
                    ? widget.style.selection
                    : null,
              ),
            ),
          ),
        ));
      }
    }

    // While a card is on its way to the pile it is the flight layer's to draw,
    // so the pile shows the card underneath it — never nothing, which would
    // read as the discard vanishing mid-throw.
    final topIndex = s.discard.length - (hideUpcard ? 2 : 1);

    // One buried card under the top of the discard, so the pile has thickness.
    if (topIndex >= 1) {
      children.add(Positioned(
        left: discardC.dx - cardW / 2 - 2,
        top: discardC.dy - cardH / 2 + 2,
        child: Opacity(
          opacity: enter * 0.9,
          child: Transform.rotate(
            angle: -0.045,
            child: CardView(
              card: s.discard[topIndex - 1],
              width: cardW,
              style: widget.style.cards,
              dim: 0.35,
            ),
          ),
        ),
      ));
    }

    final top = topIndex >= 0 ? s.discard[topIndex] : null;
    if (top != null) {
      children.add(Positioned(
        left: discardC.dx - cardW / 2,
        top: discardC.dy - cardH / 2,
        child: Opacity(
          opacity: enter,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(squashX, squashY, 1),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _tapDiscardPile,
              child: CardView(
                card: top,
                width: cardW,
                style: widget.style.cards,
                dim: s.phase == GinRummyPhase.draw && s.mustDrawFromStock
                    ? 0.45
                    : 0,
                highlight: canTakeDiscard ? widget.style.selection : null,
              ),
            ),
          ),
        ),
      ));
    }

    // Stock count, so a player can see the hand running out.
    children.add(Positioned(
      left: 0,
      right: 0,
      top: g.pileBottom + 8,
      child: Center(
        child: GamePill(
          text: '${s.stock.length} in the stock',
          strong: s.stock.length <= 6,
        ),
      ),
    ));

    return Positioned.fill(child: Stack(children: children));
  }

  /// During the lay-off the piles are irrelevant — what the defender needs to
  /// see is the melds they are allowed to feed.
  Widget _buildKnockerMelds(_Geom g, GinRummyState s) {
    final knock = s.knock;
    if (knock == null) return const SizedBox.shrink();
    final mini = (g.size.width * 0.088).clamp(26.0, 42.0);
    // Centred in the band the piles would have used, not pinned under the
    // opponent's fan — otherwise the middle of the table is a hole.
    return Positioned(
      left: 10,
      right: 10,
      top: g.opponentBottom + 12,
      bottom: g.size.height - g.actionTop + 34,
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GamePill(
                text:
                    '${widget.style.seatLabel(knock.knockerIndex)} knocked with '
                    '${knock.knockerDeadwoodValue}',
                strong: true,
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final m in knock.knockerMelds)
                    _MiniRow(
                      cards: m.cards,
                      width: mini,
                      style: widget.style.cards,
                      kind: m.kind,
                      runTint: widget.style.runTint,
                      setTint: widget.style.setTint,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -- status strip ----------------------------------------------------------

  Widget _buildStatus(_Geom g, GinRummyState s) {
    final acting = s.currentIndex == _bottomSeat;
    final who = widget.style.seatLabel(s.currentIndex);
    final String message;
    switch (s.phase) {
      case GinRummyPhase.upcardOffer:
        message = acting
            ? 'Take the upcard or pass'
            : '$who is deciding on the upcard';
      case GinRummyPhase.draw:
        message = acting
            ? (s.mustDrawFromStock ? 'Draw from the stock' : 'Draw a card')
            : '$who is drawing';
      case GinRummyPhase.discard:
        message = acting ? 'Discard a card' : '$who is discarding';
      case GinRummyPhase.layOff:
        message = acting
            ? 'Lay off onto the melds, then finish'
            : '$who is laying off';
      case GinRummyPhase.handOver:
      case GinRummyPhase.matchOver:
        message = '';
    }
    if (message.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 8,
      right: 8,
      // The status normally hangs off the piles. During the lay-off there are
      // no piles, so it sits with the button it is telling you to press.
      top: s.phase == GinRummyPhase.layOff ? g.actionTop - 32 : g.statusTop,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Flexible(child: GamePill(text: message, strong: acting))],
      ),
    );
  }

  // -- the hand --------------------------------------------------------------

  /// The hand board: a header strip carrying the deadwood count, melds in
  /// tinted trays, then the loose cards. Bottom-anchored, so a hand with one
  /// meld does not leave a band of empty felt beneath it.
  List<Widget> _buildHand(_Geom g, GinRummyState s) {
    final hand = s.hands[_bottomSeat];
    if (hand.isEmpty) return const [];

    final analysis = _analysis;
    final meldGroups = [for (final m in analysis.melds) m.cards];
    final deadwood = analysis.deadwood;
    final enter = Curves.easeOutCubic.transform(
      ((_entrance!.value - 0.2) / 0.8).clamp(0.0, 1.0),
    );

    final canKnock = analysis.deadwoodValue <= _knockThreshold &&
        hand.length == _game.rules.handSize + 1;

    final widgets = <Widget>[
      Positioned(
        left: 10,
        right: 10,
        top: g.headerTop,
        child: Opacity(
          opacity: enter,
          child: _HandHeader(
            deadwood: analysis.deadwoodValue,
            threshold: _knockThreshold,
            armed: canKnock,
            accent: widget.style.selection,
          ),
        ),
      ),
    ];

    if (meldGroups.isNotEmpty) {
      widgets.addAll(_buildCardRow(
        g: g,
        groups: meldGroups,
        kinds: [for (final m in analysis.melds) m.kind],
        top: g.meldTop,
        enter: enter,
        state: s,
      ));
    }
    if (deadwood.isNotEmpty) {
      widgets.addAll(_buildCardRow(
        g: g,
        groups: [deadwood],
        kinds: const [null],
        top: g.deadTop,
        enter: enter,
        state: s,
      ));
    }
    return widgets;
  }

  /// Lays out [groups] as one centred row, each group on its own tray.
  List<Widget> _buildCardRow({
    required _Geom g,
    required List<List<PlayingCard>> groups,
    required List<MeldKind?> kinds,
    required double top,
    required double enter,
    required GinRummyState state,
  }) {
    final cardW = g.cardW;
    final cardH = g.cardH;
    final total = groups.fold<int>(0, (n, group) => n + group.length);
    if (total == 0) return const [];

    const trayPad = _Geom.kTrayGapPad;
    final n = groups.length;
    final gap = cardW * _Geom.kTrayGapFactor + trayPad * 2;
    final available = g.size.width - 20;
    // The fan restarts in every tray, so the row is `n` whole cards plus
    // `total - n` steps plus the gaps. Solve the step that fills the table.
    var step = total <= n
        ? 0.0
        : (available - cardW * n - gap * (n - 1)) / (total - n);
    // Cards may sit fully clear of each other when the row has room — the old
    // hard cap at 0.72 was what left a seven-card hand marooned mid-table.
    step = step.clamp(cardW * 0.30, cardW * 1.02);

    final width = cardW * n + step * (total - n) + gap * (n - 1);
    var x = (g.size.width - width) / 2;

    final trays = <Widget>[];
    final cards = <Widget>[];
    var dealt = 0;
    final layoffPhase = state.phase == GinRummyPhase.layOff;
    final knock = state.knock;
    final air = _inAir;

    for (var gi = 0; gi < groups.length; gi++) {
      final group = groups[gi];
      final kind = kinds[gi];
      final groupW = cardW + step * (group.length - 1);

      trays.add(Positioned(
        left: x - trayPad,
        top: top - trayPad - 11,
        child: _MeldTray(
          width: groupW + trayPad * 2,
          height: cardH + trayPad * 2 + 11,
          kind: kind,
          runTint: widget.style.runTint,
          setTint: widget.style.setTint,
        ),
      ));

      for (var i = 0; i < group.length; i++) {
        final card = group[i];
        final selected = _selected == card;
        final blocked = card == state.blockedDiscard;
        final canLayOff = layoffPhase &&
            knock != null &&
            _bottomActs &&
            knock.defenderDeadwood.contains(card) &&
            GinRummyMelds.layOffTarget(knock.knockerMelds, card) >= 0;
        final cardX = x + i * step;
        final stagger = Curves.easeOutCubic.transform(
          ((enter * (total + 2)) - dealt).clamp(0.0, 1.0),
        );
        dealt++;
        // A card still in the air is drawn by the flight layer, not here.
        if (stagger <= 0.01 || (air != null && air.hides(card))) continue;
        final lift = selected ? cardH * 0.16 : 0.0;
        cards.add(Positioned(
          left: cardX,
          top: top - lift + (1 - stagger) * g.size.height * 0.16,
          child: Opacity(
            opacity: stagger,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _tapHandCard(card),
              child: CardView(
                card: card,
                width: cardW,
                style: widget.style.cards,
                dim: blocked ? 0.4 : 0,
                shadow: selected || i == group.length - 1,
                highlight: selected
                    ? widget.style.selection
                    : (canLayOff ? widget.style.runTint : null),
              ),
            ),
          ),
        ));
      }
      x += groupW + gap;
    }

    return [...trays, ...cards];
  }

  // -- cards in the air ------------------------------------------------------

  /// The one card currently travelling, drawn over everything else. Endpoints
  /// come from [_Geom], the same source the static layout uses.
  List<Widget> _buildFlight(_Geom g) {
    final air = _inAir;
    final c = _flight;
    if (air == null || c == null || c.value >= 1) return const [];

    final t = Curves.easeOutCubic.transform(c.value);
    final from = air.origin(g, bottomSeat: _bottomSeat);
    final to = air.target(g, bottomSeat: _bottomSeat);
    final at = Offset.lerp(from, to, t)!;
    // A shallow arc plus a shrinking lift-shadow: the card reads as leaving the
    // surface and coming back down rather than sliding across it.
    final hop = math.sin(t * math.pi);
    final centre = at - Offset(0, hop * g.size.height * 0.045);
    final w = _lerp(air.fromWidth(g, _bottomSeat), air.toWidth(g, _bottomSeat), t) *
        (1 + 0.06 * hop);
    final h = w * kCardAspectRatio;
    final angle = _lerp(air.fromAngle, air.toAngle, t);

    return [
      Positioned.fill(
        // Keyed so a test can assert a card is actually in the air rather than
        // teleporting between two places.
        key: const ValueKey('gin-rummy-flight'),
        child: IgnorePointer(
          child: Stack(
            children: [
              Positioned(
                left: centre.dx - w / 2,
                top: centre.dy - h / 2,
                child: Transform.rotate(
                  angle: angle,
                  child: CardView(
                    card: air.card,
                    faceUp: air.faceUp,
                    width: w,
                    style: widget.style.cards,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  // -- action bars -----------------------------------------------------------

  Widget _buildOfferBar(_Geom g) {
    return Positioned(
      left: 0,
      right: 0,
      top: g.actionTop,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TableButton(
            label: 'Take upcard',
            onTap: () => _submit(const GinRummyMove.takeUpcard()),
          ),
          const SizedBox(width: 10),
          _TableButton(
            label: 'Pass',
            tone: _ButtonTone.quiet,
            onTap: () => _submit(const GinRummyMove.passUpcard()),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(_Geom g, GinRummyState s) {
    final card = _selected;
    final canKnock = card != null && _game.canKnockWith(s, _bottomSeat, card);
    final after = card == null
        ? null
        : _game.deadwoodAfterDiscarding(s, _bottomSeat, card);
    final gin = after == 0;

    return Positioned(
      left: 0,
      right: 0,
      top: g.actionTop,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TableButton(
            label: card == null ? 'Pick a card' : 'Discard ${card.label}',
            tone: card == null ? _ButtonTone.disabled : _ButtonTone.primary,
            onTap: card == null ? null : () => _confirmDiscard(knock: false),
          ),
          const SizedBox(width: 10),
          _TableButton(
            label: gin ? 'Gin!' : 'Knock${after == null ? '' : ' ($after)'}',
            tone: canKnock ? _ButtonTone.gold : _ButtonTone.disabled,
            onTap: canKnock ? () => _confirmDiscard(knock: true) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildLayoffBar(_Geom g) {
    return Positioned(
      left: 0,
      right: 0,
      top: g.actionTop,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TableButton(
            label: 'Finish',
            onTap: () => _submit(const GinRummyMove.finishLayoff()),
          ),
        ],
      ),
    );
  }

  // -- summaries -------------------------------------------------------------

  Widget _buildSummary(Size size, GinRummyState s) {
    final result = s.result;
    if (result == null) return const SizedBox.shrink();
    final match = s.matchResult;
    final style = widget.style;
    final reveal = _reveal?.value ?? 1;

    final String headline;
    if (result.cancelled) {
      headline = 'Hand cancelled';
    } else if (result.gin) {
      headline = '${style.seatLabel(result.knockerIndex)} goes gin';
    } else if (result.undercut) {
      headline = '${style.seatLabel(result.defenderIndex)} undercuts';
    } else {
      headline = '${style.seatLabel(result.knockerIndex)} knocks';
    }
    final mini = (size.width * 0.098).clamp(26.0, 42.0);

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.34 * reveal),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Revealed(
                reveal: reveal,
                order: 0,
                child: _SummaryHeadline(
                  headline: headline,
                  points: result.cancelled ? null : result.points,
                  subtitle: result.cancelled
                      ? 'The stock ran out — same dealer deals again'
                      : 'to ${style.seatLabel(result.winnerIndex!)}',
                  accent: style.selection,
                ),
              ),
              const SizedBox(height: 12),
              // The two hands take the middle and are centred in it. A
              // top-hugged column over a column of bare felt was the defect
              // this replaces, so the scroll view is given the full viewport as
              // a minimum and only actually scrolls when a hand overflows it.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: box.maxHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Revealed(
                            reveal: reveal,
                            order: 1,
                            child: _summaryFor(
                              seat: result.knockerIndex,
                              melds: result.knockerMelds,
                              deadwood: result.knockerDeadwood,
                              deadwoodValue: result.knockerDeadwoodValue,
                              mini: mini,
                              note: result.gin ? 'Gin — no deadwood' : null,
                              winner:
                                  result.winnerIndex == result.knockerIndex,
                            ),
                          ),
                          _Revealed(
                            reveal: reveal,
                            order: 2,
                            child: _summaryFor(
                              seat: result.defenderIndex,
                              melds: result.defenderMelds,
                              deadwood: result.defenderDeadwood,
                              deadwoodValue: result.defenderDeadwoodValue,
                              mini: mini,
                              note: result.laidOff.isEmpty
                                  ? null
                                  : 'Laid off '
                                      '${result.laidOff.map((c) => c.label).join(' ')}',
                              winner:
                                  result.winnerIndex == result.defenderIndex,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _Revealed(
                reveal: reveal,
                order: 3,
                child: _scoreLines(s, result, match),
              ),
              const SizedBox(height: 12),
              _Revealed(
                reveal: reveal,
                order: 4,
                child: match == null
                    ? Center(
                        child: _TableButton(
                          label: 'Next hand',
                          onTap: () => _submit(const GinRummyMove.nextHand()),
                        ),
                      )
                    : Center(
                        child: GamePill(
                          text: match.winnerIndex == null
                              ? 'Match drawn'
                              : '${style.seatLabel(match.winnerIndex!)} wins '
                                  'the match',
                          strong: true,
                          accent: style.selection,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryFor({
    required int seat,
    required List<Meld> melds,
    required List<PlayingCard> deadwood,
    required int deadwoodValue,
    required double mini,
    required bool winner,
    String? note,
  }) {
    final accent = widget.style.selection;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: winner ? 0.11 : 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: winner
              ? accent.withValues(alpha: 0.62)
              : Colors.white.withValues(alpha: 0.13),
          width: winner ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.style.seatLabel(seat),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              _CountBadge(
                label: 'DEADWOOD',
                value: deadwoodValue,
                accent: accent,
                lit: deadwoodValue == 0,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final m in melds)
                _MiniRow(
                  cards: m.cards,
                  width: mini,
                  style: widget.style.cards,
                  kind: m.kind,
                  runTint: widget.style.runTint,
                  setTint: widget.style.setTint,
                ),
              if (melds.isEmpty)
                const Text(
                  'No melds',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              if (deadwood.isNotEmpty)
                _MiniRow(
                  cards: deadwood,
                  width: mini,
                  style: widget.style.cards,
                  kind: null,
                  runTint: widget.style.runTint,
                  setTint: widget.style.setTint,
                ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(
              note,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scoreLines(
    GinRummyState s,
    GinRummyHandResult result,
    GinRummyMatchResult? match,
  ) {
    final style = widget.style;
    final lines = <String>[];
    if (result.cancelled) {
      lines.add('No score — the same dealer deals again.');
    } else {
      final winner = style.seatLabel(result.winnerIndex!);
      if (result.gin) {
        lines.add('$winner: ${result.defenderDeadwoodValue} deadwood + '
            '${_game.rules.ginBonus} gin = ${result.points}');
      } else if (result.undercut) {
        lines.add('$winner: ${result.knockerDeadwoodValue} − '
            '${result.defenderDeadwoodValue} + ${_game.rules.undercutBonus} '
            'undercut = ${result.points}');
      } else {
        lines.add('$winner: ${result.defenderDeadwoodValue} − '
            '${result.knockerDeadwoodValue} = ${result.points}');
      }
    }
    if (match != null) {
      lines.add('Box bonus ${match.boxBonuses[0]} / ${match.boxBonuses[1]}'
          '  ·  game bonus ${match.gameBonus}'
          '${match.shutout ? ' (shutout)' : ''}');
      lines.add('Final ${match.finalScores[0]} — ${match.finalScores[1]}');
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ScoreTrack(
            leftLabel: style.p1Label,
            rightLabel: style.p2Label,
            left: s.scores[0],
            right: s.scores[1],
            target: _game.rules.targetScore,
            accent: style.selection,
          ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                line,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -- handoff ---------------------------------------------------------------

  Widget _buildHandoffCover(GinRummyState s) {
    final scheme = Theme.of(context).colorScheme;
    final table = widget.style.resolveTable(scheme);
    final label = widget.style.seatLabel(s.currentIndex);
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
                Color.lerp(table, Colors.black, 0.58)!,
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
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

/// Every position on the table, as a pure function of the box and the hand's
/// composition.
///
/// The bottom block is anchored to the bottom edge and the mid-table band takes
/// whatever is left, so a hand with one meld and a hand with three both fill
/// the table instead of clumping in the middle over a strip of bare felt.
class _Geom {
  final Size size;
  final int meldCards;
  final int meldGroups;
  final int deadCards;
  final bool actionBar;

  const _Geom({
    required this.size,
    required this.meldCards,
    required this.meldGroups,
    required this.deadCards,
    required this.actionBar,
  });

  // -- opponent --------------------------------------------------------------

  double get backW => (size.width * 0.112).clamp(24.0, 46.0);
  double get opponentTop => size.height * 0.070;
  double get opponentBottom => opponentTop + backW * kCardAspectRatio;
  Offset get opponentCentre =>
      Offset(size.width / 2, (opponentTop + opponentBottom) / 2);

  // -- hand board (bottom-anchored) -----------------------------------------

  int get handRows => (meldCards > 0 ? 1 : 0) + (deadCards > 0 ? 1 : 0);

  /// Width of one row of [cards] split into [groups] trays, in units of the
  /// card width plus a constant, at the reference fan.
  ///
  /// A group is a tray, and the fan restarts inside each one — the row is
  /// `groups` whole cards plus `cards - groups` overlapped steps plus the gaps
  /// between trays. Getting this wrong (treating it as one continuous fan) is
  /// what pushed a two-meld hand off the right edge of the table.
  static (double, double) _rowCost(int cards, int groups) => (
        groups + kRowStep * (cards - groups) + kTrayGapFactor * (groups - 1),
        kTrayGapPad * 2 * (groups - 1),
      );

  /// Cards overlap to this fraction of their width inside a tray.
  static const double kRowStep = 0.72;
  static const double kTrayGapFactor = 0.30;
  static const double kTrayGapPad = 5.0;

  /// Sized so the widest row spans the table rather than floating in the
  /// middle of it, then capped by the height the two rows have to share.
  double get cardW {
    if (handRows == 0) return 0;
    final avail = size.width - 20;
    var byWidth = double.infinity;
    if (meldCards > 0) {
      final (scale, constant) = _rowCost(meldCards, meldGroups);
      byWidth = math.min(byWidth, (avail - constant) / scale);
    }
    if (deadCards > 0) {
      final (scale, constant) = _rowCost(deadCards, 1);
      byWidth = math.min(byWidth, (avail - constant) / scale);
    }
    final byHeight =
        (size.height * 0.455 - 34) / (handRows * kCardAspectRatio);
    return math.min(math.min(byWidth, byHeight), 80.0).clamp(26.0, 80.0);
  }

  double get cardH => cardW * kCardAspectRatio;

  double get deadTop => size.height - cardH - 12;

  double get meldTop =>
      deadCards > 0 ? deadTop - cardH - 20 : size.height - cardH - 12;

  /// Top of the whole board, tray label included.
  double get handTop => (meldCards > 0 ? meldTop : deadTop) - 16;

  double get headerTop => handTop - 32;

  double get actionTop => headerTop - (actionBar ? 52 : 12);

  Offset get handCentre =>
      Offset(size.width / 2, (deadCards > 0 ? deadTop : meldTop) + cardH / 2);

  // -- mid table -------------------------------------------------------------

  /// The band between the opponent's fan and the action row, shared by the
  /// piles, the stock count and the status line.
  double get _bandTop => opponentBottom + 12;
  double get _bandBottom => actionTop - 10;
  double get _bandHeight => math.max(120.0, _bandBottom - _bandTop);

  /// Piles grow into whatever the band has spare, so the middle of the table
  /// is never a hole.
  double get pileW =>
      ((_bandHeight - 62) / kCardAspectRatio).clamp(42.0, 96.0);
  double get pileH => pileW * kCardAspectRatio;

  double get _pileTop => _bandTop + (_bandHeight - (pileH + 62)) / 2;
  double get pileBottom => _pileTop + pileH;

  Offset get stockCentre =>
      Offset(size.width / 2 - pileW * 0.66, _pileTop + pileH / 2);
  Offset get discardCentre =>
      Offset(size.width / 2 + pileW * 0.66, _pileTop + pileH / 2);

  double get statusTop => pileBottom + 34;
}

// ---------------------------------------------------------------------------
// Cards in the air
// ---------------------------------------------------------------------------

double _lerp(double a, double b, double t) => a + (b - a) * t;

enum _FlightEnd { stock, discard, hand, opponent }

/// One card travelling between two places on the table.
///
/// Built from the move that just applied, never from a timer, and it carries
/// only the endpoints as *names* — the pixels come from [_Geom] at paint time,
/// so a flight cannot land somewhere the layout is not.
@immutable
class _Flight {
  final PlayingCard? card;
  final bool faceUp;
  final _FlightEnd from;
  final _FlightEnd to;

  /// Seat the card belongs to, so the hand end resolves to the right side.
  final int actor;

  final double fromAngle;
  final double toAngle;

  const _Flight({
    required this.card,
    required this.faceUp,
    required this.from,
    required this.to,
    required this.actor,
    this.fromAngle = 0,
    this.toAngle = 0,
  });

  /// A card leaving a pile for somebody's hand.
  static _Flight? draw(GinRummyState s, {required _FlightEnd from}) {
    final actor = s.lastActor;
    final card = s.lastCard;
    if (actor == null || card == null) return null;
    return _Flight(
      card: card,
      // Only the drawer's own card is face up, and a stock draw is face down
      // to everyone until it lands.
      faceUp: from == _FlightEnd.discard,
      from: from,
      to: _FlightEnd.hand,
      actor: actor,
      fromAngle: from == _FlightEnd.discard ? -0.05 : 0.04,
    );
  }

  /// A card leaving a hand for the discard pile.
  static _Flight? discard(GinRummyState s) {
    final actor = s.lastActor;
    final card = s.lastCard;
    if (actor == null || card == null) return null;
    return _Flight(
      card: card,
      faceUp: true,
      from: _FlightEnd.hand,
      to: _FlightEnd.discard,
      actor: actor,
      fromAngle: 0,
      toAngle: 0.06,
    );
  }

  bool get toDiscardPile => to == _FlightEnd.discard;

  /// True when this card is on its way into the hidden fan at the top, whose
  /// last back therefore must not be drawn yet.
  bool landsWithOpponent(int bottomSeat) =>
      to == _FlightEnd.hand && actor != bottomSeat;

  /// Whether [c] is the card in the air and so must not also be drawn in the
  /// hand it is heading for.
  bool hides(PlayingCard c) => card == c;

  Offset origin(_Geom g, {required int bottomSeat}) =>
      _resolve(from, g, bottomSeat);

  Offset target(_Geom g, {required int bottomSeat}) =>
      _resolve(to, g, bottomSeat);

  double fromWidth(_Geom g, int bottomSeat) => _width(from, g, bottomSeat);
  double toWidth(_Geom g, int bottomSeat) => _width(to, g, bottomSeat);

  Offset _resolve(_FlightEnd end, _Geom g, int bottomSeat) {
    switch (end) {
      case _FlightEnd.stock:
        return g.stockCentre;
      case _FlightEnd.discard:
        return g.discardCentre;
      case _FlightEnd.opponent:
        return g.opponentCentre;
      case _FlightEnd.hand:
        return actor == bottomSeat ? g.handCentre : g.opponentCentre;
    }
  }

  double _width(_FlightEnd end, _Geom g, int bottomSeat) {
    switch (end) {
      case _FlightEnd.stock:
      case _FlightEnd.discard:
        return g.pileW;
      case _FlightEnd.opponent:
        return g.backW;
      case _FlightEnd.hand:
        if (actor != bottomSeat) return g.backW;
        return g.cardW > 0 ? g.cardW : g.pileW;
    }
  }

}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

/// Staggered slide-and-fade for the knock reveal. Plain interpolation on a
/// controller value — never an [AnimatedSwitcher], which cannot survive the
/// same message arriving twice.
class _Revealed extends StatelessWidget {
  final double reveal;
  final int order;
  final Widget child;

  const _Revealed({
    required this.reveal,
    required this.order,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeOutCubic.transform(
      ((reveal * 5) - order * 0.72).clamp(0.0, 1.0),
    );
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (1 - t) * 18),
        child: child,
      ),
    );
  }
}

/// The result line at the top of the summary: what happened, and the points it
/// was worth as a number you can read across the room.
class _SummaryHeadline extends StatelessWidget {
  final String headline;
  final int? points;
  final String subtitle;
  final Color accent;

  const _SummaryHeadline({
    required this.headline,
    required this.points,
    required this.subtitle,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 11),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  headline.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (points != null) ...[
            const SizedBox(width: 10),
            Text(
              '+$points',
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 30,
                height: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The strip above the hand: what this board is, and the number the player is
/// actually watching.
class _HandHeader extends StatelessWidget {
  final int deadwood;
  final int threshold;
  final bool armed;
  final Color accent;

  const _HandHeader({
    required this.deadwood,
    required this.threshold,
    required this.armed,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            armed ? 'YOUR HAND · KNOCK IS ON' : 'YOUR HAND',
            style: TextStyle(
              color: Colors.white.withValues(alpha: armed ? 0.92 : 0.55),
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 1.2,
            ),
          ),
        ),
        _CountBadge(
          label: 'DEADWOOD',
          value: deadwood,
          accent: accent,
          lit: deadwood <= threshold,
          large: true,
        ),
      ],
    );
  }
}

/// A labelled number, sized so the count is the thing you see first.
class _CountBadge extends StatelessWidget {
  final String label;
  final int value;
  final Color accent;
  final bool lit;
  final bool large;

  const _CountBadge({
    required this.label,
    required this.value,
    required this.accent,
    required this.lit,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = lit ? accent : Colors.white;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.fromLTRB(large ? 10 : 7, large ? 3 : 2, 9, large ? 4 : 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: lit ? 0.52 : 0.34),
        borderRadius: BorderRadius.circular(large ? 11 : 8),
        border: Border.all(
          color: lit
              ? accent.withValues(alpha: 0.85)
              : Colors.white.withValues(alpha: 0.18),
          width: lit ? 1.4 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: fg.withValues(alpha: 0.68),
              fontWeight: FontWeight.w800,
              fontSize: large ? 9.5 : 8.5,
              letterSpacing: 1.0,
            ),
          ),
          SizedBox(width: large ? 7 : 5),
          Text(
            '$value',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w900,
              fontSize: large ? 22 : 14,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

/// Both running totals against the target, so the match position is a shape
/// rather than two numbers to compare.
class _ScoreTrack extends StatelessWidget {
  final String leftLabel;
  final String rightLabel;
  final int left;
  final int right;
  final int target;
  final Color accent;

  const _ScoreTrack({
    required this.leftLabel,
    required this.rightLabel,
    required this.left,
    required this.right,
    required this.target,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    Widget bar(String label, int score, Color colour) {
      final fraction = target <= 0 ? 1.0 : (score / target).clamp(0.0, 1.0);
      return Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          children: [
            SizedBox(
              width: 62,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 7,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: fraction,
                        child: ColoredBox(color: colour),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 30,
              child: Text(
                '$score',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        bar(leftLabel, left, accent),
        bar(rightLabel, right, Colors.white.withValues(alpha: 0.72)),
      ],
    );
  }
}

/// A row of small cards, used where a meld has to read at a glance without
/// being playable. Sets and runs carry the same mark they do in the hand.
class _MiniRow extends StatelessWidget {
  final List<PlayingCard> cards;
  final double width;
  final PlayingCardStyle style;
  final MeldKind? kind;
  final Color runTint;
  final Color setTint;

  const _MiniRow({
    required this.cards,
    required this.width,
    required this.style,
    required this.kind,
    required this.runTint,
    required this.setTint,
  });

  @override
  Widget build(BuildContext context) {
    final step = width * 0.68;
    final tint = kind == null
        ? null
        : (kind == MeldKind.run ? runTint : setTint);
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
      decoration: BoxDecoration(
        color: (tint ?? Colors.white).withValues(alpha: tint == null ? 0.07 : 0.20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (tint ?? Colors.white)
              .withValues(alpha: tint == null ? 0.16 : 0.55),
        ),
      ),
      child: SizedBox(
        width: width + step * (cards.length - 1),
        height: width * kCardAspectRatio,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: -9,
              child: _MeldMark(kind: kind, tint: tint, scale: 0.85),
            ),
            for (var i = 0; i < cards.length; i++)
              Positioned(
                left: i * step,
                child: CardView(
                  card: cards[i],
                  width: width,
                  style: style,
                  shadow: false,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The tinted backing behind one group in the hand. A null [kind] is the
/// deadwood tray: neutral, unlit, and deliberately the plainest thing here.
class _MeldTray extends StatelessWidget {
  final double width;
  final double height;
  final MeldKind? kind;
  final Color runTint;
  final Color setTint;

  const _MeldTray({
    required this.width,
    required this.height,
    required this.kind,
    required this.runTint,
    required this.setTint,
  });

  @override
  Widget build(BuildContext context) {
    final tint = kind == null
        ? Colors.white
        : (kind == MeldKind.run ? runTint : setTint);
    final melded = kind != null;
    return IgnorePointer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              tint.withValues(alpha: melded ? 0.26 : 0.09),
              tint.withValues(alpha: melded ? 0.12 : 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: tint.withValues(alpha: melded ? 0.62 : 0.18),
            width: melded ? 1.3 : 1,
          ),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 5, top: 1),
            child: _MeldMark(kind: kind, tint: melded ? tint : null),
          ),
        ),
      ),
    );
  }
}

/// The glanceable difference between a set and a run: colour, word, and a mark
/// that says what the grouping *means* — three equal bars for a set of one
/// rank, three rising steps for a run in sequence.
class _MeldMark extends StatelessWidget {
  final MeldKind? kind;
  final Color? tint;
  final double scale;

  const _MeldMark({required this.kind, required this.tint, this.scale = 1});

  @override
  Widget build(BuildContext context) {
    final colour = tint ?? Colors.white.withValues(alpha: 0.42);
    final label = switch (kind) {
      MeldKind.run => 'RUN',
      MeldKind.set => 'SET',
      null => 'LOOSE',
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CustomPaint(
          size: Size(11 * scale, 9 * scale),
          painter: _MeldMarkPainter(kind: kind, colour: colour),
        ),
        SizedBox(width: 3 * scale),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: colour,
              fontSize: 8.5 * scale,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}

class _MeldMarkPainter extends CustomPainter {
  final MeldKind? kind;
  final Color colour;

  const _MeldMarkPainter({required this.kind, required this.colour});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = colour;
    final w = size.width / 3.4;
    for (var i = 0; i < 3; i++) {
      final double h;
      switch (kind) {
        case MeldKind.set:
          h = size.height; // three equal bars: same rank
        case MeldKind.run:
          h = size.height * (0.42 + 0.29 * i); // rising steps: a sequence
        case null:
          h = size.height * 0.34; // low, loose, unmelded
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * w * 1.2, size.height - h, w, h),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_MeldMarkPainter old) =>
      old.kind != kind || old.colour != colour;
}

/// The recessed spot a pile lives in — an inset well rather than a hairline
/// rectangle, so an empty stock still reads as a place on the table.
class _PileWell extends StatelessWidget {
  final double width;
  final double height;

  const _PileWell({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: width,
        height: height,
        child: const CustomPaint(painter: _PileWellPainter()),
      ),
    );
  }
}

class _PileWellPainter extends CustomPainter {
  const _PileWellPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(size.width * 0.085),
    );
    // Sunk into the baize: dark at the top edge, a thin catch-light at the
    // bottom, exactly the way a real cut-out reads.
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.22),
            Colors.black.withValues(alpha: 0.06),
          ],
        ).createShader(rect),
    );
    canvas.drawRRect(
      rrect.deflate(0.7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = Colors.black.withValues(alpha: 0.30),
    );
    canvas.drawRRect(
      rrect.deflate(2.0),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white.withValues(alpha: 0.14),
    );
  }

  @override
  bool shouldRepaint(_PileWellPainter old) => false;
}

class _SeatChip extends StatelessWidget {
  final String label;
  final int score;
  final int cards;
  final int target;
  final bool active;

  const _SeatChip({
    required this.label,
    required this.score,
    required this.cards,
    required this.target,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: active ? 0.42 : 0.20),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: Colors.white.withValues(alpha: active ? 0.48 : 0.12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: active ? 1 : 0.66),
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              fontSize: 11.5,
              height: 1.1,
            ),
          ),
          Text(
            '$score / $target  ·  $cards cards',
            style: TextStyle(
              color: Colors.white.withValues(alpha: active ? 0.82 : 0.5),
              fontWeight: FontWeight.w600,
              fontSize: 9.5,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

enum _ButtonTone { primary, gold, quiet, disabled }

class _TableButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final _ButtonTone tone;

  const _TableButton({
    required this.label,
    required this.onTap,
    this.tone = _ButtonTone.primary,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      _ButtonTone.primary => (Colors.black.withValues(alpha: 0.58), Colors.white),
      _ButtonTone.gold => (const Color(0xFFF4B740), const Color(0xFF221B08)),
      _ButtonTone.quiet => (
          Colors.black.withValues(alpha: 0.34),
          Colors.white.withValues(alpha: 0.86),
        ),
      _ButtonTone.disabled => (
          Colors.black.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.40),
        ),
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: tone == _ButtonTone.gold
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    offset: const Offset(0, 2),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Green baize with a key light from the upper left.
///
/// Not a flat fill: a warm radial key, a woven micro-texture, corner falloff,
/// and an inset rail so the felt reads as a surface set into a surround. It is
/// rastered once (see the [RepaintBoundary] in `build`), so the cost is paid
/// at layout size changes and never per frame.
class _FeltPainter extends CustomPainter {
  final Color felt;

  const _FeltPainter(this.felt);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. Key light: warm and off-centre, falling away to a deep shadow.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.42, -0.62),
          radius: 1.42,
          colors: [
            Color.lerp(felt, const Color(0xFFFFF3C4), 0.20)!,
            Color.lerp(felt, Colors.white, 0.05)!,
            felt,
            Color.lerp(felt, Colors.black, 0.52)!,
          ],
          stops: const [0.0, 0.20, 0.50, 1.0],
        ).createShader(rect),
    );

    // 2. Weave. Two crossed sets of hairlines at a few percent alpha — at phone
    // scale this is what separates baize from a green rectangle.
    canvas.save();
    canvas.clipRect(rect);
    final weave = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.022);
    final shade = Paint()
      ..strokeWidth = 1
      ..color = Colors.black.withValues(alpha: 0.035);
    const spacing = 5.0;
    final reach = size.width + size.height;
    for (var d = -size.height; d < reach; d += spacing) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), weave);
      canvas.drawLine(
        Offset(d + 1.6, 0),
        Offset(d + size.height + 1.6, size.height),
        shade,
      );
    }
    for (var d = 0.0; d < reach; d += spacing) {
      canvas.drawLine(Offset(d, 0), Offset(d - size.height, size.height), weave);
    }
    canvas.restore();

    // 3. Sheen where the key lands, wide and very soft.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.42, size.height * 0.22),
        width: size.width * 1.15,
        height: size.height * 0.34,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, size.shortestSide * 0.16),
    );

    // 4. Corner falloff, so the surface curves away instead of ending flat.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.86,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.06),
            Colors.black.withValues(alpha: 0.30),
          ],
          stops: const [0.55, 0.82, 1.0],
        ).createShader(rect),
    );

    // 5. The rail: a dark inner edge with a catch-light just inside it.
    final radius = Radius.circular(size.shortestSide * 0.075);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(1.0), radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = Colors.black.withValues(alpha: 0.34),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(3.4), radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Colors.white.withValues(alpha: 0.10),
    );
  }

  @override
  bool shouldRepaint(_FeltPainter old) => old.felt != felt;
}
