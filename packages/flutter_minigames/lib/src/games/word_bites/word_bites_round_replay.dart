import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_minigames/src/ui/ui.dart';

import 'word_bites_game.dart';
import 'word_bites_style.dart';

/// Fraction of a play's time budget spent sliding pieces into place.
const double _slideFrac = 0.35;

/// Fraction of a play's time budget spent held on the formed word (ends at
/// `_slideFrac + _holdFrac`).
const double _holdFrac = 0.45;
// The remaining 0.20 is the fade-out before the next play begins.

/// Held on the fully-resolved final frame after the last word, in seconds.
const double _finalHoldSeconds = 0.45;

/// Where in a play's local timeline (0..1) we currently are, and which play
/// (if any) is active. `activeIndex == null` means every play has finished —
/// the timeline is in its closing hold.
typedef _Frame = ({int? activeIndex, double lf});

/// Compressed highlight reel of one player's Word Bites round.
///
/// Word Bites has no continuous board history — pieces move throughout the
/// live round and [WordBitesState] only keeps a snapshot of piece positions
/// per scored word. So this does not render one board all the plays share;
/// it clears to just the pieces involved in each play in turn, slides them in
/// from the board's centre to their scored [WordBitesPlacement] cells, holds
/// on the formed word + points, then fades before the next play's pieces
/// arrive. See the class docs on [WordBitesState] / [WordBitesPlay] for why.
class WordBitesRoundReplay extends StatefulWidget {
  final WordBitesGame game;
  final WordBitesState state;

  /// Whose round is being replayed (normally the opponent).
  final String playerId;

  /// Who is watching — used only to mark which words they also found.
  final String viewerId;

  final RoundReplayController controller;
  final WordBitesStyle style;

  const WordBitesRoundReplay({
    super.key,
    required this.game,
    required this.state,
    required this.playerId,
    required this.viewerId,
    required this.controller,
    this.style = const WordBitesStyle(),
  });

  @override
  State<WordBitesRoundReplay> createState() => _WordBitesRoundReplayState();
}

