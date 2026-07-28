import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'archery_style.dart';

/// Launcher-tile miniature for Archery: a sunny range slab with a ringed face
/// and an arrow looping in from the lower left to bury itself in the gold.
class ArcheryTileArt extends StatefulWidget {
  /// Loop phase offset (the launcher staggers tiles by phase).
  final double phase;

  const ArcheryTileArt({super.key, this.phase = 0});

  @override
  State<ArcheryTileArt> createState() => _ArcheryTileArtState();
}

class _ArcheryTileArtState extends State<ArcheryTileArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        painter: _ArcheryTilePainter(t: (_c.value + widget.phase) % 1.0),
      ),
    );
  }
}

class _ArcheryTilePainter extends CustomPainter {
  final double t;

  _ArcheryTilePainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.22),
    );
    canvas.save();
    canvas.clipRRect(outer);

    // Sky.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A83CE), Color(0xFFBFE0F2)],
        ).createShader(Offset.zero & size),
    );

    // Grass, with a lane converging toward the target.
    final horizon = size.height * 0.56;
    final ground = Rect.fromLTRB(0, horizon, size.width, size.height);
    canvas.drawRect(
      ground,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8FBE72), Color(0xFF4E8B3A)],
        ).createShader(ground),
    );
    final lane = Path()
      ..moveTo(size.width * 0.36, horizon)
      ..lineTo(size.width * 0.64, horizon)
      ..lineTo(size.width * 1.02, size.height)
      ..lineTo(size.width * -0.02, size.height)
      ..close();
    canvas.drawPath(
      lane,
      Paint()..color = Colors.white.withValues(alpha: 0.16),
    );

    // Target face, five rings, gold in the middle.
    final centre = Offset(size.width * 0.5, size.height * 0.45);
    final r = size.width * 0.30;
    // Flattened ground shadow — a full circle here reads as a hole in the turf.
    canvas.drawOval(
      Rect.fromCenter(
        center: centre.translate(0, r * 1.25),
        width: r * 1.5,
        height: r * 0.42,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.13),
    );
    for (var i = ArcheryStyle.ringColors.length - 1; i >= 0; i--) {
      canvas.drawCircle(
        centre,
        r * (i + 1) / 5,
        Paint()..color = ArcheryStyle.ringColors[i],
      );
      canvas.drawCircle(
        centre,
        r * (i + 1) / 5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.6, size.width * 0.006)
          ..color = ArcheryStyle.ringLine,
      );
    }

    // The arrow: flies in on the loop, then rests in the gold before resetting.
    final fly = Curves.easeInQuad.transform((t / 0.55).clamp(0.0, 1.0));
    final from = Offset(-size.width * 0.15, size.height * 1.05);
    final head = Offset.lerp(from, centre, fly)!;
    final dir = (centre - from);
    final unit = dir / dir.distance;
    final shaft = size.width * (0.34 - 0.16 * fly);
    final tail = head - unit * shaft;

    canvas.drawLine(
      tail,
      head,
      Paint()
        ..strokeWidth = math.max(1.4, size.width * 0.028)
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFF1E6D2),
    );
    final normal = Offset(-unit.dy, unit.dx);
    final vane = size.width * 0.075;
    for (final s in [-1.0, 1.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(tail.dx, tail.dy)
          ..lineTo(
              tail.dx + normal.dx * vane * s, tail.dy + normal.dy * vane * s)
          ..lineTo(
              tail.dx + unit.dx * vane * 1.8, tail.dy + unit.dy * vane * 1.8)
          ..close(),
        Paint()..color = const Color(0xFFD8443C),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArcheryTilePainter old) => old.t != t;
}
