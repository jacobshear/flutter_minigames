import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigame_crazy_eights/minigame_crazy_eights.dart';
import 'package:minigames_core/minigames_core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Crazy 8s with thin shell chrome.
class CrazyEightsPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const CrazyEightsPlayScreen({super.key, this.session});

  @override
  State<CrazyEightsPlayScreen> createState() => _CrazyEightsPlayScreenState();
}

class _CrazyEightsPlayScreenState extends State<CrazyEightsPlayScreen> {
  late final PlaySession _session;
  final CrazyEightsGame _game = const CrazyEightsGame();
  MatchController<CrazyEightsState, CrazyEightsMove>? _controller;
  int _round = 0;

  late final CrazyEightsStyle _tableStyle = CrazyEightsStyle(
    sounds: CrazyEightsSounds(
      onDeal: () => DemoSfx.instance.drop(longDrop: true),
      onPlay: DemoSfx.instance.drop,
      onDraw: DemoSfx.instance.mark,
      onPass: () => DemoSfx.instance.drop(longDrop: true),
      onInvalid: DemoSfx.instance.invalid,
      onWin: DemoSfx.instance.win,
      onGameDraw: DemoSfx.instance.draw,
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
        await MatchController.create<CrazyEightsState, CrazyEightsMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-c8-$_round',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: _session.hotSeat,
      seed: DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
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
                title: 'Crazy 8s',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: controller == null
                    ? const Center(child: CircularProgressIndicator())
                    // Table paints its own felt — no white panel.
                    : CrazyEightsTable(
                        key: ValueKey(_round),
                        controller: controller,
                        style: _tableStyle,
                      ),
              ),
              const SizedBox(height: 12),
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
