import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigame_checkers/minigame_checkers.dart';
import 'package:minigames_core/minigames_core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Checkers with thin shell chrome.
class CheckersPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const CheckersPlayScreen({super.key, this.session});

  @override
  State<CheckersPlayScreen> createState() => _CheckersPlayScreenState();
}

class _CheckersPlayScreenState extends State<CheckersPlayScreen> {
  late final PlaySession _session;
  final CheckersGame _game = const CheckersGame();
  MatchController<CheckersState, CheckersMove>? _controller;
  int _round = 0;

  late final CheckersStyle _boardStyle = CheckersStyle(
    darkPieceColor: DemoColors.ink,
    lightPieceColor: DemoColors.coral,
    darkSquareColor: const Color(0xFF5D4037),
    lightSquareColor: const Color(0xFFD7CCC8),
    sounds: CheckersSounds(
      onSelect: DemoSfx.instance.mark,
      onMove: DemoSfx.instance.drop,
      onCapture: () => DemoSfx.instance.drop(longDrop: true),
      onKing: DemoSfx.instance.mark,
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
        await MatchController.create<CheckersState, CheckersMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-chk-$_round',
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
                title: 'Checkers',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const Spacer(),
              if (controller == null)
                const CircularProgressIndicator()
              else
                GamePanel(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: CheckersBoard(
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
