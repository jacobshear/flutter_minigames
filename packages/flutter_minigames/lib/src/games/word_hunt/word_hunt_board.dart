import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

import 'word_hunt_game.dart';
import 'word_hunt_style.dart';

/// Hot-seat Word Hunt round flow wired to a [MatchController].
///
/// Self-contains the GP chrome: pine felt table, player chips above and below
/// the parchment slab, and a [GameNotice] for the word you just traced.
/// Flow: "Player 1 ready?" cover → timed round with live drag-trace feedback
/// → handoff cover → player 2 round → results (word lists, solution list,
/// winner banner). Timing is enforced here, client-side, GamePigeon-style;
/// word validation is re-done inside [WordHuntGame.applyMove].
class WordHuntBoard extends StatefulWidget {
  final MatchController<WordHuntState, WordHuntMove> controller;

  /// The game instance backing [controller] — carries the dictionary used for
  /// live trace feedback and the results-screen solution list.
  final WordHuntGame game;

  final WordHuntStyle style;

  const WordHuntBoard({
    super.key,
    required this.controller,
    required this.game,
    this.style = const WordHuntStyle(),
  });

  @override
  State<WordHuntBoard> createState() => _WordHuntBoardState();
}

enum _TraceStatus { neutral, valid, duplicate }

class _WordHuntBoardState extends State<WordHuntBoard>
    with TickerProviderStateMixin {
  WordHuntState? _state;
  StreamSubscription<WordHuntState>? _sub;

  // Assigned in initState, never from a field initialiser: a `late final x =
  // AnimationController(...)` that first runs during dispose() looks up a
  // deactivated element's ancestor and throws.
  late final AnimationController _roundCtrl;
  late final AnimationController _flashCtrl;
  late final AnimationController _entrance;

  bool _roundActive = false;
  bool _submitting = false;
  bool _announcedOutcome = false;

  final List<int> _trace = [];
  List<int> _flashPath = const [];

  final List<TracedWord> _roundWords = [];
  final Set<String> _roundWordSet = {};
  int _roundScore = 0;

  /// The word just traced, and how it landed. Transient by nature, so it is a
  /// notice rather than a pill: it arrives, says its piece and retracts.
  String? _notice;
  GameNoticeTone _noticeTone = GameNoticeTone.score;

  /// How long a traced word stays up. [GameNotice] owns the countdown and
  /// will not re-present a line it has already dismissed, so the board runs no
  /// timer of its own.
  static const Duration _kNoticeLife = Duration(milliseconds: 1400);

  List<String>? _solutions;

  WordHuntGame get _game => widget.game;
  WordHuntStyle get _style => widget.style;

  @override
  void initState() {
    super.initState();
    _roundCtrl = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.style.roundSeconds),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _endRound();
      });
    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _state = widget.controller.state;
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _roundCtrl.dispose();
    _flashCtrl.dispose();
    _entrance.dispose();
    super.dispose();
  }

  void _onState(WordHuntState state) {
    final outcome = _game.outcome(state);
    if (outcome != null && !_announcedOutcome) {
      _announcedOutcome = true;
      if (outcome.isWin) {
        _style.sounds.onWin?.call();
        if (_style.haptics) HapticFeedback.heavyImpact();
      } else {
        _style.sounds.onDraw?.call();
        if (_style.haptics) HapticFeedback.mediumImpact();
      }
    }
    setState(() {
      _state = state;
      _submitting = false;
      _roundActive = false;
      _trace.clear();
      _roundWords.clear();
      _roundWordSet.clear();
      _roundScore = 0;
    });
  }

  // -------------------------------------------------------------------------
  // Round lifecycle
  // -------------------------------------------------------------------------

  void _startRound() {
    if (_roundActive || _submitting) return;
    if (_style.haptics) HapticFeedback.selectionClick();
    setState(() => _roundActive = true);
    _roundCtrl.duration = Duration(seconds: _style.roundSeconds);
    _roundCtrl.forward(from: 0);
  }

  void _endRound() {
    if (_submitting) return;
    final state = _state;
    if (state == null) return;
    _submitting = true;
    _roundActive = false;
    _trace.clear();
    final isFinalRound = state.submitted.length == state.playerIds.length - 1;
    if (!isFinalRound) {
      _style.sounds.onRoundEnd?.call();
      if (_style.haptics) HapticFeedback.mediumImpact();
    }
    widget.controller.submitMove(WordHuntMove(List.of(_roundWords)));
  }

  // -------------------------------------------------------------------------
  // Trace gesture
  // -------------------------------------------------------------------------

  String _traceWord(WordHuntState state) =>
      _trace.map((i) => state.letters[i]).join();

  _TraceStatus _statusOf(String word) {
    if (word.length >= WordHuntGame.minWordLength &&
        _game.dictionary.contains(word)) {
      return _roundWordSet.contains(word)
          ? _TraceStatus.duplicate
          : _TraceStatus.valid;
    }
    return _TraceStatus.neutral;
  }

  void _onPanStart(Offset local, _GridGeom geom, WordHuntState state) {
    if (!_roundActive) return;
    final cell = geom.hitTest(local);
    if (cell == null) return;
    setState(() {
      _trace
        ..clear()
        ..add(cell);
      // Starting a new trace clears the last verdict. It also lets the same
      // verdict be raised again — a notice will not re-present a message it
      // already dismissed unless the caller lets go of it first, and tracing
      // the same duplicate twice is routine here.
      _notice = null;
    });
    _style.sounds.onTilePick?.call();
    if (_style.haptics) HapticFeedback.selectionClick();
  }

  void _onPanUpdate(Offset local, _GridGeom geom, WordHuntState state) {
    if (!_roundActive) return;
    final cell = geom.hitTest(local);
    if (cell == null) return;
    if (_trace.isEmpty) {
      setState(() => _trace.add(cell));
      _style.sounds.onTilePick?.call();
      if (_style.haptics) HapticFeedback.selectionClick();
      return;
    }
    if (cell == _trace.last) return;
    // Back up: sliding onto the previous tile retracts the last one.
    if (_trace.length >= 2 && cell == _trace[_trace.length - 2]) {
      setState(() => _trace.removeLast());
      _style.sounds.onTilePick?.call();
      return;
    }
    if (_trace.contains(cell)) return;
    if (!WordHuntGame.areAdjacent(_trace.last, cell, state.size)) return;
    setState(() => _trace.add(cell));
    _style.sounds.onTilePick?.call();
    if (_style.haptics) HapticFeedback.selectionClick();
  }

  void _onPanEnd(WordHuntState state) {
    if (_trace.isEmpty) return;
    final word = _traceWord(state);
    final path = List.of(_trace);
    final status = _statusOf(word);
    setState(() => _trace.clear());

    if (status == _TraceStatus.valid) {
      final points = WordHuntGame.scoreForLength(word.length);
      setState(() {
        _roundWords.add(TracedWord(word, path));
        _roundWordSet.add(word);
        _roundScore += points;
        _raise('${word.toUpperCase()}  +$points', GameNoticeTone.score);
      });
      _style.sounds.onWordFound?.call();
      if (_style.haptics) HapticFeedback.lightImpact();
    } else if (status == _TraceStatus.duplicate) {
      setState(() {
        _raise('${word.toUpperCase()} — already found', GameNoticeTone.info);
      });
      _style.sounds.onInvalid?.call();
    } else if (word.length >= WordHuntGame.minWordLength) {
      setState(() {
        _flashPath = path;
        // A refusal shakes, which is exactly the read wanted here.
        _raise('${word.toUpperCase()} — not a word', GameNoticeTone.warn);
      });
      _flashCtrl.forward(from: 0);
      _style.sounds.onInvalid?.call();
      if (_style.haptics) HapticFeedback.selectionClick();
    }
  }

  void _raise(String message, GameNoticeTone tone) {
    _notice = message;
    _noticeTone = tone;
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = _state;
    if (state == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final table = _style.resolveTable(scheme);
    final outcome = _game.outcome(state);

    final Widget body;
    if (outcome != null) {
      body = _buildResults(state, outcome, scheme);
    } else if (_roundActive) {
      body = _buildRound(state, scheme);
    } else {
      body = _buildCover(state, scheme);
    }

    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) {
        final enter = Curves.easeOutCubic.transform(_entrance.value);
        return Opacity(
          opacity: enter.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.96 + 0.04 * enter, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        constraints: const BoxConstraints(maxWidth: 392),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _chip(state, 1, outcome),
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: KeyedSubtree(
                key: ValueKey(
                  outcome != null
                      ? 'results'
                      : '${state.currentPlayerId}-$_roundActive',
                ),
                child: body,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: _chip(state, 0, outcome),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(WordHuntState state, int playerIndex, GameOutcome? outcome) {
    final id = state.playerIds[playerIndex];
    final active = outcome == null && state.currentPlayerId == id;
    final winner = outcome?.isWin == true && outcome!.winnerId == id;
    final done = state.hasSubmitted(id);
    final label = _style.labelFor(playerIndex);
    final trailing = outcome != null || done
        ? ' · ${state.scoreOf(id)}'
        : (active && _roundActive ? ' · $_roundScore' : '');
    // Whose seat this is and what they have scored is a state, not an event:
    // the static pill, never a notice.
    return GamePill(
      text: '$label$trailing',
      strong: active || winner,
      accent: winner ? const Color(0xFFF4B740) : null,
      dot: winner,
    );
  }

  // -------------------------------------------------------------------------
  // Cover ("Player N ready?")
  // -------------------------------------------------------------------------

  Widget _buildCover(WordHuntState state, ColorScheme scheme) {
    final playerIndex = state.playerIds.indexOf(state.currentPlayerId);
    final label = _style.labelFor(playerIndex);
    final handoff = state.submitted.isNotEmpty;
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (handoff)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Pass the phone',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            Text(
              '$label ready?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 26,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_style.roundSeconds} seconds — trace words on the grid',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 22),
            _PillButton(
              label: 'Start round',
              color: _style.resolveValid(scheme),
              onTap: _startRound,
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Live round
  // -------------------------------------------------------------------------

  Widget _buildRound(WordHuntState state, ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _roundCtrl,
          builder: (context, _) {
            final total = _style.roundSeconds;
            final remaining = (total * (1 - _roundCtrl.value)).ceil();
            final urgent = remaining <= 10;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 4, right: 4),
              child: Row(
                children: [
                  _statBlock(
                    caption: 'TIME',
                    value:
                        '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
                    color: urgent ? const Color(0xFFFF6B57) : Colors.white,
                  ),
                  const Spacer(),
                  _statBlock(
                    caption: 'WORDS',
                    value: '${_roundWords.length}',
                    color: Colors.white,
                  ),
                  const Spacer(),
                  _statBlock(
                    caption: 'SCORE',
                    value: '$_roundScore',
                    color: const Color(0xFFF4B740),
                    alignEnd: true,
                  ),
                ],
              ),
            );
          },
        ),
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, c) {
              final geom = _GridGeom(c.maxWidth, state.size);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => _onPanStart(d.localPosition, geom, state),
                onPanUpdate: (d) => _onPanUpdate(d.localPosition, geom, state),
                onPanEnd: (_) => _onPanEnd(state),
                onPanCancel: () => _onPanEnd(state),
                child: _buildGrid(state, geom, scheme),
              );
            },
          ),
        ),
        _buildFoundRail(scheme),
      ],
    );
  }

  /// The words taken so far this round, newest first.
  ///
  /// The counter alone told you *how many* you had while the board sat over a
  /// strip of empty felt; the words themselves are what stops you retracing
  /// one you already have, and they earn the space.
  Widget _buildFoundRail(ColorScheme scheme) {
    final valid = _style.resolveValid(scheme);
    return SizedBox(
      height: 44,
      child: _roundWords.isEmpty
          ? Center(
              child: Text(
                'Trace three letters or more',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.42),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            )
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: _roundWords.length,
              itemBuilder: (context, i) {
                final w = _roundWords[_roundWords.length - 1 - i].word;
                return Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      // The newest sits brightest, so the eye lands on what
                      // just happened without re-reading the row.
                      color: valid.withValues(alpha: i == 0 ? 0.60 : 0.22),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      children: [
                        Text(
                          w.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${WordHuntGame.scoreForLength(w.length)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _statBlock({
    required String caption,
    required String value,
    required Color color,
    bool alignEnd = false,
  }) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          caption,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontWeight: FontWeight.w800,
            fontSize: 10,
            letterSpacing: 1.2,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 24,
            height: 1.05,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(WordHuntState state, _GridGeom geom, ColorScheme scheme) {
    final word = _traceWord(state);
    final status = _statusOf(word);
    final traceColor = switch (status) {
      _TraceStatus.valid => _style.resolveValid(scheme),
      _TraceStatus.duplicate => _style.resolveDuplicate(scheme),
      _TraceStatus.neutral => _style.resolveNeutral(scheme),
    };
    final board = _style.resolveBoard(scheme);

    return Stack(
      children: [
        // Parchment slab.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(geom.side * 0.05),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(board, Colors.white, 0.10)!,
                  board,
                  Color.lerp(board, Colors.black, 0.08)!,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  offset: const Offset(0, 5),
                  blurRadius: 7,
                ),
              ],
            ),
          ),
        ),
        // Grain. A flat gradient reads as a coloured rectangle; laid paper has
        // fibre in it and dirties toward its edges where hands have held it.
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(geom.side * 0.05),
              child: CustomPaint(painter: _ParchmentPainter(board)),
            ),
          ),
        ),
        // Tiles.
        for (var i = 0; i < state.letters.length; i++)
          _tile(state, i, geom, traceColor, scheme),
        // Trace overlay (live path + invalid flash).
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _flashCtrl,
              builder: (context, _) => CustomPaint(
                painter: _TracePainter(
                  geom: geom,
                  trace: List.of(_trace),
                  traceColor: traceColor,
                  flashPath: _flashPath,
                  flashColor: _style.resolveInvalid(scheme),
                  flashT: _flashCtrl.isAnimating ? _flashCtrl.value : 1.0,
                ),
              ),
            ),
          ),
        ),
        // The word you just traced.
        Positioned(
          top: geom.side * 0.035,
          left: 0,
          right: 0,
          child: IgnorePointer(child: Center(child: _noticeWidget())),
        ),
      ],
    );
  }

  Widget _tile(
    WordHuntState state,
    int index,
    _GridGeom geom,
    Color traceColor,
    ColorScheme scheme,
  ) {
    final rect = geom.tileRect(index);
    final selected = _trace.contains(index);
    final tile = _style.resolveTile(scheme);
    final letter = _style.resolveLetter(scheme);
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: AnimatedScale(
        scale: selected ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? traceColor : tile,
            borderRadius: BorderRadius.circular(rect.width * 0.22),
            border: Border.all(
              color: selected
                  ? Color.lerp(traceColor, Colors.black, 0.18)!
                  : const Color(0xFFD8C58F),
              width: math.max(1, rect.width * 0.03),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: selected ? 0.26 : 0.14),
                offset: Offset(0, rect.width * 0.055),
                blurRadius: rect.width * 0.10,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            state.letters[index].toUpperCase(),
            style: TextStyle(
              color: selected ? Colors.white : letter,
              fontWeight: FontWeight.w800,
              fontSize:
                  rect.width * (state.letters[index].length > 1 ? 0.34 : 0.46),
            ),
          ),
        ),
      ),
    );
  }

  /// The traced-word message.
  ///
  /// One animating node, never an [AnimatedSwitcher]: the same word is traced
  /// again constantly in this game — a duplicate, then the same duplicate
  /// again — and a switcher keyed on the text would mount the repeat beside
  /// its own still-leaving copy and throw "Duplicate keys found".
  Widget _noticeWidget() => GameNotice(
        message: _notice,
        tone: _noticeTone,
        autoDismiss: _kNoticeLife,
      );

  // -------------------------------------------------------------------------
  // Results
  // -------------------------------------------------------------------------

  Widget _buildResults(
    WordHuntState state,
    GameOutcome outcome,
    ColorScheme scheme,
  ) {
    final solutions = _solutions ??= _game.solveBoard(state.letters);
    final foundByAnyone = <String>{
      for (final id in state.playerIds) ...state.wordsOf(id),
    };
    final banner = outcome.isDraw
        ? 'DRAW'
        : '${_style.labelFor(state.playerIds.indexOf(outcome.winnerId!))} wins'
            .toUpperCase();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The result is not news by the time this screen is up — it is the
        // heading of a page you sit and read. A pill, not a notice.
        GamePill(
          text: banner,
          strong: true,
          accent: outcome.isDraw ? null : const Color(0xFFF4B740),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _playerColumn(state, 0, outcome, solutions.length),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _playerColumn(state, 1, outcome, solutions.length),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'All ${solutions.length} words on this board',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 120,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final word in solutions)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: foundByAnyone.contains(word)
                          ? _style.resolveValid(scheme).withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      word.toUpperCase(),
                      style: TextStyle(
                        color: Colors.white.withValues(
                          alpha: foundByAnyone.contains(word) ? 1 : 0.75,
                        ),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _playerColumn(
    WordHuntState state,
    int playerIndex,
    GameOutcome outcome,
    int totalWords,
  ) {
    final id = state.playerIds[playerIndex];
    final words = state.wordsOf(id);
    final winner = outcome.isWin && outcome.winnerId == id;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: winner ? 0.30 : 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: winner
              ? const Color(0xFFF4B740)
              : Colors.white.withValues(alpha: 0.10),
          width: winner ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _style.labelFor(playerIndex),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          Text(
            '${state.scoreOf(id)}',
            style: const TextStyle(
              color: Color(0xFFF4B740),
              fontWeight: FontWeight.w800,
              fontSize: 24,
              height: 1.1,
            ),
          ),
          Text(
            'Found ${words.length} of $totalWords',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 128,
            child: words.isEmpty
                ? Center(
                    child: Text(
                      'No words',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: words.length,
                    itemBuilder: (context, i) {
                      final w = words[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                w.toUpperCase(),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              '${WordHuntGame.scoreForLength(w.length)}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

class _GridGeom {
  final double side;
  final int n;
  final double pad;
  final double gap;
  final double cell;

  _GridGeom(this.side, this.n)
      : pad = side * 0.045,
        gap = side * 0.022,
        cell = (side - side * 0.09 - side * 0.022 * (n - 1)) / n;

  Rect tileRect(int index) {
    final row = index ~/ n;
    final col = index % n;
    return Rect.fromLTWH(
      pad + col * (cell + gap),
      pad + row * (cell + gap),
      cell,
      cell,
    );
  }

  Offset center(int index) => tileRect(index).center;

  /// Nearest tile whose center is within a forgiving radius, or null.
  /// The radius is kept under half the diagonal step so a diagonal drag
  /// cannot accidentally grab an orthogonal neighbour.
  int? hitTest(Offset local) {
    final stride = cell + gap;
    final col = ((local.dx - pad) / stride).floor().clamp(0, n - 1);
    final row = ((local.dy - pad) / stride).floor().clamp(0, n - 1);
    final index = row * n + col;
    final d = (local - center(index)).distance;
    return d <= cell * 0.44 ? index : null;
  }
}

// ---------------------------------------------------------------------------
// Parchment
// ---------------------------------------------------------------------------

/// Deterministic hash in `[0, 1)` — no `Random` anywhere in painting, so the
/// same slab renders identically every frame and in every test.
double _grain(int x, int y, int seed) {
  var n = (x * 374761393) ^ (y * 668265263) ^ (seed * 1274126177);
  n = (n ^ (n >> 13)) * 1274126177;
  n = n ^ (n >> 16);
  return (n & 0x3fffffff) / 0x3fffffff;
}

/// Laid paper: short fibres running with the grain, plus a soft dirty edge.
class _ParchmentPainter extends CustomPainter {
  final Color board;

  const _ParchmentPainter(this.board);

  @override
  void paint(Canvas canvas, Size size) {
    final fibre = Paint()
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    final cols = (size.width / 5).ceil();
    final rows = (size.height / 5).ceil();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final j = _grain(x, y, 11);
        if (j < 0.55) continue;
        final k = _grain(x, y, 29);
        fibre.color = (j > 0.82 ? Colors.white : const Color(0xFF6B5A33))
            .withValues(alpha: 0.03 + k * 0.05);
        final px = x * 5.0 + k * 5;
        final py = y * 5.0 + j * 5;
        canvas.drawLine(Offset(px, py), Offset(px + 2.2 + k, py), fibre);
      }
    }

    // Edges darken the way a much-handled sheet does.
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.3),
          radius: 0.95,
          colors: [
            const Color(0x00000000),
            Color.lerp(board, const Color(0xFF6B5A33), 0.30)!
                .withValues(alpha: 0.20),
          ],
          stops: const [0.62, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ParchmentPainter old) => old.board != board;
}

// ---------------------------------------------------------------------------
// Trace painter
// ---------------------------------------------------------------------------

class _TracePainter extends CustomPainter {
  final _GridGeom geom;
  final List<int> trace;
  final Color traceColor;
  final List<int> flashPath;
  final Color flashColor;
  final double flashT;

  _TracePainter({
    required this.geom,
    required this.trace,
    required this.traceColor,
    required this.flashPath,
    required this.flashColor,
    required this.flashT,
  });

  void _drawPath(Canvas canvas, List<int> path, Color color, double alpha) {
    if (path.isEmpty || alpha <= 0.01) return;
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.42 * alpha)
      ..strokeWidth = geom.cell * 0.36
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (path.length == 1) {
      canvas.drawCircle(
        geom.center(path.first),
        geom.cell * 0.18,
        Paint()..color = color.withValues(alpha: 0.42 * alpha),
      );
      return;
    }
    final p = Path()
      ..moveTo(geom.center(path.first).dx, geom.center(path.first).dy);
    for (final cell in path.skip(1)) {
      final c = geom.center(cell);
      p.lineTo(c.dx, c.dy);
    }
    canvas.drawPath(p, stroke);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawPath(canvas, trace, traceColor, 1);
    if (flashT < 1) {
      _drawPath(canvas, flashPath, flashColor, 1 - flashT);
    }
  }

  @override
  bool shouldRepaint(_TracePainter old) =>
      old.trace.length != trace.length ||
      old.traceColor != traceColor ||
      old.flashT != flashT ||
      old.flashPath != flashPath;
}

// ---------------------------------------------------------------------------
// Pill button (package-local; chrome-free)
// ---------------------------------------------------------------------------

class _PillButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                offset: const Offset(0, 4),
                blurRadius: 10,
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