class _WordBitesRoundReplayState extends State<WordBitesRoundReplay>
    with TickerProviderStateMixin {
  late List<WordBitesPlay> _plays;
  late List<double> _durations; // seconds, pacing-scaled, one per play
  late double _totalSeconds;
  late Set<String> _viewerWords;
  late Map<int, WordBitesPiece> _pieceById;

  // Assigned in initState, never as a `late final` field initialiser: one
  // that first runs during dispose() looks up a deactivated element's
  // ancestor and throws (see word_bites_board.dart's own controllers).
  late AnimationController _controller;

  bool _skipped = false;

  @override
  void initState() {
    super.initState();
    _pieceById = {for (final p in widget.state.pieces) p.id: p};
    _plays = widget.state.submissionOf(widget.playerId)?.plays ??
        const <WordBitesPlay>[];
    _viewerWords = {
      for (final p in widget.state.submissionOf(widget.viewerId)?.plays ??
          const <WordBitesPlay>[])
        p.word,
    };

    final raw = [for (final p in _plays) _baseSecondsFor(p.word.length)];
    final rawTotal = raw.fold<double>(0, (a, b) => a + b);
    final scale = rawTotal > 15.0 ? 15.0 / rawTotal : 1.0;
    _durations = [for (final s in raw) s * scale];
    final wordsTotal = _durations.fold<double>(0, (a, b) => a + b);
    _totalSeconds = wordsTotal + _finalHoldSeconds;

    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: (_totalSeconds * 1000).round().clamp(1, 1 << 30),
      ),
    )..addStatusListener(_onStatus);
    widget.controller.addListener(_onReplayControllerNotify);
    _controller.forward();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onReplayControllerNotify);
    _controller.dispose();
    super.dispose();
  }

  static double _baseSecondsFor(int wordLength) =>
      (0.35 + 0.13 * (wordLength - 3)).clamp(0.35, 1.2);

  void _onReplayControllerNotify() {
    if (!widget.controller.skipRequested || _skipped) return;
    _controller.stop();
    setState(() => _skipped = true);
    widget.controller.markFinished();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_skipped) {
      widget.controller.markFinished();
    }
  }

  /// Which play (if any) is active at global progress [t] (0..1), and how
  /// far into that play's own local timeline we are.
  _Frame _frameAt(double t) {
    final seconds = t * _totalSeconds;
    var acc = 0.0;
    for (var i = 0; i < _durations.length; i++) {
      final d = _durations[i];
      if (seconds < acc + d) {
        final lf = d <= 0 ? 1.0 : ((seconds - acc) / d).clamp(0.0, 1.0);
        return (activeIndex: i, lf: lf);
      }
      acc += d;
    }
    return (activeIndex: null, lf: 0);
  }

  /// A play counts as "found" (scored + added to the strip) once its hold
  /// phase begins — that is the moment its word is fully formed on screen.
  bool _isRevealed(int i, _Frame frame) {
    if (frame.activeIndex == null) return true;
    if (i < frame.activeIndex!) return true;
    return i == frame.activeIndex && frame.lf >= _slideFrac;
  }

  /// The word run's cells for [play] — the maximal contiguous run its
  /// placements spell, same geometry the game itself validated. Used both to
  /// flash the right cells and to centre the score popup.
  List<WordBitesCell> _wordRunCells(WordBitesPlay play) {
    final letters = <WordBitesCell, String>{};
    for (final pl in play.placements) {
      final piece = _pieceById[pl.pieceId];
      if (piece == null) continue;
      for (final (cell, letter) in piece.cellsAt(pl.row, pl.col)) {
        letters[cell] = letter;
      }
    }
    for (final horizontal in const [true, false]) {
      for (final cell in letters.keys) {
        final (r, c) = cell;
        final before = horizontal ? (r, c - 1) : (r - 1, c);
        if (letters.containsKey(before)) continue;
        final runCells = <WordBitesCell>[];
        final sb = StringBuffer();
        var cur = cell;
        while (letters.containsKey(cur)) {
          runCells.add(cur);
          sb.write(letters[cur]);
          final (cr, cc) = cur;
          cur = horizontal ? (cr, cc + 1) : (cr + 1, cc);
        }
        if (sb.toString() == play.word) return runCells;
      }
    }
    return letters.keys.toList(); // shouldn't happen for a validated play
  }

  Rect _pieceRect(WordBitesPiece piece, WordBitesCell anchor, double cell) {
    final (row, col) = anchor;
    return Rect.fromLTWH(
      col * cell,
      row * cell,
      piece.cellWidth * cell,
      piece.cellHeight * cell,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;

    // A single AnimatedBuilder over the whole reactive body: header score,
    // board, and found strip all derive from the same frame, so they must
    // all repaint on the same tick rather than just the board (a `setState`
    // from skip() is the only other thing that can rebuild the outer tree).
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _skipped ? 1.0 : _controller.value;
        final frame = _frameAt(t);

        var runningScore = 0;
        for (var i = 0; i < _plays.length; i++) {
          if (_isRevealed(i, frame)) {
            runningScore += WordBitesGame.scoreForLength(_plays[i].word.length);
          }
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: RadialGradient(
              center: const Alignment(0, -0.35),
              radius: 1.5,
              colors: [
                Color.lerp(style.table, Colors.white, 0.07)!,
                style.table,
                Color.lerp(style.table, Colors.black, 0.26)!,
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
              _header(style, runningScore),
              const SizedBox(height: 10),
              AspectRatio(
                aspectRatio: widget.state.cols / widget.state.rows,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cell = constraints.maxWidth / widget.state.cols;
                    return _boardStack(style, cell, frame);
                  },
                ),
              ),
              const SizedBox(height: 10),
              _foundStrip(style, frame),
            ],
          ),
        );
      },
    );
  }

  Widget _header(WordBitesStyle style, int runningScore) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GamePill(text: 'Round replay', accent: style.accent, dot: true),
        const Spacer(),
        Text(
          '$runningScore',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 23,
            height: 1,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _boardStack(WordBitesStyle style, double cell, _Frame frame) {
    final children = <Widget>[
      Positioned.fill(
        child: CustomPaint(
          painter: _ReplayBoardPainter(
            rows: widget.state.rows,
            cols: widget.state.cols,
            board: style.board,
            grout: style.grout,
          ),
        ),
      ),
    ];

    final activeIndex = frame.activeIndex;
    if (activeIndex != null && activeIndex < _plays.length) {
      final play = _plays[activeIndex];
      final lf = frame.lf;
      final slideT = (lf / _slideFrac).clamp(0.0, 1.0);
      final holdEnd = _slideFrac + _holdFrac;
      final inSlide = lf < _slideFrac;
      final inHold = lf >= _slideFrac && lf < holdEnd;
      final inFade = lf >= holdEnd;
      final fadeT =
          inFade ? ((lf - holdEnd) / (1.0 - holdEnd)).clamp(0.0, 1.0) : 0.0;
      final opacity = inFade ? (1.0 - fadeT) : 1.0;

      final boardSize =
          Size(cell * widget.state.cols, cell * widget.state.rows);
      final center = boardSize.center(Offset.zero);

      final easedSlide = Curves.easeOutCubic.transform(slideT);
      final settlePop = inSlide ? math.sin(math.pi * slideT) * 0.06 : 0.0;
      final scale = 1.0 + settlePop;

      if (opacity > 0.01) {
        for (final pl in play.placements) {
          final piece = _pieceById[pl.pieceId];
          if (piece == null) continue;
          final endRect = _pieceRect(piece, (pl.row, pl.col), cell);
          final startTopLeft =
              center - Offset(endRect.width / 2, endRect.height / 2);
          final topLeft = inSlide
              ? Offset.lerp(startTopLeft, endRect.topLeft, easedSlide)!
              : endRect.topLeft;
          children.add(
            Positioned(
              left: topLeft.dx,
              top: topLeft.dy,
              width: endRect.width,
              height: endRect.height,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Padding(
                    padding: EdgeInsets.all(cell * 0.05),
                    child: _pieceTile(piece, style, cell),
                  ),
                ),
              ),
            ),
          );
        }
      }

      final runCells = _wordRunCells(play);
      var cx = 0.0, cy = 0.0;
      for (final (r, c) in runCells) {
        cx += (c + 0.5) * cell;
        cy += (r + 0.5) * cell;
      }
      final flashCenter = runCells.isEmpty
          ? center
          : Offset(cx / runCells.length, cy / runCells.length);

      if (inHold) {
        final holdT = ((lf - _slideFrac) / _holdFrac).clamp(0.0, 1.0);
        children.add(
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ReplayFlashPainter(
                  cells: runCells,
                  cell: cell,
                  t: holdT,
                  color: style.flash,
                ),
              ),
            ),
          ),
        );
      }

      final points = WordBitesGame.scoreForLength(play.word.length);
      final noticeLeft = (flashCenter.dx - 110)
          .clamp(0.0, math.max(0.0, boardSize.width - 220))
          .toDouble();
      children.add(
        Positioned(
          left: noticeLeft,
          top: math.max(2.0, flashCenter.dy - cell * 1.5),
          width: 220,
          child: IgnorePointer(
            child: Center(
              child: GameNotice(
                message: inHold ? '${play.word.toUpperCase()}  +$points' : null,
                tone: GameNoticeTone.score,
                accent: style.flash,
                token: activeIndex,
              ),
            ),
          ),
        ),
      );
    }

    return Stack(clipBehavior: Clip.none, children: children);
  }

  Widget _pieceTile(WordBitesPiece piece, WordBitesStyle style, double cell) {
    final letterCells = switch (piece.shape) {
      WordBitesPieceShape.single => [piece.letters],
      _ => [piece.letters[0], piece.letters[1]],
    };
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cell * 0.22),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(style.piece, Colors.white, 0.35)!,
            style.piece,
            Color.lerp(style.piece, const Color(0xFF8A6B3F), 0.22)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        border: Border.all(
          color: Color.lerp(style.piece, const Color(0xFF6B4A26), 0.45)!,
          width: math.max(1, cell * 0.028),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: cell * 0.14,
            offset: Offset(0, cell * 0.06),
          ),
        ],
      ),
      child: piece.shape == WordBitesPieceShape.vertical
          ? Column(
              children:
                  _letterChildren(letterCells, style, cell, vertical: true))
          : Row(
              children:
                  _letterChildren(letterCells, style, cell, vertical: false)),
    );
  }

  List<Widget> _letterChildren(
    List<String> letters,
    WordBitesStyle style,
    double cell, {
    required bool vertical,
  }) {
    final children = <Widget>[];
    for (var i = 0; i < letters.length; i++) {
      if (i > 0) {
        children.add(Container(
          width: vertical ? double.infinity : 1.2,
          height: vertical ? 1.2 : double.infinity,
          margin: vertical
              ? EdgeInsets.symmetric(horizontal: cell * 0.16)
              : EdgeInsets.symmetric(vertical: cell * 0.16),
          color: style.letter.withValues(alpha: 0.25),
        ));
      }
      children.add(Expanded(
        child: Center(
          child: Text(
            letters[i].toUpperCase(),
            style: TextStyle(
              color: style.letter,
              fontWeight: FontWeight.w900,
              fontSize: cell * 0.52,
              height: 1,
            ),
          ),
        ),
      ));
    }
    return children;
  }

  /// The words revealed so far, in found order. Words the viewer also found
  /// are subdued; words only [playerId] found are vivid (a flash-tinted
  /// glow) — "here's one you missed".
  Widget _foundStrip(WordBitesStyle style, _Frame frame) {
    if (_plays.isEmpty) {
      return const Text(
        'No words',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: Colors.white70,
        ),
      );
    }

    final revealed = [
      for (var i = 0; i < _plays.length; i++)
        if (_isRevealed(i, frame)) _plays[i],
    ];

    return SizedBox(
      height: 30,
      child: revealed.isEmpty
          ? const SizedBox.shrink()
          : Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final play in revealed)
                  _foundChip(style, play,
                      foundByViewer: _viewerWords.contains(play.word)),
              ],
            ),
    );
  }

  Widget _foundChip(
    WordBitesStyle style,
    WordBitesPlay play, {
    required bool foundByViewer,
  }) {
    final points = WordBitesGame.scoreForLength(play.word.length);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: style.flash.withValues(alpha: foundByViewer ? 0.14 : 0.30),
        borderRadius: BorderRadius.circular(999),
        border: foundByViewer
            ? null
            : Border.all(color: style.flash.withValues(alpha: 0.75), width: 1),
        boxShadow: foundByViewer
            ? null
            : [
                BoxShadow(
                  color: style.flash.withValues(alpha: 0.35),
                  blurRadius: 8,
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            play.word.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: Colors.white.withValues(alpha: foundByViewer ? 0.55 : 1.0),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '$points',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color:
                  Colors.white.withValues(alpha: foundByViewer ? 0.40 : 0.80),
            ),
          ),
        ],
      ),
    );
  }
}

