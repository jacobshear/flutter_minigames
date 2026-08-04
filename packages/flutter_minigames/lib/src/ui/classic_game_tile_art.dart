import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_minigames/games/chess.dart' show ChessPieceArt;


// Fixed toy palette (iOS system hues), lifted verbatim from the demo app so
// the dioramas read identically wherever the library is embedded.
const Color _ink = Color(0xFF1C1C1E);
const Color _coral = Color(0xFFFF3B30);
const Color _teal = Color(0xFF34C759);
const Color _gold = Color(0xFFFFCC00);

/// Which miniature to paint on a launcher tile.
enum GameTileKind {
  ticTacToe,
  connectFour,
  dotsAndBoxes,
  reversi,
  checkers,
  mancala,
  gomoku,
  chess,
}

/// Colorful toy diorama that plays complete short matches on a smooth loop,
/// picking a **new random script** each cycle.
class GameTileArt extends StatefulWidget {
  final GameTileKind kind;
  final double phase;

  const GameTileArt({
    super.key,
    required this.kind,
    this.phase = 0,
  });

  @override
  State<GameTileArt> createState() => _GameTileArtState();
}

class _GameTileArtState extends State<GameTileArt>
    with SingleTickerProviderStateMixin {
  final _rng = math.Random();

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: switch (widget.kind) {
      GameTileKind.ticTacToe => const Duration(milliseconds: 5600),
      GameTileKind.connectFour => const Duration(milliseconds: 7000),
      GameTileKind.dotsAndBoxes => const Duration(milliseconds: 7800),
      GameTileKind.reversi => const Duration(milliseconds: 9600),
      GameTileKind.checkers => const Duration(milliseconds: 7200),
      GameTileKind.mancala => const Duration(milliseconds: 6800),
      GameTileKind.gomoku => const Duration(milliseconds: 7400),
      GameTileKind.chess => const Duration(milliseconds: 7600),
    },
  )..repeat();

  late int _script = _rng.nextInt(1 << 20);
  double _lastT = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _maybeReshuffle(double t) {
    if (t + 0.25 < _lastT) {
      // Avoid immediate repeat of the same script.
      var next = _rng.nextInt(1 << 20);
      while (next == _script) {
        next = _rng.nextInt(1 << 20);
      }
      _script = next;
    }
    _lastT = t;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = (_c.value + widget.phase) % 1.0;
        _maybeReshuffle(t);
        return CustomPaint(
          painter: switch (widget.kind) {
            GameTileKind.ticTacToe =>
              _TicTacToeTilePainter(t: t, script: _script),
            GameTileKind.connectFour =>
              _ConnectFourTilePainter(t: t, script: _script),
            GameTileKind.dotsAndBoxes =>
              _DotsBoxesTilePainter(t: t, script: _script),
            GameTileKind.reversi => _ReversiTilePainter(t: t, script: _script),
            GameTileKind.checkers =>
              _CheckersTilePainter(t: t, script: _script),
            GameTileKind.mancala => _MancalaTilePainter(t: t, script: _script),
            GameTileKind.gomoku => _GomokuTilePainter(t: t, script: _script),
            GameTileKind.chess => _ChessTilePainter(t: t, script: _script),
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline — no whole-tile opacity fade (that flashed the blue C4 board).
//
//   0 ────── actionEnd ── celebrateEnd ──────── 1
//   | moves…          | hold win      | clear  |
// Clear multiplies piece progress to 0 so the board empties in place.
// ---------------------------------------------------------------------------

const double _kActionEnd = 0.72;
const double _kCelebrateEnd = 0.84;

double _boardPresence(double t) {
  if (t < _kCelebrateEnd) return 1;
  return 1 -
      Curves.easeInOutCubic.transform(
        (t - _kCelebrateEnd) / (1 - _kCelebrateEnd),
      );
}

double _beat(
  double t,
  int step,
  int moveCount, {
  double drawShare = 0.62,
}) {
  if (t >= _kActionEnd) return 1;
  final u = (t / _kActionEnd).clamp(0.0, 1.0);
  final pos = u * moveCount;
  final i = pos.floor().clamp(0, moveCount);
  if (step > i) return 0;
  if (step < i) return 1;
  final local = pos - i;
  if (local >= drawShare) return 1;
  return Curves.easeOutCubic.transform(local / drawShare);
}

double _piece(double t, int step, int moveCount, {double drawShare = 0.62}) {
  return _beat(t, step, moveCount, drawShare: drawShare) * _boardPresence(t);
}

double _celebrate(double t) {
  if (t < _kActionEnd) return 0;
  final hold = Curves.easeOutCubic.transform(
    ((t - _kActionEnd) / (_kCelebrateEnd - _kActionEnd)).clamp(0.0, 1.0),
  );
  return hold * _boardPresence(t);
}

T _pick<T>(int script, List<T> options) => options[script % options.length];

// ---------------------------------------------------------------------------
// Canvas-shape helpers — every tile painter was authored against a square
// launcher tile, but the same painters also draw the chat card's wide art
// window. These keep square rendering byte-for-byte authored while letting a
// wide canvas fill edge-to-edge instead of pillarboxing a floating square.
// ---------------------------------------------------------------------------

/// True when the canvas is meaningfully non-square — a card's art window
/// rather than a square launcher tile. Public because every game's tile art
/// makes the same square-vs-wide call, not just the classics.
bool isWideTile(Size size) =>
    (size.width - size.height).abs() > size.shortestSide * 0.05;

/// The silhouette a tile painter's backdrop fills: the authored rounded-square
/// on square canvases, edge-to-edge on wide ones. A wide consumer clips its
/// own corners; keeping the tile's larger radius there would punch transparent
/// notches into the card's art window.
RRect tileSilhouette(Size size) => RRect.fromRectAndRadius(
      Offset.zero & size,
      isWideTile(size) ? Radius.zero : Radius.circular(size.width * 0.22),
    );

bool _isWide(Size size) => isWideTile(size);

RRect _tileRRect(Size size) => tileSilhouette(size);

/// The centered square a scene draws in. Square canvases keep [fraction] of
/// the side — each painter's authored inset. Wide canvases open up to
/// [wideFraction] of the short side: the board is the point of a wide
/// thumbnail, and the backdrop already fills the gutters.
Rect _sceneSquare(Size size, double fraction, {double wideFraction = 0.92}) {
  final side = size.shortestSide * (_isWide(size) ? wideFraction : fraction);
  return Rect.fromCenter(
    center: size.center(Offset.zero),
    width: side,
    height: side,
  );
}

/// First run of [need] same-owner cells in a row-major [cols]x[rows] grid, as
/// cell indices — the winning line of a finished live board. Checks →, ↓ and
/// both diagonals, which covers tic-tac-toe, connect four and gomoku.
List<int>? _findRun(List<String?> cells, int cols, int rows, int need) {
  const dirs = [(1, 0), (0, 1), (1, 1), (1, -1)];
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final owner = cells[r * cols + c];
      if (owner == null) continue;
      for (final (dc, dr) in dirs) {
        final er = r + dr * (need - 1);
        final ec = c + dc * (need - 1);
        if (er < 0 || er >= rows || ec < 0 || ec >= cols) continue;
        var ok = true;
        for (var k = 1; k < need; k++) {
          if (cells[(r + dr * k) * cols + (c + dc * k)] != owner) {
            ok = false;
            break;
          }
        }
        if (ok) {
          return [for (var k = 0; k < need; k++) (r + dr * k) * cols + (c + dc * k)];
        }
      }
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Tic-tac-toe
// ---------------------------------------------------------------------------

class _TttScript {
  final List<(int col, int row, bool isX)> moves;
  final (int c0, int r0, int c1, int r1)? winLine;
  final bool xWins;

  const _TttScript(this.moves, {this.winLine, this.xWins = true});
}

const _tttScripts = <_TttScript>[
  _TttScript(
    [(0, 0, true), (1, 1, false), (2, 0, true), (0, 2, false), (1, 0, true)],
    winLine: (0, 0, 2, 0),
  ),
  _TttScript(
    [(0, 0, true), (0, 1, false), (1, 1, true), (0, 2, false), (2, 2, true)],
    winLine: (0, 0, 2, 2),
  ),
  _TttScript(
    [(0, 0, true), (1, 0, false), (0, 1, true), (1, 1, false), (0, 2, true)],
    winLine: (0, 0, 0, 2),
  ),
  _TttScript(
    [(2, 0, true), (0, 0, false), (2, 1, true), (1, 1, false), (2, 2, true)],
    winLine: (2, 0, 2, 2),
  ),
  _TttScript(
    [
      (0, 0, true),
      (0, 1, false),
      (2, 2, true),
      (1, 1, false),
      (2, 0, true),
      (2, 1, false),
    ],
    winLine: (0, 1, 2, 1),
    xWins: false,
  ),
  _TttScript(
    [
      (0, 0, true),
      (2, 0, false),
      (1, 0, true),
      (1, 1, false),
      (0, 1, true),
      (0, 2, false),
    ],
    winLine: (2, 0, 0, 2),
    xWins: false,
  ),
  // Draw
  _TttScript([
    (0, 0, true),
    (1, 1, false),
    (2, 2, true),
    (0, 1, false),
    (2, 1, true),
    (2, 0, false),
    (0, 2, true),
    (1, 2, false),
    (1, 0, true),
  ]),
];

/// A live owner-grid handed to a tile painter: the match's own `cells` list
/// plus the seat order, so an owner id maps to the art's first/second colour.
///
/// Every classic that stores `List<String?> cells` uses this, which is what
/// keeps "seed the authored art from the real board" one idea rather than six.
typedef LiveCells = ({List<String?> cells, List<String> playerIds});

/// True when [owner] is the first seat (the art's primary colour).
bool _isFirstSeat(String owner, List<String> ids) =>
    ids.isNotEmpty && owner == ids.first;

class _TicTacToeTilePainter extends CustomPainter {
  final double t;
  final int script;

  /// The real 3x3 board, when this tile shows a live match. Non-null draws
  /// every placed mark at full strength and skips the scripted draw-on.
  final LiveCells? live;

  _TicTacToeTilePainter({required this.t, required this.script, this.live});

  @override
  void paint(Canvas canvas, Size size) {
    final s = _pick(script, _tttScripts);

    canvas.drawRRect(
      _tileRRect(size),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF8F0), Color(0xFFFFE8D6)],
        ).createShader(Offset.zero & size),
    );

    final board = _sceneSquare(size, 0.64);
    final cell = board.width / 3;
    final grid = Paint()
      ..color = _ink.withValues(alpha: 0.55)
      ..strokeWidth = board.width * 0.044
      ..strokeCap = StrokeCap.round;

    for (var i = 1; i <= 2; i++) {
      canvas.drawLine(
        Offset(board.left + cell * i, board.top + cell * 0.12),
        Offset(board.left + cell * i, board.bottom - cell * 0.12),
        grid,
      );
      canvas.drawLine(
        Offset(board.left + cell * 0.12, board.top + cell * i),
        Offset(board.right - cell * 0.12, board.top + cell * i),
        grid,
      );
    }

    // Live board: every mark already placed, drawn at full strength. Scripted:
    // the authored draw-on. Both feed the same painter below.
    //
    // The spreads are load-bearing: without them the `else` dangles onto the
    // INNER `if (cells[i] != null)`, which starved the scripted branch — the
    // launcher tile animated an empty grid.
    final liveBoard = live;
    final placements = <(int col, int row, bool isX, double p)>[
      if (liveBoard != null) ...[
        for (var i = 0; i < liveBoard.cells.length && i < 9; i++)
          if (liveBoard.cells[i] != null)
            (
              i % 3,
              i ~/ 3,
              _isFirstSeat(liveBoard.cells[i]!, liveBoard.playerIds),
              1.0,
            ),
      ] else ...[
        for (var i = 0; i < s.moves.length; i++)
          (s.moves[i].$1, s.moves[i].$2, s.moves[i].$3, _piece(t, i, s.moves.length)),
      ],
    ];

    for (final (col, row, isX, p) in placements) {
      if (p <= 0.001) continue;
      final c = Offset(
        board.left + (col + 0.5) * cell,
        board.top + (row + 0.5) * cell,
      );
      if (isX) {
        _drawX(canvas, c, cell * 0.22, board.width * 0.062, _coral, p);
      } else {
        _drawO(canvas, c, cell * 0.24, board.width * 0.062, _teal, p);
      }
    }

    Offset cellCenter(int col, int row) => Offset(
          board.left + (col + 0.5) * cell,
          board.top + (row + 0.5) * cell,
        );

    if (liveBoard != null) {
      // A finished live board shows its win: strike the three-in-a-row in the
      // winner's own mark color, full strength — a still has no celebrate ramp.
      final run = _findRun(liveBoard.cells, 3, 3, 3);
      if (run != null) {
        final color = _isFirstSeat(liveBoard.cells[run.first]!, liveBoard.playerIds)
            ? _coral
            : _teal;
        canvas.drawLine(
          cellCenter(run.first % 3, run.first ~/ 3),
          cellCenter(run.last % 3, run.last ~/ 3),
          Paint()
            ..color = color.withValues(alpha: 0.9)
            ..strokeWidth = board.width * 0.078
            ..strokeCap = StrokeCap.round,
        );
      }
      return;
    }

    final winP = _celebrate(t);
    final line = s.winLine;
    if (winP > 0.001 && line != null) {
      final (c0, r0, c1, r1) = line;
      final color = s.xWins ? _coral : _teal;
      // Draw full line, scale alpha with winP (clears with presence).
      canvas.drawLine(
        cellCenter(c0, r0),
        cellCenter(c1, r1),
        Paint()
          ..color = color.withValues(alpha: 0.9 * winP)
          ..strokeWidth = board.width * 0.078 * (0.5 + 0.5 * winP)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawX(
    Canvas canvas,
    Offset c,
    double s,
    double stroke,
    Color color,
    double p,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final p1 = (p * 2).clamp(0.0, 1.0);
    final p2 = ((p - 0.5) * 2).clamp(0.0, 1.0);
    final a0 = c + Offset(-s, -s);
    final a1 = c + Offset(s, s);
    canvas.drawLine(a0, Offset.lerp(a0, a1, p1)!, paint);
    if (p2 > 0) {
      final b0 = c + Offset(s, -s);
      final b1 = c + Offset(-s, s);
      canvas.drawLine(b0, Offset.lerp(b0, b1, p2)!, paint);
    }
  }

  void _drawO(
    Canvas canvas,
    Offset c,
    double radius,
    double stroke,
    Color color,
    double p,
  ) {
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius),
      -math.pi / 2,
      2 * math.pi * p,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TicTacToeTilePainter old) =>
      old.t != t || old.script != script || old.live != live;
}

// ---------------------------------------------------------------------------
// Connect four
// ---------------------------------------------------------------------------

class _C4Script {
  final List<(int col, int landRow, Color color)> drops;
  final (int c0, int r0, int c1, int r1)? winLine;
  final Color winColor;

  const _C4Script(
    this.drops, {
    this.winLine,
    this.winColor = _coral,
  });
}

const _c4Scripts = <_C4Script>[
  // Coral vertical col 2
  _C4Script(
    [
      (2, 3, _coral),
      (1, 3, _gold),
      (2, 2, _coral),
      (0, 3, _gold),
      (2, 1, _coral),
      (3, 3, _gold),
      (2, 0, _coral),
    ],
    winLine: (2, 0, 2, 3),
  ),
  // Gold vertical col 1
  _C4Script(
    [
      (2, 3, _coral),
      (1, 3, _gold),
      (3, 3, _coral),
      (1, 2, _gold),
      (4, 3, _coral),
      (1, 1, _gold),
      (0, 3, _coral),
      (1, 0, _gold),
    ],
    winLine: (1, 0, 1, 3),
    winColor: _gold,
  ),
  // Coral horizontal bottom 0–3
  _C4Script(
    [
      (0, 3, _coral),
      (4, 3, _gold),
      (1, 3, _coral),
      (4, 2, _gold),
      (2, 3, _coral),
      (4, 1, _gold),
      (3, 3, _coral),
    ],
    winLine: (0, 3, 3, 3),
  ),
  // Gold horizontal bottom 1–4
  _C4Script(
    [
      (0, 3, _coral),
      (1, 3, _gold),
      (0, 2, _coral),
      (2, 3, _gold),
      (0, 1, _coral),
      (3, 3, _gold),
      (0, 0, _coral),
      (4, 3, _gold),
    ],
    winLine: (1, 3, 4, 3),
    winColor: _gold,
  ),
  // Coral vertical col 0
  _C4Script(
    [
      (0, 3, _coral),
      (2, 3, _gold),
      (0, 2, _coral),
      (3, 3, _gold),
      (0, 1, _coral),
      (1, 3, _gold),
      (0, 0, _coral),
    ],
    winLine: (0, 0, 0, 3),
  ),
  // Gold vertical col 3
  _C4Script(
    [
      (1, 3, _coral),
      (3, 3, _gold),
      (2, 3, _coral),
      (3, 2, _gold),
      (0, 3, _coral),
      (3, 1, _gold),
      (4, 3, _coral),
      (3, 0, _gold),
    ],
    winLine: (3, 0, 3, 3),
    winColor: _gold,
  ),
];

class _ConnectFourTilePainter extends CustomPainter {
  final double t;
  final int script;

  /// The real 7x6 grid, when this tile shows a live match. Non-null seats every
  /// disc in its slot with no drop animation — a still, not a replay.
  final LiveCells? live;

  _ConnectFourTilePainter({required this.t, required this.script, this.live});

  @override
  void paint(Canvas canvas, Size size) {
    final s = _pick(script, _c4Scripts);

    canvas.drawRRect(
      _tileRRect(size),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5B9DFF), Color(0xFF2B6BCB)],
        ).createShader(Offset.zero & size),
    );

    final frame = _sceneSquare(size, 0.72);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, Radius.circular(frame.width * 0.11)),
      Paint()..color = const Color(0xFF1E5AAD),
    );

    // The scripted diorama plays on a toy 5x4; a live match is the real 7x6
    // (drawing 7-wide cells onto the toy grid put discs outside the frame).
    final cols = live != null ? 7 : 5;
    final rows = live != null ? 6 : 4;
    final cellW = frame.width / cols;
    final cellH = frame.height / rows;
    final holeR = math.min(cellW, cellH) * 0.32;

    for (var col = 0; col < cols; col++) {
      for (var row = 0; row < rows; row++) {
        final c = Offset(
          frame.left + (col + 0.5) * cellW,
          frame.top + (row + 0.5) * cellH,
        );
        canvas.drawCircle(c, holeR, Paint()..color = const Color(0xFFE8F0FF));
      }
    }

    final liveBoard = live;
    final presence = liveBoard != null ? 1.0 : _boardPresence(t);
    // Live: every disc resting in its own cell, full size, no fall. State row
    // 0 is the BOTTOM (gravity fills lowest index first); the painter draws
    // row 0 at the top, so live rows flip. Scripted: the authored drops.
    // The spreads are load-bearing: without them the `else` dangles onto the
    // INNER `if (cells[i] != null)` and the scripted branch never runs.
    final drops = <(int col, int landRow, Color color, double p)>[
      if (liveBoard != null) ...[
        for (var i = 0; i < liveBoard.cells.length && i < 42; i++)
          if (liveBoard.cells[i] != null)
            (
              i % 7,
              rows - 1 - i ~/ 7,
              _isFirstSeat(liveBoard.cells[i]!, liveBoard.playerIds)
                  ? _coral
                  : _gold,
              1.0,
            ),
      ] else ...[
        for (var i = 0; i < s.drops.length; i++)
          (
            s.drops[i].$1,
            s.drops[i].$2,
            s.drops[i].$3,
            _piece(t, i, s.drops.length, drawShare: 0.70),
          ),
      ],
    ];
    for (final (col, landRow, color, p) in drops) {
      if (p <= 0.001) continue;
      final restY = frame.top + (landRow + 0.5) * cellH;
      final startY = frame.top - cellH * 0.75;
      // Drop only while placing; clear shrinks discs in place (no reverse rise).
      final fallT = Curves.easeInCubic.transform(
        (presence < 1 ? 1.0 : p).clamp(0.0, 1.0),
      );
      var y = lerpDouble(startY, restY, fallT)!;
      if (presence >= 1 && p > 0.82) {
        final b = (p - 0.82) / 0.18;
        y -= math.sin(b * math.pi) * cellH * 0.07;
      }
      // On clear, pin to rest slot and scale out.
      if (presence < 1) y = restY;
      final c = Offset(frame.left + (col + 0.5) * cellW, y);
      final radius = holeR * 0.92 * p.clamp(0.0, 1.0);
      if (radius < 0.5) continue;
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.35),
            colors: [
              Color.lerp(color, Colors.white, 0.35)!,
              color,
            ],
          ).createShader(Rect.fromCircle(center: c, radius: holeR)),
      );
    }

    if (liveBoard != null) {
      // A finished live board strikes its four-in-a-row in the winner's disc
      // color, full strength — a still has no celebrate ramp.
      final run = _findRun(liveBoard.cells, 7, 6, 4);
      if (run != null) {
        final winColor =
            _isFirstSeat(liveBoard.cells[run.first]!, liveBoard.playerIds)
                ? _coral
                : _gold;
        Offset at(int i) => Offset(
              frame.left + (i % 7 + 0.5) * cellW,
              frame.top + (rows - 1 - i ~/ 7 + 0.5) * cellH,
            );
        canvas.drawLine(
          at(run.first),
          at(run.last),
          Paint()
            ..color = winColor.withValues(alpha: 0.9)
            ..strokeWidth = math.min(cellW, cellH) * 0.28
            ..strokeCap = StrokeCap.round,
        );
      }
      return;
    }

    final winP = _celebrate(t);
    final line = s.winLine;
    if (winP > 0.001 && line != null) {
      final (c0, r0, c1, r1) = line;
      final a = Offset(
        frame.left + (c0 + 0.5) * cellW,
        frame.top + (r0 + 0.5) * cellH,
      );
      final b = Offset(
        frame.left + (c1 + 0.5) * cellW,
        frame.top + (r1 + 0.5) * cellH,
      );
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = s.winColor.withValues(alpha: 0.9 * winP)
          ..strokeWidth = math.min(cellW, cellH) * 0.28 * winP
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ConnectFourTilePainter old) =>
      old.t != t || old.script != script || old.live != live;
}

