import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_minigames/games/word_hunt.dart';
import 'package:flutter_minigames/core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';
import '../widgets/game_chrome.dart';

/// Hot-seat Word Hunt with thin shell chrome. Both players share one seeded
/// board; each plays a timed round, then the results screen settles it.
class WordHuntPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const WordHuntPlayScreen({super.key, this.session});

  /// The ENABLE list takes a moment to parse — loaded once per app run and
  /// shared across screens/new games. Hosts (and tests) may pre-seed it to
  /// skip the first-open load.
  static Future<WordDictionary>? dictionaryFuture;

  @override
  State<WordHuntPlayScreen> createState() => _WordHuntPlayScreenState();
}

class _WordHuntPlayScreenState extends State<WordHuntPlayScreen> {
  static Future<WordDictionary> _loadDictionary() =>
      WordHuntPlayScreen.dictionaryFuture ??= WordDictionary.load();

  late final PlaySession _session;
  WordHuntGame? _game;
  MatchController<WordHuntState, WordHuntMove>? _controller;
  int _round = 0;

  late final WordHuntStyle _boardStyle = WordHuntStyle(
    sounds: WordHuntSounds(
      onTilePick: DemoSfx.instance.mark,
      onWordFound: DemoSfx.instance.drop,
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
    _startNewGame();
  }

  Future<void> _startNewGame() async {
    // Swap the board off the old controller first (null shows the spinner and
    // unmounts the board, cancelling its subscription); dispose after create.
    final old = _controller;
    if (mounted) setState(() => _controller = null);
    final dictionary = await _loadDictionary();
    final game = _game ??= WordHuntGame(dictionary: dictionary);
    final controller =
        await MatchController.create<WordHuntState, WordHuntMove>(
      game: game,
      transport: _session.transport,
      matchId: 'local-wht-$_round',
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
    final game = _game;
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
                title: 'Word Hunt',
                subtitle: _session.hotSeat ? 'Pass and play' : 'Online',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: controller == null || game == null
                      ? const CircularProgressIndicator()
                      // Board paints its own felt table — no white panel.
                      : SingleChildScrollView(
                          child: WordHuntBoard(
                            key: ValueKey(_round),
                            controller: controller,
                            game: game,
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
