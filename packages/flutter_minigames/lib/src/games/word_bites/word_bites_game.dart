import 'dart:math';

import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/words/words.dart';

/// A board cell as `(row, col)`.
typedef WordBitesCell = (int, int);

/// The three GamePigeon piece shapes. Dominoes never rotate: a horizontal
/// domino always occupies two cells side by side, a vertical one two stacked
/// cells, letters read left-to-right / top-to-bottom.
enum WordBitesPieceShape { single, horizontal, vertical }

/// One draggable letter piece from the shared round set.
class WordBitesPiece {
  final int id;
  final WordBitesPieceShape shape;

  /// Lowercase letters — 1 char for singles, 2 for dominoes.
  final String letters;

  const WordBitesPiece({
    required this.id,
    required this.shape,
    required this.letters,
  }) : assert(
          (shape == WordBitesPieceShape.single) == (letters.length == 1),
          'singles carry 1 letter, dominoes 2',
        );

  int get cellWidth => shape == WordBitesPieceShape.horizontal ? 2 : 1;
  int get cellHeight => shape == WordBitesPieceShape.vertical ? 2 : 1;

  /// The cells covered when the piece anchor (top-left) sits at
  /// ([row], [col]), each paired with the letter it carries.
  List<(WordBitesCell, String)> cellsAt(int row, int col) => switch (shape) {
        WordBitesPieceShape.single => [((row, col), letters)],
        WordBitesPieceShape.horizontal => [
            ((row, col), letters[0]),
            ((row, col + 1), letters[1]),
          ],
        WordBitesPieceShape.vertical => [
            ((row, col), letters[0]),
            ((row + 1, col), letters[1]),
          ],
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'shape': switch (shape) {
          WordBitesPieceShape.single => 's',
          WordBitesPieceShape.horizontal => 'h',
          WordBitesPieceShape.vertical => 'v',
        },
        'letters': letters,
      };

  factory WordBitesPiece.fromJson(Map<String, dynamic> json) => WordBitesPiece(
        id: json['id'] as int,
        shape: switch (json['shape'] as String) {
          'h' => WordBitesPieceShape.horizontal,
          'v' => WordBitesPieceShape.vertical,
          _ => WordBitesPieceShape.single,
        },
        letters: json['letters'] as String,
      );
}

/// Where one piece sat when a word scored — the serialized evidence.
class WordBitesPlacement {
  final int pieceId;
  final int row;
  final int col;

  const WordBitesPlacement({
    required this.pieceId,
    required this.row,
    required this.col,
  });

  List<int> toJson() => [pieceId, row, col];

  factory WordBitesPlacement.fromJson(List<dynamic> json) => WordBitesPlacement(
        pieceId: json[0] as int,
        row: json[1] as int,
        col: json[2] as int,
      );
}

/// One scored word plus the piece arrangement that formed it.
class WordBitesPlay {
  final String word;
  final List<WordBitesPlacement> placements;

  const WordBitesPlay({required this.word, required this.placements});

  Map<String, dynamic> toJson() => {
        'w': word,
        'p': [for (final p in placements) p.toJson()],
      };

  factory WordBitesPlay.fromJson(Map<String, dynamic> json) => WordBitesPlay(
        word: json['w'] as String,
        placements: [
          for (final p in json['p'] as List)
            WordBitesPlacement.fromJson(p as List),
        ],
      );
}

/// A whole timed round submitted as one move.
class WordBitesMove {
  final List<WordBitesPlay> words;

  const WordBitesMove({required this.words});
}

/// A validated, scored round on the state.
class WordBitesSubmission {
  final String playerId;
  final List<WordBitesPlay> plays;
  final int score;

  const WordBitesSubmission({
    required this.playerId,
    required this.plays,
    required this.score,
  });
}

/// Round-submission state: shared piece set + zero, one, or two submissions.
class WordBitesState {
  final List<String> playerIds;
  final int rows;
  final int cols;
  final List<WordBitesPiece> pieces;
  final List<WordBitesSubmission> submissions;

  const WordBitesState({
    required this.playerIds,
    required this.rows,
    required this.cols,
    required this.pieces,
    required this.submissions,
  });

  bool get isFinished => submissions.length >= playerIds.length;

  /// Player whose round it is to play/submit. After the final submission this
  /// stays on the last player (a `currentPlayer` is always required).
  String get currentPlayerId =>
      isFinished ? playerIds.last : playerIds[submissions.length];

  int scoreOf(String playerId) {
    for (final s in submissions) {
      if (s.playerId == playerId) return s.score;
    }
    return 0;
  }

  WordBitesSubmission? submissionOf(String playerId) {
    for (final s in submissions) {
      if (s.playerId == playerId) return s;
    }
    return null;
  }
}