// ---------------------------------------------------------------------------
// Dots & boxes — full 3×3 boxes (4×4 dots), centered; scripts claim a subset
// ---------------------------------------------------------------------------

class _DabScript {
  /// Claimed edges only. kind is 'h' or 'v'; (r,c) is the edge origin
  /// on a 4×4 dot grid (h: r 0..3, c 0..2; v: r 0..2, c 0..3).
  final List<(String kind, int r, int c, Color color)> edges;

  /// (boxRow, boxCol, closeStep, owner) — box indices 0..2 on the 3×3.
  final List<(int br, int bc, int closeStep, Color owner)> fills;
  final Color winColor;

  const _DabScript({
    required this.edges,
    required this.fills,
    required this.winColor,
  });
}

const _dabScripts = <_DabScript>[
  // Coral 3 – teal 1 on the bottom-right of the 3×3
  _DabScript(
    edges: [
      ('h', 1, 1, _coral),
      ('v', 1, 1, _teal),
      ('v', 1, 2, _coral),
      ('h', 2, 1, _teal), // teal box(1,1)
      ('h', 1, 2, _coral),
      ('v', 1, 3, _teal),
      ('h', 2, 2, _coral), // coral box(1,2)
      ('v', 2, 1, _teal),
      ('v', 2, 3, _coral),
      ('h', 3, 1, _coral),
      ('h', 3, 2, _coral),
      ('v', 2, 2, _coral), // coral box(2,1)+box(2,2)
    ],
    fills: [
      (1, 1, 3, _teal),
      (1, 2, 6, _coral),
      (2, 1, 11, _coral),
      (2, 2, 11, _coral),
    ],
    winColor: _coral,
  ),
  // Teal 3 – coral 1 (mirror colors)
  _DabScript(
    edges: [
      ('h', 1, 1, _teal),
      ('v', 1, 1, _coral),
      ('v', 1, 2, _teal),
      ('h', 2, 1, _coral), // coral box(1,1)
      ('h', 1, 2, _teal),
      ('v', 1, 3, _coral),
      ('h', 2, 2, _teal), // teal box(1,2)
      ('v', 2, 1, _coral),
      ('v', 2, 3, _teal),
      ('h', 3, 1, _teal),
      ('h', 3, 2, _teal),
      ('v', 2, 2, _teal), // teal bottoms
    ],
    fills: [
      (1, 1, 3, _coral),
      (1, 2, 6, _teal),
      (2, 1, 11, _teal),
      (2, 2, 11, _teal),
    ],
    winColor: _teal,
  ),
  // Coral cascade along top-left 2×2 of the 3×3
  _DabScript(
    edges: [
      ('h', 0, 0, _coral),
      ('v', 0, 0, _teal),
      ('h', 0, 1, _coral),
      ('v', 0, 2, _teal),
      ('v', 1, 0, _coral),
      ('v', 1, 2, _teal),
      ('h', 2, 0, _coral),
      ('h', 2, 1, _teal),
      ('v', 0, 1, _coral),
      ('h', 1, 0, _coral), // coral box(0,0)
      ('h', 1, 1, _coral), // coral box(0,1)
      ('v', 1, 1, _coral), // coral box(1,0)+box(1,1)
    ],
    fills: [
      (0, 0, 9, _coral),
      (0, 1, 10, _coral),
      (1, 0, 11, _coral),
      (1, 1, 11, _coral),
    ],
    winColor: _coral,
  ),
  // Split 2–2 on the bottom-right 2×2
  _DabScript(
    edges: [
      ('h', 1, 1, _coral),
      ('v', 1, 1, _teal),
      ('v', 1, 2, _coral),
      ('h', 2, 1, _teal), // teal box(1,1)
      ('h', 1, 2, _teal),
      ('v', 1, 3, _coral),
      ('h', 2, 2, _teal), // teal box(1,2)
      ('v', 2, 1, _coral),
      ('v', 2, 3, _coral),
      ('h', 3, 1, _coral),
      ('h', 3, 2, _coral),
      ('v', 2, 2, _coral), // coral bottoms
    ],
    fills: [
      (1, 1, 3, _teal),
      (1, 2, 6, _teal),
      (2, 1, 11, _coral),
      (2, 2, 11, _coral),
    ],
    winColor: _gold,
  ),
];

