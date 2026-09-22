import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/ui.dart';
import 'anagrams_game.dart';
import 'anagrams_style.dart';

/// A compressed highlight reel of one player's finished Anagrams round.
///
/// Built purely from [AnagramsState.wordsOf] — never a real-time re-run.
/// Shows the shared rack, then replays [playerId]'s words in the order they
/// were found: rack tiles for the word-in-progress lift with a
/// [AnagramsStyle.validColor] glow, the word forms letter by letter above the
/// rack, a "+points" popup fires as each word lands, and the found word drops
/// into a strip below — subdued if [viewerId] found it too, vivid if they
/// missed it. The live score counter accumulates per word and lands exactly
/// on [AnagramsState.scoreOf] at the end.
///
/// Driven end to end by a single [AnimationController] (never `Timer`/
/// `Future.delayed`), so it speeds up automatically under
/// `ReplayTimeDilation`. [controller] is the host's handle: calling
/// `controller.skip()` jumps straight to the fully-resolved final frame.
class AnagramsRoundReplay extends StatefulWidget {
  final AnagramsGame game;

  /// The finished/submitted round state.
  final AnagramsState state;

  /// Whose round this replay reconstructs.
  final String playerId;

  /// The person watching — used only to tag which of [playerId]'s words they
  /// also found ("you got it too" vs "here's one you missed").
  final String viewerId;

  final RoundReplayController controller;

  final AnagramsStyle style;

  const AnagramsRoundReplay({
    super.key,
    required this.game,
    required this.state,
    required this.playerId,
    required this.viewerId,
    required this.controller,
    this.style = const AnagramsStyle(),
  });

  @override
  State<AnagramsRoundReplay> createState() => _AnagramsRoundReplayState();
}

