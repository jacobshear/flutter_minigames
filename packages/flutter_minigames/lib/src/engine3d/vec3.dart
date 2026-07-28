import 'dart:math' as math;

/// An immutable 3-D vector in world space.
///
/// World convention used across this package:
/// * **+x** — right (lateral)
/// * **+y** — up
/// * **+z** — away from the viewer, down-range (depth)
///
/// Note this is *not* screen space: screen y grows downward, and [Camera3]
/// flips it during projection. Keeping world-y up means gravity is simply
/// negative y and throw arcs read naturally.
class Vec3 {
  final double x;
  final double y;
  final double z;

  const Vec3(this.x, this.y, this.z);

  static const zero = Vec3(0, 0, 0);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator -() => Vec3(-x, -y, -z);

  double get lengthSquared => x * x + y * y + z * z;
  double get length => math.sqrt(lengthSquared);

  /// Horizontal (xz-plane) speed — the component gravity never touches.
  double get horizontalLength => math.sqrt(x * x + z * z);

  Vec3 get normalized {
    final l = length;
    return l < 1e-12 ? zero : Vec3(x / l, y / l, z / l);
  }

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 copyWith({double? x, double? y, double? z}) =>
      Vec3(x ?? this.x, y ?? this.y, z ?? this.z);

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'z': z};

  static Vec3 fromJson(Map<String, dynamic> j) => Vec3(
        (j['x'] as num).toDouble(),
        (j['y'] as num).toDouble(),
        (j['z'] as num).toDouble(),
      );

  @override
  String toString() => 'Vec3(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, '
      '${z.toStringAsFixed(3)})';

  @override
  bool operator ==(Object other) =>
      other is Vec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);
}
