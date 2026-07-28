import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../catalog/game_catalog.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_tile_art.dart';

/// Full-screen GamePigeon-style launcher: static grid of illustrated tiles.
///
/// This is a faithful *standalone* interpretation of the GP game picker so you
/// can feel the product alone. The same [gameCatalog] is what a host app
/// embeds — white surface, dense tiles, no ambient chrome.
class HomeMenuScreen extends StatelessWidget {
  const HomeMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final games = gameCatalog;

    return Scaffold(
      backgroundColor: DemoColors.surface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Row(
                  children: [
                    Text(
                      'Games',
                      style: gameDisplay(size: 28, weight: FontWeight.w800),
                    ),
                    const Spacer(),
                    Text(
                      'Local',
                      style: gameBody(
                        size: 13,
                        weight: FontWeight.w700,
                        color: DemoColors.secondaryLabel,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              sliver: _GameGrid(games: games),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameGrid extends StatelessWidget {
  final List<GameCatalogEntry> games;
  const _GameGrid({required this.games});

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        // Tile + caption. Narrower tiles at 4-up need a touch more height so
        // two-line captions don't clip.
        childAspectRatio: 0.72,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) => _LauncherTile(
          entry: games[i],
          phase: i / games.length,
        ),
        childCount: games.length,
      ),
    );
  }
}

class _LauncherTile extends StatefulWidget {
  final GameCatalogEntry entry;
  final double phase;
  const _LauncherTile({required this.entry, this.phase = 0});

  @override
  State<_LauncherTile> createState() => _LauncherTileState();
}

class _LauncherTileState extends State<_LauncherTile> {
  bool _pressed = false;

  void _open() {
    final entry = widget.entry;
    if (!entry.available || entry.builder == null) return;
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: entry.builder!,
        // Full-screen for the standalone demo. A chat host would use a sheet
        // route / embedded navigator instead — same builder.
        fullscreenDialog: false,
      ),
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
        scale: _pressed ? 0.94 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: Column(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Opacity(
                      opacity: enabled ? 1 : 0.45,
                      child: entry.artBuilder != null
                          ? entry.artBuilder!(context, widget.phase)
                          : GameTileArt(
                              kind: entry.art!,
                              phase: widget.phase,
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: gameBody(
                size: 12,
                weight: FontWeight.w700,
                color: DemoColors.ink,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