class _AnagramsRoundReplayState extends State<AnagramsRoundReplay>
    with TickerProviderStateMixin {
  // Assigned in initState, never from a field initialiser: a `late final x =
  // AnimationController(...)` that first runs during dispose() looks up a
  // deactivated element's ancestor and throws.
  late final AnimationController _ctrl;

  late final List<String> _words;
  late final Set<String> _viewerWords;

  /// Cumulative (possibly compressed) seconds at which word `i` lands. Word
  /// playback only — the final hold isn't part of this timeline.
  late final List<double> _cumulative;
  late final double _totalSeconds;

  bool _skipped = false;

  static const double _popupWindowSeconds = 0.4;

  /// Beat the final frame holds for after the last word lands, before
  /// [RoundReplayController.markFinished] fires. Folded into the single
  /// driving [_ctrl] (rather than a second controller) so the whole replay —
  /// playback and hold alike — speeds up together under fast-forward and
  /// completes off one `forward()` call.
  static const double _holdSeconds = 0.45;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);

    _words = widget.state.wordsOf(widget.playerId);
    _viewerWords = widget.state.wordsOf(widget.viewerId).toSet();

    // Pacing formula: base seconds per word scale with length, uniformly
    // compressed so the whole reel never exceeds 15s (short rounds play
    // unscaled — no padding).
    final baseSeconds = [
      for (final w in _words)
        (0.35 + 0.13 * (w.length - 3)).clamp(0.35, 1.2).toDouble(),
    ];
    final rawTotal = baseSeconds.fold<double>(0.0, (a, b) => a + b);
    final scale = rawTotal > 15.0 ? 15.0 / rawTotal : 1.0;
    final wordSeconds = [for (final b in baseSeconds) b * scale];
    var running = 0.0;
    _cumulative = [for (final s in wordSeconds) running += s];
    _totalSeconds = _cumulative.isEmpty ? 0.0 : _cumulative.last;

    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(
        microseconds:
            ((_totalSeconds + _holdSeconds) * Duration.microsecondsPerSecond)
                .round(),
      ),
    );
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (_skipped || !widget.controller.skipRequested) return;
    setState(() {
      _skipped = true;
      _ctrl.stop();
    });
    widget.controller.markFinished();
  }

  void _finish() {
    if (widget.controller.finished) return;
    widget.controller.markFinished();
  }

  _Frame _frame() {
    if (_words.isEmpty) {
      return const _Frame(
        foundCount: 0,
        liveScore: 0,
        currentIndex: -1,
        revealedLetters: [],
        activeIndices: [],
      );
    }
    if (_skipped) {
      return _Frame(
        foundCount: _words.length,
        liveScore: widget.state.scoreOf(widget.playerId),
        currentIndex: -1,
        revealedLetters: const [],
        activeIndices: const [],
      );
    }

    // Raw elapsed seconds across the whole timeline (words + hold); segment
    // math clamps to the word-playback portion so the hold reads as the
    // fully-resolved final frame.
    final totalWithHold = _totalSeconds + _holdSeconds;
    final t = (_ctrl.value * totalWithHold).clamp(0.0, totalWithHold);
    final segT = t.clamp(0.0, _totalSeconds);
    var foundCount = 0;
    var liveScore = 0;
    var currentIndex = -1;
    var currentProgress = 0.0;
    for (var i = 0; i < _words.length; i++) {
      final start = i == 0 ? 0.0 : _cumulative[i - 1];
      final end = _cumulative[i];
      if (segT >= end) {
        foundCount++;
        liveScore += AnagramsGame.scoreForWord(_words[i]);
      } else if (segT >= start) {
        currentIndex = i;
        currentProgress = end > start
            ? ((segT - start) / (end - start)).clamp(0.0, 1.0)
            : 1.0;
        break;
      } else {
        break;
      }
    }

    var revealedLetters = const <String>[];
    var activeIndices = const <int>[];
    if (currentIndex >= 0) {
      final word = _words[currentIndex];
      final revealedCount =
          (currentProgress * word.length).ceil().clamp(0, word.length);
      revealedLetters = word.substring(0, revealedCount).split('');
      final indices = _indicesForWord(widget.state.letters, word);
      final activeCount = math.min(revealedCount, indices.length);
      activeIndices = indices.sublist(0, activeCount);
    }

    // Rising "+points" popup for the most recently landed word.
    String? poppingWord;
    var poppingPoints = 0;
    var poppingProgress = 0.0;
    if (foundCount > 0) {
      final lastIdx = foundCount - 1;
      final sincePop = t - _cumulative[lastIdx];
      if (sincePop >= 0 && sincePop < _popupWindowSeconds) {
        poppingWord = _words[lastIdx];
        poppingPoints = AnagramsGame.scoreForWord(poppingWord);
        poppingProgress = (sincePop / _popupWindowSeconds).clamp(0.0, 1.0);
      }
    }

    return _Frame(
      foundCount: foundCount,
      liveScore: liveScore,
      currentIndex: currentIndex,
      revealedLetters: revealedLetters,
      activeIndices: activeIndices,
      poppingWord: poppingWord,
      poppingPoints: poppingPoints,
      poppingProgress: poppingProgress,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final table = style.resolveTable(scheme);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final f = _frame();
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
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
              _scoreHeader(f.liveScore),
              const SizedBox(height: 12),
              _foundStrip(f),
              const SizedBox(height: 14),
              _wordInProgressRow(scheme, f),
              const SizedBox(height: 14),
              _rack(scheme, f),
            ],
          ),
        );
      },
    );
  }

  Widget _scoreHeader(int score) {
    final style = widget.style;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$score',
            style: TextStyle(
              color: style.validColor,
              fontWeight: FontWeight.w900,
              fontSize: 20,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _foundStrip(_Frame f) {
    final style = widget.style;
    if (_words.isEmpty) {
      return const SizedBox(
        height: 30,
        child: Center(
          child: Text(
            'No words',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final shown = _words.take(f.foundCount).toList();
    return SizedBox(
      height: 32,
      child: shown.isEmpty
          ? const SizedBox.shrink()
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: shown.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final w = shown[i];
                return _FoundChip(
                  word: w,
                  viewerFound: _viewerWords.contains(w),
                  style: style,
                );
              },
            ),
    );
  }

  Widget _wordInProgressRow(ColorScheme scheme, _Frame f) {
    final style = widget.style;
    if (f.currentIndex < 0 && f.poppingWord == null) {
      return const SizedBox(height: 40);
    }
    return SizedBox(
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (f.currentIndex >= 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < f.revealedLetters.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  _ReplayTile(
                    letter: f.revealedLetters[i],
                    size: 30,
                    style: style,
                    scheme: scheme,
                    active: true,
                  ),
                ],
              ],
            ),
          if (f.poppingWord != null)
            Positioned(
              top: -4 - 22 * f.poppingProgress,
              child: Opacity(
                opacity: (1 - f.poppingProgress).clamp(0.0, 1.0),
                child: Text(
                  '+${f.poppingPoints}',
                  style: TextStyle(
                    color: style.validColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    shadows: const [
                      Shadow(color: Colors.black38, blurRadius: 6),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rack(ColorScheme scheme, _Frame f) {
    final style = widget.style;
    final letters = widget.state.letters;
    return LayoutBuilder(
      builder: (context, c) {
        final n = letters.length;
        final tile =
            n == 0 ? 0.0 : math.min((c.maxWidth - (n - 1) * 8) / n, 46.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _ReplayTile(
                letter: letters[i],
                size: tile,
                style: style,
                scheme: scheme,
                active: f.activeIndices.contains(i),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// One computed animation frame: what's found, the live score, and what the
/// word-in-progress row should show.
class _Frame {
  final int foundCount;
  final int liveScore;
  final int currentIndex;
  final List<String> revealedLetters;
  final List<int> activeIndices;
  final String? poppingWord;
  final int poppingPoints;
  final double poppingProgress;

  const _Frame({
    required this.foundCount,
    required this.liveScore,
    required this.currentIndex,
    required this.revealedLetters,
    required this.activeIndices,
    this.poppingWord,
    this.poppingPoints = 0,
    this.poppingProgress = 0,
  });
}

/// Rack tile indices that spell [word] out of [letters], greedy left to
/// right: for each character, the first not-yet-used index whose letter
/// matches.
List<int> _indicesForWord(String letters, String word) {
  final used = List<bool>.filled(letters.length, false);
  final indices = <int>[];
  for (final ch in word.split('')) {
    for (var i = 0; i < letters.length; i++) {
      if (!used[i] && letters[i] == ch) {
        used[i] = true;
        indices.add(i);
        break;
      }
    }
  }
  return indices;
}

/// A wooden replay tile — same face as the round board's letter tiles, plus
/// an [active] lift + glow for tiles taking part in the word currently
/// playing.
class _ReplayTile extends StatelessWidget {
  final String letter;
  final double size;
  final AnagramsStyle style;
  final ColorScheme scheme;
  final bool active;

  const _ReplayTile({
    required this.letter,
    required this.size,
    required this.style,
    required this.scheme,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final top = style.resolveTileTop(scheme);
    final bottom = style.resolveTileBottom(scheme);
    final glyph = style.resolveGlyph(scheme);
    return AnimatedScale(
      scale: active ? 1.12 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.22),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bottom],
          ),
          border: Border.all(
            color: active
                ? style.validColor.withValues(alpha: 0.85)
                : glyph.withValues(alpha: 0.35),
            width: active ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              offset: const Offset(0, 2.5),
              blurRadius: 5,
            ),
            if (active)
              BoxShadow(
                color: style.validColor.withValues(alpha: 0.55),
                blurRadius: 10,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Text(
          letter.toUpperCase(),
          style: TextStyle(
            color: glyph,
            fontSize: size * 0.52,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// A found-word chip for the replay strip. Subdued when the viewer already
/// found the same word ("you got it too"); vivid with a [AnagramsStyle.
/// validColor] glow when they missed it ("here's one you missed").
class _FoundChip extends StatelessWidget {
  final String word;
  final bool viewerFound;
  final AnagramsStyle style;

  const _FoundChip({
    required this.word,
    required this.viewerFound,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: viewerFound
            ? Colors.black.withValues(alpha: 0.22)
            : style.validColor.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(999),
        border: viewerFound
            ? null
            : Border.all(color: style.validColor.withValues(alpha: 0.6)),
        boxShadow: viewerFound
            ? null
            : [
                BoxShadow(
                  color: style.validColor.withValues(alpha: 0.35),
                  blurRadius: 6,
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            word.toUpperCase(),
            style: TextStyle(
              color: viewerFound
                  ? Colors.white.withValues(alpha: 0.6)
                  : Colors.white,
              fontWeight: viewerFound ? FontWeight.w600 : FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '${AnagramsGame.scoreForWord(word)}',
            style: TextStyle(
              color: viewerFound
                  ? Colors.white.withValues(alpha: 0.45)
                  : style.validColor,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