/// Simplified porcelain-tile board background for the replay — a faithful
/// but cheaper read of `_KitchenTilePainter` in word_bites_board.dart.
class _ReplayBoardPainter extends CustomPainter {
  final int rows;
  final int cols;
  final Color board;
  final Color grout;

  _ReplayBoardPainter({
    required this.rows,
    required this.cols,
    required this.board,
    required this.grout,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / cols;
    final rect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.22));
    canvas.drawRRect(outer, Paint()..color = grout);

    final inset = cell * 0.04;
    final tileRadius = Radius.circular(cell * 0.12);
    final tilePaint = Paint();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final tile = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            c * cell + inset,
            r * cell + inset,
            cell - inset * 2,
            cell - inset * 2,
          ),
          tileRadius,
        );
        tilePaint.color =
            Color.lerp(board, Colors.white, (r + c).isEven ? 0.05 : 0.0)!;
        canvas.drawRRect(tile, tilePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_ReplayBoardPainter old) =>
      old.rows != rows ||
      old.cols != cols ||
      old.board != board ||
      old.grout != grout;
}

/// Pulsing green highlight over a formed word's cells while it is held.
class _ReplayFlashPainter extends CustomPainter {
  final List<WordBitesCell> cells;
  final double cell;
  final double t;
  final Color color;

  _ReplayFlashPainter({
    required this.cells,
    required this.cell,
    required this.t,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = (0.55 + 0.30 * math.sin(t * math.pi * 3)).clamp(0.0, 1.0);
    final paint = Paint()..color = color.withValues(alpha: pulse * 0.55);
    for (final (r, c) in cells) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            c * cell + cell * 0.05,
            r * cell + cell * 0.05,
            cell * 0.9,
            cell * 0.9,
          ),
          Radius.circular(cell * 0.2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ReplayFlashPainter old) =>
      old.t != t || old.cells != cells || old.color != color;
}
