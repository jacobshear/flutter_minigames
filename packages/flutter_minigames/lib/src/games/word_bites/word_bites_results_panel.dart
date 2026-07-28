import 'package:flutter/material.dart';

import 'word_bites_game.dart';

/// End-of-match results: winner banner, side-by-side word lists, scores.
///
/// Reads everything from the finished [WordBitesState]; per-word points come
/// from [WordBitesGame.scoreForLength] so the panel needs no dictionary.
class WordBitesResultsPanel extends StatelessWidget {
  final WordBitesState state;
  final String player1Label;
  final String player2Label;
  final Color player1Color;
  final Color player2Color;

  const WordBitesResultsPanel({
    super.key,
    required this.state,
    this.player1Label = 'Player 1',
    this.player2Label = 'Player 2',
    this.player1Color = const Color(0xFF007AFF),
    this.player2Color = const Color(0xFFFF3B30),
  });

  @override
  Widget build(BuildContext context) {
    final p1 = state.playerIds[0];
    final p2 = state.playerIds[1];
    final s1 = state.scoreOf(p1);
    final s2 = state.scoreOf(p2);

    final String banner;
    final Color bannerColor;
    if (s1 == s2) {
      banner = 'DRAW';
      bannerColor = const Color(0xFF8E8E93);
    } else if (s1 > s2) {
      banner = '${player1Label.toUpperCase()} WINS';
      bannerColor = player1Color;
    } else {
      banner = '${player2Label.toUpperCase()} WINS';
      bannerColor = player2Color;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: bannerColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              banner,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PlayerColumn(
                  label: player1Label,
                  color: player1Color,
                  score: s1,
                  submission: state.submissionOf(p1),
                  winner: s1 > s2,
                ),
              ),
              Container(
                width: 1,
                height: 120,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: const Color(0x1A3C3C43),
              ),
              Expanded(
                child: _PlayerColumn(
                  label: player2Label,
                  color: player2Color,
                  score: s2,
                  submission: state.submissionOf(p2),
                  winner: s2 > s1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayerColumn extends StatelessWidget {
  final String label;
  final Color color;
  final int score;
  final WordBitesSubmission? submission;
  final bool winner;

  const _PlayerColumn({
    required this.label,
    required this.color,
    required this.score,
    required this.submission,
    required this.winner,
  });

  @override
  Widget build(BuildContext context) {
    final plays = submission?.plays ?? const <WordBitesPlay>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: winner ? color : const Color(0xFF1C1C1E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '$score',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 26,
            color: winner ? color : const Color(0xFF1C1C1E),
          ),
        ),
        const SizedBox(height: 10),
        if (plays.isEmpty)
          const Text(
            'No words',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Color(0x993C3C43),
            ),
          )
        else
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final play in plays)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        play.word.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: Color.lerp(color, Colors.black, 0.25),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${WordBitesGame.scoreForLength(play.word.length)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          color: Color(0x993C3C43),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
