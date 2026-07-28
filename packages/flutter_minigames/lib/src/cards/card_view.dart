import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'card_art.dart';
import 'playing_card.dart';

/// One card as a widget, sized by [width] at the standard 1 : 1.4 ratio.
///
/// Deliberately dumb: no gestures, no animation, no game knowledge. Wrap it in
/// whatever a game needs (`GestureDetector`, `Transform.rotate`, a `Positioned`
/// in a fan) and let the game own the motion.
class CardView extends StatelessWidget {
  /// The card to show. May be null when [faceUp] is false.
  final PlayingCard? card;

  final bool faceUp;

  /// Card width in logical pixels; height is `width * kCardAspectRatio`.
  final double width;

  final PlayingCardStyle style;

  /// Contact shadow under the card. Off for cards inside a tight stack, where
  /// one shadow under the pile beats one per card.
  final bool shadow;

  /// Ring drawn just inside the card edge — the standard "this is selectable /
  /// selected" affordance. Null draws nothing.
  final Color? highlight;

  /// 0 = normal, 1 = fully washed out. Use for cards that exist but cannot be
  /// acted on.
  final double dim;

  const CardView({
    super.key,
    required this.card,
    required this.width,
    this.faceUp = true,
    this.style = kDefaultCardStyle,
    this.shadow = true,
    this.highlight,
    this.dim = 0,
  }) : assert(card != null || !faceUp, 'a face-up card needs a card value');

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * kCardAspectRatio,
      child: CustomPaint(
        painter: _CardViewPainter(
          card: card,
          faceUp: faceUp,
          style: style,
          shadow: shadow,
          highlight: highlight,
          dim: dim,
        ),
      ),
    );
  }
}

class _CardViewPainter extends CustomPainter {
  final PlayingCard? card;
  final bool faceUp;
  final PlayingCardStyle style;
  final bool shadow;
  final Color? highlight;
  final double dim;

  const _CardViewPainter({
    required this.card,
    required this.faceUp,
    required this.style,
    required this.shadow,
    required this.highlight,
    required this.dim,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(style.cornerRadius(size.width));
    final rrect = RRect.fromRectAndRadius(rect, radius);

    if (shadow) {
      // Two passes under a key from the upper left: a wide ambient blur, then
      // a tight core, so the card sits on the table instead of floating.
      canvas.drawRRect(
        rrect.shift(Offset(size.width * 0.045, size.width * 0.065)),
        Paint()
          ..color = const Color(0x3D000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.085),
      );
      canvas.drawRRect(
        rrect.shift(Offset(size.width * 0.014, size.width * 0.020)),
        Paint()
          ..color = const Color(0x40000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.020),
      );
    }

    if (faceUp) {
      paintPlayingCard(canvas, rect, card!, style: style);
    } else {
      paintCardBack(canvas, rect, style: style);
    }

    if (dim > 0) {
      canvas.drawRRect(
        rrect,
        Paint()..color = const Color(0xFF20242C).withValues(alpha: 0.42 * dim),
      );
    }

    final ring = highlight;
    if (ring != null) {
      canvas.drawRRect(
        rrect.deflate(math.max(1.0, size.width * 0.022)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.6, size.width * 0.042)
          ..color = ring,
      );
    }
  }

  @override
  bool shouldRepaint(_CardViewPainter old) =>
      old.card != card ||
      old.faceUp != faceUp ||
      old.style != style ||
      old.shadow != shadow ||
      old.highlight != highlight ||
      old.dim != dim;
}
