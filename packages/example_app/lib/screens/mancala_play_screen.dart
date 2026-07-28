import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigame_mancala/minigame_mancala.dart';
import 'package:minigames_core/minigames_core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Mancala with thin shell chrome.
class MancalaPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const MancalaPlayScreen({super.key, this.session});

  @override
  State<MancalaPlayScreen> createState() => _MancalaPlayScreenState();
}

class _MancalaPlayScreenState extends State<MancalaPlayScreen> {
  late final PlaySession _session;

  /// Capture or Avalanche — two different rule sets, picked per match.
  MancalaMode _mode = MancalaMode.capture;

  MancalaGame get _game => MancalaGame(seedsPerPit: 4, mode: _mode);
  MatchController<MancalaState, MancalaMove>? _controller;
  int _round = 0;

  late final MancalaStyle _boardStyle = MancalaStyle(
    southAccent: DemoColors.ink,
    northAccent: DemoColors.coral,
    sounds: MancalaSounds(
      onDrop: DemoSfx.instance.drop,
      onCapture: () => DemoSfx.instance.drop(longDrop: true),
      onExtraTurn: DemoSfx.instance.mark,
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
    final controller =
        await MatchController.create<MancalaState, MancalaMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-mcl-$_round',
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
                title: 'Mancala',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const SizedBox(height: 8),
              _ModePicker(
                selected: _mode,
                onSelect: (m) {
                  if (m == _mode) return;
                  HapticFeedback.selectionClick();
                  DemoSfx.instance.newGame();
                  // Different rules — a different match.
                  setState(() {
                    _mode = m;
                    _round++;
                  });
                  _startNewGame();
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: controller == null
                      ? const CircularProgressIndicator()
                      // Board paints its own felt table — no white panel.
                      : SingleChildScrollView(
                          child: MancalaBoard(
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

/// Segmented Capture / Avalanche control. Quiet iOS chrome: the selection reads
/// as a filled pill, the rest as plain text on the track.
class _ModePicker extends StatelessWidget {
  final MancalaMode selected;
  final ValueChanged<MancalaMode> onSelect;

  const _ModePicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in MancalaMode.values)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: m == selected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: m == selected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    m.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          m == selected ? FontWeight.w700 : FontWeight.w600,
                      color: m == selected
                          ? DemoColors.ink
                          : DemoColors.ink.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
