import 'dart:math';

import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/words/words.dart';

/// GamePigeon-style Word Hunt as a pure [TurnGame].
///
/// Both players get the SAME seeded 4×4 letter grid and a timed round each
/// (timing enforced by the round UI — same trust model as GamePigeon).
/// A "move" is one whole round submission: every word the player traced,
/// each with its tile path. [applyMove] re-validates everything server-side
/// style — path adjacency, tile reuse, spelling, dictionary, minimum length,
/// dedupe — so a client can never smuggle a fake score.
///
/// Scoring by word length (GP approximation, documented in
/// [WordHuntGame.scoreForLength]): 3→100, 4→400, 5→800, 6→1400, 7→1800,
/// 8+→2200. Higher total wins; equal totals draw.
///
/// Out of scope (GamePigeon also offers these): 5×5 and cross-shaped boards.
/// The state carries a size-agnostic letter list so a future variant can add
/// them without a schema break.

/// One traced word: the word plus the exact tile path used.
class TracedWord {
  /// The word spelled, lowercase.
  final String word;

  /// Cell indices (row-major) in trace order.
  final List<int> path;

  const TracedWord(this.word, this.path);
}

/// A whole round submission — every word a player found, with paths.
class WordHuntMove {
  final List<TracedWord> words;

  const WordHuntMove(this.words);
}

class WordHuntState {
  /// Row-major tiles, lowercase. Each entry is one letter, except the classic
  /// Boggle "Qu" die face which is the two-letter string `'qu'`.
  final List<String> letters;

  /// Turn order: `playerIds[0]` plays the first round.
  final List<String> playerIds;

  /// Accepted (re-validated) words per player, in submission order.
  final Map<String, List<String>> found;

  /// Player ids that have completed their round, in completion order.
  final List<String> submitted;

  const WordHuntState({
    required this.letters,
    required this.playerIds,
    required this.found,
    required this.submitted,
  });

  /// Board side length (4 for the classic grid).
  int get size => sqrt(letters.length).round();

  bool hasSubmitted(String playerId) => submitted.contains(playerId);

  bool get allSubmitted => playerIds.every(submitted.contains);

  /// The player whose round it is. Once everyone has submitted this returns
  /// the last player (the game is over; [WordHuntGame.outcome] is non-null).
  String get currentPlayerId => playerIds.firstWhere(
        (p) => !submitted.contains(p),
        orElse: () => playerIds.last,
      );

  List<String> wordsOf(String playerId) => found[playerId] ?? const [];

  int scoreOf(String playerId) => wordsOf(playerId)
      .fold(0, (total, w) => total + WordHuntGame.scoreForLength(w.length));
}

class WordHuntGame extends TurnGame<WordHuntState, WordHuntMove> {
  /// Dictionary used for validation and board solving. Both clients bundle
  /// the identical list, so validation in [applyMove] stays deterministic.
  final WordDictionary dictionary;

  /// Minimum findable words a generated board must offer. Boards below the
  /// threshold are deterministically re-rolled (seed+1, seed+2, …) so both
  /// clients converge on the same board.
  final int minSolutions;

  /// Safety cap on re-rolls; the best board seen so far is used if no
  /// candidate reaches [minSolutions].
  final int maxGenerationAttempts;

  WordHuntGame({
    required this.dictionary,
    this.minSolutions = 40,
    this.maxGenerationAttempts = 64,
  });

  /// Classic 4×4 board.
  static const int boardSize = 4;

  static const int minWordLength = 3;

  /// GP-style scoring by word length (approximation of GamePigeon's table).
  static int scoreForLength(int length) => switch (length) {
        < minWordLength => 0,
        3 => 100,
        4 => 400,
        5 => 800,
        6 => 1400,
        7 => 1800,
        _ => 2200,
      };

  /// The classic 16 Boggle dice (1992 set). `Q` renders as the `Qu` face.
  static const List<String> _dice = [
    'AAEEGN',
    'ABBJOO',
    'ACHOPS',
    'AFFKPS',
    'AOOTTW',
    'CIMOTU',
    'DEILRX',
    'DELRVY',
    'DISTTY',
    'EEGHNW',
    'EEINSU',
    'EHRTVW',
    'EIOSST',
    'ELRTTY',
    'HIMNQU',
    'HLNNRZ',
  ];

  @override
  String get id => 'word_hunt';

  // -------------------------------------------------------------------------
  // Board generation + solving
  // -------------------------------------------------------------------------

  /// Deterministically rolls one candidate board from [seed]: shuffle the
  /// 16 dice, pick one face each.
  static List<String> rollBoard(int seed) {
    final rng = Random(seed);
    final dice = List.of(_dice)..shuffle(rng);
    return [
      for (final die in dice) _face(die[rng.nextInt(die.length)]),
    ];
  }

  static String _face(String c) => c == 'Q' ? 'qu' : c.toLowerCase();

  /// The board both clients derive from [seed]: rolls candidates at seed,
  /// seed+1, … until one offers at least [minSolutions] findable words
  /// (falls back to the richest candidate after [maxGenerationAttempts]).
  List<String> generateBoard(int seed) {
    List<String> best = const [];
    var bestCount = -1;
    for (var attempt = 0; attempt < maxGenerationAttempts; attempt++) {
      final letters = rollBoard(seed + attempt);
      final count = solveBoard(letters).length;
      if (count >= minSolutions) return letters;
      if (count > bestCount) {
        bestCount = count;
        best = letters;
      }
    }
    return best;
  }

