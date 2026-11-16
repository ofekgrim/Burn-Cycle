import 'dart:math';

/// Deterministic PRNG (xorshift32 seeded through a murmur3 finaliser).
///
/// `dart:math`'s seeded [Random] does not promise the same sequence on every
/// platform, and a daily run has to roll the same camp on a phone and in a
/// browser. Every operation here stays inside 32 bits, so the VM and
/// JavaScript builds produce identical numbers.
class SeededRng implements Random {
  SeededRng(int seed) : _state = _nonZero(_fmix(seed));

  int _state;

  /// Folds a run seed and up to three small integers (year, day, purpose...)
  /// into an independent sub-seed. Each purpose gets its own stream, so how
  /// many numbers one system draws never shifts another system's rolls.
  static int mix(int seed, int a, [int b = 0, int c = 0]) {
    var h = _fmix(seed);
    h = _fmix(_mul32(h, 31) ^ (a & 0xFFFFFFFF));
    h = _fmix(_mul32(h, 31) ^ (b & 0xFFFFFFFF));
    h = _fmix(_mul32(h, 31) ^ (c & 0xFFFFFFFF));
    return h;
  }

  static int _nonZero(int s) => s == 0 ? 0x9E3779B9 : s;

  /// 32-bit multiply that never leaves the 53 bits JavaScript can hold.
  static int _mul32(int a, int b) {
    final lo = (a & 0xFFFF) * b;
    final hi = (((a >>> 16) & 0xFFFF) * b) & 0xFFFF;
    return (lo + hi * 0x10000) & 0xFFFFFFFF;
  }

  static int _fmix(int value) {
    var h = value & 0xFFFFFFFF;
    h ^= h >>> 16;
    h = _mul32(h, 0x85EBCA6B);
    h ^= h >>> 13;
    h = _mul32(h, 0xC2B2AE35);
    h ^= h >>> 16;
    return h & 0xFFFFFFFF;
  }

  int _nextU32() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >>> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x & 0xFFFFFFFF;
    return _state;
  }

  @override
  double nextDouble() => _nextU32() / 4294967296.0;

  @override
  int nextInt(int max) => (nextDouble() * max).floor();

  @override
  bool nextBool() => _nextU32() >= 0x80000000;
}
