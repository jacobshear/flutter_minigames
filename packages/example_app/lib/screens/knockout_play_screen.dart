import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigame_knockout/minigame_knockout.dart';
import 'package:minigames_core/minigames_core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Knockout with thin shell chrome. Mirrors the shuffleboard screen:
/// PlaySession + MatchController, create-and-swap-before-dispose on New game.
class KnockoutPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const KnockoutPlayScreen({super.key, this.session});

  @override
  State<KnockoutPlayScreen> createState() => _KnockoutPlayScreenState();
}

class _KnockoutPlayScreenState extends State<KnockoutPlayScreen> {
  late final PlaySession _session;
  final KnockoutGame _game = const KnockoutGame();
  MatchController<KnockoutState, KnockoutMove>? _controller;
  int _round = 0;

  late final KnockoutStyle _boardStyle = KnockoutStyle(
    sounds: KnockoutSounds(
      onLaunch: DemoSfx.instance.drop,
      onCollision: DemoSfx.instance.mark,
      onKnockOff: () => DemoSfx.instance.drop(longDrop: true),
      onOwnLoss: DemoSfx.instance.invalid,
      onWin: DemoSfx.instance.win,
      onDraw: DemoSfx.instance.draw,
    ),
  );

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? PlaySession.localHotSeat();
    _startNewGame();
  }

  Future<void> _startNewGame() async {
    // Create + swap first, dispose after: the board unsubscribes from the old
    // controller when it rebinds, which lets the old stream close cleanly.
    final old = _controller;
    final controller =
        await MatchController.create<KnockoutState, KnockoutMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-knockout-$_round',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: _session.hotSeat,
      seed: _round,
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
                title: 'Knockout',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: controller == null
                    ? const Center(child: CircularProgressIndicator())
                    : KnockoutBoard(
                        key: ValueKey(_round),
                        controller: controller,
                        style: _boardStyle,
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
