/// One shot, released and resolved, recorded exactly as the live board threw
/// it — enough for [BasketballRoundReplay] to reproduce its flight through
/// the same [BasketballRoundSim] the board runs and land on the same result.
///
/// Basketball transmits a single directional float per shot ([BasketballAim]
/// in `basketball_court.dart`): power and loft are solved once per match and
/// never vary, so [aim] together with [spawnX] *is* the launch velocity —
/// there is nothing else to capture. Feeding the same [aim] into
/// [BasketballRoundSim.shoot] for a ball placed at the same [spawnX], at the
/// same simulated round time, reproduces the same release velocity and spin
/// bit-for-bit (the spin formula lives with the sim, not here, so the two can
/// never drift apart). That is also why [BasketballShot] does not carry a
/// velocity vector: a float and an offset already pin the whole flight down.
///
/// Kept deliberately tiny — a round throws 20-60 of these, and the whole log
/// rides along on every [BasketballMove].
class BasketballShot {
  /// 0-based round this shot was thrown in.
  final int round;

  /// Round-clock milliseconds when the ball was released.
  final int tMs;

  /// Lateral spawn offset this ball appeared at, metres.
  final double spawnX;

  /// -1..1 steering, exactly as [BasketballAim.aimFromDrag] produced live.
  final double aim;

  /// True if this shot passed down through the hoop.
  final bool made;

  /// Points this shot earned (0 or 1 — basketball is flat-scored today, but
  /// this is kept as its own field rather than inferred from [made] so a
  /// future scoring rule does not also have to touch the replay format).
  final int points;

  /// This player's shot sequence number for the whole match (0-based, spans
  /// both rounds) — a stable identity for widget keys, independent of round
  /// boundaries.
  final int ballIndex;

  const BasketballShot({
    required this.round,
    required this.tMs,
    required this.spawnX,
    required this.aim,
    required this.made,
    required this.points,
    required this.ballIndex,
  });

  /// Compact array encoding: `[round, tMs, spawnX, aim, made, points,
  /// ballIndex]`. Floats are rounded to 3 decimals — plenty of precision for
  /// a 0.33 m spawn spread and a -1..1 steering value — to keep the payload
  /// lean across a whole round's worth of shots.
  List<Object?> encode() => [
        round,
        tMs,
        _round3(spawnX),
        _round3(aim),
        made,
        points,
        ballIndex,
      ];

  static double _round3(double v) => (v * 1000).roundToDouble() / 1000;

  /// Decodes one [encode]d entry, or `null` for anything that isn't the
  /// expected shape. Never throws — a corrupt or foreign entry is simply
  /// dropped by [decodeShotList], not raised from here.
  static BasketballShot? decode(Object? raw) {
    if (raw is! List || raw.length < 7) return null;
    double asDouble(Object? v) => v is num ? v.toDouble() : 0;
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    return BasketballShot(
      round: asInt(raw[0]),
      tMs: asInt(raw[1]),
      spawnX: asDouble(raw[2]),
      aim: asDouble(raw[3]).clamp(-1.0, 1.0).toDouble(),
      made: raw[4] == true,
      points: asInt(raw[5]),
      ballIndex: asInt(raw[6]),
    );
  }
}

/// Encodes a whole shot log for one player's move.
List<List<Object?>> encodeShotList(List<BasketballShot> shots) =>
    [for (final s in shots) s.encode()];

/// Decodes a shot log defensively: anything that isn't a list of decodable
/// entries becomes an empty list rather than throwing, so a corrupt or
/// LEGACY (pre-shot-log) payload degrades to "no shot log" — which
/// [BasketballRoundReplay] handles by falling back to a plain score reveal —
/// instead of crashing the reducer.
List<BasketballShot> decodeShotList(Object? raw) {
  if (raw is! List) return const [];
  final out = <BasketballShot>[];
  for (final entry in raw) {
    final shot = BasketballShot.decode(entry);
    if (shot != null) out.add(shot);
  }
  return out;
}
