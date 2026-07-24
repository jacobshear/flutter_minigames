import 'dart:math';

import 'package:minigames_core/minigames_core.dart';
import 'package:minigames_words/minigames_words.dart';

/// GamePigeon-style Anagrams as a round-submission [TurnGame].
///
/// Both players get the SAME scrambled letters (derived from the match seed)
/// and play a timed round on their own device/turn. A "move" is one player's
/// entire found-word list for their round; [applyMove] re-validates every word
/// against the shared dictionary + letter multiset and computes the score
/// server-side-style — the client's claimed score is never trusted. Timing is
/// enforced by the round UI (same trust model as GamePigeon).
///
/// Turn order: `playerIds[0]` plays first, then `playerIds[1]`; after both
/// submissions the match is finished and the higher total wins (tie = draw).
class AnagramsState {
  /// The scrambled round letters, lowercase (e.g. `'plnaet'`).
  final String letters;

  final List<String> playerIds;

  /// Validated, accepted words per player — only players that have submitted
  /// have an entry. Word order is preserved (order found).
  final Map<String, List<String>> submissions;

  const AnagramsState({
    required this.letters,
    required this.playerIds,
    required this.submissions,
  });

  bool hasSubmitted(String playerId) => submissions.containsKey(playerId);

  /// Accepted words for [playerId] (empty until they submit).
  List<String> wordsOf(String playerId) => submissions[playerId] ?? const [];

  /// Validated score for [playerId], recomputed from accepted words.
  int scoreOf(String playerId) =>
      wordsOf(playerId).fold(0, (sum, w) => sum + AnagramsGame.scoreForWord(w));

  /// First player (in turn order) who hasn't submitted, or `null` when done.
  String? get nextToPlay {
    for (final id in playerIds) {
      if (!hasSubmitted(id)) return id;
    }
    return null;
  }

  bool get isFinished => nextToPlay == null;
}

/// One player's round result: the raw word list they claim to have found.
class AnagramsMove {
  final List<String> words;

  const AnagramsMove(this.words);
}

class AnagramsGame extends TurnGame<AnagramsState, AnagramsMove> {
  /// Shared dictionary — both clients bundle the identical list, so
  /// validation inside [applyMove] stays deterministic across devices.
  final WordDictionary dictionary;

  /// Letters per round. 6 matches GamePigeon (a 6-letter base word is
  /// guaranteed to exist because letters come from scrambling one).
  final int letterCount;

  /// Round length in seconds. GamePigeon doesn't publish its exact timer;
  /// 60 s is our documented assumption, enforced by the round UI.
  final int roundSeconds;

  /// Minimum accepted word length (GamePigeon accepts 3+).
  static const int minWordLength = 3;

  const AnagramsGame({
    required this.dictionary,
    this.letterCount = 6,
    this.roundSeconds = 60,
  });

  @override
  String get id => 'anagrams';

  /// GP-approximate scoring by word length: 3 = 100, 4 = 400, 5 = 1200,
  /// 6+ = 2000. Words under [minWordLength] score nothing.
  static int scoreForWord(String word) => switch (word.length) {
        < minWordLength => 0,
        3 => 100,
        4 => 400,
        5 => 1200,
        _ => 2000,
      };

  /// Deterministic round letters for [seed]: pick a [letterCount]-letter
  /// dictionary word, then scramble it with the same seed. Both clients
  /// derive identical letters from the match seed.
  String lettersForSeed(int seed) {
    final base = dictionary.pickWord(length: letterCount, seed: seed);
    final chars = base.split('')..shuffle(Random(seed));
    return chars.join();
  }

  @override
  AnagramsState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2);
    return AnagramsState(
      letters: lettersForSeed(seed),
      playerIds: List.of(playerIds),
      submissions: const {},
    );
  }

  @override
  String currentPlayer(AnagramsState state) =>
      state.nextToPlay ?? state.playerIds.last;

  /// A move is legal iff it's [playerId]'s round and they haven't submitted.
  /// Invalid words inside the list don't make the move illegal — they're
  /// filtered by [applyMove] (that's the whole anti-cheat model).
  @override
  bool validateMove(AnagramsState state, AnagramsMove move, String playerId) {
    if (state.isFinished) return false;
    if (playerId != state.nextToPlay) return false;
    return true;
  }

  /// True if [word] can be formed from the round letters (each letter used
  /// at most once).
  bool fitsLetters(AnagramsState state, String word) =>
      _fits(word.toLowerCase(), _letterCounts(state.letters));

  /// Full acceptance check for a single word during a live round (UI-side
  /// feedback uses this; [applyMove] applies the same rules plus dedupe).
  bool isAcceptableWord(AnagramsState state, String word) {
    final w = word.toLowerCase().trim();
    if (w.length < minWordLength) return false;
    if (!fitsLetters(state, w)) return false;
    return dictionary.contains(w);
  }

  /// Validate + dedupe one submitted list. Order of first occurrence is kept.
  List<String> acceptedWords(AnagramsState state, Iterable<String> raw) {
    final available = _letterCounts(state.letters);
    final seen = <String>{};
    final out = <String>[];
    for (final r in raw) {
      final w = r.toLowerCase().trim();
      if (w.length < minWordLength) continue;
      if (!seen.add(w)) continue; // duplicate — scores once
      if (!_fits(w, available)) continue;
      if (!dictionary.contains(w)) continue;
      out.add(w);
    }
    return out;
  }

  @override
  AnagramsState applyMove(AnagramsState state, AnagramsMove move) {
    final playerId = state.nextToPlay!;
    return AnagramsState(
      letters: state.letters,
      playerIds: state.playerIds,
      submissions: {
        ...state.submissions,
        playerId: acceptedWords(state, move.words),
      },
    );
  }

  @override
  GameOutcome? outcome(AnagramsState state) {
    if (!state.isFinished) return null;
    final a = state.playerIds[0];
    final b = state.playerIds[1];
    final sa = state.scoreOf(a);
    final sb = state.scoreOf(b);
    if (sa == sb) return const GameOutcome.draw();
    return GameOutcome.win(sa > sb ? a : b);
  }

  @override
  Map<String, dynamic> encodeState(AnagramsState state) => {
        'letters': state.letters,
        'playerIds': state.playerIds,
        'submissions': {
          for (final e in state.submissions.entries) e.key: e.value,
        },
      };

  @override
  AnagramsState decodeState(Map<String, dynamic> json, int version) =>
      AnagramsState(
        letters: json['letters'] as String,
        playerIds:
            (json['playerIds'] as List).map((e) => e as String).toList(),
        submissions: {
          for (final e in (json['submissions'] as Map).entries)
            e.key as String:
                (e.value as List).map((w) => w as String).toList(),
        },
      );

  @override
  Map<String, dynamic> encodeMove(AnagramsMove move) => {'words': move.words};

  @override
  AnagramsMove decodeMove(Map<String, dynamic> json) => AnagramsMove(
        (json['words'] as List).map((e) => e as String).toList(),
      );

  static List<int> _letterCounts(String s) {
    final counts = List<int>.filled(26, 0);
    for (final c in s.codeUnits) {
      if (c >= 0x61 && c <= 0x7a) counts[c - 0x61]++;
    }
    return counts;
  }

  static bool _fits(String word, List<int> available) {
    if (word.isEmpty) return false;
    final need = _letterCounts(word);
    // Reject anything containing non a-z characters.
    var counted = 0;
    for (var i = 0; i < 26; i++) {
      if (need[i] > available[i]) return false;
      counted += need[i];
    }
    return counted == word.length;
  }
}
