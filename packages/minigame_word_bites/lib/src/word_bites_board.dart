import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigames_ui/minigames_ui.dart';
import 'package:minigames_words/minigames_words.dart';

import 'word_bites_game.dart';
import 'word_bites_style.dart';

/// The drag-and-snap Word Bites round board.
///
/// Self-contained GP-style scene: felt table backdrop, player chip + timer
/// row, kitchen-tile grid, chunky draggable letter pieces. Word detection
/// runs on every settle — a maximal contiguous horizontal or vertical run of
/// 3+ letters that is a dictionary word scores automatically (green flash +
/// score popup) and is reported via [onWordScored] with its placement
/// evidence. Each unique word scores once per board lifetime (= per round).
///
/// Drops that would overlap another piece or leave the grid bounce back.
/// Dominoes never rotate.
class WordBitesBoard extends StatefulWidget {
  final List<WordBitesPiece> pieces;
  final WordDictionary dictionary;
  final int rows;
  final int cols;
  final int minWordLength;
  final WordBitesStyle style;

  /// Whether input is accepted (round is live).
  final bool enabled;

  /// Chip label for the player whose round this is.
  final String playerLabel;

  /// Live round score shown on the chip (owned by the host screen).
  final int score;

  /// Countdown shown on the timer pill; hidden when null.
  final int? secondsLeft;

  /// Seed for the deterministic initial scatter — pass the match seed so both
  /// hot-seat rounds start from the identical layout.
  final int layoutSeed;

  /// Optional fixed starting layout (piece id -> anchor cell). Overrides the
  /// scatter; any words the layout already forms score after the first frame.
  final Map<int, WordBitesCell>? initialAnchors;

  /// A word just scored (already deduped board-side).
  final void Function(WordBitesPlay play, int points)? onWordScored;

  const WordBitesBoard({
    super.key,
    required this.pieces,
    required this.dictionary,
    this.rows = 9,
    this.cols = 8,
    this.minWordLength = 3,
    this.style = const WordBitesStyle(),
    this.enabled = true,
    this.playerLabel = 'Player 1',
    this.score = 0,
    this.secondsLeft,
    this.layoutSeed = 0,
    this.initialAnchors,
    this.onWordScored,
  });

  @override
  State<WordBitesBoard> createState() => _WordBitesBoardState();
}

