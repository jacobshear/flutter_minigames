import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/games/mini_golf.dart';
import 'package:flutter_minigames/core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Mini Golf with thin shell chrome. Mirrors the shuffleboard screen:
/// PlaySession + MatchController, create-and-swap-before-dispose on New game.
///
/// The board is a 3/4 perspective-3-D scene on `minigames_3d`: you look down the
/// hole from behind the ball, drag back to aim, and the camera follows the ball
/// as it rolls. Courses are 3, 6 or 9 holes; every hole is a different shape,
/// dealt from a seeded permutation of the eight [MiniGolfArchetype]s, with its
/// own par.
class MiniGolfPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const MiniGolfPlayScreen({super.key, this.session});

  @override
  State<MiniGolfPlayScreen> createState() => _MiniGolfPlayScreenState();
}

class _MiniGolfPlayScreenState extends State<MiniGolfPlayScreen> {
  late final PlaySession _session;

  /// Course length. GamePigeon plays 9, so that's the default.
  static const _holeChoices = [3, 6, 9];
  int _holeCount = 9;

  MiniGolfGame get _game => MiniGolfGame(holeCount: _holeCount);
  MatchController<MiniGolfState, MiniGolfMove>? _controller;
  int _round = 0;

  // Only the procedural clips in the demo bank exist — no new assets, so every
  // cue reuses one: drop for the strike, mark for a bank off a rail, dropLong
  // for the ball dropping, invalid for out of bounds.
  late final MiniGolfStyle _boardStyle = MiniGolfStyle(
    sounds: MiniGolfSounds(
      onPutt: DemoSfx.instance.drop,
      onWallHit: DemoSfx.instance.mark,
      onSink: () => DemoSfx.instance.drop(longDrop: true),
      onRest: DemoSfx.instance.mark,
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
        await MatchController.create<MiniGolfState, MiniGolfMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-mini-golf-$_round',
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
                title: 'Mini Golf',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const SizedBox(height: 8),
              _HolePicker(
                choices: _holeChoices,
                selected: _holeCount,
                onSelect: (n) {
                  if (n == _holeCount) return;
                  HapticFeedback.selectionClick();
                  DemoSfx.instance.newGame();
                  // A different course length is a different match.
                  setState(() {
                    _holeCount = n;
                    _round++;
                  });
                  _startNewGame();
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: controller == null
                    ? const Center(child: CircularProgressIndicator())
                    : MiniGolfBoard(
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

/// Segmented 3 / 6 / 9 course-length control. Quiet iOS chrome: the selection
/// reads as a filled pill, the rest as plain text on the track.
class _HolePicker extends StatelessWidget {
  final List<int> choices;
  final int selected;
  final ValueChanged<int> onSelect;

  const _HolePicker({
    required this.choices,
    required this.selected,
    required this.onSelect,
  });

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
            for (final n in choices)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(n),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: n == selected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: n == selected
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
                    '$n holes',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          n == selected ? FontWeight.w700 : FontWeight.w600,
                      color: n == selected
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
