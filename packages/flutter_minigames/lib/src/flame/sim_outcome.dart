/// The serializable result of one settled simulation run.
///
/// This is the *outcome* half of the "simulate-locally, serialize-the-outcome"
/// seam: the shooter runs the physics to rest and captures where every body
/// ended up. A game layer turns this into its own move. The harness reports
/// **world (simulation) coordinates** — the game is responsible for mapping
/// them into whatever normalized/table space its state uses.
library;

/// The resting pose of a single dynamic body once the sim has settled.
class SettledBody {
  /// The id the body was added with ([TableSimulation.addDisc]).
  final String id;

  /// World-space position at rest (or last-known position if [removed]).
  final double x;
  final double y;

  /// World-space rotation at rest, in radians.
  final double angle;

  /// True when the body left the playfield during the run (e.g. slid off an
  /// open end) and was removed from the sim. [x]/[y] hold its last position.
  final bool removed;

  const SettledBody({
    required this.id,
    required this.x,
    required this.y,
    required this.angle,
    this.removed = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'angle': angle,
        'removed': removed,
      };

  factory SettledBody.fromJson(Map<String, dynamic> json) => SettledBody(
        id: json['id'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        angle: (json['angle'] as num).toDouble(),
        removed: json['removed'] as bool? ?? false,
      );

  @override
  String toString() =>
      'SettledBody($id, ${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}'
      '${removed ? ', removed' : ''})';
}

/// The full settled state of a simulation run: every body's resting pose plus
/// how the run terminated.
class SimOutcome {
  /// Every body that was in the sim when it settled, in insertion order.
  final List<SettledBody> bodies;

  /// Number of fixed steps the run took to settle.
  final int steps;

  /// True when the run hit its hard step budget instead of coming to rest.
  /// Positions are still reported — treat them as the best available snapshot.
  final bool timedOut;

  const SimOutcome({
    required this.bodies,
    required this.steps,
    this.timedOut = false,
  });

  /// The settled body with [id], or null if it was never added.
  SettledBody? operator [](String id) {
    for (final b in bodies) {
      if (b.id == id) return b;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'bodies': [for (final b in bodies) b.toJson()],
        'steps': steps,
        'timedOut': timedOut,
      };

  factory SimOutcome.fromJson(Map<String, dynamic> json) => SimOutcome(
        bodies: [
          for (final b in (json['bodies'] as List))
            SettledBody.fromJson(Map<String, dynamic>.from(b as Map)),
        ],
        steps: json['steps'] as int? ?? 0,
        timedOut: json['timedOut'] as bool? ?? false,
      );
}
