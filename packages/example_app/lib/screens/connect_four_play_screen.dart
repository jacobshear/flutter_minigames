import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigame_connect_four/minigame_connect_four.dart';
import 'package:minigames_core/minigames_core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Local hot-seat Connect Four via [PlaySession].
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
    holeColor: const Color(0xFFFFF6E8),
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
    await _controller?.dispose();
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
        bloom: DemoColors.teal,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                const SizedBox(height: 6),
                GameTopBar(onBack: () => Navigator.of(context).maybePop()),
                const SizedBox(height: 12),
                GameScreenHeader(
                  title: 'Connect four',
                  subtitle: _session.hotSeat
                      ? 'Hot seat · tap a column'
                      : 'Networked match',
                  accent: DemoColors.teal,
                ),
                const Spacer(),
                if (controller == null)
                  const CircularProgressIndicator()
                else
                  GamePanel(
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 20),
                    child: ConnectFourBoard(
                      key: ValueKey(_round),
                      controller: controller,
                      style: _boardStyle,
                    ),
                  ),
                const Spacer(),
                GameButton(
                  label: 'New game',
                  icon: Icons.refresh_rounded,
                  color: DemoColors.teal,
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
