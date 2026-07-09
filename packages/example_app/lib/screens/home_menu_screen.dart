import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../catalog/game_catalog.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Root of the demo: pick a mini-game, play it locally (hot seat).
class HomeMenuScreen extends StatefulWidget {
  const HomeMenuScreen({super.key});

  @override
  State<HomeMenuScreen> createState() => _HomeMenuScreenState();
}

class _HomeMenuScreenState extends State<HomeMenuScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final games = gameCatalog;

    return Scaffold(
      body: GameBackdrop(
        bloom: DemoColors.coral,
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // Header fades/slides in.
              SliverToBoxAdapter(
                child: AnimatedBuilder(
                  animation: _enter,
                  builder: (context, child) {
                    final t = Curves.easeOutCubic.transform(
                      (_enter.value / 0.45).clamp(0.0, 1.0),
                    );
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, 16 * (1 - t)),
                        child: child,
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const GameBadge(
                          label: 'Arcade demo',
                          color: DemoColors.teal,
                          foreground: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Mini games',
                          style: gameDisplay(size: 40, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Hot-seat play. Same transport a multiplayer host '
                          'will plug in later.',
                          style: gameBody(size: 15),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
                sliver: SliverList.separated(
                  itemCount: games.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, i) {
                    return AnimatedBuilder(
                      animation: _enter,
                      builder: (context, child) {
                        // Stagger each card after the header.
                        final start = 0.18 + i * 0.12;
                        final local =
                            ((_enter.value - start) / 0.4).clamp(0.0, 1.0);
                        final t = Curves.easeOutCubic.transform(local);
                        return Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, 22 * (1 - t)),
                            child: Transform.scale(
                              scale: 0.96 + 0.04 * t,
                              alignment: Alignment.topCenter,
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: _GameCard(entry: games[i]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatefulWidget {
  final GameCatalogEntry entry;
  const _GameCard({required this.entry});

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;

  // Loop 0→1 only (no reverse). Phase is applied via sin so motion is
  // continuous — never a modulo wrap that jumps.
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  /// Radians offset so cards don't bob in sync.
  late final double _phase =
      (widget.entry.id.hashCode.abs() % 628) / 100; // ~0..6.28

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  void _open() {
    final entry = widget.entry;
    if (!entry.available || entry.builder == null) return;
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: entry.builder!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final enabled = entry.available;
    final accent = entry.accent;

    return AnimatedBuilder(
      animation: _float,
      builder: (context, child) {
        // Smooth sine bob: continuous, no reverse-edge pops.
        final wave = math.sin(_float.value * math.pi * 2 + _phase);
        // wave is -1..1 → lift 0..~2.4px up (negative Y is up).
        final lift = enabled && !_pressed ? wave * 1.2 : 0.0;
        final glow = enabled ? 0.045 + 0.035 * ((wave + 1) / 2) : 0.0;

        return Transform.translate(
          offset: Offset(0, _pressed ? 1.5 : -lift),
          child: Transform.scale(
            scale: _pressed ? 0.985 : 1,
            child: GestureDetector(
              onTapDown:
                  enabled ? (_) => setState(() => _pressed = true) : null,
              onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
              onTapCancel:
                  enabled ? () => setState(() => _pressed = false) : null,
              onTap: enabled ? _open : null,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
                decoration: BoxDecoration(
                  color: DemoColors.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Color.lerp(
                      DemoColors.border,
                      accent.withValues(alpha: 0.32),
                      glow * 2.2,
                    )!,
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: DemoColors.ink.withValues(alpha: 0.07),
                      blurRadius: 20,
                      // Keep shadow stable — animating offset every frame
                      // reads as jitter. Only the tile moves.
                      offset: const Offset(0, 10),
                      spreadRadius: -2,
                    ),
                    BoxShadow(
                      color: accent.withValues(alpha: glow),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        );
      },
      child: Row(
        children: [
          _IconBadge(accent: accent, icon: entry.icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: gameDisplay(size: 20, weight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(entry.tagline, style: gameBody(size: 13)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.28),
                      width: 1.1,
                    ),
                  ),
                  child: Text(
                    enabled ? entry.players : 'Coming soon',
                    style: gameBody(
                      size: 11,
                      weight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _PlayOrb(enabled: enabled, accent: accent),
        ],
      ),
    );
  }
}

class _IconBadge extends StatefulWidget {
  final Color accent;
  final IconData icon;
  const _IconBadge({required this.accent, required this.icon});

  @override
  State<_IconBadge> createState() => _IconBadgeState();
}

class _IconBadgeState extends State<_IconBadge>
    with SingleTickerProviderStateMixin {
  // Continuous loop + sine (same pattern as cards) so glow never snaps.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
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
        final t = (math.sin(_c.value * math.pi * 2) + 1) / 2; // smooth 0..1
        return Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(widget.accent, Colors.white, 0.16 + 0.1 * t)!,
                widget.accent,
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: widget.accent.withValues(alpha: 0.26 + 0.12 * t),
                blurRadius: 12 + 5 * t,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Icon(widget.icon, color: Colors.white, size: 28),
    );
  }
}

class _PlayOrb extends StatelessWidget {
  final bool enabled;
  final Color accent;
  const _PlayOrb({required this.enabled, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: enabled ? accent.withValues(alpha: 0.14) : DemoColors.ink.withValues(alpha: 0.06),
        shape: BoxShape.circle,
        border: Border.all(
          color: enabled
              ? accent.withValues(alpha: 0.35)
              : DemoColors.ink.withValues(alpha: 0.12),
          width: 1.3,
        ),
      ),
      child: Icon(
        enabled ? Icons.play_arrow_rounded : Icons.schedule_rounded,
        color: enabled ? accent : DemoColors.ink.withValues(alpha: 0.35),
        size: 22,
      ),
    );
  }
}
