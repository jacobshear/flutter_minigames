import 'package:flutter/material.dart';

/// A small static label over a board: a phase name, a seat, a running total.
///
/// The quiet sibling of [GameNotice] — this one does not move, does not
/// auto-dismiss, and carries no tone. Use it for chrome that is simply
/// present; use a notice for something that just happened.
class GamePill extends StatelessWidget {
  final String text;

  /// Heavier fill and type. For the one pill on screen that matters most.
  final bool strong;

  /// Hairline and glyph accent — usually the seat colour.
  final Color? accent;

  /// Optional leading dot, sized to the text. Reads as a seat swatch.
  final bool dot;

  const GamePill({
    super.key,
    required this.text,
    this.strong = false,
    this.accent,
    this.dot = false,
  });

  @override
  Widget build(BuildContext context) {
    final a = accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: strong ? 0.52 : 0.32),
        borderRadius: BorderRadius.circular(10),
        border: a == null
            ? Border.all(color: Colors.white.withValues(alpha: 0.10))
            : Border.all(color: a.withValues(alpha: 0.75), width: 1.1),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: strong ? 13 : 10,
          vertical: strong ? 7 : 5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot && a != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: a, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: strong ? 1 : 0.80),
                  fontSize: strong ? 13.5 : 12,
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
