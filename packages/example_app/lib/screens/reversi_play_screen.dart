import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/games/reversi.dart';
import 'package:flutter_minigames/core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Reversi with thin shell chrome.
class ReversiPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const ReversiPlayScreen({super.key, this.session});

  @override
  State<ReversiPlayScreen> createState() => _ReversiPlayScreenState();
}

class _ReversiPlayScreenState extends State<ReversiPlayScreen> {
  late final PlaySession _session;
  final ReversiGame _game = const ReversiGame();
  MatchController<ReversiState, ReversiMove>? _controller;
  int _round = 0;

  late final ReversiStyle _boardStyle = ReversiStyle(
    darkColor: DemoColors.ink,
    lightColor: const Color(0xFFF5F5F7),
    boardColor: const Color(0xFF2D8A4E),
    sounds: ReversiSounds(
      onPlace: DemoSfx.instance.mark,
      onFlip: (_) => DemoSfx.instance.drop(),
      onPass: DemoSfx.instance.invalid,
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
    final controller = await MatchController.create<ReversiState, ReversiMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-rev-$_round',
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
                title: 'Reversi',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const Spacer(),
              if (controller == null)
                const CircularProgressIndicator()
              else
                GamePanel(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: ReversiBoard(
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
