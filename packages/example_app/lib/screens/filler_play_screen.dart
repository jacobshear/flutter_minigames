import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/games/filler.dart';
import 'package:flutter_minigames/core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Filler with thin shell chrome.
class FillerPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const FillerPlayScreen({super.key, this.session});

  @override
  State<FillerPlayScreen> createState() => _FillerPlayScreenState();
}

class _FillerPlayScreenState extends State<FillerPlayScreen> {
  late final PlaySession _session;
  final FillerGame _game = const FillerGame();
  MatchController<FillerState, FillerMove>? _controller;
  int _round = 0;

  late final FillerStyle _boardStyle = FillerStyle(
    sounds: FillerSounds(
      onPick: DemoSfx.instance.mark,
      onCapture: DemoSfx.instance.drop,
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
    // Create + swap first, dispose after: the board unsubscribes from the old
    // controller when it rebinds, which lets the old stream close cleanly.
    final old = _controller;
    final controller = await MatchController.create<FillerState, FillerMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-fil-$_round',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: _session.hotSeat,
      seed: DateTime.now().millisecondsSinceEpoch ^ _round,
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
                title: 'Filler',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: controller == null
                      ? const CircularProgressIndicator()
                      // Board paints its own felt table — no white panel.
                      : SingleChildScrollView(
                          child: FillerBoard(
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
