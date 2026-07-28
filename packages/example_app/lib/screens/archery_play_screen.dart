import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/games/archery.dart';
import 'package:flutter_minigames/core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Archery with thin shell chrome. Mirrors the mini-golf screen:
/// PlaySession + MatchController, create-and-swap-before-dispose on New game.
///
/// The round number is the match seed, so "New game" is a genuinely new set of
/// four ranges and winds — and replaying the same round reproduces them exactly.
class ArcheryPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const ArcheryPlayScreen({super.key, this.session});

  @override
  State<ArcheryPlayScreen> createState() => _ArcheryPlayScreenState();
}

class _ArcheryPlayScreenState extends State<ArcheryPlayScreen> {
  late final PlaySession _session;

  static const _game = ArcheryGame();
  MatchController<ArcheryState, ArcheryMove>? _controller;
  int _round = 0;

  late final ArcheryStyle _style = ArcheryStyle(
    sounds: ArcherySounds(
      onBowDraw: DemoSfx.instance.mark,
      onFocusWarn: DemoSfx.instance.invalid,
      onLoose: DemoSfx.instance.drop,
      onHit: () => DemoSfx.instance.drop(longDrop: true),
      onBullseye: DemoSfx.instance.newGame,
      onMiss: DemoSfx.instance.invalid,
      onNextTarget: DemoSfx.instance.mark,
      onWin: DemoSfx.instance.win,
      onTie: DemoSfx.instance.draw,
    ),
  );

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? PlaySession.localHotSeat();
    _startNewGame();
  }

  Future<void> _startNewGame() async {
    // Create + swap first, dispose after: the range unsubscribes from the old
    // controller when it rebinds, which lets the old stream close cleanly.
    final old = _controller;
    final controller = await MatchController.create<ArcheryState, ArcheryMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-archery-$_round',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: _session.hotSeat,
      seed: 1000 + _round,
    );
    if (mounted) setState(() => _controller = controller);
    await old?.dispose();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    const shell = Color(0xFF1B1E24);
    return Scaffold(
      backgroundColor: DemoColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            children: [
              const SizedBox(height: 4),
              GameTopBar(onBack: () => Navigator.of(context).maybePop()),
              const SizedBox(height: 8),
              GameScreenHeader(
                title: 'Archery',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: const RadialGradient(
                      center: Alignment(0, -0.4),
                      radius: 1.5,
                      colors: [Color(0xFF262B33), shell, Color(0xFF0E1014)],
                      stops: [0.0, 0.5, 1.0],
                    ),
                  ),
                  child: controller == null
                      ? const Center(child: CircularProgressIndicator())
                      : ArcheryRange(
                          key: ValueKey(_round),
                          controller: controller,
                          style: _style,
                        ),
                ),
              ),
              const SizedBox(height: 8),
              GameButton(
                label: 'New game',
                color: DemoColors.blue,
                onTap: () {
                  HapticFeedback.selectionClick();
                  DemoSfx.instance.newGame();
                  setState(() => _round++);
                  _startNewGame();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
