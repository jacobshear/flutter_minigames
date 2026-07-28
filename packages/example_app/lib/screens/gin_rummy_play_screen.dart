import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/games/gin_rummy.dart';
import 'package:flutter_minigames/core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Gin Rummy with the thin demo shell around it.
class GinRummyPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const GinRummyPlayScreen({super.key, this.session});

  @override
  State<GinRummyPlayScreen> createState() => _GinRummyPlayScreenState();
}

class _GinRummyPlayScreenState extends State<GinRummyPlayScreen> {
  late final PlaySession _session;
  final GinRummyGame _game = const GinRummyGame();
  MatchController<GinRummyState, GinRummyMove>? _controller;
  int _round = 0;

  /// Only the seven demo clips exist, so several cues share one: a draw and a
  /// lay-off are both light ticks, a knock is the heavy drop.
  late final GinRummyStyle _tableStyle = GinRummyStyle(
    sounds: GinRummySounds(
      onDeal: () => DemoSfx.instance.drop(longDrop: true),
      onDrawStock: DemoSfx.instance.mark,
      onTakeDiscard: DemoSfx.instance.mark,
      onPassUpcard: DemoSfx.instance.mark,
      onDiscard: DemoSfx.instance.drop,
      onKnock: () => DemoSfx.instance.drop(longDrop: true),
      onGin: DemoSfx.instance.win,
      onLayOff: DemoSfx.instance.mark,
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
    final controller =
        await MatchController.create<GinRummyState, GinRummyMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-gin-$_round',
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
                title: 'Gin Rummy',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: controller == null
                    ? const Center(child: CircularProgressIndicator())
                    : GinRummyTable(
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