class _DotsBoxesTilePainter extends CustomPainter {
  final double t;
  final int script;

  /// The REAL board, when this tile shows a live match: owner-per-edge and
  /// owner-per-box, indexed exactly as `DotsAndBoxesState` stores them
  /// (h: `r * n + c`, v: `r * (n + 1) + c`, boxes: `r * n + c`), plus the
  /// seat order so owners map to the art's two colours.
  ///
  /// Non-null skips the scripted draw-on entirely — every claimed edge is drawn
  /// full length and every won box is filled solid, because a live board is a
  /// still, not a replay.
  final ({
    List<String?> hEdges,
    List<String?> vEdges,
    List<String?> boxes,
    List<String> playerIds,
  })? live;

  _DotsBoxesTilePainter({
    required this.t,
    required this.script,
    this.live,
  });

  /// The art's two seat colours, in `playerIds` order.
  Color _ownerColor(String owner, List<String> ids) =>
      ids.isNotEmpty && owner == ids.first ? _coral : _teal;

  /// 4 dots per side → 3×3 boxes (matches live [DotsAndBoxesGame.gridSize]).
  static const int dots = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final s = _pick(script, _dabScripts);

    canvas.drawRRect(
      _tileRRect(size),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBF0), Color(0xFFFFF0C8)],
        ).createShader(Offset.zero & size),
    );

    // Square playfield, explicitly centered in the tile (not pad-from-width
    // only — that drifts when the tile aspect isn't 1:1).
    final area = _sceneSquare(size, 0.82);
    final step = area.width / (dots - 1);

    Offset d(int x, int y) => Offset(area.left + x * step, area.top + y * step);

    final free = Paint()
      ..color = _ink.withValues(alpha: 0.11)
      ..strokeWidth = size.shortestSide * 0.016
      ..strokeCap = StrokeCap.round;
    for (var y = 0; y < dots; y++) {
      for (var x = 0; x < dots - 1; x++) {
        canvas.drawLine(d(x, y), d(x + 1, y), free);
      }
    }
    for (var y = 0; y < dots - 1; y++) {
      for (var x = 0; x < dots; x++) {
        canvas.drawLine(d(x, y), d(x, y + 1), free);
      }
    }

    final presence = live != null ? 1.0 : _boardPresence(t);
    final claimedW = size.shortestSide * 0.028;

    final liveBoard = live;
    if (liveBoard != null) {
      // Claimed edges at full length — no draw-on, no retract.
      void drawEdge(String? owner, Offset a, Offset b) {
        if (owner == null) return;
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = _ownerColor(owner, liveBoard.playerIds)
            ..strokeWidth = claimedW
            ..strokeCap = StrokeCap.round,
        );
      }

      const n = dots - 1;
      for (var r = 0; r <= n; r++) {
        for (var c = 0; c < n; c++) {
          final i = r * n + c;
          if (i < liveBoard.hEdges.length) {
            drawEdge(liveBoard.hEdges[i], d(c, r), d(c + 1, r));
          }
        }
      }
      for (var r = 0; r < n; r++) {
        for (var c = 0; c <= n; c++) {
          final i = r * (n + 1) + c;
          if (i < liveBoard.vEdges.length) {
            drawEdge(liveBoard.vEdges[i], d(c, r), d(c, r + 1));
          }
        }
      }

      final livePad = step * 0.18;
      for (var i = 0; i < liveBoard.boxes.length && i < n * n; i++) {
        final owner = liveBoard.boxes[i];
        if (owner == null) continue;
        final br = i ~/ n;
        final bc = i % n;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(
                area.left + (bc + 0.5) * step,
                area.top + (br + 0.5) * step,
              ),
              width: step - livePad,
              height: step - livePad,
            ),
            Radius.circular(step * 0.16),
          ),
          Paint()
            ..color = _ownerColor(owner, liveBoard.playerIds)
                .withValues(alpha: 0.32),
        );
      }
    }

    for (var i = 0; i < s.edges.length && liveBoard == null; i++) {
      final p = _piece(t, i, s.edges.length, drawShare: 0.58);
      if (p <= 0.001) continue;
      final (kind, er, ec, color) = s.edges[i];
      final Offset a;
      final Offset b;
      if (kind == 'h') {
        a = d(ec, er);
        b = d(ec + 1, er);
      } else {
        a = d(ec, er);
        b = d(ec, er + 1);
      }
      // During clear, retract stroke back to start.
      final end = Offset.lerp(a, b, p)!;
      canvas.drawLine(
        a,
        end,
        Paint()
          ..color = color
          ..strokeWidth = claimedW
          ..strokeCap = StrokeCap.round,
      );
    }

    final fillPad = step * 0.18;
    for (final (br, bc, closeStep, owner) in (liveBoard == null ? s.fills : const <(int, int, int, Color)>[])) {
      final p = _piece(t, closeStep, s.edges.length, drawShare: 0.58);
      if (p < 0.85) continue;
      final local = Curves.easeOutCubic.transform(
        ((p - 0.85) / 0.15).clamp(0.0, 1.0),
      );
      final cFill = local * presence;
      if (cFill <= 0.001) continue;
      final cx = area.left + (bc + 0.5) * step;
      final cy = area.top + (br + 0.5) * step;
      final boxSide = (step - fillPad) * (0.2 + 0.8 * cFill);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: boxSide,
            height: boxSide,
          ),
          Radius.circular(size.shortestSide * 0.02),
        ),
        Paint()..color = owner.withValues(alpha: 0.32 * cFill),
      );
    }

    final dotR = size.shortestSide * 0.022;
    for (var y = 0; y < dots; y++) {
      for (var x = 0; x < dots; x++) {
        canvas.drawCircle(d(x, y), dotR, Paint()..color = _ink);
      }
    }

    final winP = _celebrate(t);
    if (winP > 0.001) {
      canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.10),
        size.shortestSide * 0.08 * winP,
        Paint()
          ..color = s.winColor.withValues(alpha: 0.4 * winP)
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, size.shortestSide * 0.04),
      );
    }
  }

  @override
  bool shouldRepaint(_DotsBoxesTilePainter old) =>
      old.t != t || old.script != script || old.live != live;
}

