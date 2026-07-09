import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/demo_theme.dart';

/// Full-screen party backdrop: warm gradient + soft accent bloom.
class GameBackdrop extends StatelessWidget {
  final Widget child;
  final Color bloom;

  const GameBackdrop({
    super.key,
    required this.child,
    this.bloom = DemoColors.coral,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            DemoColors.paperTop,
            Color(0xFFFFEFD4),
            DemoColors.paperBottom,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _Blob(color: bloom.withValues(alpha: 0.18), size: 240),
          ),
          Positioned(
            bottom: 40,
            left: -70,
            child: _Blob(
              color: DemoColors.teal.withValues(alpha: 0.12),
              size: 220,
            ),
          ),
          Positioned(
            top: 180,
            left: 40,
            child: _Blob(
              color: DemoColors.gold.withValues(alpha: 0.10),
              size: 120,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

/// Chunky card: thick ink border + hard drop shadow.
class GamePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  final Color? accentBorder;

  const GamePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.radius = 28,
    this.accentBorder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? DemoColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: accentBorder ?? DemoColors.border,
          width: 3,
        ),
        boxShadow: gameShadow(dy: 6, alpha: 0.16),
      ),
      child: child,
    );
  }
}

/// Pressable primary CTA — hard shadow that “sinks” when pressed.
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
    this.color = DemoColors.ink,
    this.foreground = DemoColors.card,
    this.icon,
  });

  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final dy = _pressed ? 2.0 : 6.0;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.translationValues(0, _pressed ? 4 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: DemoColors.border, width: 3),
          boxShadow: gameShadow(dy: dy, alpha: 0.22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, color: widget.foreground, size: 20),
              const SizedBox(width: 8),
            ],
            Text(
              widget.label,
              style: gameDisplay(
                size: 18,
                weight: FontWeight.w700,
                color: widget.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pill badge (LOCAL, 2P, etc.).
class GameBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color? foreground;

  const GameBadge({
    super.key,
    required this.label,
    this.color = DemoColors.gold,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? DemoColors.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: DemoColors.border, width: 2.5),
        boxShadow: gameShadow(dy: 3, alpha: 0.14),
      ),
      child: Text(
        label.toUpperCase(),
        style: gameDisplay(
          size: 11,
          weight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Circular back control with the same hard chrome.
class GameBackButton extends StatelessWidget {
  final VoidCallback onBack;

  const GameBackButton({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onBack();
      },
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: DemoColors.card,
          shape: BoxShape.circle,
          border: Border.all(color: DemoColors.border, width: 3),
          boxShadow: gameShadow(dy: 4, alpha: 0.14),
        ),
        child: const Icon(Icons.arrow_back_rounded, color: DemoColors.ink),
      ),
    );
  }
}

/// Title + subtitle block used on every play screen.
class GameScreenHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;

  const GameScreenHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.accent = DemoColors.coral,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: gameDisplay(size: 32, weight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: accent.withValues(alpha: 0.55),
              width: 2,
            ),
          ),
          child: Text(
            subtitle,
            style: gameBody(
              size: 13,
              weight: FontWeight.w800,
              color: DemoColors.ink.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared top row: back + optional trailing badge.
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
        GameBadge(label: badge, color: DemoColors.gold),
      ],
    );
  }
}
