import 'package:flutter/material.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

import 'word_hunt_game.dart';
import 'word_hunt_style.dart';

/// A compressed highlight reel of [playerId]'s Word Hunt round, for
/// [viewerId] to watch after their own round is in.
///
/// Never a real-time re-run: every accepted word is played back in
/// submission order with a short, length-scaled trace-and-pop beat (see the
/// pacing formula on [_WordHuntRoundReplayState._buildDurations]), so an
/// 80-second round compresses to a few seconds. [controller] drives skip and
/// reports completion, exactly like the live board reports a finished round.
class WordHuntRoundReplay extends StatefulWidget {
  /// The game instance — supplies [WordHuntGame.findPathForWord] when a
  /// state has no recorded path (legacy data) and [WordHuntGame.scoreForLength]
  /// for scoring.
  final WordHuntGame game;

  /// The finished/submitted state to replay from.
  final WordHuntState state;

  /// Whose round this replay shows.
  final String playerId;

  /// Who is watching — used only to mark words they also found.
  final String viewerId;

  final RoundReplayController controller;

  final WordHuntStyle style;

  const WordHuntRoundReplay({
    super.key,
    required this.game,
    required this.state,
    required this.playerId,
    required this.viewerId,
    required this.controller,
    this.style = const WordHuntStyle(),
  });

  @override
  State<WordHuntRoundReplay> createState() => _WordHuntRoundReplayState();
}

/// One word's slot on the timeline: when it starts tracing, how long the
/// trace-and-pop beat lasts, and the path it traces.
class _WordSlot {
  final String word;
  final List<int> path;
  final double start;
  final double duration;

  const _WordSlot({
    required this.word,
    required this.path,
    required this.start,
    required this.duration,
  });

  double get end => start + duration;
}

/// What to paint for a given elapsed time on the timeline.
class _Frame {
  /// Index into the word list currently being traced, or -1 between words /
  /// during the closing hold.
  final int activeIndex;

  /// How much of the active word's path is revealed, 0..1.
  final double activeProgress;

  /// How many words (from the start) have finished their pop and belong in
  /// the found strip / running score.
  final int revealedCount;

  const _Frame(this.activeIndex, this.activeProgress, this.revealedCount);
}