// ---------------------------------------------------------------------------
// Reversi tile — plastic chips, drop+bounce place, staggered cosine flips
// ---------------------------------------------------------------------------

class _RevScript {
  /// Fully legal places on a 6×6 board (dark first). Opening is the standard
  /// center four; each place is verified against full flip rules.
  final List<(int r, int c)> places;
  final bool darkWins;

  const _RevScript(this.places, {this.darkWins = true});
}

/// Curated legal multi-flip sequences on 6×6.
const _revScripts = <_RevScript>[
  _RevScript([
    (4, 3),
    (2, 4),
    (1, 2),
    (4, 2),
    (1, 3),
    (0, 2),
    (4, 1),
  ]),
  _RevScript([
    (3, 4),
    (4, 2),
    (2, 1),
    (2, 4),
    (3, 1),
    (2, 0),
    (1, 4),
  ]),
  _RevScript([
    (2, 1),
    (1, 3),
    (3, 4),
    (3, 1),
    (2, 4),
    (3, 5),
    (4, 3),
  ]),
  _RevScript([
    (1, 2),
    (3, 1),
    (4, 3),
    (1, 3),
    (4, 2),
    (5, 3),
    (3, 4),
  ]),
  _RevScript([
    (4, 3),
    (4, 2),
    (4, 1),
    (5, 2),
    (2, 1),
    (4, 4),
    (4, 5),
  ]),
  _RevScript([
    (1, 2),
    (1, 1),
    (2, 1),
    (1, 3),
    (0, 1),
    (0, 0),
    (3, 4),
    (2, 0),
  ], darkWins: false),
];

/// Per-disc pose for a single frame of the tile loop.
class _RevPose {
  final bool isDark;
  final double scale; // overall size (place + clear)
  final double scaleX; // land squash
  final double scaleY; // flip squash
  final double dropY; // place drop offset in cell units (negative = above)
  final double liftY; // flip lift in cell units (negative = above)

  const _RevPose({
    required this.isDark,
    this.scale = 1,
    this.scaleX = 1,
    this.scaleY = 1,
    this.dropY = 0,
    this.liftY = 0,
  });
}

class _ReversiTilePainter extends CustomPainter {
  final double t;
  final int script;

  /// The real 8x8 board, when this tile shows a live match. Seeds the discs
  /// directly and skips the scripted place-and-cascade — a still has nothing
  /// mid-flip.
  final LiveCells? live;
  _ReversiTilePainter({
    required this.t,
    required this.script,
    this.live,
  });

  /// Scripted dioramas play on a toy 6x6; a live match is the real 8x8 —
  /// seeding 64 cells through a 6-wide mapping scrambled the board.
  int get n => live != null ? 8 : 6;

  static const _dirs = <(int, int)>[
    (-1, -1),
    (-1, 0),
    (-1, 1),
    (0, -1),
    (0, 1),
    (1, -1),
    (1, 0),
    (1, 1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scriptData = _pick(script, _revScripts);
    final presence = live != null ? 1.0 : _boardPresence(t);

    _paintFelt(canvas, size);

    final board = _sceneSquare(size, 0.80);
    final cell = board.width / n;

    _paintGrid(canvas, board, cell, size);

    // Logical board: null empty, true dark, false light.
    final cells = List.generate(n, (_) => List<bool?>.filled(n, null));
    final liveBoard = live;
    if (liveBoard != null) {
      // Seed from the match; the first seat plays dark.
      for (var i = 0; i < liveBoard.cells.length && i < n * n; i++) {
        final owner = liveBoard.cells[i];
        if (owner == null) continue;
        cells[i ~/ n][i % n] = _isFirstSeat(owner, liveBoard.playerIds);
      }
    } else {
      cells[2][2] = false;
      cells[2][3] = true;
      cells[3][2] = true;
      cells[3][3] = false;
    }

    final poses = List.generate(n, (_) => List<_RevPose?>.filled(n, null));
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final v = cells[r][c];
        if (v != null) {
          poses[r][c] = _RevPose(isDark: v, scale: presence);
        }
      }
    }

    final moveCount = liveBoard != null ? 0 : scriptData.places.length;
    var darkTurn = true;

    for (var i = 0; i < moveCount; i++) {
      // Longer drawShare so place + cascade have room to breathe.
      final raw = _beat(t, i, moveCount, drawShare: 0.90);
      final (pr, pc) = scriptData.places[i];
      final isDark = darkTurn;

      final flips = _flips(cells, pr, pc, isDark);
      if (cells[pr][pc] != null || flips.isEmpty) {
        darkTurn = !darkTurn;
        continue;
      }

      // Within-beat timeline:
      // 0.00–0.34  place drop + land bounce
      // 0.26–0.92  staggered flips (distance from place)
      // rest       settle
      if (raw > 0.01) {
        final place = _placePhysics(raw);
        cells[pr][pc] = isDark;
        poses[pr][pc] = _RevPose(
          isDark: isDark,
          scale: place.scale * presence,
          scaleX: place.scaleX,
          scaleY: place.scaleY,
          dropY: place.dropY,
        );
      }

      if (raw > 0.22) {
        // Sort flips by Manhattan distance so stagger is deterministic.
        final sorted = [...flips]..sort((a, b) {
            final da = (a.$1 - pr).abs() + (a.$2 - pc).abs();
            final db = (b.$1 - pr).abs() + (b.$2 - pc).abs();
            return da.compareTo(db);
          });

        for (var fi = 0; fi < sorted.length; fi++) {
          final (fr, fc) = sorted[fi];
          final dist = (fr - pr).abs() + (fc - pc).abs();
          // Stagger by ring + slight index so multi-disc lines cascade.
          final delay = 0.24 + (dist - 1) * 0.085 + fi * 0.012;
          final local = ((raw - delay) / 0.48).clamp(0.0, 1.0);
          final fp = Curves.easeInOutCubic.transform(local);
          final flip = _flipPhysics(fp);
          final showDark = fp < 0.5 ? !isDark : isDark;
          poses[fr][fc] = _RevPose(
            isDark: showDark,
            scale: presence,
            scaleX: flip.scaleX,
            scaleY: flip.scaleY,
            liftY: flip.liftY,
          );
          if (fp >= 1) cells[fr][fc] = isDark;
        }

        if (raw >= 1) {
          for (final (fr, fc) in flips) {
            cells[fr][fc] = isDark;
            poses[fr][fc] = _RevPose(isDark: isDark, scale: presence);
          }
        }
      }

      darkTurn = !darkTurn;
    }

    // Draw discs back-to-front by row so drop shadows stack naturally.
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final pose = poses[row][col];
        if (pose == null || pose.scale < 0.04) continue;

        final cx = board.left + (col + 0.5) * cell;
        final cy = board.top + (row + 0.5) * cell;
        final radius = cell * 0.40;
        final dy = (pose.dropY + pose.liftY) * cell;

