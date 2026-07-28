import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/games/anagrams.dart';
import 'package:flutter_minigames/core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Anagrams: both players get the same letters and a timed round.
/// Flow: "Player 1 ready?" cover → round → handoff cover → round → results.
class AnagramsPlayScreen extends StatefulWidget {
  final PlaySession? session;

  /// Preloaded dictionary override (tests inject a ready instance so the
  /// screen never awaits real IO inside a fake-async zone).
  final WordDictionary? dictionary;

  const AnagramsPlayScreen({super.key, this.session, this.dictionary});

  @override
  State<AnagramsPlayScreen> createState() => _AnagramsPlayScreenState();
}

enum _Phase { loading, p1Cover, p1Round, handoffCover, p2Round, results }

class _AnagramsPlayScreenState extends State<AnagramsPlayScreen> {
  /// The ENABLE list takes a moment to load — parse it once per app run and
  /// share the instance across screens/new games.
  static Future<WordDictionary>? _dictFuture;

  late final PlaySession _session;
  AnagramsGame? _game;
  MatchController<AnagramsState, AnagramsMove>? _controller;
  List<String> _allWords = const [];
  _Phase _phase = _Phase.loading;
  int _round = 0;
  final math.Random _rnd = math.Random();

  late final AnagramsStyle _style = AnagramsStyle(
    validColor: DemoColors.teal,
    invalidColor: DemoColors.coral,
    sounds: AnagramsSounds(
      onTap: DemoSfx.instance.mark,
      onValid: DemoSfx.instance.drop,
      onInvalid: DemoSfx.instance.invalid,
      onRoundEnd: () => DemoSfx.instance.drop(longDrop: true),
      onWin: DemoSfx.instance.win,
      onDraw: DemoSfx.instance.draw,
    ),
  );

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? PlaySession.localHotSeat();
    final injected = widget.dictionary;
    _dictFuture ??=
        injected != null ? Future.value(injected) : WordDictionary.load();
    _startNewGame();
  }

  Future<void> _startNewGame() async {
    setState(() => _phase = _Phase.loading);
    final dict = widget.dictionary ?? await _dictFuture!;
    final game = AnagramsGame(dictionary: dict);
    // Create + swap first, dispose after: the board unsubscribes from the old
    // controller when it rebinds, which lets the old stream close cleanly.
    final old = _controller;
    final controller =
        await MatchController.create<AnagramsState, AnagramsMove>(
      game: game,
      transport: _session.transport,
      matchId: 'local-ana-$_round',
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
      _game = game;
      _controller = controller;
      _allWords = dict.anagramsOf(controller.state!.letters);
      _phase = _Phase.p1Cover;
    });
    await old?.dispose();
  }

  Future<void> _onRoundComplete(List<String> words) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.submitMove(AnagramsMove(words));
    if (!mounted) return;
    setState(() {
      if (_phase == _Phase.p1Round) {
        _phase = _Phase.handoffCover;
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
                title: 'Anagrams',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const SizedBox(height: 8),
              Expanded(child: Center(child: _body())),
              if (_phase == _Phase.results) ...[
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
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final game = _game;
    final state = _controller?.state;
    if (_phase == _Phase.loading || game == null || state == null) {
      return const CircularProgressIndicator();
    }
    switch (_phase) {
      case _Phase.p1Cover:
        return _RoundCover(
          playerLabel: _style.player1Label,
          seconds: game.roundSeconds,
          letterCount: state.letters.length,
          style: _style,
          onStart: () => setState(() => _phase = _Phase.p1Round),
        );
      case _Phase.p1Round:
        return SingleChildScrollView(
          child: AnagramsRoundBoard(
            key: ValueKey('round-p1-$_round'),
            game: game,
            state: state,
            playerLabel: _style.player1Label,
            style: _style,
            onRoundComplete: _onRoundComplete,
          ),
        );
      case _Phase.handoffCover:
        return _RoundCover(
          playerLabel: _style.player2Label,
          seconds: game.roundSeconds,
          letterCount: state.letters.length,
          style: _style,
          handoff: true,
          onStart: () => setState(() => _phase = _Phase.p2Round),
        );
      case _Phase.p2Round:
        return SingleChildScrollView(
          child: AnagramsRoundBoard(
            key: ValueKey('round-p2-$_round'),
            game: game,
            state: state,
            playerLabel: _style.player2Label,
            style: _style,
            onRoundComplete: _onRoundComplete,
          ),
        );
      case _Phase.results:
        return SingleChildScrollView(
          child: AnagramsResultsView(
            key: ValueKey('results-$_round'),
            game: game,
            state: state,
            allWords: _allWords,
            style: _style,
          ),
        );
      case _Phase.loading:
        return const CircularProgressIndicator();
    }
  }
}

/// Pre-round felt cover: keeps the letters hidden until the player is ready
/// (pass-and-play fairness) and explains the round in one line.
class _RoundCover extends StatelessWidget {
  final String playerLabel;
  final int seconds;
  final int letterCount;
  final AnagramsStyle style;
  final bool handoff;
  final VoidCallback onStart;

  const _RoundCover({
    required this.playerLabel,
    required this.seconds,
    required this.letterCount,
    required this.style,
    required this.onStart,
    this.handoff = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final table = style.resolveTable(scheme);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 30),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 1.5,
          colors: [
            Color.lerp(table, Colors.white, 0.07)!,
            table,
            Color.lerp(table, Colors.black, 0.26)!,
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
            'Same $letterCount letters for both players.\n'
            'Make as many words as you can in $seconds seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 26),
          GameButton(
            label: 'Start round',
            color: DemoColors.teal,
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
