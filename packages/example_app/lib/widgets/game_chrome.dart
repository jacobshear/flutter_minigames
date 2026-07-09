import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/demo_theme.dart';

/// Neutral light surface for launcher + play shells.
/// Intentionally static — ambient motion belongs inside games, not chrome.
/// Safe for embedding as a chat sheet later (no full-bleed brand spectacle).
class GameBackdrop extends StatelessWidget {
  final Widget child;
  final Color bloom;

  const GameBackdrop({
    super.key,
    required this.child,
    this.bloom = DemoColors.blue,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DemoColors.surface,
      child: child,
    );
  }
}

/// Soft white panel around a board (optional; prefer full-bleed boards).
class GamePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  final Color? accentBorder;

  const GamePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.radius = 20,
    this.accentBorder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? DemoColors.card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: gameShadow(),
      ),
      child: child,
    );
  }
}

/// Compact primary action (New game).
class GameButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color foreground;
  final IconData? icon;

  const GameButton({
    super.key,
    required this.label,
    required this.onTap,
    this.color = DemoColors.blue,
    this.foreground = Colors.white,
    this.icon,
  });

  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: widget.foreground, size: 18),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: gameDisplay(
                  size: 16,
                  weight: FontWeight.w700,
                  color: widget.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small system-style capsule.
class GameBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color? foreground;

  const GameBadge({
    super.key,
    required this.label,
    this.color = DemoColors.card,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? DemoColors.secondaryLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: gameBody(size: 12, weight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class GameBackButton extends StatefulWidget {
  final VoidCallback onBack;

  const GameBackButton({super.key, required this.onBack});

  @override
  State<GameBackButton> createState() => _GameBackButtonState();
}

class _GameBackButtonState extends State<GameBackButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onBack();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1,
        duration: const Duration(milliseconds: 90),
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: DemoColors.card,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.chevron_left_rounded,
            color: DemoColors.ink,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class GameScreenHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;

  const GameScreenHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.accent = DemoColors.blue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: gameDisplay(size: 20, weight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: gameBody(size: 13, weight: FontWeight.w600),
        ),
      ],
    );
  }
}

class GameTopBar extends StatelessWidget {
  final VoidCallback onBack;
  final String badge;

  const GameTopBar({
    super.key,
    required this.onBack,
    this.badge = 'Local',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GameBackButton(onBack: onBack),
        const Spacer(),
        GameBadge(label: badge),
      ],
    );
  }
}
