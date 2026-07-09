import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../catalog/game_catalog.dart';
import '../theme/demo_theme.dart';

/// Root of the demo: pick a mini-game, play it locally (hot seat).
/// Multiplayer is intentionally not on this menu yet — the transport seam
/// under `lib/multiplayer/` is ready when a host wires a real backend.
class HomeMenuScreen extends StatelessWidget {
  const HomeMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final games = gameCatalog;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [DemoColors.paperTop, DemoColors.paperBottom],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'flutter_minigames',
                        style: GoogleFonts.fraunces(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DemoColors.ink.withValues(alpha: 0.5),
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Play locally',
                        style: GoogleFonts.fraunces(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: DemoColors.ink,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Hot-seat demos of every game. Same MatchController '
                        'and GameTransport a networked host will use later.',
                        style: GoogleFonts.fraunces(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: DemoColors.ink.withValues(alpha: 0.55),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
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

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: enabled ? _open : null,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 110),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1 : 0.72,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: BoxDecoration(
              color: DemoColors.card,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: DemoColors.ink.withValues(alpha: 0.08),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: entry.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(entry.icon, color: entry.accent, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: GoogleFonts.fraunces(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: DemoColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.tagline,
                        style: GoogleFonts.fraunces(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: DemoColors.ink.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        enabled ? entry.players : 'Coming soon',
                        style: GoogleFonts.fraunces(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: enabled
                              ? entry.accent
                              : DemoColors.ink.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  enabled ? Icons.chevron_right_rounded : Icons.schedule_rounded,
                  color: DemoColors.ink.withValues(alpha: 0.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