class _WordBitesBoardState extends State<WordBitesBoard>
    with TickerProviderStateMixin {
  late Map<int, WordBitesCell> _anchors;
  final Map<String, WordBitesPlay> _scored = {};

  int? _dragId;
  Offset _dragPx = Offset.zero;
  WordBitesCell? _dragOrigin;

  int? _settleId;
  Offset _settleFromPx = Offset.zero;
  bool _settleIsBounce = false;

  // Assigned in initState, never from a field initialiser: a `late final x =
  // AnimationController(...)` that first runs during dispose() looks up a
  // deactivated element's ancestor and throws.
  late final AnimationController _settle;
  late final AnimationController _flash;

  List<WordBitesCell> _flashCells = const [];
  Offset _flashCenter = Offset.zero; // px, board space

  /// The word (or words) the last settle spelled. A scored word is an event,
  /// so it gets a notice that retracts on its own rather than a label that
  /// hangs about.
  String? _notice;

  double _cell = 0;

  WordBitesPiece _pieceById(int id) =>
      widget.pieces.firstWhere((p) => p.id == id);

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 170),
    )..addStatusListener(_onSettleStatus);
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _anchors = widget.initialAnchors != null
        ? Map.of(widget.initialAnchors!)
        : _scatter();
    if (widget.initialAnchors != null) {
      // A caller-provided layout may already spell words — score them once
      // geometry is known (cell size is set during the first layout pass).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_detectWords);
      });
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    _flash.dispose();
    super.dispose();
  }

  /// Deterministic non-overlapping scatter. Early attempts also refuse
  /// orthogonal adjacency so the round never opens with a pre-formed word.
  Map<int, WordBitesCell> _scatter() {
    final rnd = math.Random(widget.layoutSeed);
    final occupied = <WordBitesCell>{};
    final out = <int, WordBitesCell>{};

    bool blocked(List<(WordBitesCell, String)> cells, bool checkAdjacent) {
      for (final (cell, _) in cells) {
        if (occupied.contains(cell)) return true;
        if (checkAdjacent) {
          final (r, c) = cell;
          for (final n in [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)]) {
            if (occupied.contains(n)) return true;
          }
        }
      }
      return false;
    }

    for (final piece in widget.pieces) {
      var placed = false;
      for (var attempt = 0; attempt < 220 && !placed; attempt++) {
        final row = rnd.nextInt(widget.rows - piece.cellHeight + 1);
        final col = rnd.nextInt(widget.cols - piece.cellWidth + 1);
        final cells = piece.cellsAt(row, col);
        if (blocked(cells, attempt < 150)) continue;
        occupied.addAll([for (final (c, _) in cells) c]);
        out[piece.id] = (row, col);
        placed = true;
      }
      if (!placed) {
        // Fallback: first free slot, overlap-free only.
        for (var row = 0;
            row <= widget.rows - piece.cellHeight && !placed;
            row++) {
          for (var col = 0;
              col <= widget.cols - piece.cellWidth && !placed;
              col++) {
            final cells = piece.cellsAt(row, col);
            if (blocked(cells, false)) continue;
            occupied.addAll([for (final (c, _) in cells) c]);
            out[piece.id] = (row, col);
            placed = true;
          }
        }
      }
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Dragging
  // -------------------------------------------------------------------------

  Rect _pieceRect(WordBitesPiece piece, WordBitesCell anchor) {
    final (row, col) = anchor;
    return Rect.fromLTWH(
      col * _cell,
      row * _cell,
      piece.cellWidth * _cell,
      piece.cellHeight * _cell,
    );
  }

  void _onPanStart(DragStartDetails d) {
    if (!widget.enabled || _cell <= 0) return;
    int? hit;
    for (final piece in widget.pieces) {
      final anchor = _anchors[piece.id];
      if (anchor == null) continue;
      final rect = piece.id == _settleId
          ? Rect.fromLTWH(
              _currentTopLeft(piece).dx,
              _currentTopLeft(piece).dy,
              piece.cellWidth * _cell,
              piece.cellHeight * _cell,
            )
          : _pieceRect(piece, anchor);
      if (rect.inflate(_cell * 0.08).contains(d.localPosition)) hit = piece.id;
    }
    if (hit == null) return;
    if (_settleId == hit) {
      _settle.stop();
      _settleId = null;
    }
    final piece = _pieceById(hit);
    setState(() {
      _dragId = hit;
      _dragOrigin = _anchors[hit];
      _dragPx = _pieceRect(piece, _anchors[hit]!).topLeft;
      // Lifting a piece clears the last word's banner, and lets an identical
      // one be raised again: a notice will not re-present a message it has
      // already dismissed while the caller is still holding it.
      _notice = null;
    });
    widget.style.sounds.onPickup?.call();
    if (widget.style.haptics) HapticFeedback.selectionClick();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final id = _dragId;
    if (id == null) return;
    final piece = _pieceById(id);
    final maxX = (widget.cols - piece.cellWidth) * _cell;
    final maxY = (widget.rows - piece.cellHeight) * _cell;
    setState(() {
      _dragPx = Offset(
        (_dragPx.dx + d.delta.dx).clamp(-_cell * 0.45, maxX + _cell * 0.45),
        (_dragPx.dy + d.delta.dy).clamp(-_cell * 0.45, maxY + _cell * 0.45),
      );
    });
  }

  bool _overlapsOthers(WordBitesPiece piece, WordBitesCell anchor) {
    final (row, col) = anchor;
    final mine = {for (final (c, _) in piece.cellsAt(row, col)) c};
    for (final other in widget.pieces) {
      if (other.id == piece.id) continue;
      final a = _anchors[other.id];
      if (a == null) continue;
      for (final (c, _) in other.cellsAt(a.$1, a.$2)) {
        if (mine.contains(c)) return true;
      }
    }
    return false;
  }

  void _onPanEnd() {
    final id = _dragId;
    if (id == null) return;
    final piece = _pieceById(id);
    final col = (_dragPx.dx / _cell)
        .round()
        .clamp(0, widget.cols - piece.cellWidth);
    final row = (_dragPx.dy / _cell)
        .round()
        .clamp(0, widget.rows - piece.cellHeight);
    final target = (row, col);

    final ok = !_overlapsOthers(piece, target);
    setState(() {
      if (ok) {
        _anchors[id] = target;
        _startSettle(id, bounce: false);
      } else {
        _anchors[id] = _dragOrigin!;
        _startSettle(id, bounce: true);
      }
      _dragId = null;
      _dragOrigin = null;
    });
    if (!ok) {
      widget.style.sounds.onInvalid?.call();
      if (widget.style.haptics) HapticFeedback.lightImpact();
    }
  }

  void _startSettle(int id, {required bool bounce}) {
    _settleId = id;
    _settleFromPx = _dragPx;
    _settleIsBounce = bounce;
    _settle.forward(from: 0);
  }

  void _onSettleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final wasBounce = _settleIsBounce;
    setState(() {
      _settleId = null;
      if (!wasBounce) _detectWords();
    });
    if (!wasBounce) {
      widget.style.sounds.onSettle?.call();
      if (widget.style.haptics) HapticFeedback.selectionClick();
    }
  }

  // -------------------------------------------------------------------------
  // Word detection — maximal runs only (GP rule: ABCD never scores ABC)
  // -------------------------------------------------------------------------

  void _detectWords() {
    final letters = <WordBitesCell, String>{};
    final pieceOf = <WordBitesCell, int>{};
    for (final piece in widget.pieces) {
      final a = _anchors[piece.id];
      if (a == null) continue;
      for (final (cell, letter) in piece.cellsAt(a.$1, a.$2)) {
        letters[cell] = letter;
        pieceOf[cell] = piece.id;
      }
    }

    final candidates = <(String, List<WordBitesCell>)>[];
    void scan(bool horizontal) {
      final outer = horizontal ? widget.rows : widget.cols;
      final inner = horizontal ? widget.cols : widget.rows;
      for (var o = 0; o < outer; o++) {
        var i = 0;
        while (i < inner) {
          WordBitesCell at(int k) => horizontal ? (o, k) : (k, o);
          if (!letters.containsKey(at(i))) {
            i++;
            continue;
          }
          final run = <WordBitesCell>[];
          final sb = StringBuffer();
          while (i < inner && letters.containsKey(at(i))) {
            run.add(at(i));
            sb.write(letters[at(i)]);
            i++;
          }
          if (run.length >= widget.minWordLength) {
            candidates.add((sb.toString(), run));
          }
        }
      }
    }

    scan(true);
    scan(false);

    var points = 0;
    final flashCells = <WordBitesCell>{};
    final took = <String>[];
    for (final (word, cells) in candidates) {
      if (_scored.containsKey(word)) continue;
      if (!widget.dictionary.contains(word)) continue;
      final ids = <int>{for (final c in cells) pieceOf[c]!};
      final play = WordBitesPlay(
        word: word,
        placements: [
          for (final id in ids)
            WordBitesPlacement(
              pieceId: id,
              row: _anchors[id]!.$1,
              col: _anchors[id]!.$2,
            ),
        ],
      );
      final pts = WordBitesGame.scoreForLength(word.length);
      _scored[word] = play;
      points += pts;
      took.add(word);
      flashCells.addAll(cells);
      widget.onWordScored?.call(play, pts);
    }

    if (points > 0) {
      _flashCells = flashCells.toList();
      // Name the word, not just the number: "+8" alone leaves you guessing
      // which of the runs you just made actually counted.
      _notice = '${took.map((w) => w.toUpperCase()).join(' · ')}  +$points';
      var cx = 0.0, cy = 0.0;
      for (final (r, c) in _flashCells) {
        cx += (c + 0.5) * _cell;
        cy += (r + 0.5) * _cell;
      }
      _flashCenter = Offset(cx / _flashCells.length, cy / _flashCells.length);
      _flash.forward(from: 0);
      widget.style.sounds.onWordScored?.call();
      if (widget.style.haptics) HapticFeedback.mediumImpact();
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  Offset _currentTopLeft(WordBitesPiece piece) {
    if (piece.id == _dragId) return _dragPx;
    final anchor = _anchors[piece.id]!;
    final target = _pieceRect(piece, anchor).topLeft;
    if (piece.id == _settleId) {
      final t = Curves.easeOutCubic.transform(_settle.value);
      return Offset.lerp(_settleFromPx, target, t)!;
    }
    return target;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final table = style.table;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
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
          _headerRow(style),
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: widget.cols / widget.rows,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _cell = constraints.maxWidth / widget.cols;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: (_) => _onPanEnd(),
                  onPanCancel: _onPanEnd,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_settle, _flash]),
                    builder: (context, _) => _boardStack(style),
                  ),
                );
              },
            ),
          ),
          _foundRail(style),
        ],
      ),
    );
  }

  /// The words taken this round, newest first.
  ///
  /// The flash and the notice both pass; this is the record. It also stops a
  /// 9×8 board floating in the middle of the screen with a strip of bare felt
  /// under it.
  Widget _foundRail(WordBitesStyle style) {
    final words = _scored.keys.toList();
    return SizedBox(
      height: 42,
      child: words.isEmpty
          ? Center(
              child: Text(
                'Slide the bites together to spell words',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            )
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 9),
              itemCount: words.length,
              itemBuilder: (context, i) {
                final w = words[words.length - 1 - i];
                return Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      // Newest brightest, so the eye finds the last one taken.
                      color: style.flash.withValues(alpha: i == 0 ? 0.62 : 0.24),
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
                          '${WordBitesGame.scoreForLength(w.length)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.74),
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

  /// Whose round it is, what they have, and how long is left.
  ///
  /// All three are states rather than events, so the seat is a [GamePill] —
  /// but the score and the clock are the two numbers the round is actually
  /// about, and they were set in the same 14pt as the label. They are now
  /// read at a glance from across the table.
  Widget _headerRow(WordBitesStyle style) {
    final secondsLeft = widget.secondsLeft;
    final low = secondsLeft != null && secondsLeft <= 10;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GamePill(
          text: widget.playerLabel,
          accent: style.accent,
          dot: true,
        ),
        const SizedBox(width: 10),
        Text(
          '${widget.score}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 23,
            height: 1,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const Spacer(),
        if (secondsLeft != null)
          Text(
            '${secondsLeft ~/ 60}:${(secondsLeft % 60).toString().padLeft(2, '0')}',
            style: TextStyle(
              // Under ten seconds the clock is the only thing that matters,
              // so it is the only thing that changes colour.
              color: low ? const Color(0xFFFF6B5E) : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 23,
              height: 1,
              letterSpacing: 0.4,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }

  Widget _boardStack(WordBitesStyle style) {
    // Render order: static pieces, settling piece, dragged piece on top.
    final ordered = List<WordBitesPiece>.of(widget.pieces)
      ..sort((a, b) {
        int rank(WordBitesPiece p) =>
            p.id == _dragId ? 2 : (p.id == _settleId ? 1 : 0);
        return rank(a).compareTo(rank(b));
      });

    final flashT = _flash.value;
    final flashing = _flash.isAnimating && _flashCells.isNotEmpty;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _KitchenTilePainter(
              rows: widget.rows,
              cols: widget.cols,
              board: style.board,
              grout: style.grout,
            ),
          ),
        ),
        for (final piece in ordered) _pieceView(piece, style),
        if (flashing)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FlashPainter(
                  cells: _flashCells,
                  cell: _cell,
                  t: flashT,
                  color: style.flash,
                ),
              ),
            ),
          ),
        _scoreNotice(style),
      ],
    );
  }

  /// The scored word, named where it was spelled.
  ///
  /// Kept over the run itself rather than parked in the chrome — the green
  /// flash says *where*, this says *what*. One animating node, so two words
  /// scoring in quick succession queue instead of colliding.
  Widget _scoreNotice(WordBitesStyle style) {
    final boardW = _cell * widget.cols;
    final left = (_flashCenter.dx - 110)
        .clamp(0.0, math.max(0.0, boardW - 220))
        .toDouble();
    return Positioned(
      left: left,
      top: math.max(2.0, _flashCenter.dy - _cell * 1.5),
      width: 220,
      child: IgnorePointer(
        child: Center(
          child: GameNotice(
            message: _notice,
            tone: GameNoticeTone.score,
            accent: style.flash,
            autoDismiss: const Duration(milliseconds: 1600),
          ),
        ),
      ),
    );
  }

  Widget _pieceView(WordBitesPiece piece, WordBitesStyle style) {
    final topLeft = _currentTopLeft(piece);
    final lifted = piece.id == _dragId;
    final settling = piece.id == _settleId;
    // Satisfying settle: a small scale pulse as the piece lands.
    final settlePop =
        settling ? math.sin(math.pi * _settle.value) * 0.06 : 0.0;
    final scale = lifted ? 1.08 : 1.0 + settlePop;
    final w = piece.cellWidth * _cell;
    final h = piece.cellHeight * _cell;

    final letterCells = switch (piece.shape) {
      WordBitesPieceShape.single => [piece.letters],
      _ => [piece.letters[0], piece.letters[1]],
    };

    final tile = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cell * 0.22),
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
          width: math.max(1, _cell * 0.028),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: lifted ? 0.32 : 0.16),
            blurRadius: lifted ? _cell * 0.35 : _cell * 0.12,
            offset: Offset(0, lifted ? _cell * 0.16 : _cell * 0.055),
          ),
        ],
      ),
      child: piece.shape == WordBitesPieceShape.vertical
          ? Column(children: _letterChildren(letterCells, style, vertical: true))
          : Row(children: _letterChildren(letterCells, style, vertical: false)),
    );

    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: w,
      height: h,
      child: Transform.scale(
        scale: scale,
        child: Padding(
          padding: EdgeInsets.all(_cell * 0.05),
          child: tile,
        ),
      ),
    );
  }

  List<Widget> _letterChildren(
    List<String> letters,
    WordBitesStyle style, {
    required bool vertical,
  }) {
    final children = <Widget>[];
    for (var i = 0; i < letters.length; i++) {
      if (i > 0) {
        children.add(Container(
          width: vertical ? double.infinity : 1.2,
          height: vertical ? 1.2 : double.infinity,
          margin: vertical
              ? EdgeInsets.symmetric(horizontal: _cell * 0.16)
              : EdgeInsets.symmetric(vertical: _cell * 0.16),
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
              fontSize: _cell * 0.52,
              height: 1,
            ),
          ),
        ),
      ));
    }
    return children;
  }
}