        _paintChip(
          canvas,
          Offset(cx, cy + dy),
          radius,
          isDark: pose.isDark,
          scale: pose.scale.clamp(0.0, 1.25),
          scaleX: pose.scaleX.clamp(0.55, 1.35),
          scaleY: pose.scaleY.clamp(0.06, 1.2),
          shadowMul: (1 - pose.dropY.abs().clamp(0.0, 1.0) * 0.55) *
              pose.scaleY.clamp(0.15, 1.0),
        );
      }
    }

    final winP = _celebrate(t);
    if (winP > 0.001) {
      // Soft crown glow matching the winning face color.
      final color =
          scriptData.darkWins ? _ink : const Color(0xFFF5F5F7);
      canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.10),
        size.width * 0.09 * winP,
        Paint()
          ..color = color.withValues(alpha: 0.38 * winP)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.05),
      );
      // Pulse a thin gold ring for “match over.”
      canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.10),
        size.width * 0.055 * winP,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.012
          ..color = _gold.withValues(alpha: 0.55 * winP),
      );
    }
  }

  void _paintFelt(Canvas canvas, Size size) {
    final outer = _tileRRect(size);
    // Deep green felt matching the live board (≈ 0xFF2D8A4E).
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3FA862),
            Color(0xFF2D8A4E),
            Color(0xFF1F6B3A),
          ],
          stops: [0.0, 0.48, 1.0],
        ).createShader(Offset.zero & size),
    );
    // Soft top light + bottom vignette for depth.
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.15, -0.35),
          radius: 1.05,
          colors: [
            Colors.white.withValues(alpha: 0.14),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.12),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Offset.zero & size),
    );
    // Thin lip edge so the tile reads as a tray, not a flat stamp.
    canvas.drawRRect(
      outer.deflate(size.shortestSide * 0.012),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.014
        ..color = Colors.black.withValues(alpha: 0.12),
    );
  }

  void _paintGrid(Canvas canvas, Rect board, double cell, Size size) {
    // Slightly inset playfield.
    final inset = board.deflate(cell * 0.02);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inset, Radius.circular(cell * 0.12)),
      Paint()..color = Colors.black.withValues(alpha: 0.06),
    );

    final grid = Paint()
      ..color = Colors.black.withValues(alpha: 0.20)
      ..strokeWidth = math.max(0.6, size.shortestSide * 0.007);
    final gridHi = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = math.max(0.4, size.shortestSide * 0.005);

    for (var i = 0; i <= n; i++) {
      final o = i * cell;
      // Vertical
      canvas.drawLine(
        Offset(board.left + o, board.top),
        Offset(board.left + o, board.bottom),
        grid,
      );
      canvas.drawLine(
        Offset(board.left + o + 0.7, board.top),
        Offset(board.left + o + 0.7, board.bottom),
        gridHi,
      );
      // Horizontal
      canvas.drawLine(
        Offset(board.left, board.top + o),
        Offset(board.right, board.top + o),
        grid,
      );
      canvas.drawLine(
        Offset(board.left, board.top + o + 0.7),
        Offset(board.right, board.top + o + 0.7),
        gridHi,
      );
    }

    // Recessed cell wells (subtle, not noisy).
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final cx = board.left + (col + 0.5) * cell;
        final cy = board.top + (row + 0.5) * cell;
        canvas.drawCircle(
          Offset(cx, cy + cell * 0.015),
          cell * 0.34,
          Paint()..color = Colors.black.withValues(alpha: 0.05),
        );
      }
    }

    // Classic Othello star points — authored positions on the toy 6×6, the
    // real ones on a live 8×8.
    final star = Paint()..color = Colors.black.withValues(alpha: 0.28);
    for (final (r, c) in n == 6
        ? const [(1, 1), (1, 4), (4, 1), (4, 4)]
        : const [(1, 1), (1, 6), (6, 1), (6, 6)]) {
      canvas.drawCircle(
        Offset(board.left + (c + 0.5) * cell, board.top + (r + 0.5) * cell),
        cell * 0.055,
        star,
      );
    }
  }

  /// Place physics in beat-local time [raw] 0..1.
  ({double scale, double scaleX, double scaleY, double dropY}) _placePhysics(
    double raw,
  ) {
    // Phase A: free-fall toward the cell (0 → 0.38).
    // Phase B: impact squash + settle bounce (0.38 → 0.72).
    // Phase C: rest.
    if (raw >= 0.72) {
      return (scale: 1.0, scaleX: 1.0, scaleY: 1.0, dropY: 0.0);
    }
    if (raw < 0.38) {
      final u = Curves.easeInCubic.transform(raw / 0.38);
      // Start slightly small + high; grow as it approaches.
      return (
        scale: lerpDouble(0.72, 1.02, u)!,
        scaleX: 1.0,
        scaleY: 1.0,
        dropY: lerpDouble(-0.95, 0.0, u)!,
      );
    }
    // Impact squash then ease-out rebound.
    final u = (raw - 0.38) / 0.34;
    final bounce = math.sin(u * math.pi); // 0 → 1 → 0
    final squash = bounce * 0.18;
    return (
      scale: lerpDouble(1.02, 1.0, Curves.easeOutCubic.transform(u))!,
      scaleX: 1.0 + squash,
      scaleY: 1.0 - squash * 0.85,
      dropY: -0.04 * bounce, // tiny hop after land
    );
  }

  /// Flip physics for progress [fp] 0..1 (easeInOut already applied).
  /// Cosine Y-scale keeps motion continuous (no piecewise kink at mid).
  ({double scaleX, double scaleY, double liftY}) _flipPhysics(double fp) {
    if (fp <= 0) return (scaleX: 1.0, scaleY: 1.0, liftY: 0.0);
    if (fp >= 1) return (scaleX: 1.0, scaleY: 1.0, liftY: 0.0);
    // |cos(πt)| → 1…0…1; floor at 0.08 so edge thickness stays visible.
    final cosAbs = math.cos(math.pi * fp).abs();
    final scaleY = 0.08 + 0.92 * cosAbs;
    // Slight X swell near edge-on (reads as thickness).
    final edge = (1.0 - cosAbs).clamp(0.0, 1.0);
    final scaleX = 1.0 + 0.12 * edge;
    // Lift off the felt mid-flip.
    final liftY = -0.18 * math.sin(math.pi * fp);
    return (scaleX: scaleX, scaleY: scaleY, liftY: liftY);
  }

  List<(int, int)> _flips(
    List<List<bool?>> cells,
    int row,
    int col,
    bool isDark,
  ) {
    if (row < 0 || row >= n || col < 0 || col >= n) return const [];
    if (cells[row][col] != null) return const [];
    final flips = <(int, int)>[];
    for (final (dr, dc) in _dirs) {
      final line = <(int, int)>[];
      var r = row + dr;
      var c = col + dc;
      while (r >= 0 && r < n && c >= 0 && c < n) {
        final v = cells[r][c];
        if (v == null) break;
        if (v != isDark) {
          line.add((r, c));
          r += dr;
          c += dc;
          continue;
        }
        if (v == isDark && line.isNotEmpty) flips.addAll(line);
        break;
      }
    }
    return flips;
  }

  /// Thick plastic dual-face chip: contact shadow, body, rim, specular,
  /// and a mid-flip edge band so the disc reads as a real Othello piece.
  void _paintChip(
    Canvas canvas,
    Offset center,
    double radius, {
    required bool isDark,
    required double scale,
    required double scaleX,
    required double scaleY,
    double shadowMul = 1,
  }) {
    final r = radius * scale;
    if (r < 0.35) return;

    final sy = scaleY.clamp(0.06, 1.2);
    final sx = scaleX.clamp(0.55, 1.35);

    // Contact shadow sits under the disc (not scaled with flip squash).
    final shadowAlpha = (0.26 * shadowMul * scale).clamp(0.0, 0.35);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + r * 0.42),
        width: r * 1.75 * sx,
        height: r * 0.38 * sy.clamp(0.35, 1.0),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: shadowAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.28),
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(sx, sy);

    final face = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F7);
    final deep = isDark ? const Color(0xFF0A0A0B) : const Color(0xFFD8D8DE);
    final hi = isDark ? const Color(0xFF4A4A4E) : const Color(0xFFFFFFFF);
    final rim = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE2E2E8);
    // Mid-tone edge of a dual-face plastic disc.
    final edgeBand = Color.lerp(
      const Color(0xFF1C1C1E),
      const Color(0xFFF5F5F7),
      isDark ? 0.42 : 0.58,
    )!;

    final bodyRect = Rect.fromCircle(center: Offset.zero, radius: r);

    // Near edge-on: paint a thick lozenge so thickness is readable.
    if (sy < 0.38) {
      final h = r * 0.55;
      final edgeRect = Rect.fromCenter(
        center: Offset.zero,
        width: r * 2.05,
        height: h,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(edgeRect, Radius.circular(h * 0.45)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              isDark ? face : edgeBand,
              edgeBand,
              isDark ? edgeBand : face,
            ],
          ).createShader(edgeRect),
      );
      // Specular line along the rim.
      canvas.drawLine(
        Offset(-r * 0.85, -h * 0.15),
        Offset(r * 0.85, -h * 0.15),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..strokeWidth = r * 0.12
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
      return;
    }

    // Main body — matches live _Disc radial gradient.
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.40),
          radius: 1.08,
          colors: [
            Color.lerp(face, Colors.white, isDark ? 0.32 : 0.42)!,
            face,
            Color.lerp(face, Colors.black, isDark ? 0.28 : 0.14)!,
          ],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(bodyRect),
    );

    // Inner face plate (slightly inset) for plastic depth.
    canvas.drawCircle(
      Offset.zero,
      r * 0.88,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.28, -0.36),
          radius: 0.95,
          colors: [
            Color.lerp(face, hi, isDark ? 0.18 : 0.35)!,
            face,
            deep.withValues(alpha: isDark ? 0.55 : 0.25),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 0.88)),
    );

    // Rim ring — reads as chip wall thickness.
    canvas.drawCircle(
      Offset.zero,
      r * 0.94,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.085
        ..color = rim.withValues(alpha: 0.90),
    );
    // Outer micro-outline for silhouette on the green felt.
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.035
        ..color = Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
    );

    // Specular highlight.
    final hx = -r * 0.28;
    final hy = -r * 0.30;
    final hr = r * (isDark ? 0.30 : 0.34);
    canvas.drawCircle(
      Offset(hx, hy),
      hr,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.38 : 0.72),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(hx, hy), radius: hr)),
    );
    // Secondary soft glint.
    canvas.drawCircle(
      Offset(r * 0.22, r * 0.18),
      r * 0.16,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.08 : 0.18),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCircle(center: Offset(r * 0.22, r * 0.18), radius: r * 0.16),
        ),
    );

    // Edge glint while partially flipped (sy mid-range).
    if (sy < 0.55) {
      final edgeA = ((0.55 - sy) / 0.55).clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(-r * 0.92, 0),
        Offset(r * 0.92, 0),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.40 * edgeA)
          ..strokeWidth = r * 0.14
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ReversiTilePainter old) =>
      old.t != t || old.script != script || old.live != live;
}

// ---------------------------------------------------------------------------
// Checkers tile — 8×8 wood board, slide + jump + crown
// ---------------------------------------------------------------------------

class _ChkScript {
  /// Moves as (fromRow, fromCol, toRow, toCol). Dark (ink) starts.
  final List<(int fr, int fc, int tr, int tc)> moves;
  final bool darkWins;

  const _ChkScript(this.moves, {this.darkWins = true});
}

/// Short showcase sequences on a full board (not full games).
const _chkScripts = <_ChkScript>[
  // Dark advances, red answers, dark jumps.
  _ChkScript([
    (5, 0, 4, 1),
    (2, 1, 3, 0),
    (5, 2, 4, 3),
    (2, 3, 3, 2),
    (4, 1, 2, 3), // jump red at 3,2
  ]),
  // Red wins path-ish showcase
  _ChkScript([
    (5, 0, 4, 1),
    (2, 1, 3, 2),
    (5, 2, 4, 3),
    (3, 2, 5, 0), // red jump
  ], darkWins: false),
  _ChkScript([
    (5, 4, 4, 5),
    (2, 5, 3, 4),
    (5, 6, 4, 7),
    (2, 7, 3, 6),
    (4, 5, 2, 7),
  ]),
];

