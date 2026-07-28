import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/games/go_fish.dart';
import 'package:flutter_minigames/core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Go Fish with the thin demo shell around it.
class GoFishPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const GoFishPlayScreen({super.key, this.session});

  @override
  State<GoFishPlayScreen> createState() => _GoFishPlayScreenState();
}

class _GoFishPlayScreenState extends State<GoFishPlayScreen> {
  late final PlaySession _session;
  final GoFishGame _game = const GoFishGame();
  MatchController<GoFishState, GoFishMove>? _controller;
  int _round = 0;

  /// Only the seven demo clips exist, so cues share: an ask and a go fish are
  /// both light ticks, a haul landing and a book laid down are the drops.
  late final GoFishStyle _tableStyle = GoFishStyle(
    sounds: GoFishSounds(
      onDeal: () => DemoSfx.instance.drop(longDrop: true),
      onAsk: DemoSfx.instance.mark,
      onCatch: DemoSfx.instance.drop,
      onGoFish: DemoSfx.instance.mark,
      onDryPond: DemoSfx.instance.invalid,
      onBook: () => DemoSfx.instance.drop(longDrop: true),
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
    // Create + swap first, dispose after: the table unsubscribes from the old
    // controller when it rebinds, which lets the old stream close cleanly.
    final old = _controller;
    final controller = await MatchController.create<GoFishState, GoFishMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-gofish-$_round',
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
                title: 'Go Fish',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: controller == null
                    ? const Center(child: CircularProgressIndicator())
                    : GoFishTable(
                        key: ValueKey(_round),
                        controller: controller,
                        style: _tableStyle,
                      ),
              ),
              const SizedBox(height: 12),
              GameButton(
                label: 'New match',
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
