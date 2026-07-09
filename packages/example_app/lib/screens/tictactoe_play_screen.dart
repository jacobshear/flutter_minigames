import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigame_tictactoe/minigame_tictactoe.dart';
import 'package:minigames_core/minigames_core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Local hot-seat tic-tac-toe via [PlaySession].
class TicTacToePlayScreen extends StatefulWidget {
  final PlaySession? session;

  const TicTacToePlayScreen({super.key, this.session});

  @override
  State<TicTacToePlayScreen> createState() => _TicTacToePlayScreenState();
}

class _TicTacToePlayScreenState extends State<TicTacToePlayScreen> {
  late final PlaySession _session;
  final TicTacToeGame _game = const TicTacToeGame();
  MatchController<TicTacToeState, TicTacToeMove>? _controller;
  int _round = 0;

  late final TicTacToeStyle _boardStyle = TicTacToeStyle(
    xColor: DemoColors.coral,
    oColor: DemoColors.teal,
    gridColor: const Color(0xD11F2430),
    sounds: TicTacToeSounds(
      onPlace: DemoSfx.instance.mark,
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
        await MatchController.create<TicTacToeState, TicTacToeMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-ttt-$_round',
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
      body: GameBackdrop(
        bloom: DemoColors.coral,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              children: [
                const SizedBox(height: 6),
                GameTopBar(onBack: () => Navigator.of(context).maybePop()),
                const SizedBox(height: 14),
                GameScreenHeader(
                  title: 'Tic-tac-toe',
                  subtitle: _session.hotSeat
                      ? 'Hot seat · pass the device'
                      : 'Networked match',
                  accent: DemoColors.coral,
                ),
                const Spacer(),
                if (controller == null)
                  const CircularProgressIndicator()
                else
                  GamePanel(
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 26),
                    child: TicTacToeBoard(
                      key: ValueKey(_round),
                      controller: controller,
                      style: _boardStyle,
                    ),
                  ),
                const Spacer(),
                GameButton(
                  label: 'New game',
                  icon: Icons.refresh_rounded,
                  color: DemoColors.coral,
                  foreground: Colors.white,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    DemoSfx.instance.newGame();
                    setState(() => _round++);
                    _startNewGame();
                  },
                ),
                const SizedBox(height: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