class _CheckersTilePainter extends CustomPainter {
  final double t;
  final int script;

  /// The real 8x8 board, when this tile shows a live match. Seeds the piece
  /// layout directly and skips the scripted moves — nothing is in flight on a
  /// still, so there is no sliding piece and no capture to animate.
  final LiveCells? live;

  /// King flags, index-aligned with [live]'s cells. Kings get a small gold
  /// ring so a live board reads truthfully; null draws every piece as a man.
  final List<bool>? liveKings;

  _CheckersTilePainter({
    required this.t,
    required this.script,
    this.live,
    this.liveKings,
  });

  static const int n = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final s = _pick(script, _chkScripts);
    final presence = live != null ? 1.0 : _boardPresence(t);

    canvas.drawRRect(
      _tileRRect(size),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8D6E63), Color(0xFF5D4037)],
        ).createShader(Offset.zero & size),
    );

    final board = _sceneSquare(size, 0.86);
    final cell = board.width / n;

    // Squares
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final dark = (r + c).isOdd;
        canvas.drawRect(
          Rect.fromLTWH(
            board.left + c * cell,
            board.top + r * cell,
            cell + 0.5,
            cell + 0.5,
          ),
          Paint()
            ..color = dark ? const Color(0xFF5D4037) : const Color(0xFFD7CCC8),
        );
      }
    }

    // Opening layout: dark bottom, red top (owners: true=dark, false=red)
    final owners = List.generate(n, (_) => List<bool?>.filled(n, null));
    final liveBoard = live;
    if (liveBoard != null) {
      // Seed straight from the match; the first seat plays dark.
      for (var i = 0; i < liveBoard.cells.length && i < n * n; i++) {
        final owner = liveBoard.cells[i];
        if (owner == null) continue;
        owners[i ~/ n][i % n] = _isFirstSeat(owner, liveBoard.playerIds);
      }
    } else {
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < n; c++) {
          if ((r + c).isOdd) owners[r][c] = false;
        }
      }
      for (var r = 5; r < n; r++) {
        for (var c = 0; c < n; c++) {
          if ((r + c).isOdd) owners[r][c] = true;
        }
      }
    }

    // Apply completed moves; animate current.
    final moveCount = s.moves.length;
    var movingFrom = (-1, -1);
    var movingTo = (-1, -1);
    var moveP = 0.0;
    var movingDark = true;
    var capturedAt = (-1, -1);

    for (var i = 0; i < moveCount && liveBoard == null; i++) {
      final raw = _beat(t, i, moveCount, drawShare: 0.72);
      final (fr, fc, tr, tc) = s.moves[i];
      if (raw <= 0) break;
      if (raw < 1) {
        movingFrom = (fr, fc);
        movingTo = (tr, tc);
        moveP = Curves.easeInOutCubic.transform(raw);
        movingDark = owners[fr][fc] ?? true;
        if ((tr - fr).abs() == 2) {
          capturedAt = ((fr + tr) ~/ 2, (fc + tc) ~/ 2);
        }
        owners[fr][fc] = null;
        break;
      }
      // Commit
      final isDark = owners[fr][fc];
      owners[fr][fc] = null;
      if ((tr - fr).abs() == 2) {
        owners[(fr + tr) ~/ 2][(fc + tc) ~/ 2] = null;
      }
      owners[tr][tc] = isDark;
    }

    void paintMan(int r, int c, bool isDark, {double ox = 0, double oy = 0}) {
      final cx = board.left + (c + 0.5) * cell + ox;
      final cy = board.top + (r + 0.5) * cell + oy;
      final rad = cell * 0.36 * presence;
      if (rad < 0.4) return;
      final face = isDark ? _ink : _coral;
      canvas.drawCircle(
        Offset(cx, cy + rad * 0.12),
        rad * 0.9,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.2 * presence)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, rad * 0.2),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        rad,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.4),
            colors: [
              Color.lerp(face, Colors.white, 0.3)!,
              face,
              Color.lerp(face, Colors.black, 0.25)!,
            ],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: rad)),
      );
    }

    // Captured fade
    if (capturedAt.$1 >= 0 && moveP > 0) {
      final (cr, cc) = capturedAt;
      final fade = (1 - moveP).clamp(0.0, 1.0);
      canvas.saveLayer(
        board,
        Paint()..color = Colors.white.withValues(alpha: fade),
      );
      paintMan(cr, cc, !movingDark);
      canvas.restore();
    }

    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final o = owners[r][c];
        if (o == null) continue;
        if (r == movingFrom.$1 && c == movingFrom.$2) continue;
        paintMan(r, c, o);
      }
    }

    // Kings wear a small gold ring — the one piece of live state the plain
    // man-vs-man drawing would otherwise hide.
    final kings = liveKings;
    if (liveBoard != null && kings != null) {
      for (var i = 0; i < kings.length && i < n * n; i++) {
        if (!kings[i] || liveBoard.cells[i] == null) continue;
        canvas.drawCircle(
          Offset(
            board.left + (i % n + 0.5) * cell,
            board.top + (i ~/ n + 0.5) * cell,
          ),
          cell * 0.16,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.09
            ..color = _gold.withValues(alpha: 0.95),
        );
      }
    }

    if (movingFrom.$1 >= 0) {
      final (fr, fc) = movingFrom;
      final (tr, tc) = movingTo;
      final ox = (tc - fc) * cell * moveP;
      final oy = (tr - fr) * cell * moveP;
      final lift =
          (tr - fr).abs() == 2 ? math.sin(moveP * math.pi) * cell * 0.28 : 0.0;
      paintMan(fr, fc, movingDark, ox: ox, oy: oy - lift);
    }

    final winP = _celebrate(t);
    if (winP > 0.001) {
      final color = s.darkWins ? _ink : _coral;
      canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.10),
        size.shortestSide * 0.08 * winP,
        Paint()
          ..color = color.withValues(alpha: 0.4 * winP)
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, size.shortestSide * 0.04),
      );
    }
  }

  @override
  bool shouldRepaint(_CheckersTilePainter old) =>
      old.t != t ||
      old.script != script ||
      old.live != live ||
      old.liveKings != liveKings;
}

// ---------------------------------------------------------------------------
// Mancala tile — wood board, sow seeds into stores
// ---------------------------------------------------------------------------

class _MclScript {
  /// South-first pit indices to sow (0–5 south, 7–12 north).
  final List<int> pits;
  final bool southWins;

  const _MclScript(this.pits, {this.southWins = true});
}

const _mclScripts = <_MclScript>[
  _MclScript([2, 9, 5, 11, 1]),
  _MclScript([0, 7, 3, 10, 4], southWins: false),
  _MclScript([2, 8, 1, 12, 5]),
];

class _MancalaTilePainter extends CustomPainter {
  final double t;
  final int script;

  /// The REAL board, when this tile is showing a live match rather than the
  /// scripted demo: 14 pit counts, stores at 6 and 13.
  ///
  /// Non-null skips the script replay entirely — same chrome, same marbles,
  /// same everything, just seeded from the match instead of a canned sow. The
  /// art was never the problem; only its truthfulness was.
  final List<int>? livePits;

  _MancalaTilePainter({
    required this.t,
    required this.script,
    this.livePits,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = _pick(script, _mclScripts);
    // A live board is a still: it never plays the clear-out phase.
    final presence = livePits != null ? 1.0 : _boardPresence(t);

    // Maroon felt table, matching the live board's backdrop.
    canvas.drawRRect(
      _tileRRect(size),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7A4441), Color(0xFF5E322F), Color(0xFF46231F)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Offset.zero & size),
    );

