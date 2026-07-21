import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigames_core/minigames_core.dart';

import 'chess_game.dart';
import 'chess_pieces.dart';
import 'chess_style.dart';

/// Animated chess board wired to a [MatchController].
///
/// Self-contains the GP chrome: maroon felt table, Player 1 / Player 2 chips
/// above and below the slab, and a translucent black pill over the board
/// center for CHECK / CHECKMATE / STALEMATE / DRAW. Juice: move slide (rook
/// follows on castling), capture fade, legal-move dots, promotion picker,
/// confetti.
class ChessBoard extends StatefulWidget {
  final MatchController<ChessState, ChessMove> controller;
  final ChessStyle style;

  const ChessBoard({
    super.key,
    required this.controller,
    this.style = const ChessStyle(),
  });

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _PieceSlide {
  final String piece;
  final int from;
  final int to;
  const _PieceSlide(this.piece, this.from, this.to);
}

class _PieceFade {
  final String piece;
  final int cell;
  const _PieceFade(this.piece, this.cell);
}

class _ChessBoardState extends State<ChessBoard>
    with TickerProviderStateMixin {
  static const _game = ChessGame();

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );
  late final AnimationController _confettiCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  final math.Random _rnd = math.Random();
  StreamSubscription<ChessState>? _sub;
  Timer? _checkTimer;
  Timer? _mateTimer;

  /// Win pill sequencing: CHECKMATE flashes first, then the winner name.
  bool _showMatePill = false;

  ChessState? _state;
  List<String?> _cells = const [];
  GameOutcome? _outcome;
  bool _inCheck = false;
  bool _isStalemate = false;
  bool _showCheckPill = false;

  int? _selected;
  List<ChessMove> _targets = const [];
  List<ChessMove> _promoChoices = const [];

  List<_PieceSlide> _slides = const [];
  List<_PieceFade> _fades = const [];
  List<_Confetto> _confetti = const [];

