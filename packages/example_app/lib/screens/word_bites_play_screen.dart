import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minigame_word_bites/minigame_word_bites.dart';
import 'package:minigames_core/minigames_core.dart';
import 'package:minigames_words/minigames_words.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Word Bites: ready cover, 90 s player 1 round, handoff cover,
/// 90 s player 2 round, then side-by-side results.
class WordBitesPlayScreen extends StatefulWidget {
  final PlaySession? session;

  /// Test hook — injects a small dictionary instead of loading the bundled
  /// ENABLE list.
  final WordDictionary? dictionary;

  const WordBitesPlayScreen({super.key, this.session, this.dictionary});

  @override
  State<WordBitesPlayScreen> createState() => _WordBitesPlayScreenState();
}

enum _Phase { ready1, play1, handoff, play2, results }

class _WordBitesPlayScreenState extends State<WordBitesPlayScreen>
    with TickerProviderStateMixin {
  /// The ENABLE list takes a moment to parse — load once, share forever.
  static Future<WordDictionary>? _dictFuture;

  static const int roundSeconds = 90;

  late final PlaySession _session;
  WordDictionary? _dict;
  WordBitesGame? _game;
  MatchController<WordBitesState, WordBitesMove>? _controller;

  _Phase _phase = _Phase.ready1;
  int _round = 0;

  final List<WordBitesPlay> _roundPlays = [];
  int _roundScore = 0;
  int _secondsLeft = roundSeconds;

  late final AnimationController _timer = AnimationController(
    vsync: this,
    duration: const Duration(seconds: roundSeconds),
  )
    ..addListener(_onTimerTick)
    ..addStatusListener(_onTimerStatus);

  late final WordBitesSounds _sounds = WordBitesSounds(
    onPickup: DemoSfx.instance.mark,
    onSettle: DemoSfx.instance.drop,
    onWordScored: () => DemoSfx.instance.drop(longDrop: true),
    onInvalid: DemoSfx.instance.invalid,
  );

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? PlaySession.localHotSeat();
    final injected = widget.dictionary;
    if (injected != null) {
      _initWithDictionary(injected);
    } else {
      (_dictFuture ??= WordDictionary.load()).then((d) {
        if (mounted) _initWithDictionary(d);
      });
    }
  }

  void _initWithDictionary(WordDictionary dict) {
    _dict = dict;
    _game = WordBitesGame(dictionary: dict);
    _startNewMatch();
  }

  Future<void> _startNewMatch() async {
    // Create + swap first, dispose after: the board unsubscribes from the old
    // controller when it rebinds, which lets the old stream close cleanly.
    final old = _controller;
    final controller =
        await MatchController.create<WordBitesState, WordBitesMove>(
      game: _game!,
      transport: _session.transport,
      matchId: 'local-wb-$_round',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: _session.hotSeat,
      seed: _round * 7919 + 17,
    );
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _phase = _Phase.ready1;
      _roundPlays.clear();
      _roundScore = 0;
      _secondsLeft = roundSeconds;
      _timer.value = 0;
    });
    await old?.dispose();
  }

  void _onTimerTick() {
    final left = (roundSeconds * (1 - _timer.value)).ceil();
    if (left != _secondsLeft) setState(() => _secondsLeft = left);
  }

  void _onTimerStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _endRound();
  }

  void _startRound() {
    HapticFeedback.selectionClick();
    DemoSfx.instance.newGame();
    setState(() {
      _phase = _phase == _Phase.ready1 ? _Phase.play1 : _Phase.play2;
      _roundPlays.clear();
      _roundScore = 0;
      _secondsLeft = roundSeconds;
    });
    _timer.forward(from: 0);
  }

  Future<void> _endRound() async {
    _timer.stop();
    final controller = _controller;
    if (controller == null) return;
    await controller.submitMove(WordBitesMove(words: List.of(_roundPlays)));
    if (!mounted) return;
    final outcome = controller.outcome;
    setState(() {
      _roundPlays.clear();
      _roundScore = 0;
      _secondsLeft = roundSeconds;
      _timer.value = 0;
      _phase = outcome == null ? _Phase.handoff : _Phase.results;
    });
    if (outcome != null) {
      if (outcome.isDraw) {
        DemoSfx.instance.draw();
      } else {
        DemoSfx.instance.win();
      }
    }
  }

  void _newMatch() {
    HapticFeedback.selectionClick();
    DemoSfx.instance.newGame();
    _round++;
    _startNewMatch();
  }

  @override
  void dispose() {
    _timer.dispose();
    _controller?.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final state = controller?.state;

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
                title: 'Word Bites',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: state == null
                    ? const Center(child: CircularProgressIndicator())
                    : _body(state),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(WordBitesState state) {
    switch (_phase) {
      case _Phase.ready1:
        return _cover(
          title: 'Player 1 ready?',
          caption:
              '$roundSeconds seconds — drag the pieces together to spell words',
          button: 'Start round',
          accent: DemoColors.blue,
        );
      case _Phase.handoff:
        return _cover(
          title: 'Pass to Player 2',
          caption: 'Same pieces, same clock. Beat '
              '${state.scoreOf(state.playerIds[0])} points',
          button: 'Start round',
          accent: DemoColors.coral,
        );
      case _Phase.play1:
      case _Phase.play2:
        return _roundView(state);
      case _Phase.results:
        return _results(state);
    }
  }

  Widget _cover({
    required String title,
    required String caption,
    required String button,
    required Color accent,
  }) {
    return Center(
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 30, 28, 26),
        decoration: BoxDecoration(
          color: DemoColors.card,
          borderRadius: BorderRadius.circular(24),
          boxShadow: gameShadow(),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: gameDisplay(size: 24, weight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 230,
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: gameBody(size: 13.5),
              ),
            ),
            const SizedBox(height: 20),
            GameButton(label: button, color: accent, onTap: _startRound),
          ],
        ),
      ),
    );
  }

  Widget _roundView(WordBitesState state) {
    final isP1 = _phase == _Phase.play1;
    return SingleChildScrollView(
      child: Column(
        children: [
          WordBitesBoard(
            key: ValueKey('board-$_round-${_phase.name}'),
            pieces: state.pieces,
            dictionary: _dict!,
            style: WordBitesStyle(
              sounds: _sounds,
              accentColor: isP1 ? DemoColors.blue : DemoColors.coral,
            ),
            playerLabel: isP1 ? 'Player 1' : 'Player 2',
            score: _roundScore,
            secondsLeft: _secondsLeft,
            layoutSeed: _round, // identical scatter for both players
            onWordScored: (play, points) {
              setState(() {
                _roundPlays.add(play);
                _roundScore += points;
              });
            },
          ),
          const SizedBox(height: 10),
          if (_roundPlays.isNotEmpty)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final play in _roundPlays)
                  GameBadge(
                    label: play.word.toUpperCase(),
                    foreground: DemoColors.ink,
                  ),
              ],
            ),
          const SizedBox(height: 12),
          GameButton(
            label: 'End round',
            color: DemoColors.ink,
            onTap: () {
              HapticFeedback.selectionClick();
              _endRound();
            },
          ),
        ],
      ),
    );
  }

  Widget _results(WordBitesState state) {
    return SingleChildScrollView(
      child: Column(
        children: [
          WordBitesResultsPanel(
            state: state,
            player1Color: DemoColors.blue,
            player2Color: DemoColors.coral,
          ),
          const SizedBox(height: 16),
          GameButton(
            label: 'New match',
            color: DemoColors.blue,
            onTap: _newMatch,
          ),
        ],
      ),
    );
  }
}