    // Vertical tray (portrait), opened up a touch when the canvas is a wide
    // card window rather than a square tile.
    final trayScale = _isWide(size) ? 1.08 : 1.0;
    final board = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.shortestSide * 0.72 * trayScale,
      height: size.shortestSide * 0.88 * trayScale,
    );
    // Pale birch slab — static chrome; only the marbles clear with presence.
    canvas.drawRRect(
      RRect.fromRectAndRadius(board, Radius.circular(board.width * 0.14)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEADCBB), Color(0xFFD9C69F)],
        ).createShader(board),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(board, Radius.circular(board.width * 0.14)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF5E4C32).withValues(alpha: 0.35),
    );

    // Real Kalah opening: 4 seeds per pit, empty stores. Each scripted move
    // replays an actual sow — seeds drop one-by-one into consecutive cups,
    // skipping the opponent's store, exactly like the live board.
    final pits = List<int>.filled(14, 4);
    pits[6] = 0;
    pits[13] = 0;

    List<int> sowPath(int pit, int hand) {
      final oppStore = pit < 6 ? 13 : 6;
      final path = <int>[];
      var cup = pit;
      for (var k = 0; k < hand; k++) {
        cup = (cup + 1) % 14;
        if (cup == oppStore) cup = (cup + 1) % 14;
        path.add(cup);
      }
      return path;
    }

    final moveCount = s.pits.length;
    var highlight = -1;
    var flyFrom = -1;
    var flyTo = -1;
    var flyT = 0.0;
    var flyHand = 0;
    final live = livePits;
    if (live != null) {
      // Seed straight from the match — no sow to animate, nothing in hand.
      for (var i = 0; i < pits.length && i < live.length; i++) {
        pits[i] = live[i];
      }
    }
    for (var i = 0; i < moveCount && live == null; i++) {
      final raw = _beat(t, i, moveCount, drawShare: 0.72);
      if (raw <= 0) break;
      final pit = s.pits[i];
      final hand = pits[pit];
      if (hand <= 0) continue;
      final path = sowPath(pit, hand);
      if (raw >= 1) {
        // Move fully settled into the board state.
        pits[pit] = 0;
        for (final c in path) {
          pits[c] += 1;
        }
        continue;
      }
      // Mid-sow: landed seeds are in their cups; the rest fly as a hand.
      final prog = raw * hand;
      final done = prog.floor().clamp(0, hand - 1);
      pits[pit] = 0;
      for (var k = 0; k < done; k++) {
        pits[path[k]] += 1;
      }
      flyFrom = done == 0 ? pit : path[done - 1];
      flyTo = path[done];
      flyT = Curves.easeInOut.transform((prog - done).clamp(0.0, 1.0));
      flyHand = hand - done;
      highlight = flyTo;
      break;
    }

    // Vertical two-column layout matching the live board:
    // left top→down 7..12, right bottom→up 0..5; south store TOP, north BOTTOM.
    Offset cupC(int idx) {
      if (idx == 6) {
        // South store — top (after right column 5).
        return Offset(board.center.dx, board.top + board.height * 0.10);
      }
      if (idx == 13) {
        // North store — bottom (after left column 12).
        return Offset(board.center.dx, board.bottom - board.height * 0.10);
      }
      final row = idx < 6 ? (5 - idx) : (idx - 7); // top→bottom index
      final col = idx < 6 ? 1 : 0; // south right, north left
      return Offset(
        board.left + board.width * (0.30 + col * 0.40),
        board.top + board.height * (0.22 + row * 0.105),
      );
    }

    // GP glass-marble palette (hi, base) — white / blue / black.
    const marbleColors = [
      (Color(0xFFFFFFFF), Color(0xFFE8E8E2)),
      (Color(0xFFBBD4F8), Color(0xFF4C7FD9)),
      (Color(0xFF94949C), Color(0xFF45454B)),
    ];

    void drawMarble(Offset p, double r, int colorIdx) {
      // Marbles scale out in place during the clear phase (house pattern —
      // the board itself never fades).
      final rr = r * presence;
      if (rr < 0.3) return;
      final (hi, base) = marbleColors[colorIdx % 3];
      canvas.drawCircle(
        p,
        rr,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.3),
            colors: [hi, base],
          ).createShader(Rect.fromCircle(center: p, radius: rr)),
      );
    }

    void drawCup(int idx, double r, int count) {
      final c = cupC(idx);
      // Shallow same-wood scoop: tan fill + top-shadow rim.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFAE9668),
              const Color(0xFFCDB88E),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.08
          ..color = const Color(0xFF8A7350).withValues(alpha: 0.5),
      );
      if (highlight == idx) {
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.14
            ..color = const Color(0xFF8B6F47).withValues(alpha: 0.9),
        );
      }
      final n = count.clamp(0, 6);
      for (var i = 0; i < n; i++) {
        final a = -math.pi / 2 + i * (2 * math.pi / math.max(n, 1));
        final p =
            c + Offset(math.cos(a), math.sin(a)) * r * (n > 1 ? 0.40 : 0.0);
        drawMarble(p, r * 0.18, idx * 2 + i * 5);
      }
    }

    // Radius sized under the row pitch so cups never overlap.
    final pitR = board.width * 0.062;

    // Elongated end-stores (stadium wells like the live board), marbles
    // packed in centered rows along the oval.
    void drawStore(int idx, int count) {
      final c = cupC(idx);
      final rect = Rect.fromCenter(
        center: c,
        width: board.width * 0.56,
        height: board.height * 0.115,
      );
      final rr = RRect.fromRectAndRadius(
        rect,
        Radius.circular(rect.height / 2),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFAE9668),
              const Color(0xFFCDB88E),
            ],
          ).createShader(rect),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rect.height * 0.06
          ..color = const Color(0xFF8A7350).withValues(alpha: 0.5),
      );
      if (highlight == idx) {
        canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = rect.height * 0.10
            ..color = const Color(0xFF8B6F47).withValues(alpha: 0.9),
        );
      }
      final n = count.clamp(0, 8);
      for (var i = 0; i < n; i++) {
        final col = i % 4;
        final row = i ~/ 4;
        final colsInRow = row == 0 ? math.min(n, 4) : n - 4;
        final p = Offset(
          c.dx + rect.width * 0.226 * (col - (colsInRow - 1) / 2),
          c.dy + (n <= 4 ? 0 : (row == 0 ? -1 : 1)) * rect.height * 0.18,
        );
        drawMarble(p, pitR * 0.24, idx * 2 + i * 5);
      }
    }

    for (var i = 0; i < 6; i++) {
      drawCup(i, pitR, pits[i]);
      drawCup(12 - i, pitR, pits[12 - i]);
    }
    drawStore(6, pits[6]);
    drawStore(13, pits[13]);

    // Flying hand: remaining seeds arc between cups, one dropping per hop.
    if (flyFrom >= 0 && flyT > 0 && flyT < 1) {
      final a = cupC(flyFrom);
      final b = cupC(flyTo);
      final mid = Offset.lerp(a, b, flyT)!;
      final lift = (b - a).distance * 0.42 * math.sin(math.pi * flyT);
      final p = Offset(mid.dx, mid.dy - lift);
      final n = flyHand.clamp(1, 5);
      for (var j = 0; j < n; j++) {
        final off = n == 1
            ? Offset.zero
            : Offset.fromDirection(
                -math.pi / 2 + j * 2 * math.pi / n,
                pitR * 0.18,
              );
        drawMarble(p + off, pitR * 0.20, flyFrom * 2 + j * 5);
      }
    }

    final winP = _celebrate(t);
    if (winP > 0.001) {
      // Warm glow over the winner's store (ink reads as a smudge on pale wood).
      final color = s.southWins ? _gold : _coral;
      canvas.drawCircle(
        cupC(s.southWins ? 6 : 13),
        board.width * 0.18 * winP,
        Paint()
          ..color = color.withValues(alpha: 0.45 * winP)
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, size.shortestSide * 0.04),
      );
    }
  }

  @override
  bool shouldRepaint(_MancalaTilePainter old) =>
      old.t != t || old.script != script || old.livePits != livePits;
}

// ---------------------------------------------------------------------------
// Gomoku tile — birch grid, stones click in until five line up
// ---------------------------------------------------------------------------

class _GmkScript {
  /// Alternating placements starting with black.
  final List<(int row, int col)> moves;

  /// Indices into [moves] forming the winning five.
  final List<int> winMoves;
  final bool blackWins;

  const _GmkScript(this.moves, this.winMoves, {this.blackWins = true});
}

const _gmkScripts = <_GmkScript>[
  // Black horizontal on the middle row.
  _GmkScript(
    [
      (4, 2),
      (2, 2),
      (4, 3),
      (3, 5),
      (4, 4),
      (5, 3),
      (4, 5),
      (6, 6),
      (4, 6),
    ],
    [0, 2, 4, 6, 8],
  ),
  // White main diagonal.
  _GmkScript(
    [
      (2, 6),
      (2, 2),
      (3, 2),
      (3, 3),
      (6, 3),
      (4, 4),
      (5, 6),
      (5, 5),
      (7, 4),
      (6, 6),
    ],
    [1, 3, 5, 7, 9],
    blackWins: false,
  ),
  // Black anti-diagonal climbing right.
  _GmkScript(
    [
      (6, 2),
      (3, 2),
      (5, 3),
      (4, 2),
      (4, 4),
      (5, 6),
      (3, 5),
      (6, 6),
      (2, 6),
    ],
    [0, 2, 4, 6, 8],
  ),
  // Black vertical on the right side.
  _GmkScript(
    [
      (2, 6),
      (3, 3),
      (3, 6),
      (4, 4),
      (4, 6),
      (5, 5),
      (5, 6),
      (2, 3),
      (6, 6),
    ],
    [0, 2, 4, 6, 8],
  ),
];

class _GomokuTilePainter extends CustomPainter {
  final double t;
  final int script;

  /// The real board, when this tile shows a live match. Stones are square-
  /// indexed row-major over [boardSize]; the first seat plays black.
  final LiveCells? live;

  /// Row length of [live]'s board. Gomoku's size is configurable, so it comes
  /// in with the state rather than being assumed.
  final int liveSize;
  _GomokuTilePainter({
    required this.t,
    required this.script,
    this.live,
    this.liveSize = 15,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = _pick(script, _gmkScripts);
    final presence = live != null ? 1.0 : _boardPresence(t);

    // Scripted dioramas play on a toy 9-line board; a live match draws its
    // real grid (placing liveSize-indexed stones on the toy grid painted most
    // of a 15x15 game off the tile entirely).
    final n = live != null ? liveSize : 9;

    // Birch slab tile.
    canvas.drawRRect(
      _tileRRect(size),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEDE0C3), Color(0xFFD9C69E)],
        ).createShader(Offset.zero & size),
    );

    final board = _sceneSquare(size, 0.80);
    final gap = board.width / (n - 1);

    Offset at(int r, int c) =>
        Offset(board.left + c * gap, board.top + r * gap);

    final line = Paint()
      ..color = const Color(0xFF6B5233).withValues(alpha: 0.5)
      ..strokeWidth = math.max(1.0, gap * 0.06);
    for (var i = 0; i < n; i++) {
      canvas.drawLine(at(i, 0), at(i, n - 1), line);
      canvas.drawLine(at(0, i), at(n - 1, i), line);
    }
    final mid = (n - 1) ~/ 2;
    canvas.drawCircle(
      at(mid, mid),
      gap * 0.14,
      Paint()..color = const Color(0xFF6B5233).withValues(alpha: 0.6),
    );

    void paintStone(int r, int c, bool isBlack, double p) {
      final rad = gap * 0.42 * p * presence;
      if (rad < 0.4) return;
      final face = isBlack ? const Color(0xFF26262B) : const Color(0xFFF2F1EC);
      final o = at(r, c);
      canvas.drawCircle(
        o.translate(0, rad * 0.14),
        rad * 0.9,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.2 * presence)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, rad * 0.2),
      );
      canvas.drawCircle(
        o,
        rad,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.4),
            colors: [
              Color.lerp(face, Colors.white, isBlack ? 0.32 : 0.6)!,
              face,
              Color.lerp(face, Colors.black, isBlack ? 0.35 : 0.16)!,
            ],
          ).createShader(Rect.fromCircle(center: o, radius: rad)),
      );
    }

    final liveBoard = live;
    if (liveBoard != null) {
      // Every stone already on the board, full size, no pop-in.
      for (var i = 0; i < liveBoard.cells.length; i++) {
        final owner = liveBoard.cells[i];
        if (owner == null) continue;
        paintStone(
          i ~/ liveSize,
          i % liveSize,
          _isFirstSeat(owner, liveBoard.playerIds),
          1.0,
        );
      }
    } else {
      final moveCount = s.moves.length;
      for (var i = 0; i < moveCount; i++) {
        final p = _piece(t, i, moveCount, drawShare: 0.5);
        if (p <= 0) break;
        final (r, c) = s.moves[i];
        paintStone(r, c, i.isEven, Curves.easeOutBack.transform(p));
      }
    }

    if (liveBoard != null) {
      // A finished live board rings its winning five in gold, full strength.
      final run = _findRun(liveBoard.cells, liveSize, liveSize, 5);
      if (run != null) {
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, gap * 0.14)
          ..color = _gold.withValues(alpha: 0.9);
        for (final i in run) {
          canvas.drawCircle(at(i ~/ liveSize, i % liveSize), gap * 0.46, ring);
        }
      }
      return;
    }

    // Gold rings pop over the winning five.
    final winP = _celebrate(t);
    if (winP > 0.001) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, gap * 0.14)
        ..color = _gold.withValues(alpha: 0.9 * winP);
      for (final m in s.winMoves) {
        final (r, c) = s.moves[m];
        canvas.drawCircle(at(r, c), gap * 0.42 * (0.7 + 0.4 * winP), ring);
      }
      // Winner glow at the top edge, matching the other tiles.
      final glow = s.blackWins ? _ink : const Color(0xFFF2F1EC);
      canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.10),
        size.shortestSide * 0.08 * winP,
        Paint()
          ..color = glow.withValues(alpha: 0.4 * winP)
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, size.shortestSide * 0.04),
      );
    }
  }

  @override
  bool shouldRepaint(_GomokuTilePainter old) =>
      old.t != t ||
      old.script != script ||
      old.live != live ||
      old.liveSize != liveSize;
}

