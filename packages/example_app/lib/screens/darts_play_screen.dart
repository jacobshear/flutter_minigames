import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/games/darts.dart';
import 'package:flutter_minigames/core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat 501 darts with thin shell chrome. Mirrors the shuffleboard screen:
/// PlaySession + MatchController, create-and-swap-before-dispose on New game.
class DartsPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const DartsPlayScreen({super.key, this.session});

  @override
  State<DartsPlayScreen> createState() => _DartsPlayScreenState();
}

class _DartsPlayScreenState extends State<DartsPlayScreen> {
  late final PlaySession _session;
  final DartsGame _game = const DartsGame();
  MatchController<DartsState, DartsMove>? _controller;
  int _round = 0;

  // Sounds come from real sim + rules events inside the board, never timers.
  late final DartsStyle _boardStyle = DartsStyle(
    sounds: DartsSounds(
      onThrow: DemoSfx.instance.mark,
      onStick: DemoSfx.instance.drop,
      onBigScore: () => DemoSfx.instance.drop(longDrop: true),
      onMiss: DemoSfx.instance.invalid,
      onBust: DemoSfx.instance.invalid,
      onWin: DemoSfx.instance.win,
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
    final controller = await MatchController.create<DartsState, DartsMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-darts-$_round',
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
                title: 'Darts',
                subtitle: _session.hotSeat ? '501 · pass and play' : '501',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: controller == null
                    ? const Center(child: CircularProgressIndicator())
                    // The scene sizes itself to whatever height it is given.
                    : DartsBoardWidget(
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
