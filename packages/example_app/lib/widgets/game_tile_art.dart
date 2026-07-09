import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/demo_theme.dart';

/// Which miniature to paint on a launcher tile.
enum GameTileKind { ticTacToe, connectFour, dotsAndBoxes }

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

class _TicTacToeTilePainter extends CustomPainter {
  final double t;
  final int script;
  _TicTacToeTilePainter({required this.t, required this.script});

  @override
  void paint(Canvas canvas, Size size) {
    final s = _pick(script, _tttScripts);

    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.22),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF8F0), Color(0xFFFFE8D6)],
        ).createShader(Offset.zero & size),
    );

    final pad = size.width * 0.18;
    final board = Rect.fromLTWH(
      pad,
      pad,
      size.width - pad * 2,
      size.height - pad * 2,
    );
    final cell = board.width / 3;
    final grid = Paint()
      ..color = DemoColors.ink.withValues(alpha: 0.55)
      ..strokeWidth = size.width * 0.028
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

    for (var i = 0; i < s.moves.length; i++) {
      final p = _piece(t, i, s.moves.length);
      if (p <= 0.001) continue;
      final (col, row, isX) = s.moves[i];
      final c = Offset(
        board.left + (col + 0.5) * cell,
        board.top + (row + 0.5) * cell,
      );
      if (isX) {
        _drawX(canvas, c, cell * 0.22, size.width * 0.04, DemoColors.coral, p);
      } else {
        _drawO(canvas, c, cell * 0.24, size.width * 0.04, DemoColors.teal, p);
      }
    }

    final winP = _celebrate(t);
    final line = s.winLine;
    if (winP > 0.001 && line != null) {
      final (c0, r0, c1, r1) = line;
      final a = Offset(
        board.left + (c0 + 0.5) * cell,
        board.top + (r0 + 0.5) * cell,
      );
      final b = Offset(
        board.left + (c1 + 0.5) * cell,
        board.top + (r1 + 0.5) * cell,
      );
      final color = s.xWins ? DemoColors.coral : DemoColors.teal;
      // Draw full line, scale alpha with winP (clears with presence).
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = color.withValues(alpha: 0.9 * winP)
          ..strokeWidth = size.width * 0.05 * (0.5 + 0.5 * winP)
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
      old.t != t || old.script != script;
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
    this.winColor = DemoColors.coral,
  });
}

const _c4Scripts = <_C4Script>[
  // Coral vertical col 2
  _C4Script(
    [
      (2, 3, DemoColors.coral),
      (1, 3, DemoColors.gold),
      (2, 2, DemoColors.coral),
      (0, 3, DemoColors.gold),
      (2, 1, DemoColors.coral),
      (3, 3, DemoColors.gold),
      (2, 0, DemoColors.coral),
    ],
    winLine: (2, 0, 2, 3),
  ),
  // Gold vertical col 1
  _C4Script(
    [
      (2, 3, DemoColors.coral),
      (1, 3, DemoColors.gold),
      (3, 3, DemoColors.coral),
      (1, 2, DemoColors.gold),
      (4, 3, DemoColors.coral),
      (1, 1, DemoColors.gold),
      (0, 3, DemoColors.coral),
      (1, 0, DemoColors.gold),
    ],
    winLine: (1, 0, 1, 3),
    winColor: DemoColors.gold,
  ),
  // Coral horizontal bottom 0–3
  _C4Script(
    [
      (0, 3, DemoColors.coral),
      (4, 3, DemoColors.gold),
      (1, 3, DemoColors.coral),
      (4, 2, DemoColors.gold),
      (2, 3, DemoColors.coral),
      (4, 1, DemoColors.gold),
      (3, 3, DemoColors.coral),
    ],
    winLine: (0, 3, 3, 3),
  ),
  // Gold horizontal bottom 1–4
  _C4Script(
    [
      (0, 3, DemoColors.coral),
      (1, 3, DemoColors.gold),
      (0, 2, DemoColors.coral),
      (2, 3, DemoColors.gold),
      (0, 1, DemoColors.coral),
      (3, 3, DemoColors.gold),
      (0, 0, DemoColors.coral),
      (4, 3, DemoColors.gold),
    ],
    winLine: (1, 3, 4, 3),
    winColor: DemoColors.gold,
  ),
  // Coral vertical col 0
  _C4Script(
    [
      (0, 3, DemoColors.coral),
      (2, 3, DemoColors.gold),
      (0, 2, DemoColors.coral),
      (3, 3, DemoColors.gold),
      (0, 1, DemoColors.coral),
      (1, 3, DemoColors.gold),
      (0, 0, DemoColors.coral),
    ],
    winLine: (0, 0, 0, 3),
  ),
  // Gold vertical col 3
  _C4Script(
    [
      (1, 3, DemoColors.coral),
      (3, 3, DemoColors.gold),
      (2, 3, DemoColors.coral),
      (3, 2, DemoColors.gold),
      (0, 3, DemoColors.coral),
      (3, 1, DemoColors.gold),
      (4, 3, DemoColors.coral),
      (3, 0, DemoColors.gold),
    ],
    winLine: (3, 0, 3, 3),
    winColor: DemoColors.gold,
  ),
];

