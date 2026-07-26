import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'basketball_game.dart';
import 'basketball_style.dart';

/// End-of-match results: both shootarounds broken down by round, the winner
/// banner, and a confetti burst for the winner.
class BasketballResultsView extends StatefulWidget {
  final BasketballGame game;
  final BasketballState state;
  final BasketballStyle style;

  const BasketballResultsView({
    super.key,
    required this.game,
    required this.state,
    this.style = const BasketballStyle(),
  });

  @override
  State<BasketballResultsView> createState() => _BasketballResultsViewState();
}

class _BasketballResultsViewState extends State<BasketballResultsView>
    with SingleTickerProviderStateMixin {
  // Built in initState, never a `late` inline initializer (dispose safety).
  late final AnimationController _confettiCtrl;
  final math.Random _rnd = math.Random();
  List<_Confetto> _confetti = const [];

  @override
  void initState() {
    super.initState();
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    final outcome = widget.game.outcome(widget.state);
    if (widget.style.confetti && outcome != null && !outcome.isDraw) {
      _confetti = _spawn();
      _confettiCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _confettiCtrl.dispose();
    super.dispose();
  }

  List<_Confetto> _spawn() {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF007AFF));
    final palette = [
      widget.style.resolvePlayer1(scheme),
      widget.style.resolvePlayer2(scheme),
      widget.style.resolveBall(scheme),
      Colors.white,
    ];
    return List.generate(36, (i) {
      final angle = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 2.6;
      return _Confetto(
        angle: angle,
        speed: 0.5 + _rnd.nextDouble(),
        size: 0.012 + _rnd.nextDouble() * 0.02,
        color: palette[i % palette.length],
        spin: (_rnd.nextDouble() - 0.5) * 12,
        phase: _rnd.nextDouble() * math.pi,
        round: _rnd.nextBool(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final state = widget.state;
    final backdrop = style.resolveBackdrop(scheme);
    final p1 = state.playerIds.first;
    final p2 = state.playerIds.last;
    final outcome = widget.game.outcome(state);

    final banner = outcome == null
        ? ''
        : outcome.isDraw
            ? 'Draw'
            : '${outcome.winnerId == p1 ? style.player1Label : style.player2Label} wins';

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: RadialGradient(
              center: const Alignment(0, -0.35),
              radius: 1.5,
              colors: [
                Color.lerp(backdrop, Colors.white, 0.10)!,
                backdrop,
                Color.lerp(backdrop, Colors.black, 0.32)!,
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
              Text(
                banner.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 23,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ScoreColumn(
                    label: style.player1Label,
                    rounds: state.roundsOf(p1),
                    total: state.scoreOf(p1),
                    accent: style.resolvePlayer1(scheme),
                    winner: outcome?.winnerId == p1,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: Text(
                        '–',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w900,
                          fontSize: 28,
                        ),
                      ),
                    ),
                  ),
                  _ScoreColumn(
                    label: style.player2Label,
                    rounds: state.roundsOf(p2),
                    total: state.scoreOf(p2),
                    accent: style.resolvePlayer2(scheme),
                    winner: outcome?.winnerId == p2,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (style.confetti && _confetti.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _confettiCtrl,
                builder: (context, _) => LayoutBuilder(
                  builder: (context, c) => CustomPaint(
                    painter: _ConfettiPainter(
                      confetti: _confetti,
                      t: _confettiCtrl.value,
                      boardSize: c.maxWidth,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScoreColumn extends StatelessWidget {
  final String label;
  final List<int> rounds;
  final int total;
  final Color accent;
  final bool winner;

  const _ScoreColumn({
    required this.label,
    required this.rounds,
    required this.total,
    required this.accent,
    required this.winner,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.3),
            border: Border.all(
              color: winner
                  ? const Color(0xFFF4B740)
                  : Colors.white.withValues(alpha: 0.18),
              width: winner ? 3 : 1.5,
            ),
          ),
          child: Text(
            '$total',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 32,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: winner ? 1 : 0.75),
                fontWeight: winner ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < rounds.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Round ${i + 1}   ${rounds[i]}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontWeight: FontWeight.w600,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }
}

// Confetti (compact port of the shared GP burst).
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
            Rect.fromCenter(center: Offset.zero, width: dim, height: dim * 0.55),
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
