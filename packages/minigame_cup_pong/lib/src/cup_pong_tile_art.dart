import 'package:flutter/material.dart';
import 'package:minigames_3d/minigames_3d.dart';

import 'cup_pong_game.dart';
import 'cup_pong_painter.dart';
import 'cup_pong_sounds.dart';
import 'cup_pong_style.dart';
import 'cup_pong_world.dart';

/// Launcher-tile miniature for Cup Pong: the real first-person scene, shrunk.
///
/// It calls the same [paintCupPongTable] the board does, with a canned
/// [CupPongView] and a ball looping along a genuinely solved arc — so the tile
/// can never drift out of sync with how the game actually looks, and the
/// thumbnail already tells you it is a depth game.
class CupPongTileArt extends StatefulWidget {
  /// Loop phase offset (the launcher staggers tiles by phase).
  final double phase;

  const CupPongTileArt({super.key, this.phase = 0});

  @override
  State<CupPongTileArt> createState() => _CupPongTileArtState();
}

class _CupPongTileArtState extends State<CupPongTileArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  /// The looping arc, precomputed once — the tile should not run a solver.
  late final List<Vec3> _arc;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _arc = _buildArc();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static List<Vec3> _buildArc() {
    // Aim at the second-row right-hand cup so the arc crosses the rack rather
    // than dropping straight down the middle.
    final cups = CupPongGame.rackFor([for (var i = 0; i < 10; i++) i]);
    final target = CupPongWorld.mouthOf(cups[2]);
    const loft = 0.62;
    const config = ThrowConfig(gravity: 9.81, drag: 0.05, fixedDt: 1 / 240);
    final from = CupPongWorld.launchPoint;
    final analytic = LaunchSolver.velocityToHit(
      from: from,
      target: target,
      loft: loft,
      gravity: config.gravity,
    );
    if (analytic == null) return [from];
    final speed = LaunchSolver.refineForDrag(
      from: from,
      target: target,
      loft: loft,
      analyticSpeed: analytic.length,
      config: config,
    );
    final v = analytic * (speed / analytic.length);
    final p = Projectile(position: from, velocity: v, config: config);
    final out = <Vec3>[p.position];
    for (var i = 0; i < 600; i++) {
      p.step();
      out.add(p.position);
      if (p.velocity.y < 0 && p.position.y <= target.y) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        painter: _CupPongTilePainter(
          t: (_c.value + widget.phase) % 1.0,
          arc: _arc,
          scheme: Theme.of(context).colorScheme,
        ),
      ),
    );
  }
}

class _CupPongTilePainter extends CustomPainter {
  final double t;
  final List<Vec3> arc;
  final ColorScheme scheme;

  static const _style = CupPongStyle(
    confetti: false,
    haptics: false,
    sounds: CupPongSounds.silent,
  );

  _CupPongTilePainter({
    required this.t,
    required this.arc,
    required this.scheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.width * 0.22),
      ),
    );

    // Hold the ball in hand for the first fifth of the loop, then fly.
    const hold = 0.2;
    final flight = ((t - hold) / (1 - hold)).clamp(0.0, 1.0);
    final idx = (flight * (arc.length - 1)).round();
    final pos = arc[idx];

    final cups = CupPongGame.rackFor([for (var i = 0; i < 10; i++) i]);
    final view = CupPongView(
      cups: [
        for (final c in cups)
          CupView(
            id: c.id,
            mouth: CupPongWorld.mouthOf(c),
            mouthRadius: CupPongWorld.cupMouthRadius,
            baseRadius: CupPongWorld.cupBaseRadius,
            height: CupPongWorld.cupHeight,
          ),
      ],
      ball: BallView(
        position: pos,
        radius: CupPongWorld.ballRadius,
        spin: flight * 26,
        inHand: t < hold,
      ),
    );

    paintCupPongTable(canvas, size, view, _style, scheme);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CupPongTilePainter old) => old.t != t;
}