class _WordHuntRoundReplayState extends State<WordHuntRoundReplay>
    with TickerProviderStateMixin {
  // Assigned in initState, never as a field initializer: a controller first
  // built during dispose() looks up a deactivated element's ancestor and
  // throws (see word_hunt_board.dart / word_bites_board.dart).
  late final AnimationController _ctrl;

  late final List<_WordSlot> _slots;
  late final double _wordsSeconds;

  static const double _holdSeconds = 0.45;

  bool _skipped = false;

  @override
  void initState() {
    super.initState();
    _slots = _buildSlots();
    _wordsSeconds = _slots.isEmpty ? 0 : _slots.last.end;

    final totalMs =
        ((_wordsSeconds + _holdSeconds) * 1000).round().clamp(1, 1 << 30);
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    )..addStatusListener(_onStatus);

    widget.controller.addListener(_onControllerChanged);

    if (_slots.isEmpty) {
      // Nothing to play — settle immediately rather than hang on an empty
      // timeline.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _skipped = true);
        widget.controller.markFinished();
      });
    } else {
      _ctrl.forward();
    }
  }

  /// Per-word pacing: `baseSeconds = (0.35 + 0.13 * (len - 3)).clamp(0.35,
  /// 1.2)`, summed and — if the round total exceeds 15s — scaled down so the
  /// whole reel fits in 15s. Short rounds are not padded back up.
  List<_WordSlot> _buildSlots() {
    final words = widget.state.wordsOf(widget.playerId);
    if (words.isEmpty) return const [];

    final rawDurations = [
      for (final w in words) (0.35 + 0.13 * (w.length - 3)).clamp(0.35, 1.2),
    ];
    final rawTotal = rawDurations.fold<double>(0, (a, b) => a + b);
    final scale = rawTotal > 15.0 ? 15.0 / rawTotal : 1.0;

    final slots = <_WordSlot>[];
    var start = 0.0;
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      final path = widget.state.pathOf(widget.playerId, word) ??
          widget.game.findPathForWord(widget.state.letters, word) ??
          const <int>[];
      final duration = rawDurations[i] * scale;
      slots.add(_WordSlot(
        word: word,
        path: path,
        start: start,
        duration: duration,
      ));
      start += duration;
    }
    return slots;
  }

  _Frame _frameAt(double t) {
    var revealed = 0;
    for (var i = 0; i < _slots.length; i++) {
      final slot = _slots[i];
      if (t < slot.start) break;
      if (t < slot.end) {
        final progress = slot.duration <= 0
            ? 1.0
            : ((t - slot.start) / slot.duration).clamp(0.0, 1.0);
        return _Frame(i, progress, revealed);
      }
      revealed = i + 1;
    }
    return _Frame(-1, 0, revealed);
  }

  void _onControllerChanged() {
    if (_skipped || !widget.controller.skipRequested) return;
    _ctrl.stop();
    setState(() => _skipped = true);
    widget.controller.markFinished();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_skipped) {
      widget.controller.markFinished();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _ctrl.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_slots.isEmpty || _skipped) {
      final frame = _Frame(-1, 0, _slots.length);
      return _buildScene(scheme, frame);
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value * (_wordsSeconds + _holdSeconds);
        return _buildScene(scheme, _frameAt(t));
      },
    );
  }

  Widget _buildScene(ColorScheme scheme, _Frame frame) {
    final state = widget.state;
    final style = widget.style;
    final table = style.resolveTable(scheme);
    final playerIndex = state.playerIds.indexOf(widget.playerId);
    final label =
        playerIndex < 0 ? widget.playerId : style.labelFor(playerIndex);
    final viewerWords = state.wordsOf(widget.viewerId).toSet();

    var runningScore = 0;
    for (var i = 0; i < frame.revealedCount; i++) {
      runningScore += WordHuntGame.scoreForLength(_slots[i].word.length);
    }

    final activeSlot =
        frame.activeIndex >= 0 ? _slots[frame.activeIndex] : null;
    final notice = activeSlot == null
        ? null
        : '${activeSlot.word.toUpperCase()}  '
            '+${WordHuntGame.scoreForLength(activeSlot.word.length)}';

    return Container(
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GamePill(text: '$label’s round', strong: true),
              GamePill(
                  text: '$runningScore', accent: style.resolveValid(scheme)),
            ],
          ),
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, c) {
                final geom = _ReplayGridGeom(c.maxWidth, state.size);
                return Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(geom.side * 0.05),
                          color: style.resolveBoard(scheme),
                        ),
                      ),
                    ),
                    for (var i = 0; i < state.letters.length; i++)
                      _tile(state, i, geom, scheme, activeSlot, frame),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _ReplayTracePainter(
                            geom: geom,
                            path: activeSlot?.path ?? const [],
                            progress: frame.activeProgress,
                            color: style.resolveValid(scheme),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: geom.side * 0.035,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Center(
                          child: GameNotice(
                            message: notice,
                            tone: GameNoticeTone.score,
                            token: frame.activeIndex,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          _buildFoundStrip(scheme, frame, viewerWords),
        ],
      ),
    );
  }

  Widget _tile(
    WordHuntState state,
    int index,
    _ReplayGridGeom geom,
    ColorScheme scheme,
    _WordSlot? activeSlot,
    _Frame frame,
  ) {
    final rect = geom.tileRect(index);
    final pathIndex = activeSlot?.path.indexOf(index) ?? -1;
    final onActivePath = activeSlot != null &&
        pathIndex >= 0 &&
        pathIndex <= _revealedCellIndex(activeSlot, frame.activeProgress);
    final tile = widget.style.resolveTile(scheme);
    final letter = widget.style.resolveLetter(scheme);
    final valid = widget.style.resolveValid(scheme);
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: AnimatedScale(
        scale: onActivePath ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          decoration: BoxDecoration(
            color: onActivePath ? valid : tile,
            borderRadius: BorderRadius.circular(rect.width * 0.22),
            border: Border.all(
              color: onActivePath
                  ? Color.lerp(valid, Colors.black, 0.18)!
                  : const Color(0xFFD8C58F),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            state.letters[index].toUpperCase(),
            style: TextStyle(
              color: onActivePath ? Colors.white : letter,
              fontWeight: FontWeight.w800,
              fontSize:
                  rect.width * (state.letters[index].length > 1 ? 0.34 : 0.46),
            ),
          ),
        ),
      ),
    );
  }

  /// How many cells of [slot]'s path are revealed at [progress] (0..1) —
  /// the index of the furthest revealed cell.
  int _revealedCellIndex(_WordSlot slot, double progress) {
    final segments = slot.path.length - 1;
    if (segments <= 0) return 0;
    return (progress * segments).ceil().clamp(0, segments);
  }

  /// The words revealed so far, newest first. Words [widget.viewerId] also
  /// found render subdued (lower opacity, no glow) — you already have those.
  /// Words only [widget.playerId] found render vivid — that's the point of
  /// watching.
  Widget _buildFoundStrip(
    ColorScheme scheme,
    _Frame frame,
    Set<String> viewerWords,
  ) {
    final valid = widget.style.resolveValid(scheme);
    if (frame.revealedCount == 0) {
      return SizedBox(
        height: 44,
        child: Center(
          child: Text(
            widget.state.wordsOf(widget.playerId).isEmpty
                ? 'No words'
                : 'Watching…',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 10),
        itemCount: frame.revealedCount,
        itemBuilder: (context, i) {
          final slot = _slots[frame.revealedCount - 1 - i];
          final alreadyKnown = viewerWords.contains(slot.word);
          return Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: alreadyKnown
                    ? Colors.white.withValues(alpha: 0.12)
                    : valid.withValues(alpha: i == 0 ? 0.60 : 0.32),
                borderRadius: BorderRadius.circular(7),
                border: alreadyKnown
                    ? null
                    : Border.all(color: valid.withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    slot.word.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white
                          .withValues(alpha: alreadyKnown ? 0.6 : 1),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${WordHuntGame.scoreForLength(slot.word.length)}',
                    style: TextStyle(
                      color: Colors.white
                          .withValues(alpha: alreadyKnown ? 0.45 : 0.78),
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
}

// ---------------------------------------------------------------------------
// Geometry (own small copy — word_hunt_board's _GridGeom is private and also
// carries drag hit-testing this widget never needs).
// ---------------------------------------------------------------------------

class _ReplayGridGeom {
  final double side;
  final int n;
  final double pad;
  final double gap;
  final double cell;

  _ReplayGridGeom(this.side, this.n)
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
}

// ---------------------------------------------------------------------------
// Trace painter — a growing polyline through the path's tile centers.
// ---------------------------------------------------------------------------

class _ReplayTracePainter extends CustomPainter {
  final _ReplayGridGeom geom;
  final List<int> path;
  final double progress;
  final Color color;

  const _ReplayTracePainter({
    required this.geom,
    required this.path,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (path.isEmpty || progress <= 0) return;
    if (path.length == 1) {
      canvas.drawCircle(
        geom.center(path.first),
        geom.cell * 0.18,
        Paint()..color = color.withValues(alpha: 0.8),
      );
      return;
    }

    final segments = path.length - 1;
    final reach = (progress * segments).clamp(0.0, segments.toDouble());
    final fullSegments = reach.floor();
    final partial = reach - fullSegments;

    final stroke = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = geom.cell * 0.30
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final p = Path()
      ..moveTo(geom.center(path.first).dx, geom.center(path.first).dy);
    for (var i = 1; i <= fullSegments && i < path.length; i++) {
      final c = geom.center(path[i]);
      p.lineTo(c.dx, c.dy);
    }
    if (fullSegments < segments && partial > 0) {
      final a = geom.center(path[fullSegments]);
      final b = geom.center(path[fullSegments + 1]);
      final mid = Offset.lerp(a, b, partial)!;
      p.lineTo(mid.dx, mid.dy);
    }
    canvas.drawPath(p, stroke);
  }

  @override
  bool shouldRepaint(covariant _ReplayTracePainter old) =>
      old.path != path || old.progress != progress || old.color != color;
}
