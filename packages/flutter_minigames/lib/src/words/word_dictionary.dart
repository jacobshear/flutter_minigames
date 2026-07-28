import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

/// Fast lookup over the bundled ENABLE word list.
///
/// Backed by a sorted list: `contains` is a binary search and `hasPrefix` is a
/// lower-bound probe, so Word Hunt-style DFS can prune dead branches without a
/// trie's memory cost. All words are lowercase a-z.
class WordDictionary {
  final List<String> _sorted;

  WordDictionary.fromWords(Iterable<String> words)
      : _sorted = words.map((w) => w.toLowerCase().trim()).where((w) => w.isNotEmpty).toList()
          ..sort();

  /// Loads the bundled ENABLE list. Call once and share the instance.
  static Future<WordDictionary> load() async {
    final raw = await rootBundle.loadString('packages/flutter_minigames/assets/enable1.txt');
    return WordDictionary.fromWords(raw.split('\n'));
  }

  int get length => _sorted.length;

  bool contains(String word) {
    final w = word.toLowerCase();
    var lo = 0, hi = _sorted.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final cmp = _sorted[mid].compareTo(w);
      if (cmp == 0) return true;
      if (cmp < 0) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return false;
  }

  /// True if any word starts with [prefix] — the pruning primitive for
  /// board-walk searches (Word Hunt).
  bool hasPrefix(String prefix) {
    final p = prefix.toLowerCase();
    var lo = 0, hi = _sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sorted[mid].compareTo(p) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < _sorted.length && _sorted[lo].startsWith(p);
  }

  /// All words of exactly [length] letters. Computed lazily and cached —
  /// used to pick anagram base words.
  List<String> wordsOfLength(int length) =>
      _byLength.putIfAbsent(length, () => _sorted.where((w) => w.length == length).toList());
  final Map<int, List<String>> _byLength = {};

  /// Deterministically picks a word of [length] letters from [seed] — both
  /// clients of a match derive the same word from the match seed.
  String pickWord({required int length, required int seed}) {
    final pool = wordsOfLength(length);
    if (pool.isEmpty) throw ArgumentError('no words of length $length');
    return pool[Random(seed).nextInt(pool.length)];
  }

  /// Every dictionary word formable from the letter multiset [letters]
  /// (each letter usable once), at least [minLength] long. Used for
  /// anagram round solutions / max-score display.
  List<String> anagramsOf(String letters, {int minLength = 3}) {
    final available = _letterCounts(letters.toLowerCase());
    final maxLen = letters.length;
    final out = <String>[];
    for (var len = minLength; len <= maxLen; len++) {
      for (final w in wordsOfLength(len)) {
        if (_fits(w, available)) out.add(w);
      }
    }
    return out;
  }

  static List<int> _letterCounts(String s) {
    final counts = List<int>.filled(26, 0);
    for (final c in s.codeUnits) {
      if (c >= 0x61 && c <= 0x7a) counts[c - 0x61]++;
    }
    return counts;
  }

  static bool _fits(String word, List<int> available) {
    final need = _letterCounts(word);
    for (var i = 0; i < 26; i++) {
      if (need[i] > available[i]) return false;
    }
    return true;
  }
}