  /// Every dictionary word findable on [letters] (sorted). DFS from each tile
  /// over 8-directional adjacency with `hasPrefix` pruning.
  List<String> solveBoard(List<String> letters) {
    final size = sqrt(letters.length).round();
    final words = <String>{};
    final visited = List<bool>.filled(letters.length, false);

    void dfs(int cell, String prefix) {
      final next = prefix + letters[cell];
      if (!dictionary.hasPrefix(next)) return;
      visited[cell] = true;
      if (next.length >= minWordLength && dictionary.contains(next)) {
        words.add(next);
      }
      for (final n in neighborsOf(cell, size)) {
        if (!visited[n]) dfs(n, next);
      }
      visited[cell] = false;
    }

    for (var i = 0; i < letters.length; i++) {
      dfs(i, '');
    }
    return words.toList()..sort();
  }

  /// 8-directional neighbours of [cell] on a [size]×[size] grid.
  static List<int> neighborsOf(int cell, int size) {
    final row = cell ~/ size;
    final col = cell % size;
    final out = <int>[];
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final r = row + dr;
        final c = col + dc;
        if (r >= 0 && r < size && c >= 0 && c < size) out.add(r * size + c);
      }
    }
    return out;
  }

  /// Whether two cells touch (8-directional, not the same cell).
  static bool areAdjacent(int a, int b, int size) {
    if (a == b) return false;
    final dr = (a ~/ size - b ~/ size).abs();
    final dc = (a % size - b % size).abs();
    return dr <= 1 && dc <= 1;
  }

  // -------------------------------------------------------------------------
  // TurnGame contract
  // -------------------------------------------------------------------------

  @override
  WordHuntState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2, 'Word Hunt is a two-player game');
    return WordHuntState(
      letters: generateBoard(seed),
      playerIds: List.of(playerIds),
      found: const {},
      submitted: const [],
    );
  }

  @override
  String currentPlayer(WordHuntState state) => state.currentPlayerId;

  @override
  bool validateMove(WordHuntState state, WordHuntMove move, String playerId) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    return !state.hasSubmitted(playerId);
  }

  /// Accepts the round: every traced word is re-validated and invalid or
  /// duplicate entries are silently dropped (never trust the client's list,
  /// let alone its score).
  @override
  WordHuntState applyMove(WordHuntState state, WordHuntMove move) {
    final player = state.currentPlayerId;
    final accepted = <String>[];
    final seen = <String>{};
    for (final traced in move.words) {
      final word = traced.word.toLowerCase();
      if (!seen.add(word)) continue; // dedupe within the submission
      if (!isValidTrace(state.letters, word, traced.path)) continue;
      accepted.add(word);
    }
    return WordHuntState(
      letters: state.letters,
      playerIds: state.playerIds,
      found: {...state.found, player: accepted},
      submitted: [...state.submitted, player],
    );
  }

  /// Full server-side check for one traced word: cells in range and distinct,
  /// consecutive cells 8-adjacent, tiles spell [word], length ≥ 3, and the
  /// word is in the dictionary.
  bool isValidTrace(List<String> letters, String word, List<int> path) {
    if (word.length < minWordLength) return false;
    if (path.isEmpty) return false;
    final size = sqrt(letters.length).round();
    final used = <int>{};
    final spelled = StringBuffer();
    for (var i = 0; i < path.length; i++) {
      final cell = path[i];
      if (cell < 0 || cell >= letters.length) return false;
      if (!used.add(cell)) return false; // tile reuse
      if (i > 0 && !areAdjacent(path[i - 1], cell, size)) return false;
      spelled.write(letters[cell]);
    }
    if (spelled.toString() != word) return false;
    return dictionary.contains(word);
  }

  @override
  GameOutcome? outcome(WordHuntState state) {
    if (!state.allSubmitted) return null;
    final a = state.playerIds[0];
    final b = state.playerIds[1];
    final scoreA = state.scoreOf(a);
    final scoreB = state.scoreOf(b);
    if (scoreA == scoreB) return const GameOutcome.draw();
    return GameOutcome.win(scoreA > scoreB ? a : b);
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  @override
  Map<String, dynamic> encodeState(WordHuntState state) => {
        'letters': state.letters,
        'playerIds': state.playerIds,
        'found': {
          for (final e in state.found.entries) e.key: e.value,
        },
        'submitted': state.submitted,
      };

  @override
  WordHuntState decodeState(Map<String, dynamic> json, int version) =>
      WordHuntState(
        letters: (json['letters'] as List).map((e) => e as String).toList(),
        playerIds: (json['playerIds'] as List).map((e) => e as String).toList(),
        found: {
          for (final e in (json['found'] as Map).entries)
            e.key as String: (e.value as List).map((w) => w as String).toList(),
        },
        submitted: (json['submitted'] as List).map((e) => e as String).toList(),
      );

  @override
  Map<String, dynamic> encodeMove(WordHuntMove move) => {
        'words': [
          for (final t in move.words) {'word': t.word, 'path': t.path},
        ],
      };

  @override
  WordHuntMove decodeMove(Map<String, dynamic> json) => WordHuntMove([
        for (final w in json['words'] as List)
          TracedWord(
            (w as Map)['word'] as String,
            (w['path'] as List).map((e) => e as int).toList(),
          ),
      ]);
}
