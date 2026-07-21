import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigame_gomoku/minigame_gomoku.dart';
import 'package:minigames_core/minigames_core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Gomoku with thin shell chrome.
class GomokuPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const GomokuPlayScreen({super.key, this.session});

  @override
  State<GomokuPlayScreen> createState() => _GomokuPlayScreenState();
}

class _GomokuPlayScreenState extends State<GomokuPlayScreen> {
  late final PlaySession _session;
  final GomokuGame _game = const GomokuGame();
  MatchController<GomokuState, GomokuMove>? _controller;
  int _round = 0;

  late final GomokuStyle _boardStyle = GomokuStyle(
    sounds: GomokuSounds(
      onPlace: DemoSfx.instance.drop,
      onInvalid: DemoSfx.instance.invalid,
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
    final controller = await MatchController.create<GomokuState, GomokuMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-gmk-$_round',
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
                title: 'Gomoku',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: controller == null
                      ? const CircularProgressIndicator()
                      // Board paints its own felt table — no white panel.
                      : SingleChildScrollView(
                          child: GomokuBoard(
                            key: ValueKey(_round),
                            controller: controller,
                            style: _boardStyle,
                          ),
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