class _ConnectFourTilePainter extends CustomPainter {
  final double t;
  final int script;
  _ConnectFourTilePainter({required this.t, required this.script});

  @override
  void paint(Canvas canvas, Size size) {
    final s = _pick(script, _c4Scripts);

    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.22),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5B9DFF), Color(0xFF2B6BCB)],
        ).createShader(Offset.zero & size),
    );

    final pad = size.width * 0.14;
    final frame = Rect.fromLTWH(
      pad,
      pad * 1.15,
      size.width - pad * 2,
      size.height - pad * 2.1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, Radius.circular(size.width * 0.08)),
      Paint()..color = const Color(0xFF1E5AAD),
    );

    const cols = 5;
    const rows = 4;
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

    final presence = _boardPresence(t);
    for (var i = 0; i < s.drops.length; i++) {
      final p = _piece(t, i, s.drops.length, drawShare: 0.70);
      if (p <= 0.001) continue;
      final (col, landRow, color) = s.drops[i];
      final restY = frame.top + (landRow + 0.5) * cellH;
      final startY = frame.top - cellH * 0.75;
      // During clear, reverse the drop (discs rise out) instead of flashing.
      final fallAmount = presence < 1
          ? presence
          : Curves.easeInCubic.transform(p.clamp(0.0, 1.0));
      var y = lerpDouble(startY, restY, fallAmount)!;
      if (presence >= 1 && p > 0.82) {
        final b = (p - 0.82) / 0.18;
        y -= math.sin(b * math.pi) * cellH * 0.07;
      }
      final c = Offset(frame.left + (col + 0.5) * cellW, y);
      final radius = holeR * 0.92 * (presence < 1 ? presence.clamp(0.0, 1.0) : 1);
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
          ..strokeWidth = size.width * 0.04 * winP
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ConnectFourTilePainter old) =>
      old.t != t || old.script != script;
}

// ---------------------------------------------------------------------------
// Dots & boxes — full 2×2 (12 edges), several outcomes
// ---------------------------------------------------------------------------

class _DabScript {
  final List<(String kind, int r, int c, Color color)> edges;
  /// (boxRow, boxCol, closeStep, owner)
  final List<(int br, int bc, int closeStep, Color owner)> fills;
  final Color winColor;

  const _DabScript({
    required this.edges,
    required this.fills,
    required this.winColor,
  });
}

