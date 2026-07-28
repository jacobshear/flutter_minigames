import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigames_cards/minigames_cards.dart';
import 'package:minigames_core/minigames_core.dart';
import 'package:minigames_ui/minigames_ui.dart';

import 'go_fish_game.dart';
import 'go_fish_style.dart';

/// The Go Fish table, wired to a [MatchController].
///
/// The readability problem in Go Fish is "which rank should I ask for", and
/// the answer is always in the shape of your own hand — so the hand is laid
/// out as **rank groups in trays**, and tapping a tray *is* the rank picker.
/// There is no separate list of ranks to cross-reference, and no way to pick a
/// rank you do not hold.
///
/// The other beat worth building for is the moment the opponent hands cards
/// over: those cards fly across the table and land in your group, with a pill
/// naming the haul. That is the whole payoff of an ask, so it gets the motion.
///
/// Hot-seat matches never cut straight to the handoff cover — the outgoing
/// player first sees what their ask produced (including the card they fished
/// up, which is private), then taps to pass the phone.
class GoFishTable extends StatefulWidget {
  final MatchController<GoFishState, GoFishMove> controller;
  final GoFishStyle style;

  const GoFishTable({
    super.key,
    required this.controller,
    this.style = const GoFishStyle(),
  });

  @override
  State<GoFishTable> createState() => _GoFishTableState();
}

/// Where every band of the table sits, in table-local pixels.
///
/// The old layout pinned each row to a hand-tuned fraction of the height,
/// which was tuned on a shorter table: on a 402×798 phone that pooled the
/// spare height into one dead hole between the commentary and the hand, and
/// left another strip of unused cloth under it. Here the bands are measured,
/// stacked in order, and the slack is shared out evenly between them — a
/// taller phone gets more air everywhere instead of one hole.
class _Bands {
  final double backsTop;
  final double backsCountTop;
  final double topBooksTop;
  final double pondTop;
  final double pondCountTop;
  final double noticeTop;
  final double bottomBooksTop;
  final double actionTop;
  final double trayTop;

  final double backW;
  final double pondW;
  final double chipH;

  const _Bands({
    required this.backsTop,
    required this.backsCountTop,
    required this.topBooksTop,
    required this.pondTop,
    required this.pondCountTop,
    required this.noticeTop,
    required this.bottomBooksTop,
    required this.actionTop,
    required this.trayTop,
    required this.backW,
    required this.pondW,
    required this.chipH,
  });

  double get pondCenterY => pondTop + pondW * kCardAspectRatio / 2;
}

/// Felt showing around a rank tray.
const double _kTrayPad = 4;

/// Fraction of a card the next one in a group steps by.
const double _kOverlap = 0.48;

/// Extra felt between two trays, in card widths.
const double _kTrayGap = 0.22;

/// The rank strip along the top of a tray.
const double _kTrayLabelH = 12;

const double _kCountH = 19;
const double _kNoticeH = 44;
const double _kActionH = 38;