/// Pale porcelain kitchen tiles with grout lines (the GP Word Bites board).
class _KitchenTilePainter extends CustomPainter {
  final int rows;
  final int cols;
  final Color board;
  final Color grout;

  _KitchenTilePainter({
    required this.rows,
    required this.cols,
    required this.board,
    required this.grout,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / cols;
    final rect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.28));

    // Grout base.
    canvas.drawRRect(outer, Paint()..color = grout);

    // Individual tiles.
    final inset = cell * 0.035;
    final tileRadius = Radius.circular(cell * 0.14);
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
        // Subtle checker shimmer so the surface doesn't read flat.
        final lift = (r + c).isEven ? 0.06 : 0.0;
        tilePaint.color = Color.lerp(board, Colors.white, 0.04 + lift)!;
        canvas.drawRRect(tile, tilePaint);
        // Top-edge highlight per tile (glazed ceramic read).
        canvas.drawLine(
          Offset(tile.left + cell * 0.10, tile.top + cell * 0.06),
          Offset(tile.right - cell * 0.10, tile.top + cell * 0.06),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.35)
            ..strokeWidth = math.max(1, cell * 0.03)
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Soft inner shadow around the whole slab edge.
    canvas.drawRRect(
      outer.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, cell * 0.05)
        ..color = Colors.black.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_KitchenTilePainter old) =>
      old.rows != rows ||
      old.cols != cols ||
      old.board != board ||
      old.grout != grout;
}

/// Green flash over the cells of freshly scored words.
class _FlashPainter extends CustomPainter {
  final List<WordBitesCell> cells;
  final double cell;
  final double t;
  final Color color;

  _FlashPainter({
    required this.cells,
    required this.cell,
    required this.t,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Two quick pulses that decay — GP's word flash.
    final envelope = (1 - t).clamp(0.0, 1.0);
    final pulse = 0.65 + 0.35 * math.sin(t * math.pi * 4);
    final alpha = 0.55 * envelope * pulse;
    if (alpha <= 0.01) return;
    final paint = Paint()..color = color.withValues(alpha: alpha);
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
  bool shouldRepaint(_FlashPainter old) =>
      old.t != t || old.cells != cells || old.color != color;
}
