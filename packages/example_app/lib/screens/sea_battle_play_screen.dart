import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/games/sea_battle.dart';
import 'package:flutter_minigames/core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Sea Battle with thin shell chrome.
class SeaBattlePlayScreen extends StatefulWidget {
  final PlaySession? session;

  const SeaBattlePlayScreen({super.key, this.session});

  @override
  State<SeaBattlePlayScreen> createState() => _SeaBattlePlayScreenState();
}

class _SeaBattlePlayScreenState extends State<SeaBattlePlayScreen> {
  late final PlaySession _session;
  final SeaBattleGame _game = const SeaBattleGame();
  MatchController<SeaBattleState, SeaBattleMove>? _controller;
  int _round = 0;

  late final SeaBattleStyle _boardStyle = SeaBattleStyle(
    sounds: SeaBattleSounds(
      onMiss: DemoSfx.instance.mark,
      onHit: DemoSfx.instance.drop,
      onSunk: () => DemoSfx.instance.drop(longDrop: true),
      onInvalid: DemoSfx.instance.invalid,
      onPlace: DemoSfx.instance.mark,
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
    final controller = await MatchController.create<SeaBattleState,
        SeaBattleMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-sb-$_round',
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
                title: 'Sea Battle',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: controller == null
                      ? const CircularProgressIndicator()
                      // Board paints its own felt table — no white panel.
                      : SingleChildScrollView(
                          child: SeaBattleBoard(
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