  @override
  void initState() {
    super.initState();
    final s = widget.controller.state;
    if (s != null) _adopt(s, animateFrom: null);
    _entrance.forward();
    _sub = widget.controller.stateStream.listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _checkTimer?.cancel();
    _mateTimer?.cancel();
    _entrance.dispose();
    _slide.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  /// Load [state]-derived data (engine work happens once here, never in
  /// build). [animateFrom] is the previous cell list when a move landed.
  void _adopt(ChessState state, {required List<String?>? animateFrom}) {
    final cells = state.boardCells();
    final outcome = _game.outcome(state);
    _state = state;
    _cells = cells;
    _outcome = outcome;
    _inCheck = outcome == null && _game.isInCheck(state);
    _isStalemate = outcome?.isDraw == true && _game.isStalemate(state);

    _slides = const [];
    _fades = const [];
    final from = state.lastFrom;
    final to = state.lastTo;
    if (animateFrom != null && from != null && to != null) {
      final mover = cells[to];
      final slides = <_PieceSlide>[_PieceSlide(mover ?? '?', from, to)];
      // Castling: the rook slides along with the king.
      if ((mover == 'K' || mover == 'k') && (to - from).abs() == 2) {
        final row = to ~/ 8;
        final kingside = to % 8 == 6;
        slides.add(_PieceSlide(
          mover == 'K' ? 'R' : 'r',
          row * 8 + (kingside ? 7 : 0),
          row * 8 + (kingside ? 5 : 3),
        ));
      }
      final fades = <_PieceFade>[];
      final victim = animateFrom[to];
      if (victim != null) {
        fades.add(_PieceFade(victim, to));
      } else if ((mover == 'P' || mover == 'p') && from % 8 != to % 8) {
        // En passant: the captured pawn sat beside the destination.
        final epCell = (from ~/ 8) * 8 + to % 8;
        final epVictim = animateFrom[epCell];
        if (epVictim != null) fades.add(_PieceFade(epVictim, epCell));
      }
      _slides = slides;
      _fades = fades;
      _slide.forward(from: 0);
    }
  }

  void _onState(ChessState state) {
    final style = widget.style;
    final isNewGame =
        _state != null && state.history.length < _state!.history.length;
    final prevOutcome = _outcome;
    final prevCells = isNewGame ? null : _cells;

    if (isNewGame) {
      _confettiCtrl.value = 0;
      _confetti = const [];
      _checkTimer?.cancel();
      _showCheckPill = false;
      _mateTimer?.cancel();
      _showMatePill = false;
    }

    final hadCapture = !isNewGame &&
        state.lastTo != null &&
        prevCells != null &&
        (prevCells[state.lastTo!] != null ||
            // En passant lands on an empty square but still captures.
            _epVictimCell(state, prevCells) != null);

    _adopt(state, animateFrom: prevCells);

    if (!isNewGame && state.history.isNotEmpty) {
      if (hadCapture) {
        style.sounds.onCapture?.call();
        if (style.haptics) HapticFeedback.mediumImpact();
      } else {
        style.sounds.onMove?.call();
        if (style.haptics) HapticFeedback.lightImpact();
      }
      if (_inCheck) {
        style.sounds.onCheck?.call();
        _showCheckPill = true;
        _checkTimer?.cancel();
        _checkTimer = Timer(const Duration(milliseconds: 1100), () {
          if (mounted) setState(() => _showCheckPill = false);
        });
      }
    }

    if (_outcome != null && prevOutcome == null) {
      if (_outcome!.isWin) {
        style.sounds.onWin?.call();
        if (style.haptics) HapticFeedback.heavyImpact();
        _showMatePill = true;
        _mateTimer?.cancel();
        _mateTimer = Timer(const Duration(milliseconds: 1400), () {
          if (mounted) setState(() => _showMatePill = false);
        });
        if (style.confetti) {
          _confetti = _spawnConfetti(state);
          _confettiCtrl.forward(from: 0);
        }
      } else {
        style.sounds.onDraw?.call();
        if (style.haptics) HapticFeedback.mediumImpact();
      }
    }

    setState(() {
      _selected = null;
      _targets = const [];
      _promoChoices = const [];
    });
  }

  int? _epVictimCell(ChessState state, List<String?> prevCells) {
    final from = state.lastFrom;
    final to = state.lastTo;
    if (from == null || to == null) return null;
    final mover = state.boardCells()[to];
    if (mover != 'P' && mover != 'p') return null;
    if (from % 8 == to % 8 || prevCells[to] != null) return null;
    final epCell = (from ~/ 8) * 8 + to % 8;
    return prevCells[epCell] != null ? epCell : null;
  }

  List<_Confetto> _spawnConfetti(ChessState state) {
    final scheme = Theme.of(context).colorScheme;
    final palette = [
      widget.style.resolveWhitePiece(scheme),
      widget.style.resolveBlackPiece(scheme),
      widget.style.resolveHighlight(scheme),
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

  bool _ownsPiece(String piece, ChessState state) {
    final isWhitePiece = piece == piece.toUpperCase();
    return isWhitePiece == state.whiteToMove;
  }

  void _onTapCell(int cell) {
    final state = _state;
    if (state == null || _outcome != null || _promoChoices.isNotEmpty) return;
    if (!widget.controller.canActLocally) return;

    final piece = _cells[cell];

    // Tapping a target square plays (or opens the promotion picker).
    final hits = _targets.where((m) => m.to == cell).toList();
    if (hits.isNotEmpty) {
      if (hits.length > 1) {
        setState(() => _promoChoices = hits);
        if (widget.style.haptics) HapticFeedback.selectionClick();
      } else {
        widget.controller.submitMove(hits.first);
      }
      return;
    }

    // Tapping one of the mover's pieces (re)selects it.
    if (piece != null && _ownsPiece(piece, state)) {
      final moves = _game.legalMovesFrom(state, cell);
      setState(() {
        _selected = moves.isEmpty ? null : cell;
        _targets = moves;
      });
      if (moves.isEmpty) {
        widget.style.sounds.onInvalid?.call();
      } else if (widget.style.haptics) {
        HapticFeedback.selectionClick();
      }
      return;
    }

    if (_selected != null) {
      setState(() {
        _selected = null;
        _targets = const [];
      });
    }
  }

  void _pickPromotion(ChessMove move) {
    setState(() => _promoChoices = const []);
    widget.controller.submitMove(move);
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
    final whitePiece = style.resolveWhitePiece(scheme);
    final blackPiece = style.resolveBlackPiece(scheme);

    return AnimatedBuilder(
      animation: Listenable.merge([_entrance, _slide, _confettiCtrl]),
      builder: (context, _) {
        final enter = Curves.easeOutCubic.transform(_entrance.value);

        String? pillMsg;
        if (_outcome != null) {
          if (_outcome!.isWin) {
            // CHECKMATE flashes first, then hands off to the winner name.
            pillMsg = _showMatePill
                ? 'CHECKMATE'
                : (_outcome!.winnerId == state.whiteId
                        ? '${style.whiteLabel} wins'
                        : '${style.blackLabel} wins')
                    .toUpperCase();
          } else {
            pillMsg = _isStalemate ? 'STALEMATE' : 'DRAW';
          }
        } else if (_showCheckPill) {
          pillMsg = 'CHECK';
        }

        final board = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Transform.scale(
            scale: 0.94 + 0.06 * enter,
            child: Opacity(
              opacity: enter.clamp(0.0, 1.0),
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final side = c.maxWidth;
                    final cellSize = side / 8;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) {
                        final col =
                            (d.localPosition.dx / cellSize).floor().clamp(0, 7);
                        final row =
                            (d.localPosition.dy / cellSize).floor().clamp(0, 7);
                        _onTapCell(row * 8 + col);
                      },
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: Size.square(side),
                            painter: _ChessPainter(
                              cells: _cells,
                              light: style.resolveLight(scheme),
                              dark: style.resolveDark(scheme),
                              whitePiece: whitePiece,
                              blackPiece: blackPiece,
                              highlight: style.resolveHighlight(scheme),
                              lastFrom: state.lastFrom,
                              lastTo: state.lastTo,
                              selected: _selected,
                              targets: _targets,
                              slides: _slides,
                              fades: _fades,
                              slideT:
                                  Curves.easeOutCubic.transform(_slide.value),
                              checkedKing: _inCheck
                                  ? _kingCell(state.whiteToMove)
                                  : null,
                            ),
                          ),
                          if (_promoChoices.isNotEmpty)
                            Positioned.fill(
                              child: _PromotionPicker(
                                choices: _promoChoices,
                                isWhite: state.whiteToMove,
                                whitePiece: whitePiece,
                                blackPiece: blackPiece,
                                onPick: _pickPromotion,
                                onCancel: () => setState(
                                    () => _promoChoices = const []),
                              ),
                            ),
                          if (style.confetti && _confetti.isNotEmpty)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _ConfettiPainter(
                                    confetti: _confetti,
                                    t: _confettiCtrl.value,
                                    boardSize: side,
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

        // Felt table the slab sits on; opponent chip above, local chip below.
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                child: _PlayerChip(
                  label: style.blackLabel,
                  piece: 'k',
                  pieceColor: blackPiece,
                  active: _outcome == null && !state.whiteToMove,
                  winner: _outcome?.isWin == true &&
                      _outcome!.winnerId == state.blackId,
                ),
              ),
              const SizedBox(height: 10),
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
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: _PlayerChip(
                  label: style.whiteLabel,
                  piece: 'K',
                  pieceColor: whitePiece,
                  active: _outcome == null && state.whiteToMove,
                  winner: _outcome?.isWin == true &&
                      _outcome!.winnerId == state.whiteId,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  int? _kingCell(bool white) {
    final target = white ? 'K' : 'k';
    for (var i = 0; i < _cells.length; i++) {
      if (_cells[i] == target) return i;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _ChessPainter extends CustomPainter {
  final List<String?> cells;
  final Color light;
  final Color dark;
  final Color whitePiece;
  final Color blackPiece;
  final Color highlight;
  final int? lastFrom;
  final int? lastTo;
  final int? selected;
  final List<ChessMove> targets;
  final List<_PieceSlide> slides;
  final List<_PieceFade> fades;
  final double slideT;
  final int? checkedKing;

  _ChessPainter({
    required this.cells,
    required this.light,
    required this.dark,
    required this.whitePiece,
    required this.blackPiece,
    required this.highlight,
    required this.lastFrom,
    required this.lastTo,
    required this.selected,
    required this.targets,
    required this.slides,
    required this.fades,
    required this.slideT,
    required this.checkedKing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 8;
    final slab = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.035),
    );

    // Ground shadow — the slab floats just above the felt.
    canvas.drawRRect(
      slab.shift(const Offset(0, 5)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    canvas.save();
    canvas.clipRRect(slab);

    Rect squareRect(int i) =>
        Rect.fromLTWH((i % 8) * cell, (i ~/ 8) * cell, cell + 0.5, cell + 0.5);
    Offset squareCenter(int i) =>
        Offset((i % 8 + 0.5) * cell, (i ~/ 8 + 0.5) * cell);

    for (var i = 0; i < 64; i++) {
      final isDark = ((i % 8) + (i ~/ 8)).isOdd;
      canvas.drawRect(squareRect(i), Paint()..color = isDark ? dark : light);
    }

    // Last move + selection tints.
    for (final i in [lastFrom, lastTo]) {
      if (i != null) {
        canvas.drawRect(
          squareRect(i),
          Paint()..color = highlight.withValues(alpha: 0.30),
        );
      }
    }
    if (selected != null) {
      canvas.drawRect(
        squareRect(selected!),
        Paint()..color = highlight.withValues(alpha: 0.45),
      );
    }

    // Check flare under the threatened king.
    if (checkedKing != null) {
      canvas.drawCircle(
        squareCenter(checkedKing!),
        cell * 0.52,
        Paint()
          ..color = const Color(0xFFE53935).withValues(alpha: 0.4)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.22),
      );
    }

    final animatedTargets = {for (final s in slides) s.to};
    final piecesDone = slideT >= 1;

    // Static pieces.
    for (var i = 0; i < 64; i++) {
      final piece = cells[i];
      if (piece == null) continue;
      if (!piecesDone && animatedTargets.contains(i)) continue;
      ChessPieceArt.paint(
        canvas,
        center: squareCenter(i),
        height: cell * 0.86,
        piece: piece,
        whiteFill: whitePiece,
        blackFill: blackPiece,
      );
    }

    if (!piecesDone) {
      // Captured pieces fade under the incoming slide.
      for (final f in fades) {
        ChessPieceArt.paint(
          canvas,
          center: squareCenter(f.cell),
          height: cell * 0.86 * (1 - slideT * 0.25),
          piece: f.piece,
          whiteFill: whitePiece,
          blackFill: blackPiece,
          opacity: (1 - slideT).clamp(0.0, 1.0),
        );
      }
      for (final s in slides) {
        final at = Offset.lerp(
            squareCenter(s.from), squareCenter(s.to), slideT)!;
        ChessPieceArt.paint(
          canvas,
          center: at,
          height: cell * 0.86 * (1 + 0.08 * math.sin(slideT * math.pi)),
          piece: s.piece == '?' ? 'P' : s.piece,
          whiteFill: whitePiece,
          blackFill: blackPiece,
        );
      }
    }

    // Target markers on top so they read over pieces.
    for (final m in targets) {
      final center = squareCenter(m.to);
      final isCapture = cells[m.to] != null;
      final paint = Paint()
        ..color = Colors.black.withValues(alpha: 0.30);
      if (isCapture) {
        canvas.drawCircle(
          center,
          cell * 0.44,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.09,
        );
      } else {
        canvas.drawCircle(center, cell * 0.14, paint);
      }
    }

    canvas.restore();

    // Quiet edge bevel.
    canvas.drawRRect(
      slab.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.16),
    );
  }

  @override
  bool shouldRepaint(_ChessPainter old) =>
      old.cells != cells ||
      old.slideT != slideT ||
      old.selected != selected ||
      old.targets != targets ||
      old.checkedKing != checkedKing;
}

// ---------------------------------------------------------------------------
// Promotion picker
// ---------------------------------------------------------------------------

class _PromotionPicker extends StatelessWidget {
  final List<ChessMove> choices;
  final bool isWhite;
  final Color whitePiece;
  final Color blackPiece;
  final ValueChanged<ChessMove> onPick;
  final VoidCallback onCancel;

  const _PromotionPicker({
    required this.choices,
    required this.isWhite,
    required this.whitePiece,
    required this.blackPiece,
    required this.onPick,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    const order = ['q', 'r', 'n', 'b'];
    final sorted = [...choices]..sort((a, b) => order
        .indexOf(a.promotion ?? 'q')
        .compareTo(order.indexOf(b.promotion ?? 'q')));
    return GestureDetector(
      onTap: onCancel,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.35),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in sorted)
                  GestureDetector(
                    onTap: () => onPick(m),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: CustomPaint(
                        painter: _PromoPiecePainter(
                          piece: isWhite
                              ? m.promotion!.toUpperCase()
                              : m.promotion!,
                          whitePiece: whitePiece,
                          blackPiece: blackPiece,
                        ),
                      ),
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

class _PromoPiecePainter extends CustomPainter {
  final String piece;
  final Color whitePiece;
  final Color blackPiece;

  _PromoPiecePainter({
    required this.piece,
    required this.whitePiece,
    required this.blackPiece,
  });

  @override
  void paint(Canvas canvas, Size size) {
    ChessPieceArt.paint(
      canvas,
      center: Offset(size.width / 2, size.height / 2),
      height: size.shortestSide * 0.9,
      piece: piece,
      whiteFill: whitePiece,
      blackFill: blackPiece,
    );
  }

  @override
  bool shouldRepaint(_PromoPiecePainter old) => old.piece != piece;
}

// ---------------------------------------------------------------------------
// Player chip
// ---------------------------------------------------------------------------

class _PlayerChip extends StatelessWidget {
  final String label;
  final String piece;
  final Color pieceColor;
  final bool active;
  final bool winner;

  const _PlayerChip({
    required this.label,
    required this.piece,
    required this.pieceColor,
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
          SizedBox(
            width: 18,
            height: 18,
            child: CustomPaint(
              painter: _PromoPiecePainter(
                piece: piece,
                whitePiece: pieceColor,
                blackPiece: pieceColor,
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