const _dabScripts = <_DabScript>[
  // Coral 3 – teal 1
  _DabScript(
    edges: [
      ('h', 0, 0, DemoColors.coral),
      ('v', 0, 0, DemoColors.teal),
      ('v', 0, 1, DemoColors.coral),
      ('h', 1, 0, DemoColors.teal), // teal box00
      ('h', 0, 1, DemoColors.coral),
      ('v', 0, 2, DemoColors.teal),
      ('v', 1, 0, DemoColors.coral),
      ('v', 1, 2, DemoColors.teal),
      ('h', 1, 1, DemoColors.coral), // coral box01
      ('h', 2, 0, DemoColors.coral),
      ('h', 2, 1, DemoColors.coral),
      ('v', 1, 1, DemoColors.coral), // coral box10+11
    ],
    fills: [
      (0, 0, 3, DemoColors.teal),
      (0, 1, 8, DemoColors.coral),
      (1, 0, 11, DemoColors.coral),
      (1, 1, 11, DemoColors.coral),
    ],
    winColor: DemoColors.coral,
  ),
  // Teal 3 – coral 1 (mirror colors)
  _DabScript(
    edges: [
      ('h', 0, 0, DemoColors.teal),
      ('v', 0, 0, DemoColors.coral),
      ('v', 0, 1, DemoColors.teal),
      ('h', 1, 0, DemoColors.coral), // coral box00
      ('h', 0, 1, DemoColors.teal),
      ('v', 0, 2, DemoColors.coral),
      ('v', 1, 0, DemoColors.teal),
      ('v', 1, 2, DemoColors.coral),
      ('h', 1, 1, DemoColors.teal), // teal box01
      ('h', 2, 0, DemoColors.teal),
      ('h', 2, 1, DemoColors.teal),
      ('v', 1, 1, DemoColors.teal), // teal box10+11
    ],
    fills: [
      (0, 0, 3, DemoColors.coral),
      (0, 1, 8, DemoColors.teal),
      (1, 0, 11, DemoColors.teal),
      (1, 1, 11, DemoColors.teal),
    ],
    winColor: DemoColors.teal,
  ),
  // Coral sweeps all 4 (teal never closes)
  _DabScript(
    edges: [
      ('h', 0, 0, DemoColors.coral),
      ('v', 0, 0, DemoColors.teal),
      ('h', 0, 1, DemoColors.coral),
      ('v', 0, 2, DemoColors.teal),
      ('v', 1, 0, DemoColors.coral),
      ('v', 1, 2, DemoColors.teal),
      ('h', 2, 0, DemoColors.coral),
      ('h', 2, 1, DemoColors.teal),
      ('v', 0, 1, DemoColors.coral),
      ('h', 1, 0, DemoColors.coral), // coral box00
      ('h', 1, 1, DemoColors.coral), // coral box01
      ('v', 1, 1, DemoColors.coral), // coral bottom pair
    ],
    fills: [
      (0, 0, 9, DemoColors.coral),
      (0, 1, 10, DemoColors.coral),
      (1, 0, 11, DemoColors.coral),
      (1, 1, 11, DemoColors.coral),
    ],
    winColor: DemoColors.coral,
  ),
  // Split 2–2 (still a complete game)
  _DabScript(
    edges: [
      ('h', 0, 0, DemoColors.coral),
      ('v', 0, 0, DemoColors.teal),
      ('v', 0, 1, DemoColors.coral),
      ('h', 1, 0, DemoColors.teal), // teal box00
      ('h', 0, 1, DemoColors.teal), // extra
      ('v', 0, 2, DemoColors.coral),
      ('h', 1, 1, DemoColors.teal), // teal box01
      ('v', 1, 0, DemoColors.coral),
      ('v', 1, 2, DemoColors.coral),
      ('h', 2, 0, DemoColors.coral),
      ('h', 2, 1, DemoColors.coral),
      ('v', 1, 1, DemoColors.coral), // coral bottoms
    ],
    fills: [
      (0, 0, 3, DemoColors.teal),
      (0, 1, 6, DemoColors.teal),
      (1, 0, 11, DemoColors.coral),
      (1, 1, 11, DemoColors.coral),
    ],
    winColor: DemoColors.gold, // draw-ish celebrate
  ),
];

class _DotsBoxesTilePainter extends CustomPainter {
  final double t;
  final int script;
  _DotsBoxesTilePainter({required this.t, required this.script});

  @override
  void paint(Canvas canvas, Size size) {
    final s = _pick(script, _dabScripts);

    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.22),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBF0), Color(0xFFFFF0C8)],
        ).createShader(Offset.zero & size),
    );

    final pad = size.width * 0.2;
    final area = Rect.fromLTWH(
      pad,
      pad,
      size.width - pad * 2,
      size.height - pad * 2,
    );
    const n = 3;
    final step = area.width / (n - 1);

    Offset d(int x, int y) => Offset(area.left + x * step, area.top + y * step);

    final free = Paint()
      ..color = DemoColors.ink.withValues(alpha: 0.12)
      ..strokeWidth = size.width * 0.028
      ..strokeCap = StrokeCap.round;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n - 1; x++) {
        canvas.drawLine(d(x, y), d(x + 1, y), free);
      }
    }
    for (var y = 0; y < n - 1; y++) {
      for (var x = 0; x < n; x++) {
        canvas.drawLine(d(x, y), d(x, y + 1), free);
      }
    }

    final presence = _boardPresence(t);
    for (var i = 0; i < s.edges.length; i++) {
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
          ..strokeWidth = size.width * 0.045
          ..strokeCap = StrokeCap.round,
      );
    }

    for (final (br, bc, closeStep, owner) in s.fills) {
      final p = _piece(t, closeStep, s.edges.length, drawShare: 0.58);
      if (p < 0.85) continue;
      final local = Curves.easeOutCubic.transform(
        ((p - 0.85) / 0.15).clamp(0.0, 1.0),
      );
      final cFill = local * presence;
      if (cFill <= 0.001) continue;
      final cx = area.left + (bc + 0.5) * step;
      final cy = area.top + (br + 0.5) * step;
      final side = (step - 6) * (0.2 + 0.8 * cFill);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy), width: side, height: side),
          Radius.circular(size.width * 0.035),
        ),
        Paint()..color = owner.withValues(alpha: 0.32 * cFill),
      );
    }

    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        canvas.drawCircle(
          d(x, y),
          size.width * 0.038,
          Paint()..color = DemoColors.ink,
        );
      }
    }

    final winP = _celebrate(t);
    if (winP > 0.001) {
      canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.12),
        size.width * 0.09 * winP,
        Paint()
          ..color = s.winColor.withValues(alpha: 0.4 * winP)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.045),
      );
    }
  }

  @override
  bool shouldRepaint(_DotsBoxesTilePainter old) =>
      old.t != t || old.script != script;
}
