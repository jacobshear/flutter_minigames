import 'package:flutter/material.dart';
import 'package:flutter_minigames/src/engine3d/engine3d.dart';

import 'basketball_court.dart';
import 'basketball_style.dart';
import 'basketball_view.dart';

/// Launcher-tile miniature for Basketball: the same first-person court the game
/// renders, seen from a tighter camera, with a ball looping up into the hoop.
///
/// It reuses [paintBasketballCourt] rather than re-drawing a flat approximation
/// — the tile is a real frame of the real game, so the two can never drift
/// apart, and the ball genuinely sorts between the near and far halves of the
/// rim as it drops through.
class BasketballTileArt extends StatefulWidget {
  /// Loop phase offset (the launcher staggers tiles by phase).
  final double phase;

  const BasketballTileArt({super.key, this.phase = 0});

  @override
  State<BasketballTileArt> createState() => _BasketballTileArtState();
}

class _BasketballTileArtState extends State<BasketballTileArt>
    with SingleTickerProviderStateMixin {
  // Built in initState, never a `late` inline initializer (dispose safety).
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        painter: _BasketballTilePainter(
          t: (_c.value + widget.phase) % 1.0,
          scheme: scheme,
        ),
      ),
    );
  }
}

class _BasketballTilePainter extends CustomPainter {
  final double t;
  final ColorScheme scheme;

  static const _style = BasketballStyle();

  /// Fraction of the loop the ball spends in flight; the rest it waits.
  static const double _flightFraction = 0.76;

  _BasketballTilePainter({required this.t, required this.scheme});

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.22),
    );
    canvas.save();
    canvas.clipRRect(outer);

    final u = t < _flightFraction ? t / _flightFraction : 0.0;
    // Quadratic through the release point, peaking above the ring, landing on
    // the rim plane.
    final y = 1.5 + 5.0 * u - 3.45 * u * u;
    final z = BasketballCourt.hoopZ - 2.6 * (1 - u);
    final x = -0.34 * (1 - u);

    paintBasketballCourt(
      canvas,
      size,
      BasketballView(
        hoopCentre: const Vec3(0, BasketballCourt.rimHeight, BasketballCourt.hoopZ),
        balls: [BasketballBallView(position: Vec3(x, y, z), spin: u * 7.5)],
        netWobble: u > 0.97 ? 1 : 0,
        // A tighter, closer camera so the rig fills a small tile.
        cameraEye: const Vec3(0, 2.30, BasketballCourt.hoopZ - 4.4),
        pitch: 0.05,
        fov: 1.0,
      ),
      _style,
      scheme,
    );

    // Slab vignette, matching the other launcher tiles.
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 1.1,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.28),
          ],
          stops: const [0.55, 1.0],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BasketballTilePainter old) => old.t != t;
}
