import 'package:flutter/material.dart';

import 'anagrams_game.dart';
import 'anagrams_style.dart';

/// GP-style end-of-match screen: winner banner, both players' word lists side
/// by side with validated scores, and the full solution list ("you found 12 of
/// 63 words") with best missed words up top.
///
/// Self-contains the felt backdrop. Non-scrolling — wrap it in a
/// `SingleChildScrollView` from the play screen.
class AnagramsResultsView extends StatefulWidget {
  final AnagramsGame game;

  /// The finished state (both players submitted).
  final AnagramsState state;

  /// Every dictionary word formable from the round letters — precompute once
  /// with `dictionary.anagramsOf(state.letters)`.
  final List<String> allWords;

  final AnagramsStyle style;

  const AnagramsResultsView({
    super.key,
    required this.game,
    required this.state,
    required this.allWords,
    this.style = const AnagramsStyle(),
  });

  @override
  State<AnagramsResultsView> createState() => _AnagramsResultsViewState();
}

class _AnagramsResultsViewState extends State<AnagramsResultsView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  )..forward();

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final state = widget.state;
    final table = style.resolveTable(scheme);

    final outcome = widget.game.outcome(state)!;
    final p1 = state.playerIds[0];
    final p2 = state.playerIds[1];
    final foundByAnyone = {...state.wordsOf(p1), ...state.wordsOf(p2)};

    // Solution list: longest (highest value) first, alphabetical within
    // length — GP shows the full solution at the end.
    final solutions = List.of(widget.allWords)
      ..sort((a, b) {
        final byLen = b.length.compareTo(a.length);
        return byLen != 0 ? byLen : a.compareTo(b);
      });

    final String banner;
    if (outcome.isDraw) {
      banner = 'DRAW';
    } else {
      banner = outcome.winnerId == p1
          ? '${style.player1Label} wins'.toUpperCase()
          : '${style.player2Label} wins'.toUpperCase();
    }

    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) {
        final enter = Curves.easeOutCubic.transform(_entrance.value);
        return Opacity(
          opacity: enter.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.96 + 0.04 * enter, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
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
            // Winner pill (black translucent, repo convention).
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(10),
                border: outcome.isWin
                    ? Border.all(
                        color: const Color(0xFFFFCC00)
                            .withValues(alpha: 0.65),
                      )
                    : null,
              ),
              child: Text(
                banner,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 14),
            // The round letters as mini tiles.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < state.letters.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  _MiniTile(letter: state.letters[i], style: style),
                ],
              ],
            ),
            const SizedBox(height: 16),
            // Side-by-side player columns.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _PlayerColumn(
                    label: style.player1Label,
                    words: state.wordsOf(p1),
                    score: state.scoreOf(p1),
                    winner: outcome.winnerId == p1,
                    style: style,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PlayerColumn(
                    label: style.player2Label,
                    words: state.wordsOf(p2),
                    score: state.scoreOf(p2),
                    winner: outcome.winnerId == p2,
                    style: style,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Full solution.
            Text(
              'Found ${foundByAnyone.length} of ${solutions.length} words',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final w in solutions)
                  _SolutionChip(
                    word: w,
                    found: foundByAnyone.contains(w),
                    style: style,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerColumn extends StatelessWidget {
  final String label;
  final List<String> words;
  final int score;
  final bool winner;
  final AnagramsStyle style;

  const _PlayerColumn({
    required this.label,
    required this.words,
    required this.score,
    required this.winner,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: winner ? 0.34 : 0.22),
        borderRadius: BorderRadius.circular(16),
        border: winner
            ? Border.all(
                color: const Color(0xFFFFCC00).withValues(alpha: 0.6),
                width: 1.5,
              )
            : null,
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$score',
            style: TextStyle(
              color: winner ? const Color(0xFFFFCC00) : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 26,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          if (words.isEmpty)
            Text(
              'No words',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            for (final w in words)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      w.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      '${AnagramsGame.scoreForWord(w)}',
                      style: TextStyle(
                        color: style.validColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _MiniTile extends StatelessWidget {
  final String letter;
  final AnagramsStyle style;

  const _MiniTile({required this.letter, required this.style});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            style.resolveTileTop(scheme),
            style.resolveTileBottom(scheme),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Text(
        letter.toUpperCase(),
        style: TextStyle(
          color: style.resolveGlyph(scheme),
          fontWeight: FontWeight.w900,
          fontSize: 15,
          height: 1,
        ),
      ),
    );
  }
}

class _SolutionChip extends StatelessWidget {
  final String word;
  final bool found;
  final AnagramsStyle style;

  const _SolutionChip({
    required this.word,
    required this.found,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: found
            ? style.validColor.withValues(alpha: 0.28)
            : Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: found
            ? Border.all(color: style.validColor.withValues(alpha: 0.55))
            : null,
      ),
      child: Text(
        word.toUpperCase(),
        style: TextStyle(
          color: found ? Colors.white : Colors.white.withValues(alpha: 0.6),
          fontWeight: found ? FontWeight.w800 : FontWeight.w600,
          fontSize: 11,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