/// GamePigeon Word Bites as a pure round-submission [TurnGame].
///
/// Rules implemented (GP fidelity, with documented approximations):
/// - Both players get the SAME seeded piece set: 3 horizontal dominoes,
///   3 vertical dominoes, 3 singles (9 pieces / 15 letters — GP shows roughly
///   8-9 pieces). Dominoes draw common digraphs (TH, ER, IN, …) with
///   rank-weighted probability and no duplicate digraph per set; singles draw
///   from a vowel-heavy Scrabble-like bag.
/// - Words score the moment a contiguous horizontal or vertical run spells
///   them; ONLY maximal runs count (ABCD never scores ABC), min length 3.
/// - Each unique word scores once per player per round.
/// - Scoring by length: 3=100, 4=400, 5=800, 6=1400, 7=1800, 8=2200, 9=2600
///   (approximation of GP's table; runs cap at 9 on the 8x9 board).
/// - Timing (90 s) is client-side, GP trust model. The move carries each
///   word WITH its piece arrangement; [applyMove] re-validates everything
///   (dictionary, length, dedupe, geometry) and recomputes the score —
///   invalid entries are silently dropped, the client's score is never
///   trusted.
///
/// Geometric validation performed per word: the submitted placements must use
/// distinct real pieces from the shared set, fit on the board without
/// overlapping each other, and spell the word as a MAXIMAL contiguous
/// horizontal or vertical run of the arrangement, with every submitted piece
/// contributing at least one cell to that run (a domino may contribute just
/// one letter — its partner letter sticks out perpendicular, exactly like
/// GP). Letter-multiset feasibility and domino pairing constraints are
/// implied: letters only ever come from real pieces, each usable once per
/// word, and `cellsAt` hard-wires each domino's letter adjacency.
class WordBitesGame extends TurnGame<WordBitesState, WordBitesMove> {
  final WordDictionary dictionary;
  final int rows;
  final int cols;
  final int minWordLength;

  const WordBitesGame({
    required this.dictionary,
    this.rows = 9,
    this.cols = 8,
    this.minWordLength = 3,
  });

  @override
  String get id => 'word_bites';

  /// Points by word length (see class docs). Lengths past 9 clamp to 9.
  static const Map<int, int> scoreByLength = {
    3: 100,
    4: 400,
    5: 800,
    6: 1400,
    7: 1800,
    8: 2200,
    9: 2600,
  };

  static int scoreForLength(int length) {
    if (length < 3) return 0;
    return scoreByLength[length > 9 ? 9 : length]!;
  }

  /// Common digraphs, most frequent first — domino picks are weighted toward
  /// the front of this list so TH/ER/IN-style pairs dominate.
  static const List<String> rankedDigraphs = [
    'th',
    'er',
    'in',
    'an',
    're',
    'on',
    'at',
    'st',
    'en',
    'es',
    'or',
    'te',
    'ed',
    'is',
    'ar',
    'al',
    'nd',
    'le',
    'se',
    'he',
    'ea',
    'ou',
    'it',
    'nt',
  ];

  /// Weighted single-letter bag — vowel-heavy, Scrabble-like distribution.
  static const String singleLetterBag = 'eeeeaaaaiiiooouussttrrnnldmpchgbywfk';

  static const int horizontalDominoCount = 3;
  static const int verticalDominoCount = 3;
  static const int singleCount = 3;

  /// Deterministic shared piece set for [seed]. Both clients derive the
  /// identical set, so validation in [applyMove] stays deterministic.
  static List<WordBitesPiece> generatePieces(int seed) {
    final rnd = Random(seed);
    final used = <String>{};

    String drawDigraph() {
      final n = rankedDigraphs.length;
      final total = n * (n + 1) ~/ 2;
      while (true) {
        var roll = rnd.nextInt(total);
        for (var i = 0; i < n; i++) {
          final weight = n - i;
          if (roll < weight) {
            if (used.add(rankedDigraphs[i])) return rankedDigraphs[i];
            break; // duplicate — reroll
          }
          roll -= weight;
        }
      }
    }

    final pieces = <WordBitesPiece>[];
    var id = 0;
    for (var i = 0; i < horizontalDominoCount; i++) {
      pieces.add(WordBitesPiece(
        id: id++,
        shape: WordBitesPieceShape.horizontal,
        letters: drawDigraph(),
      ));
    }
    for (var i = 0; i < verticalDominoCount; i++) {
      pieces.add(WordBitesPiece(
        id: id++,
        shape: WordBitesPieceShape.vertical,
        letters: drawDigraph(),
      ));
    }
    for (var i = 0; i < singleCount; i++) {
      pieces.add(WordBitesPiece(
        id: id++,
        shape: WordBitesPieceShape.single,
        letters: singleLetterBag[rnd.nextInt(singleLetterBag.length)],
      ));
    }
    return pieces;
  }

