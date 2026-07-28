import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/games/connect_four.dart';
import 'package:flutter_minigames/core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Connect Four with thin shell chrome.
class ConnectFourPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const ConnectFourPlayScreen({super.key, this.session});

  @override
  State<ConnectFourPlayScreen> createState() => _ConnectFourPlayScreenState();
}

class _ConnectFourPlayScreenState extends State<ConnectFourPlayScreen> {
  late final PlaySession _session;
  final ConnectFourGame _game = const ConnectFourGame();
  MatchController<ConnectFourState, ConnectFourMove>? _controller;
  int _round = 0;

  late final ConnectFourStyle _boardStyle = ConnectFourStyle(
    player0Color: DemoColors.coral,
    player1Color: DemoColors.gold,
    boardColor: const Color(0xFF2B6BCB),
    holeColor: const Color(0xFFF2F2F7),
    sounds: ConnectFourSounds(
      onDrop: (rows) => DemoSfx.instance.drop(longDrop: rows >= 4),
      onWin: DemoSfx.instance.win,
      onDraw: DemoSfx.instance.draw,
      onInvalid: DemoSfx.instance.invalid,
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
        await MatchController.create<ConnectFourState, ConnectFourMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-c4-$_round',
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
                title: '4 in a Row',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const Spacer(),
              if (controller == null)
                const CircularProgressIndicator()
              else
                GamePanel(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 16),
                  child: ConnectFourBoard(
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
