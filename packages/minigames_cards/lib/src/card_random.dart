/// Deterministic, platform-stable pseudo-randomness for card games.
///
/// `dart:math`'s `Random` is implementation-defined, so two clients replaying
/// the same match seed can end up with different deals. [CardRandom] is a
/// splitmix32 hash: same seed → same sequence on VM, AOT and web, today and
/// after any Dart upgrade. Treat the constants below as **pinned to this
/// file** — changing them invalidates every stored match.
///
/// All arithmetic stays inside 32 bits, and multiplies are done in 16-bit
/// halves so the intermediate never exceeds 2^53 (JavaScript's exact-integer
/// ceiling).
class CardRandom {
  /// splitmix32 increment (golden-ratio constant).
  static const int _gamma = 0x9E3779B9;
  static const int _mixA = 0x21F0AAAD;
  static const int _mixB = 0x735A2D97;
  static const int _mask = 0xFFFFFFFF;

  int _state;

  /// A generator seeded with [seed] (any int; only the low 32 bits matter).
  CardRandom(int seed) : _state = seed & _mask;

  /// A generator for a *derived* sequence off the same match [seed] — e.g. the
  /// nth reshuffle of a discard pile. Distinct [stream] values give unrelated
  /// sequences that still replay identically from the match seed alone.
  factory CardRandom.derived(int seed, int stream) =>
      CardRandom(_mul32(seed & _mask, 0x85EBCA6B) ^ _mul32(stream, _mixB));

  /// 32-bit multiply that is exact in JavaScript as well as on the VM.
  static int _mul32(int a, int b) {
    final lo = a & 0xFFFF;
    final hi = (a >> 16) & 0xFFFF;
    return (lo * b + (((hi * b) & 0xFFFF) << 16)) & _mask;
  }

  /// The next raw 32-bit value.
  int nextUint32() {
    _state = (_state + _gamma) & _mask;
    var z = _state;
    z = _mul32(z ^ (z >> 16), _mixA);
    z = _mul32(z ^ (z >> 15), _mixB);
    return (z ^ (z >> 15)) & _mask;
  }

  /// A uniform int in `[0, max)`. Rejection-sampled, so there is no modulo
  /// bias even when [max] does not divide 2^32.
  int nextInt(int max) {
    if (max <= 0) throw RangeError.range(max, 1, null, 'max');
    final limit = _mask - (_mask % max);
    while (true) {
      final v = nextUint32();
      if (v < limit) return v % max;
    }
  }

  /// A double in `[0, 1)`.
  double nextDouble() => nextUint32() / 4294967296.0;

  /// In-place Fisher–Yates shuffle. Every permutation is reachable and the
  /// result depends only on the seed and the list's starting order.
  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }

  /// A shuffled copy of [items].
  List<T> shuffled<T>(Iterable<T> items) {
    final out = List<T>.of(items);
    shuffle(out);
    return out;
  }
}