  @override
  WordBitesState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2);
    return WordBitesState(
      playerIds: List.of(playerIds),
      rows: rows,
      cols: cols,
      pieces: generatePieces(seed),
      submissions: const [],
    );
  }

  @override
  String currentPlayer(WordBitesState state) => state.currentPlayerId;

  /// Turn-gating only: the payload is sanitized inside [applyMove] (invalid
  /// words are dropped, not grounds to reject the whole round — matches the
  /// GP trust model where the UI only submits words it already auto-scored).
  @override
  bool validateMove(
    WordBitesState state,
    WordBitesMove move,
    String playerId,
  ) {
    if (state.isFinished) return false;
    return playerId == state.currentPlayerId;
  }

  @override
  WordBitesState applyMove(WordBitesState state, WordBitesMove move) {
    final plays = sanitizedPlays(state, move);
    var score = 0;
    for (final p in plays) {
      score += scoreForLength(p.word.length);
    }
    return WordBitesState(
      playerIds: state.playerIds,
      rows: state.rows,
      cols: state.cols,
      pieces: state.pieces,
      submissions: [
        ...state.submissions,
        WordBitesSubmission(
          playerId: state.currentPlayerId,
          plays: plays,
          score: score,
        ),
      ],
    );
  }

  /// Re-validates every claimed word: dictionary, min length, per-round
  /// dedupe, and the geometric evidence check. Order is preserved; invalid
  /// entries are dropped.
  List<WordBitesPlay> sanitizedPlays(WordBitesState state, WordBitesMove move) {
    final out = <WordBitesPlay>[];
    final seen = <String>{};
    final maxLen = max(state.rows, state.cols);
    for (final play in move.words) {
      final word = play.word.toLowerCase();
      if (word.length < minWordLength || word.length > maxLen) continue;
      if (seen.contains(word)) continue;
      if (!dictionary.contains(word)) continue;
      if (!evidenceFormsWord(state, play.placements, word)) continue;
      seen.add(word);
      out.add(WordBitesPlay(word: word, placements: List.of(play.placements)));
    }
    return out;
  }

  /// True when [placements] lay real, distinct pieces on the board without
  /// overlap and spell [word] as a maximal horizontal or vertical run, every
  /// piece contributing at least one cell to it.
  bool evidenceFormsWord(
    WordBitesState state,
    List<WordBitesPlacement> placements,
    String word,
  ) {
    if (placements.isEmpty) return false;
    final byId = {for (final p in state.pieces) p.id: p};
    final usedIds = <int>{};
    final letters = <WordBitesCell, String>{};
    final pieceOfCell = <WordBitesCell, int>{};

    for (final pl in placements) {
      final piece = byId[pl.pieceId];
      if (piece == null || !usedIds.add(pl.pieceId)) return false;
      for (final (cell, letter) in piece.cellsAt(pl.row, pl.col)) {
        final (r, c) = cell;
        if (r < 0 || r >= state.rows || c < 0 || c >= state.cols) return false;
        if (letters.containsKey(cell)) return false;
        letters[cell] = letter;
        pieceOfCell[cell] = pl.pieceId;
      }
    }

    for (final horizontal in const [true, false]) {
      for (final cell in letters.keys) {
        final (r, c) = cell;
        final before = horizontal ? (r, c - 1) : (r - 1, c);
        if (letters.containsKey(before)) continue; // not a run start
        final runCells = <WordBitesCell>[];
        final sb = StringBuffer();
        var cur = cell;
        while (letters.containsKey(cur)) {
          runCells.add(cur);
          sb.write(letters[cur]);
          final (cr, cc) = cur;
          cur = horizontal ? (cr, cc + 1) : (cr + 1, cc);
        }
        if (sb.toString() != word) continue; // maximal run must match exactly
        final contributing = {for (final rc in runCells) pieceOfCell[rc]!};
        if (contributing.length == usedIds.length) return true;
      }
    }
    return false;
  }

  @override
  GameOutcome? outcome(WordBitesState state) {
    if (!state.isFinished) return null;
    final a = state.playerIds[0];
    final b = state.playerIds[1];
    final sa = state.scoreOf(a);
    final sb = state.scoreOf(b);
    if (sa == sb) return const GameOutcome.draw();
    return GameOutcome.win(sa > sb ? a : b);
  }

  @override
  Map<String, dynamic> encodeState(WordBitesState state) => {
        'playerIds': state.playerIds,
        'rows': state.rows,
        'cols': state.cols,
        'pieces': [for (final p in state.pieces) p.toJson()],
        'subs': [
          for (final s in state.submissions)
            {
              'player': s.playerId,
              'score': s.score,
              'plays': [for (final p in s.plays) p.toJson()],
            },
        ],
      };

  @override
  WordBitesState decodeState(Map<String, dynamic> json, int version) =>
      WordBitesState(
        playerIds: [for (final p in json['playerIds'] as List) p as String],
        rows: json['rows'] as int,
        cols: json['cols'] as int,
        pieces: [
          for (final p in json['pieces'] as List)
            WordBitesPiece.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
        submissions: [
          for (final s in json['subs'] as List? ?? const [])
            WordBitesSubmission(
              playerId: (s as Map)['player'] as String,
              score: s['score'] as int,
              plays: [
                for (final p in s['plays'] as List)
                  WordBitesPlay.fromJson(Map<String, dynamic>.from(p as Map)),
              ],
            ),
        ],
      );

  @override
  Map<String, dynamic> encodeMove(WordBitesMove move) => {
        'words': [for (final p in move.words) p.toJson()],
      };

  @override
  WordBitesMove decodeMove(Map<String, dynamic> json) => WordBitesMove(
        words: [
          for (final p in json['words'] as List)
            WordBitesPlay.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
      );
}
