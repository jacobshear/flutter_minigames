import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigame_basketball/minigame_basketball.dart';
import 'package:minigames_core/minigames_core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Basketball: each player shoots two 45-second rounds at the same
/// hoop, one point per basket, higher total wins.
///
/// Flow: "Player 1 ready?" cover (where the hoop mode is picked for the whole
/// match) → player 1's two rounds → handoff cover → player 2's two rounds →
/// results. Round-submission model, not turn-alternating: each player submits
/// one move carrying both round scores.
class BasketballPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const BasketballPlayScreen({super.key, this.session});

  @override
  State<BasketballPlayScreen> createState() => _BasketballPlayScreenState();
}

enum _Phase { loading, p1Cover, p1Play, handoff, p2Play, results }

class _BasketballPlayScreenState extends State<BasketballPlayScreen> {
  late final PlaySession _session;
  final BasketballGame _game = const BasketballGame();
  MatchController<BasketballState, BasketballMove>? _controller;
  _Phase _phase = _Phase.loading;
  int _match = 0;
  BasketballHoopMode _mode = BasketballHoopMode.normal;
  final math.Random _rnd = math.Random();

  late final BasketballStyle _style = BasketballStyle(
    sounds: BasketballSounds(
      // Impact speed is available for pitch/gain shaping; the demo bank is one
      // sample per cue, so it is simply ignored here.
      onBounce: (_) => DemoSfx.instance.mark(),
      onRim: (_) => DemoSfx.instance.mark(),
      onSwish: () => DemoSfx.instance.drop(longDrop: true),
      onWhistle: DemoSfx.instance.drop,
      onBuzzer: DemoSfx.instance.invalid,
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
    setState(() => _phase = _Phase.loading);
    // Create + swap first, dispose after: avoids the controller-teardown
    // deadlock (a board rebinds off the new controller before the old closes).
    final old = _controller;
    final controller =
        await MatchController.create<BasketballState, BasketballMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-bball-$_match',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: _session.hotSeat,
      seed: _rnd.nextInt(1 << 31),
    );
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _phase = _Phase.p1Cover;
    });
    await old?.dispose();
  }

  Future<void> _onPlayerDone(List<int> roundScores) async {
    final controller = _controller;
    if (controller == null) return;
    final owner = controller.state?.nextToPlay ?? 'p1';
    await controller.submitMove(
      BasketballMove(owner: owner, roundScores: roundScores),
    );
    if (!mounted) return;
    setState(() {
      if (_phase == _Phase.p1Play) {
        _phase = _Phase.handoff;
      } else {
        _phase = _Phase.results;
        final outcome = controller.outcome;
        if (outcome == null || outcome.isDraw) {
          _style.sounds.onDraw?.call();
        } else {
          _style.sounds.onWin?.call();
        }
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                title: 'Basketball',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const SizedBox(height: 8),
              Expanded(child: _body()),
              if (_phase == _Phase.results) ...[
                const SizedBox(height: 8),
                GameButton(
                  label: 'New game',
                  color: DemoColors.blue,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    DemoSfx.instance.newGame();
                    setState(() => _match++);
                    _startNewGame();
                  },
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final controller = _controller;
    final state = controller?.state;
    if (_phase == _Phase.loading || controller == null || state == null) {
      return const Center(child: CircularProgressIndicator());
    }
    switch (_phase) {
      case _Phase.p1Cover:
        return Center(
          child: SingleChildScrollView(
            child: _Cover(
              playerLabel: _style.player1Label,
              seconds: _game.roundSeconds,
              mode: _mode,
              onModeChanged: (m) => setState(() => _mode = m),
              onStart: () => setState(() => _phase = _Phase.p1Play),
            ),
          ),
        );
      case _Phase.p1Play:
        return BasketballRoundBoard(
          key: ValueKey('bball-p1-$_match'),
          game: _game,
          mode: _mode,
          playerLabel: _style.player1Label,
          opponentLabel: _style.player2Label,
          opponentScore: state.scoreOf('p2'),
          seed: 1000 + _match,
          style: _style,
          onComplete: _onPlayerDone,
        );
      case _Phase.handoff:
        return Center(
          child: SingleChildScrollView(
            child: _Cover(
              playerLabel: _style.player2Label,
              seconds: _game.roundSeconds,
              mode: _mode,
              handoff: true,
              // The mode is a match option — locked in once play has started.
              onModeChanged: null,
              onStart: () => setState(() => _phase = _Phase.p2Play),
              toBeat: state.scoreOf('p1'),
            ),
          ),
        );
      case _Phase.p2Play:
        return BasketballRoundBoard(
          key: ValueKey('bball-p2-$_match'),
          game: _game,
          mode: _mode,
          playerLabel: _style.player2Label,
          opponentLabel: _style.player1Label,
          opponentScore: state.scoreOf('p1'),
          isPlayerOne: false,
          seed: 2000 + _match,
          style: _style,
          onComplete: _onPlayerDone,
        );
      case _Phase.results:
        return Center(
          child: SingleChildScrollView(
            child: BasketballResultsView(
              key: ValueKey('bball-results-$_match'),
              game: _game,
              state: state,
              style: _style,
            ),
          ),
        );
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());
    }
  }
}

/// Pre-round cover. Keeps hot-seat fair (each player starts their own clock)
/// and is where the match's hoop mode is chosen, before anyone has shot.
class _Cover extends StatelessWidget {
  final String playerLabel;
  final int seconds;
  final BasketballHoopMode mode;
  final ValueChanged<BasketballHoopMode>? onModeChanged;
  final VoidCallback onStart;
  final bool handoff;
  final int? toBeat;

  const _Cover({
    required this.playerLabel,
    required this.seconds,
    required this.mode,
    required this.onStart,
    this.onModeChanged,
    this.handoff = false,
    this.toBeat,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const style = BasketballStyle();
    final backdrop = style.resolveBackdrop(scheme);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 1.5,
          colors: [
            Color.lerp(backdrop, Colors.white, 0.1)!,
            backdrop,
            Color.lerp(backdrop, Colors.black, 0.3)!,
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            offset: const Offset(0, 6),
            blurRadius: 18,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (handoff) ...[
            Text(
              'Pass the phone',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            '$playerLabel ready?',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 26,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Two rounds of $seconds seconds. Sink as many as you can.\n'
            'Drag left or right to aim — every ball starts somewhere new.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w600,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (toBeat != null) ...[
            const SizedBox(height: 12),
            Text(
              '$toBeat to beat',
              style: const TextStyle(
                color: Color(0xFFF7C948),
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ],
          if (onModeChanged != null) ...[
            const SizedBox(height: 20),
            _ModePicker(mode: mode, onChanged: onModeChanged!),
          ],
          const SizedBox(height: 22),
          GameButton(
            label: handoff ? 'Start' : 'Start match',
            color: DemoColors.blue,
            onTap: () {
              HapticFeedback.selectionClick();
              onStart();
            },
          ),
        ],
      ),
    );
  }
}

/// Normal vs moving hoop — a match option, picked once at creation.
class _ModePicker extends StatelessWidget {
  final BasketballHoopMode mode;
  final ValueChanged<BasketballHoopMode> onChanged;

  const _ModePicker({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in BasketballHoopMode.values)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(m);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: m == mode
                      ? Colors.white.withValues(alpha: 0.92)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  m == BasketballHoopMode.moving ? 'Moving hoop' : 'Normal',
                  style: TextStyle(
                    color: m == mode
                        ? const Color(0xFF11151C)
                        : Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