class _GoFishTableState extends State<GoFishTable>
    with TickerProviderStateMixin {
  late final GoFishGame _game = _resolveGame();

  AnimationController? _entrance;
  AnimationController? _transfer;
  AnimationController? _bookPulse;

  StreamSubscription<GoFishState>? _sub;

  GoFishState? _shown;
  GameOutcome? _outcome;

  /// Seat whose cards are face up at the bottom.
  int _bottomSeat = 0;

  /// Rank the player has picked but not yet asked for.
  Rank? _selected;

  /// The turn has passed but the outgoing player has not yet handed the phone
  /// over — they are still looking at the result of their own ask.
  bool _pendingHandoff = false;

  bool _coverShown = false;

  /// The running commentary. [GameNotice] owns its own countdown and keeps a
  /// dismissed line down until the caller changes it, so nothing here runs a
  /// timer.
  String? _noticeShown;

  static const Duration _kNoticeLife = Duration(milliseconds: 3200);

  GoFishGame _resolveGame() {
    final g = widget.controller.game;
    return g is GoFishGame ? g : const GoFishGame();
  }

  bool get _hotSeat => widget.controller.hotSeat;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    )..addStatusListener(_onEntranceStatus);
    _transfer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..addStatusListener(_onTransferStatus);
    _bookPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    final s = widget.controller.state;
    if (s != null) {
      _shown = s;
      _outcome = _game.outcome(s);
      _bottomSeat = _hotSeat
          ? s.currentIndex
          : math.max(0, s.seatOf(widget.controller.localPlayerId));
    }
    _entrance!.forward();
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _entrance?.dispose();
    _transfer?.dispose();
    _bookPulse?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  void _onState(GoFishState next) {
    final prev = _shown;
    final sounds = widget.style.sounds;
    final outcome = _game.outcome(next);
    final event = next.lastEvent;

    if (prev != null) {
      switch (event.action) {
        case GoFishAction.deal:
          break;
        case GoFishAction.caught:
          sounds.onAsk?.call();
          _haptic(HapticFeedback.selectionClick);
          // onCatch fires when the cards land, not when the state arrives.
          _transfer?.forward(from: 0);
        case GoFishAction.fished:
          sounds.onAsk?.call();
          sounds.onGoFish?.call();
          _haptic(HapticFeedback.lightImpact);
        case GoFishAction.fishedHit:
          sounds.onAsk?.call();
          sounds.onGoFish?.call();
          _haptic(HapticFeedback.mediumImpact);
        case GoFishAction.fishedDry:
          sounds.onAsk?.call();
          sounds.onDryPond?.call();
          _haptic(HapticFeedback.selectionClick);
      }
      if (event.books.isNotEmpty) {
        sounds.onBook?.call();
        _haptic(HapticFeedback.mediumImpact);
        _bookPulse?.forward(from: 0);
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

    setState(() {
      _shown = next;
      _outcome = outcome;
      _selected = null;
      _refreshSeat(next, outcome);
      // The commentary is raised here, not in build: a new event is exactly a
      // new state arriving, and build must stay free of side effects.
      _noticeShown = _noticeFor(next).text;
    });
  }

  /// Decide who is looking at the phone. A seat change does not cover the
  /// table immediately: the player who just moved has to see their own result
  /// first (the card they fished up is theirs alone to see).
  void _refreshSeat(GoFishState s, GameOutcome? outcome) {
    if (!_hotSeat) {
      _bottomSeat = math.max(0, s.seatOf(widget.controller.localPlayerId));
      return;
    }
    if (outcome != null) {
      // Everything is face up in the summary; stay where we are.
      _pendingHandoff = false;
      _coverShown = false;
      return;
    }
    if (s.currentIndex == _bottomSeat) return;
    if (widget.style.handoffCover) {
      _pendingHandoff = true;
    } else {
      _bottomSeat = s.currentIndex;
    }
  }

  void _raiseCover() {
    setState(() {
      _pendingHandoff = false;
      _coverShown = true;
    });
    _haptic(HapticFeedback.selectionClick);
  }

  void _dismissCover() {
    final s = _shown;
    if (s == null) return;
    setState(() {
      _bottomSeat = s.currentIndex;
      _coverShown = false;
      _selected = null;
    });
    _haptic(HapticFeedback.selectionClick);
  }

  void _onEntranceStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    widget.style.sounds.onDeal?.call();
    _haptic(HapticFeedback.lightImpact);
  }

  void _onTransferStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    widget.style.sounds.onCatch?.call();
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
        !_pendingHandoff &&
        _outcome == null &&
        s.currentIndex == _bottomSeat &&
        widget.controller.canActLocally;
  }

  void _tapGroup(Rank rank) {
    final s = _shown;
    if (s == null || !_bottomActs || !s.holds(_bottomSeat, rank)) {
      _invalid();
      return;
    }
    setState(() => _selected = _selected == rank ? null : rank);
    _haptic(HapticFeedback.selectionClick);
  }

  void _ask() {
    final rank = _selected;
    if (rank == null || !_bottomActs) {
      _invalid();
      return;
    }
    setState(() => _selected = null);
    widget.controller.submitMove(GoFishMove.ask(rank));
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
            color: Colors.black.withValues(alpha: 0.18),
            offset: const Offset(0, 6),
            blurRadius: 18,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: state == null
          ? CustomPaint(
              painter: _FeltPainter(table, 0),
              child: const Center(child: CircularProgressIndicator()),
            )
          : LayoutBuilder(
              builder: (context, c) {
                final size = Size(c.maxWidth, c.maxHeight);
                // The cloth is painted inside the layout pass so the pond's
                // ripples can ring wherever the deck actually landed.
                final bands = _layout(size, state);
                return CustomPaint(
                  painter: _FeltPainter(table, bands.pondCenterY),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _entrance,
                      _transfer,
                      _bookPulse,
                    ]),
                    builder: (context, _) => _buildTable(size, state, bands),
                  ),
                );
              },
            ),
    );
  }

  /// Measure the bands, then share the leftover height out between them.
  _Bands _layout(Size size, GoFishState s) {
    final backW = (size.width * 0.115).clamp(24.0, 44.0);
    // The pond is the table's centrepiece and was drawn far too small for a
    // phone — it now takes the room the dead band used to.
    final pondW = (size.height * 0.125).clamp(46.0, 92.0);
    final chipH = (size.height * 0.052).clamp(22.0, 34.0);
    // Tray = label strip + padding + the card itself.
    final handH = _handCardWidth(size, s) * kCardAspectRatio +
        _kTrayPad * 2 +
        _kTrayLabelH;

    // An empty books row contributes nothing, so no game opens with two
    // reserved strips of nothing above and below the pond.
    final topBooks = s.books[1 - _bottomSeat].isEmpty ? 0.0 : chipH;
    final bottomBooks = s.books[_bottomSeat].isEmpty ? 0.0 : chipH;

    final heights = <double>[
      backW * kCardAspectRatio, // 0 opponent backs
      _kCountH, // 1 their count
      topBooks, // 2 their books
      pondW * kCardAspectRatio, // 3 pond
      _kCountH, // 4 pond count
      _kNoticeH, // 5 commentary
      bottomBooks, // 6 your books
      _kActionH, // 7 action bar
      handH, // 8 your hand
    ];

    const top = 46.0; // under the seat chips
    final bottom = size.height - 16;
    final live = [
      for (var i = 0; i < heights.length; i++)
        if (heights[i] > 0) i,
    ];
    final used = heights.fold<double>(0, (a, b) => a + b);
    final gap = live.length < 2
        ? 0.0
        : math.max(6.0, (bottom - top - used) / (live.length - 1));

    final tops = List<double>.filled(heights.length, top);
    var y = top;
    for (final i in live) {
      tops[i] = y;
      y += heights[i] + gap;
    }

    return _Bands(
      backsTop: tops[0],
      backsCountTop: tops[1],
      topBooksTop: tops[2],
      pondTop: tops[3],
      pondCountTop: tops[4],
      noticeTop: tops[5],
      bottomBooksTop: tops[6],
      actionTop: tops[7],
      trayTop: tops[8],
      backW: backW,
      pondW: pondW,
      chipH: chipH,
    );
  }

  Widget _buildTable(Size size, GoFishState s, _Bands b) {
    // Every child is Positioned on purpose: a bare SizedBox.shrink() in here
    // is a non-positioned child, and a Stack sizes itself to those — one empty
    // books row would collapse the whole table to nothing.
    return Stack(
      children: [
        _buildOpponentBacks(size, s, b),
        _buildSeatChips(size, s),
        if (s.books[1 - _bottomSeat].isNotEmpty)
          _buildBooksRow(size, s,
              seat: 1 - _bottomSeat, top: b.topBooksTop, chipH: b.chipH),
        _buildPond(size, s, b),
        _buildNotice(size, s, b),
        if (s.books[_bottomSeat].isNotEmpty)
          _buildBooksRow(size, s,
              seat: _bottomSeat, top: b.bottomBooksTop, chipH: b.chipH),
        ..._buildHand(size, s, b),
        if (_outcome == null) _buildActionBar(size, s, b),
        if (_transfer!.isAnimating) ..._buildTransfer(size, s, b),
        if (_outcome != null) _buildSummary(size, s),
        if (_coverShown) _buildHandoffCover(s),
      ],
    );
  }

  // -- opponent --------------------------------------------------------------

  Widget _buildOpponentBacks(Size size, GoFishState s, _Bands b) {
    final topSeat = 1 - _bottomSeat;
    final count = s.hands[topSeat].length;
    final backW = b.backW;
    final maxSpan = size.width * 0.66;
    final step = count <= 1
        ? 0.0
        : math.min(backW * 0.52, (maxSpan - backW) / (count - 1));
    final enter = Curves.easeOutCubic.transform(
      (_entrance!.value / 0.6).clamp(0.0, 1.0),
    );
    final y = b.backsTop;

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            for (var i = 0; i < count; i++)
              Positioned(
                left: size.width / 2 -
                    (backW + step * (count - 1)) / 2 +
                    i * step,
                top: y - (1 - enter) * size.height * 0.10,
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
            Positioned(
              left: 0,
              right: 0,
              top: b.backsCountTop,
              child: Center(
                child: _CountBadge(
                  count: count,
                  color: Colors.white.withValues(alpha: 0.86),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeatChips(Size size, GoFishState s) {
    final topSeat = 1 - _bottomSeat;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              left: 12,
              top: 10,
              child: _SeatChip(
                label: widget.style.seatLabel(topSeat),
                books: s.books[topSeat].length,
                active: s.currentIndex == topSeat && _outcome == null,
              ),
            ),
            Positioned(
              right: 12,
              top: 10,
              child: _SeatChip(
                label: widget.style.seatLabel(_bottomSeat),
                books: s.books[_bottomSeat].length,
                active: s.currentIndex == _bottomSeat && _outcome == null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- books -----------------------------------------------------------------

  /// A seat's completed books, laid out as rank chips. A book is four cards of
  /// one rank, so the chip says exactly that: the rank, big, over the four
  /// suits it took.
  Widget _buildBooksRow(
    Size size,
    GoFishState s, {
    required int seat,
    required double top,
    required double chipH,
  }) {
    final books = s.books[seat];
    final fresh = s.lastEvent.actor == seat && s.lastEvent.books.isNotEmpty
        ? s.lastEvent.books.last
        : null;
    return Positioned(
      left: 8,
      right: 8,
      top: top,
      height: chipH,
      child: IgnorePointer(
        child: CustomPaint(
          painter: _BooksPainter(
            books: books,
            height: chipH,
            tint: widget.style.bookTint,
            fresh: fresh,
            pulse: _bookPulse!.value,
          ),
        ),
      ),
    );
  }

  // -- pond ------------------------------------------------------------------

  Widget _buildPond(Size size, GoFishState s, _Bands b) {
    final cardW = b.pondW;
    final cardH = cardW * kCardAspectRatio;
    final cx = size.width / 2;
    final cy = b.pondCenterY;
    final enter = Curves.easeOutCubic.transform(
      ((_entrance!.value - 0.3) / 0.7).clamp(0.0, 1.0),
    );
    final depth = math.min(4, s.pond.length);

    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: enter,
          child: Stack(
            children: [
              for (var i = depth - 1; i >= 0; i--)
                Positioned(
                  left: cx - cardW / 2 - i * 1.8,
                  top: cy - cardH / 2 - i * 1.8,
                  child: CardView(
                    card: null,
                    faceUp: false,
                    width: cardW,
                    style: widget.style.cards,
                    shadow: i == 0,
                  ),
                ),
              if (depth == 0)
                Positioned(
                  left: cx - cardW / 2,
                  top: cy - cardH / 2,
                  child: _EmptyPond(width: cardW),
                ),
              Positioned(
                left: 0,
                right: 0,
                top: b.pondCountTop,
                child: Center(
                  child: _CountBadge(
                    count: s.pond.length,
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -- the running commentary ------------------------------------------------

  /// The running commentary.
  ///
  /// An ask *happening* is an event, not a state — it used to be a static pill
  /// that simply sat there until the next one replaced it, which read as
  /// chrome rather than as news. A [GameNotice] arrives, says its piece and
  /// retracts on its own, and being a single animating node it cannot collide
  /// with itself when the same line comes round twice.
  Widget _buildNotice(Size size, GoFishState s, _Bands b) {
    final event = _noticeFor(s);

    return Positioned(
      left: 10,
      right: 10,
      top: b.noticeTop,
      child: IgnorePointer(
        child: Center(
          child: GameNotice(
            message: _noticeShown,
            tone: event.tone,
            accent: event.accent,
            autoDismiss: _kNoticeLife,
          ),
        ),
      ),
    );
  }

  /// The commentary, written from the point of view of whoever is holding the
  /// phone. A fished card is private, so it is only named for its own owner.
  ({String? text, GameNoticeTone tone, Color? accent}) _noticeFor(
    GoFishState s,
  ) {
    final e = s.lastEvent;
    final style = widget.style;

    String who(int seat) =>
        seat == _bottomSeat ? 'You' : style.seatLabel(seat);
    String plural(Rank r) => r == Rank.six ? 'sixes' : '${r.label}s';

    final actor = e.actor;
    String? text;
    var tone = GameNoticeTone.info;
    Color? accent;

    switch (e.action) {
      case GoFishAction.deal:
        // The action bar already says to pick a rank; a second copy of the
        // instruction over an untouched table is just noise.
        text = null;
      case GoFishAction.caught:
        final n = e.taken.length;
        text = '${who(1 - actor!)} had $n ${plural(e.rank!)} — '
            '${who(actor)} go again';
        tone = GameNoticeTone.score;
        accent = style.catchTint;
      case GoFishAction.fished:
        final mine = actor == _bottomSeat;
        text = mine && e.drawn != null
            ? 'Go fish — you drew the ${e.drawn!.label}'
            : 'Go fish — ${who(actor!)} drew from the pond';
      case GoFishAction.fishedHit:
        text = '${who(actor!)} fished up the ${e.drawn!.label} — go again';
        tone = GameNoticeTone.score;
        accent = style.selection;
      case GoFishAction.fishedDry:
        text = 'Go fish — but the pond is empty';
        tone = GameNoticeTone.warn;
    }

    if (e.books.isNotEmpty && actor != null) {
      // Closing a book is the loudest thing that can happen on this table, so
      // it wins the line outright rather than queueing under the ask.
      text = '${who(actor)} book${actor == _bottomSeat ? '' : 's'} the '
          '${e.books.map(plural).join(' and ')}';
      tone = GameNoticeTone.score;
      accent = style.bookTint;
    }
    return (text: text, tone: tone, accent: accent);
  }

  // -- the hand --------------------------------------------------------------

  /// The width one hand card gets. Solved from the row rather than guessed at,
  /// and hoisted out of [_buildHand] so the layout can reserve exactly the
  /// height the hand will take.
  double _handCardWidth(Size size, GoFishState s) {
    final groups = s.groupedHand(_bottomSeat);
    if (groups.isEmpty) return 0;
    final total = groups.fold<int>(0, (n, g) => n + g.cards.length);
    final groupCount = groups.length;
    final denom = _kOverlap * total +
        (1 - _kOverlap + _kTrayGap) * groupCount -
        _kTrayGap;
    final available = size.width - 12;
    final cardW = ((available - _kTrayPad * 2 * (groupCount - 1)) / denom)
        .clamp(20.0, 66.0);
    return math.min(cardW, size.height * 0.16);
  }

  /// The hand, grouped by rank, each group in its own tray. The tray is the
  /// tap target: picking a rank and picking a group are the same gesture, so
  /// there is no way to ask for a rank you are not holding.
  List<Widget> _buildHand(Size size, GoFishState s, _Bands b) {
    final groups = s.groupedHand(_bottomSeat);
    if (groups.isEmpty) return const [];

    final total = groups.fold<int>(0, (n, g) => n + g.cards.length);
    const trayPad = _kTrayPad;
    const labelH = _kTrayLabelH;
    const overlap = _kOverlap; // fraction of a card the next one steps by
    const trayGap = _kTrayGap; // extra felt between two trays, in card widths

    final groupCount = groups.length;
    final available = size.width - 12;
    final cardW = _handCardWidth(size, s);
    final cardH = cardW * kCardAspectRatio;

    final gap = cardW * trayGap + trayPad * 2;
    var step = cardW * overlap;
    // A long hand in few groups overflows before the cards get small: tighten
    // the fan first, since a sliver of card still shows its corner index.
    final fixed = groupCount * cardW + gap * (groupCount - 1);
    if (total > groupCount && fixed + step * (total - groupCount) > available) {
      step = ((available - fixed) / (total - groupCount))
          .clamp(cardW * 0.24, step);
    }

    final width = groups.fold<double>(0, (w, g) {
          return w + cardW + step * (g.cards.length - 1) + gap;
        }) -
        gap;
    var x = (size.width - width) / 2;
    // The tray's label strip sits above the cards, so the band's top is the
    // tray top and the cards start one label down.
    final top = b.trayTop + trayPad + labelH;

    final enter = Curves.easeOutCubic.transform(
      ((_entrance!.value - 0.2) / 0.8).clamp(0.0, 1.0),
    );

    final trays = <Widget>[];
    final cards = <Widget>[];
    var dealt = 0;

    for (final group in groups) {
      final selected = _selected == group.rank;
      final groupW = cardW + step * (group.cards.length - 1);
      final lift = selected ? 12.0 : 0.0;

      trays.add(Positioned(
        left: x - trayPad,
        top: top - trayPad - labelH - lift,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _tapGroup(group.rank),
          child: _RankTray(
            width: groupW + trayPad * 2,
            height: cardH + trayPad * 2 + labelH,
            labelHeight: labelH,
            rank: group.rank,
            count: group.cards.length,
            color: selected
                ? widget.style.selection
                : Colors.white.withValues(alpha: 0.55),
            selected: selected,
          ),
        ),
      ));

      for (var i = 0; i < group.cards.length; i++) {
        final stagger = Curves.easeOutCubic.transform(
          ((enter * (total + 2)) - dealt).clamp(0.0, 1.0),
        );
        dealt++;
        if (stagger <= 0.01) continue;
        cards.add(Positioned(
          left: x + i * step,
          top: top - lift + (1 - stagger) * size.height * 0.14,
          child: Opacity(
            opacity: stagger,
            child: IgnorePointer(
              child: CardView(
                card: group.cards[i],
                width: cardW,
                style: widget.style.cards,
                shadow: i == group.cards.length - 1,
              ),
            ),
          ),
        ));
      }
      x += groupW + gap;
    }

    return [...trays, ...cards];
  }

  // -- action bar ------------------------------------------------------------

  Widget _buildActionBar(Size size, GoFishState s, _Bands b) {
    final children = <Widget>[];
    if (_pendingHandoff) {
      children.add(_TableButton(
        label: 'Pass to ${widget.style.seatLabel(s.currentIndex)}',
        onTap: _raiseCover,
      ));
    } else if (_bottomActs) {
      final rank = _selected;
      children.add(_TableButton(
        label: rank == null
            ? 'Pick a rank to ask for'
            : 'Ask for ${rank.label}s',
        tone: rank == null ? _ButtonTone.disabled : _ButtonTone.gold,
        onTap: rank == null ? null : _ask,
      ));
    } else {
      // Whose turn it is is a state, not an event: a static pill, never a
      // notice.
      children.add(GamePill(
        text: '${widget.style.seatLabel(s.currentIndex)} to ask',
      ));
    }

    return Positioned(
      left: 0,
      right: 0,
      top: b.actionTop,
      height: _kActionH,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      ),
    );
  }

  // -- the transfer beat -----------------------------------------------------

  /// The cards the opponent just handed over, flying from their side of the
  /// table into the hand. This is the payoff of an ask, so it gets real motion
  /// rather than a number quietly changing.
  List<Widget> _buildTransfer(Size size, GoFishState s, _Bands b) {
    final e = s.lastEvent;
    if (e.action != GoFishAction.caught || e.taken.isEmpty) return const [];
    // Only animate cards arriving at the visible hand; the opponent's private
    // haul is just a count change.
    if (e.actor != _bottomSeat) return const [];

    final t = Curves.easeOutCubic.transform(_transfer!.value);
    final cardW = (size.height * 0.095).clamp(34.0, 62.0);
    final fromY = b.backsTop;
    final toY = b.trayTop;
    final cx = size.width / 2;
    final spread = cardW * 0.7;

    return [
      for (var i = 0; i < e.taken.length; i++)
        Positioned(
          left: cx +
              (i - (e.taken.length - 1) / 2) * spread -
              cardW / 2 +
              math.sin(t * math.pi) * (i.isEven ? 10 : -10),
          top: fromY + (toY - fromY) * t,
          child: IgnorePointer(
            child: Opacity(
              opacity: (1 - t * t * 0.35).clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: (1 - t) * (i.isEven ? 0.18 : -0.18),
                child: CardView(
                  card: e.taken[i],
                  width: cardW,
                  style: widget.style.cards,
                  highlight: widget.style.catchTint,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  // -- endgame ---------------------------------------------------------------

  Widget _buildSummary(Size size, GoFishState s) {
    final outcome = _outcome!;
    final style = widget.style;
    final a = s.books[0].length;
    final b = s.books[1].length;
    final headline = outcome.isDraw
        ? '$a — $b · dead level'
        : '${style.seatLabel(a > b ? 0 : 1)} wins $a — $b';
    final reason = s.booksMade >= kGoFishBookCount
        ? 'All 13 books are made'
        : 'The pond is empty and nothing is left to trade';

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.52),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  headline.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  reason,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                for (var seat = 0; seat < 2; seat++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        Text(
                          '${style.seatLabel(seat)} · '
                          '${s.books[seat].length} '
                          '${s.books[seat].length == 1 ? 'book' : 'books'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: math.min(size.width - 40, 360),
                          height: 28,
                          child: CustomPaint(
                            painter: _BooksPainter(
                              books: s.books[seat],
                              height: 28,
                              tint: style.bookTint,
                              fresh: null,
                              pulse: 0,
                              centered: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -- handoff ---------------------------------------------------------------

  Widget _buildHandoffCover(GoFishState s) {
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
// Small pieces
// ---------------------------------------------------------------------------

/// One rank group in the hand: a tinted tray with the rank stroked into its
/// header, so the ask decision is readable without counting corner indices.
class _RankTray extends StatelessWidget {
  final double width;
  final double height;
  final double labelHeight;
  final Rank rank;
  final int count;
  final Color color;
  final bool selected;

  const _RankTray({
    required this.width,
    required this.height,
    required this.labelHeight,
    required this.rank,
    required this.count,
    required this.color,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _RankTrayPainter(
          labelHeight: labelHeight,
          rank: rank,
          count: count,
          color: color,
          selected: selected,
        ),
      ),
    );
  }
}

class _RankTrayPainter extends CustomPainter {
  final double labelHeight;
  final Rank rank;
  final int count;
  final Color color;
  final bool selected;

  const _RankTrayPainter({
    required this.labelHeight,
    required this.rank,
    required this.count,
    required this.color,
    required this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(9),
    );
    canvas.drawRRect(
      rrect,
      Paint()..color = color.withValues(alpha: selected ? 0.26 : 0.10),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.0 : 1.1
        ..color = color.withValues(alpha: selected ? 0.95 : 0.42),
    );

    // Rank, stroked rather than typeset — see CardGlyphs for why.
    final glyphH = labelHeight * 0.85;
    CardGlyphs.paintRun(
      canvas,
      rank.label,
      origin: Offset(5, (labelHeight - glyphH) / 2 + 0.5),
      height: glyphH,
      color: selected ? color : Colors.white.withValues(alpha: 0.88),
      weight: 0.22,
    );

    // A dot per card in the group: the size of the group at a glance.
    final dotR = labelHeight * 0.115;
    var dx = size.width - 5 - dotR;
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(
        Offset(dx, labelHeight / 2),
        dotR,
        Paint()..color = (selected ? color : Colors.white)
            .withValues(alpha: 0.85),
      );
      dx -= dotR * 3;
    }
  }

  @override
  bool shouldRepaint(_RankTrayPainter old) =>
      old.rank != rank ||
      old.count != count ||
      old.color != color ||
      old.selected != selected ||
      old.labelHeight != labelHeight;
}

/// A row of completed books. Each chip is the rank, big and stroked, over the
/// four suit pips it took to close — which is what a book physically is.
class _BooksPainter extends CustomPainter {
  final List<Rank> books;
  final double height;
  final Color tint;
  final Rank? fresh;
  final double pulse;
  final bool centered;

  const _BooksPainter({
    required this.books,
    required this.height,
    required this.tint,
    required this.fresh,
    required this.pulse,
    this.centered = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (books.isEmpty) return;
    const gap = 5.0;
    final chipW = math.min(
      height * 1.15,
      (size.width - gap * (books.length - 1)) / books.length,
    );
    final total = chipW * books.length + gap * (books.length - 1);
    var x = centered ? (size.width - total) / 2 : 0.0;

    for (final rank in books) {
      final isFresh = rank == fresh;
      final grow = isFresh ? 1 + 0.22 * math.sin(pulse * math.pi) : 1.0;
      final w = chipW * grow;
      final h = height * grow;
      final rect = Rect.fromCenter(
        center: Offset(x + chipW / 2, height / 2),
        width: w,
        height: h,
      );
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(h * 0.26));
      canvas.drawRRect(rrect, Paint()..color = tint.withValues(alpha: 0.22));
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isFresh ? 1.8 : 1.1
          ..color = tint.withValues(alpha: isFresh ? 1.0 : 0.62),
      );

      CardGlyphs.paintCentered(
        canvas,
        rank.label,
        center: Offset(rect.center.dx, rect.top + h * 0.38),
        height: h * 0.44,
        color: Colors.white,
        weight: 0.21,
      );

      // The four suits, in miniature, along the bottom of the chip.
      final pipS = h * 0.17;
      final pipY = rect.bottom - h * 0.20;
      final pipStart = rect.center.dx - pipS * 2.4;
      for (var i = 0; i < Suit.values.length; i++) {
        CardSuits.paint(
          canvas,
          Rect.fromCenter(
            center: Offset(pipStart + i * pipS * 1.6, pipY),
            width: pipS,
            height: pipS,
          ),
          Suit.values[i],
          Colors.white.withValues(alpha: 0.80),
        );
      }
      x += chipW + gap;
    }
  }

  @override
  bool shouldRepaint(_BooksPainter old) =>
      old.books.length != books.length ||
      old.fresh != fresh ||
      old.pulse != pulse ||
      old.height != height ||
      old.tint != tint;
}

/// A small stroked number — used where a count has to stay legible in a PNG
/// render, which rules out `Text`.
class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;

  const _CountBadge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    const h = 11.0;
    final label = '$count';
    return SizedBox(
      width: CardGlyphs.runWidth(label, h) + 14,
      height: h + 8,
      child: CustomPaint(painter: _CountPainter(label: label, color: color)),
    );
  }
}

class _CountPainter extends CustomPainter {
  final String label;
  final Color color;

  const _CountPainter({required this.label, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.height / 2),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.34),
    );
    CardGlyphs.paintCentered(
      canvas,
      label,
      center: Offset(size.width / 2, size.height / 2),
      height: size.height - 8,
      color: color,
      weight: 0.22,
    );
  }

  @override
  bool shouldRepaint(_CountPainter old) =>
      old.label != label || old.color != color;
}

/// The dashed footprint left where the pond used to be.
class _EmptyPond extends StatelessWidget {
  final double width;

  const _EmptyPond({required this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * kCardAspectRatio,
      child: CustomPaint(painter: const _EmptyPondPainter()),
    );
  }
}

class _EmptyPondPainter extends CustomPainter {
  const _EmptyPondPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(1),
      Radius.circular(size.width * 0.085),
    );
    canvas.drawRRect(
      rrect,
      Paint()..color = Colors.black.withValues(alpha: 0.16),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.28),
    );
  }

  @override
  bool shouldRepaint(_EmptyPondPainter old) => false;
}

class _SeatChip extends StatelessWidget {
  final String label;
  final int books;
  final bool active;

  const _SeatChip({
    required this.label,
    required this.books,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: active ? 0.36 : 0.18),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: Colors.white.withValues(alpha: active ? 0.45 : 0.12),
        ),
      ),
      child: Text(
        '$label · $books',
        style: TextStyle(
          color: Colors.white.withValues(alpha: active ? 1 : 0.72),
          fontWeight: active ? FontWeight.w800 : FontWeight.w600,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

enum _ButtonTone { primary, gold, disabled }

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
      _ButtonTone.primary => (
          Colors.black.withValues(alpha: 0.58),
          Colors.white,
        ),
      _ButtonTone.gold => (const Color(0xFFF4B740), const Color(0xFF221B08)),
      _ButtonTone.disabled => (
          Colors.black.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.40),
        ),
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(11),
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

/// Sea-green baize under a soft key from the upper left, with the faint swell
/// of a pond under the centre pile.
class _FeltPainter extends CustomPainter {
  final Color felt;

  /// Vertical centre of the pond, so the ripples ring the deck instead of
  /// landing at a fixed fraction that the deck has since moved away from.
  final double pondY;

  const _FeltPainter(this.felt, this.pondY);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.55),
          radius: 1.30,
          colors: [
            Color.lerp(felt, Colors.white, 0.14)!,
            felt,
            Color.lerp(felt, Colors.black, 0.45)!,
          ],
          stops: const [0.0, 0.42, 1.0],
        ).createShader(rect),
    );
    if (pondY <= 0) return;

    // The pond itself — a pool of darker, bluer water sunk into the cloth.
    // Without it the middle of the table is just felt with a deck sitting on
    // it, and every band around the deck reads as a gap rather than a bank.
    final pool = Rect.fromCenter(
      center: Offset(size.width * 0.5, pondY),
      width: size.width * 1.02,
      height: size.height * 0.44,
    );
    canvas.drawOval(
      pool,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(felt, const Color(0xFF06323B), 0.42)!,
            Color.lerp(felt, const Color(0xFF06323B), 0.22)!,
            felt.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.62, 1.0],
        ).createShader(pool),
    );

    for (var i = 1; i <= 4; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * 0.5, pondY),
          width: size.width * 0.26 * i,
          height: size.height * 0.075 * i,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          // The near rings are the brightest: a disturbance decaying outward
          // rather than four identical circles.
          ..color = Colors.white.withValues(alpha: 0.085 / i),
      );
    }
  }

  @override
  bool shouldRepaint(_FeltPainter old) =>
      old.felt != felt || old.pondY != pondY;
}