// ---------------------------------------------------------------------------
// Chess tile — two-tone board, a quick scripted miniature ending in mate
// ---------------------------------------------------------------------------

class _ChsScript {
  /// UCI moves from the standard start, alternating white/black.
  final List<String> moves;
  final bool whiteWins;

  const _ChsScript(this.moves, {this.whiteWins = true});
}

const _chsScripts = <_ChsScript>[
  // Scholar's mate.
  _ChsScript(['e2e4', 'e7e5', 'f1c4', 'b8c6', 'd1h5', 'g8f6', 'h5f7']),
  // Fool's mate — black delivers.
  _ChsScript(['f2f3', 'e7e5', 'g2g4', 'd8h4'], whiteWins: false),
  // Scholar's with the bishop line.
  _ChsScript(['e2e4', 'e7e5', 'f1c4', 'f8c5', 'd1h5', 'g8f6', 'h5f7']),
];

class _ChessTilePainter extends CustomPainter {
  final double t;
  final int script;

  /// The real position, when this tile shows a live match: 64 row-major cells
  /// (row 0 = rank 8), each null or a piece letter in `ChessState.boardCells`
  /// encoding (white upper-case). Non-null skips the scripted miniature.
  final List<String?>? livePieces;

  _ChessTilePainter({required this.t, required this.script, this.livePieces});

  static int _sq(String a) =>
      (8 - int.parse(a[1])) * 8 + (a.codeUnitAt(0) - 97);

  static List<String?> _startCells() {
    const back = ['r', 'n', 'b', 'q', 'k', 'b', 'n', 'r'];
    final cells = List<String?>.filled(64, null);
    for (var c = 0; c < 8; c++) {
      cells[c] = back[c];
      cells[8 + c] = 'p';
      cells[48 + c] = 'P';
      cells[56 + c] = back[c].toUpperCase();
    }
    return cells;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = _pick(script, _chsScripts);
    final presence = livePieces != null ? 1.0 : _boardPresence(t);

    canvas.drawRRect(
      _tileRRect(size),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEDE0C3), Color(0xFFD9C69E)],
        ).createShader(Offset.zero & size),
    );

    final board = _sceneSquare(size, 0.86);
    final cell = board.width / 8;

    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        canvas.drawRect(
          Rect.fromLTWH(board.left + c * cell, board.top + r * cell, cell + 0.5,
              cell + 0.5),
          Paint()
            ..color = (r + c).isOdd
                ? const Color(0xFFB08A5F)
                : const Color(0xFFEBDDBE),
        );
      }
    }

    Offset at(int sq) => Offset(
          board.left + (sq % 8 + 0.5) * cell,
          board.top + (sq ~/ 8 + 0.5) * cell,
        );

    // Live: the real position, nothing in flight. Scripted: apply committed
    // moves and capture the in-flight one.
    final livePosition = livePieces;
    final cells =
        livePosition != null ? List<String?>.of(livePosition) : _startCells();
    final moveCount = livePosition != null ? 0 : s.moves.length;
    String? flying;
    var flyFrom = -1, flyTo = -1;
    var flyP = 0.0;
    String? fadingVictim;
    var fadeAt = -1;

    for (var i = 0; i < moveCount; i++) {
      final raw = _beat(t, i, moveCount, drawShare: 0.6);
      if (raw <= 0) break;
      final from = _sq(s.moves[i].substring(0, 2));
      final to = _sq(s.moves[i].substring(2, 4));
      if (raw < 1) {
        flying = cells[from];
        flyFrom = from;
        flyTo = to;
        flyP = Curves.easeInOutCubic.transform(raw);
        fadingVictim = cells[to];
        fadeAt = to;
        cells[from] = null;
        break;
      }
      cells[to] = cells[from];
      cells[from] = null;
    }

    void piece(String p, Offset o, {double opacity = 1}) {
      final h = cell * 0.92 * presence;
      if (h < 1) return;
      ChessPieceArt.paint(
        canvas,
        center: o,
        height: h,
        piece: p,
        opacity: opacity,
      );
    }

    if (fadingVictim != null && flyP > 0) {
      piece(fadingVictim, at(fadeAt),
          opacity: (1 - flyP).clamp(0.0, 1.0) * presence);
    }
    for (var i = 0; i < cells.length && i < 64; i++) {
      final p = cells[i];
      if (p == null) continue;
      piece(p, at(i), opacity: presence);
    }
    if (flying != null) {
      final o = Offset.lerp(at(flyFrom), at(flyTo), flyP)!;
      piece(flying, o, opacity: presence);
    }

    // The celebrate glow and mate ring are the script's; a live still ends
    // at the position itself.
    final winP = livePosition != null ? 0.0 : _celebrate(t);
    if (winP > 0.001) {
      final glow = s.whiteWins ? const Color(0xFFF4F1E8) : _ink;
      canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.10),
        size.shortestSide * 0.08 * winP,
        Paint()
          ..color = glow.withValues(alpha: 0.45 * winP)
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, size.shortestSide * 0.04),
      );
      // Gold ring on the mating square.
      final mate = _sq(s.moves.last.substring(2, 4));
      canvas.drawCircle(
        at(mate),
        cell * 0.55 * (0.7 + 0.4 * winP),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, cell * 0.12)
          ..color = _gold.withValues(alpha: 0.9 * winP),
      );
    }
  }

  @override
  bool shouldRepaint(_ChessTilePainter old) =>
      old.t != t || old.script != script || old.livePieces != livePieces;
}

/// One static frame of [kind]'s diorama, for thumbnails that cannot animate —
/// chat cards, rasterized map bubbles. The defaults land late in the action
/// phase so the board reads as a match in progress rather than the empty
/// opening frame, with a fixed script so every surface shows the same scene.
/// The SAME authored diorama as [classicGameTilePainter], seeded from a real
/// match instead of a canned script.
///
/// This is what a chat card or map bubble should show once a match is under
/// way: identical chrome, marbles and palette — only the position is the one
/// being played. The scripted still is an advertisement for the game; after a
/// move has been made it reads as the board having reset.
///
/// Returns null for kinds that cannot yet be driven from state, so hosts fall
/// back to [classicGameTilePainter] rather than inventing a second visual
/// language for the same game.
CustomPainter? classicGameStatePainter(
  GameTileKind kind, {
  /// Mancala: 14 pit counts, stores at 6 and 13.
  List<int>? mancalaPits,

  /// Dots and boxes: owner-per-edge / owner-per-box, indexed as
  /// `DotsAndBoxesState` stores them, plus the seat order.
  ({
    List<String?> hEdges,
    List<String?> vEdges,
    List<String?> boxes,
    List<String> playerIds,
  })? dotsAndBoxes,

  /// Every classic that stores one owner per square: tic-tac-toe, connect four,
  /// reversi, checkers and gomoku all take the board this way.
  LiveCells? cells,

  /// Gomoku's row length — its board size is configurable, unlike the others.
  int gomokuSize = 15,

  /// Checkers king flags, index-aligned with [cells]; kings get a gold ring.
  List<bool>? checkersKings,

  /// Chess: 64 row-major cells (row 0 = rank 8), null or a piece letter in
  /// `ChessState.boardCells` encoding (white upper-case).
  List<String?>? chessPieces,
}) =>
    switch (kind) {
      GameTileKind.mancala when mancalaPits != null =>
        _MancalaTilePainter(t: 0, script: 0, livePits: mancalaPits),
      GameTileKind.dotsAndBoxes when dotsAndBoxes != null =>
        _DotsBoxesTilePainter(t: 0, script: 0, live: dotsAndBoxes),
      GameTileKind.ticTacToe when cells != null =>
        _TicTacToeTilePainter(t: 0, script: 0, live: cells),
      GameTileKind.connectFour when cells != null =>
        _ConnectFourTilePainter(t: 0, script: 0, live: cells),
      GameTileKind.reversi when cells != null =>
        _ReversiTilePainter(t: 0, script: 0, live: cells),
      GameTileKind.checkers when cells != null => _CheckersTilePainter(
          t: 0,
          script: 0,
          live: cells,
          liveKings: checkersKings,
        ),
      GameTileKind.gomoku when cells != null => _GomokuTilePainter(
          t: 0,
          script: 0,
          live: cells,
          liveSize: gomokuSize,
        ),
      GameTileKind.chess when chessPieces != null =>
        _ChessTilePainter(t: 0, script: 0, livePieces: chessPieces),
      _ => null,
    };

CustomPainter classicGameTilePainter(
  GameTileKind kind, {
  double t = 0.68,
  int script = 7,
}) =>
    switch (kind) {
      GameTileKind.ticTacToe => _TicTacToeTilePainter(t: t, script: script),
      GameTileKind.connectFour => _ConnectFourTilePainter(t: t, script: script),
      GameTileKind.dotsAndBoxes => _DotsBoxesTilePainter(t: t, script: script),
      GameTileKind.reversi => _ReversiTilePainter(t: t, script: script),
      GameTileKind.checkers => _CheckersTilePainter(t: t, script: script),
      GameTileKind.mancala => _MancalaTilePainter(t: t, script: script),
      GameTileKind.gomoku => _GomokuTilePainter(t: t, script: script),
      GameTileKind.chess => _ChessTilePainter(t: t, script: script),
    };
