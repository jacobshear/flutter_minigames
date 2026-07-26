import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigame_cup_pong/minigame_cup_pong.dart';
import 'package:minigames_core/minigames_core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Cup Pong with thin shell chrome. Mirrors the shuffleboard screen:
/// PlaySession + MatchController, create-and-swap-before-dispose on New game.
///
/// The board is a first-person perspective-3-D scene on `minigames_3d`: you
/// look down-range at the opponent's rack and flick up to throw the ball into
/// the screen. GamePigeon rules are implemented in full — 10 cups, two balls a
/// turn, balls back on a two-for-two, re-racks at 6 and 3 cups.
///
/// Hot-seat is perfect information (both racks are on the chips), so there is
/// no handoff cover; the active chip and the ball dots carry whose throw it is.
class CupPongPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const CupPongPlayScreen({super.key, this.session});

  @override
  State<CupPongPlayScreen> createState() => _CupPongPlayScreenState();
}

class _CupPongPlayScreenState extends State<CupPongPlayScreen> {
  late final PlaySession _session;
  final CupPongGame _game = const CupPongGame();
  MatchController<CupPongState, CupPongThrow>? _controller;
  int _round = 0;

  // Only the seven procedural clips in the demo bank exist — no new assets, so
  // every cue reuses one: drop for the release, mark for a bounce, dropLong for
  // a made cup, invalid for a miss.
  late final CupPongStyle _boardStyle = CupPongStyle(
    sounds: CupPongSounds(
      onThrow: DemoSfx.instance.drop,
      onBounce: DemoSfx.instance.mark,
      onHit: () => DemoSfx.instance.drop(longDrop: true),
      onMiss: DemoSfx.instance.invalid,
      onBallsBack: DemoSfx.instance.newGame,
      onRerack: DemoSfx.instance.mark,
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
    final controller = await MatchController.create<CupPongState, CupPongThrow>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-cup-pong-$_round',
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
                title: 'Cup Pong',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: controller == null
                    ? const Center(child: CircularProgressIndicator())
                    : CupPongBoard(
                        key: ValueKey(_round),
                        controller: controller,
                        style: _boardStyle,
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
