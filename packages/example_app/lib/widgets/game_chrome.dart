import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/demo_theme.dart';

/// Living backdrop: slow gradient drift + floating soft blooms.
class GameBackdrop extends StatefulWidget {
  final Widget child;
  final Color bloom;

  const GameBackdrop({
    super.key,
    required this.child,
    this.bloom = DemoColors.coral,
  });

  @override
  State<GameBackdrop> createState() => _GameBackdropState();
}

class _GameBackdropState extends State<GameBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
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
      builder: (context, child) {
        final t = _c.value;
        // Slow sine — background only, deliberately subtle.
        final wave = math.sin(t * math.pi * 2);
        final wave2 = math.cos(t * math.pi * 2);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-0.85 + wave * 0.08, -1),
              end: Alignment(0.85 + wave2 * 0.06, 1),
              colors: [
                DemoColors.paperTop,
                Color.lerp(
                  const Color(0xFFFFF0D8),
                  widget.bloom.withValues(alpha: 0.10),
                  0.32 + wave * 0.05,
                )!,
                DemoColors.paperBottom,
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -90 + wave * 6,
                right: -50 + wave2 * 8,
                child: _LivingBlob(
                  color: widget.bloom.withValues(alpha: 0.14),
                  size: 260,
                  pulse: 0.96 + 0.04 * ((wave + 1) / 2),
                ),
              ),
              Positioned(
                bottom: 20 - wave * 7,
                left: -80 + wave * 5,
                child: _LivingBlob(
                  color: DemoColors.teal.withValues(alpha: 0.10),
                  size: 240,
                  pulse: 0.97 + 0.03 * ((wave2 + 1) / 2),
                ),
              ),
              Positioned(
                top: 200 + wave2 * 8,
                left: 30 + wave * 10,
                child: _LivingBlob(
                  color: DemoColors.gold.withValues(alpha: 0.09),
                  size: 140,
                  pulse: 0.95 + 0.05 * ((wave + 1) / 2),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _LivingBlob extends StatelessWidget {
  final Color color;
  final double size;
  final double pulse;

  const _LivingBlob({
    required this.color,
    required this.size,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Transform.scale(
        scale: pulse,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color,
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft card with gentle depth — no harsh ink stamp border.
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
    final borderColor = accentBorder ?? DemoColors.border;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? DemoColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: gameShadow(
          dy: 14,
          blur: 28,
          alpha: 0.09,
          accent: accentBorder,
          accentAlpha: accentBorder != null ? 0.08 : 0,
        ),
      ),
      child: child,
    );
  }
}

/// Soft pressable CTA (static chrome; press feedback only).
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
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 15),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(widget.color, Colors.white, 0.12)!,
                widget.color,
                Color.lerp(widget.color, Colors.black, 0.06)!,
              ],
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.28),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
                spreadRadius: -2,
              ),
              BoxShadow(
                color: DemoColors.ink.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
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
                  size: 17,
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

/// Soft pill badge (static — motion is reserved for the backdrop).
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
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        label.toUpperCase(),
        style: gameDisplay(
          size: 11,
          weight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

/// Soft circular back control.
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
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: DemoColors.card.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            border: Border.all(color: DemoColors.border, width: 1.4),
            boxShadow: gameShadow(dy: 6, blur: 14, alpha: 0.08),
          ),
          child: const Icon(Icons.arrow_back_rounded, color: DemoColors.ink),
        ),
      ),
    );
  }
}

/// Title + soft subtitle chip.
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
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: accent.withValues(alpha: 0.28),
              width: 1.2,
            ),
          ),
          child: Text(
            subtitle,
            style: gameBody(
              size: 13,
              weight: FontWeight.w700,
              color: DemoColors.ink.withValues(alpha: 0.62),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared top row: back + badge.
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
