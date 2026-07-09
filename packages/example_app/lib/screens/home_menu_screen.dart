import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../catalog/game_catalog.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Root of the demo: pick a mini-game, play it locally (hot seat).
/// Tiles are static; ambient motion lives only in [GameBackdrop].
class HomeMenuScreen extends StatelessWidget {
  const HomeMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final games = gameCatalog;

    return Scaffold(
      body: GameBackdrop(
        bloom: DemoColors.coral,
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
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
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
                sliver: SliverList.separated(
                  itemCount: games.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, i) => _GameCard(entry: games[i]),
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

class _GameCardState extends State<_GameCard> {
  bool _pressed = false;

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

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: enabled ? _open : null,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          decoration: BoxDecoration(
            color: DemoColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: DemoColors.border, width: 1.4),
            boxShadow: gameShadow(dy: 10, blur: 20, alpha: 0.08),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(accent, Colors.white, 0.2)!,
                      accent,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(entry.icon, color: Colors.white, size: 28),
              ),
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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: enabled
                      ? accent.withValues(alpha: 0.14)
                      : DemoColors.ink.withValues(alpha: 0.06),
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
                  color: enabled
                      ? accent
                      : DemoColors.ink.withValues(alpha: 0.35),
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
