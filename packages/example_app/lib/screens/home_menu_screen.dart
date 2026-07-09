import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../catalog/game_catalog.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Root of the demo: pick a mini-game, play it locally (hot seat).
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
                      GameBadge(
                        label: 'Arcade demo',
                        color: DemoColors.teal,
                        foreground: Colors.white,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Mini games',
                        style: gameDisplay(size: 42, weight: FontWeight.w700),
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
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.translationValues(0, _pressed ? 4 : 0, 0),
        padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
        decoration: BoxDecoration(
          color: DemoColors.card,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: DemoColors.border, width: 3),
          boxShadow: gameShadow(dy: _pressed ? 2 : 6, alpha: 0.16),
        ),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: DemoColors.border, width: 3),
                boxShadow: gameShadow(dy: 3, alpha: 0.14, color: accent),
              ),
              child: Icon(entry.icon, color: Colors.white, size: 30),
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
                  Text(
                    entry.tagline,
                    style: gameBody(size: 13),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.5),
                        width: 1.8,
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
                color: enabled ? DemoColors.ink : DemoColors.ink.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: DemoColors.border, width: 2.5),
              ),
              child: Icon(
                enabled ? Icons.play_arrow_rounded : Icons.schedule_rounded,
                color: enabled ? DemoColors.card : DemoColors.ink.withValues(alpha: 0.4),
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
