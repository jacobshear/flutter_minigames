import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigame_dots_and_boxes/minigame_dots_and_boxes.dart';
import 'package:minigames_core/minigames_core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Dots and Boxes with thin shell chrome.
class DotsAndBoxesPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const DotsAndBoxesPlayScreen({super.key, this.session});

  @override
  State<DotsAndBoxesPlayScreen> createState() => _DotsAndBoxesPlayScreenState();
}

class _DotsAndBoxesPlayScreenState extends State<DotsAndBoxesPlayScreen> {
  late final PlaySession _session;
  final DotsAndBoxesGame _game = const DotsAndBoxesGame(gridSize: 3);
  MatchController<DotsAndBoxesState, DotsAndBoxesMove>? _controller;
  int _round = 0;

  late final DotsAndBoxesStyle _boardStyle = DotsAndBoxesStyle(
    player0Color: DemoColors.coral,
    player1Color: DemoColors.teal,
    boardColor: DemoColors.card,
    freeEdgeColor: DemoColors.ink.withValues(alpha: 0.12),
    dotColor: DemoColors.ink,
    sounds: DotsAndBoxesSounds(
      onClaim: DemoSfx.instance.mark,
      onBox: (_) => DemoSfx.instance.drop(),
      onExtraTurn: DemoSfx.instance.newGame,
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
    await _controller?.dispose();
    final controller =
        await MatchController.create<DotsAndBoxesState, DotsAndBoxesMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-dab-$_round',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: _session.hotSeat,
      seed: _round,
    );
    if (mounted) setState(() => _controller = controller);
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
                title: 'Dots & Boxes',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const Spacer(),
              if (controller == null)
                const CircularProgressIndicator()
              else
                GamePanel(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
                  child: DotsAndBoxesBoard(
                    key: ValueKey(_round),
                    controller: controller,
                    style: _boardStyle,
                  ),
                ),
              const Spacer(),
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
