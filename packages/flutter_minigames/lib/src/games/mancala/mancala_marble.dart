import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Tumbled sea-glass pebbles.
///
/// The old stone was a squashed ellipse under a three-colour ramp: a bead, not
/// an object. This is a real lit form — every sample point carries a surface
/// normal and the colour there is evaluated from that normal against one
/// committed light ([kBoardLight]).
///
/// The material is deliberately **not** a polished marble. Sea glass has been
/// rolled in surf for decades: the surface is frosted, so it has no mirror
/// highlight at all — just a broad low-contrast sheen. The body is cloudy
/// rather than clear, and because the piece is thin at its edges, light leaks
/// *through* the rim and it glows there. The silhouette is a worn pebble, not a
/// circle: subtly asymmetric, a little flattened, different in every piece.
///
/// ## How it is drawn
///
/// The shading runs over a polar mesh and is handed to `Canvas.drawVertices` so
/// the GPU interpolates it, which keeps the terminator, the edge glow and the
/// internal cloud genuinely position-dependent instead of a stack of
/// hand-placed blobs. The frosting is a deterministic stipple drawn on top.
///
/// Everything is recorded once per (material, shape) into a [ui.Picture] at a
/// reference radius, then replayed under a scale. A `Picture` is a command
/// list, not a bitmap, so one recording serves every size on screen at full
/// resolution and the per-frame cost is a transform plus a replay.

/// The single light for the whole board: a soft key from the upper left,
/// slightly in front of the viewer. Screen-space direction (x right, y down),
/// with z toward the viewer supplied by [_lightZ].
const Offset kBoardLight = Offset(-0.38, -0.45);
const double _lightZ = 0.82;

/// Bounce/fill from the wood the pebble sits in: up from the lower right, warm.
const Offset _kBounce = Offset(0.42, 0.60);
const double _bounceZ = 0.35;
const Color _woodBounce = Color(0xFFD8B074);

/// Cool sky fill from above.
const Color _skyFill = Color(0xFFA9C2D8);

// --- mesh resolution -------------------------------------------------------
const int _rings = 20;
const int _sectors = 44;

/// Radius the picture is recorded at. Replayed under `scale(r / _refR)`, so it
/// only sets the numeric range the recorded geometry lives in.
const double _refR = 64;

/// How squat the pebble is: the fraction of its half-width it stands proud by.
/// Well under 1 — a tumbled stone is a flattened dome, and this is what stops
/// the shading reading as a ball.
const double _thickness = 0.72;

/// The original three-colour set: cool white, charcoal, azure.
///
/// The *form* stays a tumbled sea-glass pebble — frosted, matte, worn — but the
/// palette is the high-contrast trio, not muted sea tones. Three strongly
/// separated colours read at a glance in a pit of eight; a soft four-way spread
/// of greens and blues does not, and telling the pieces apart is how you count.
enum MarbleMaterial {
  /// Cool near-white.
  white,

  /// Charcoal, almost black.
  black,

  /// Medium azure.
  blue,
}

/// A pebble instance: which glass, and which tumbled shape.
class MarbleSpec {
  final MarbleMaterial material;

  /// 0..[shapeCount] — picks the worn silhouette and internal cloud.
  final int variant;

  /// Radius multiplier — no two beach pebbles are the same size.
  final double sizeMul;

  const MarbleSpec({
    required this.material,
    required this.variant,
    required this.sizeMul,
  });

  static const shapeCount = 6;

  /// Stable pebble for a cup slot. Material is interleaved across cups with
  /// coprime steps so both board sides get an even mix rather than hash clumps.
  factory MarbleSpec.at({required int cup, required int slot, int salt = 0}) {
    final material = MarbleMaterial
        .values[(cup * 3 + slot * 5 + salt) % MarbleMaterial.values.length];
    var s = (cup * 73856093) ^ (slot * 19349663) ^ (salt * 83492791);
    s &= 0x7fffffff;
    s ^= s >> 13;
    return MarbleSpec(
      material: material,
      variant: (s >> 7) % shapeCount,
      sizeMul: 0.92 + ((s >> 3) % 9) * 0.016,
    );
  }
}

/// Per-material description of the glass.
class _Material {
  /// Diffuse body colour.
  final Color albedo;

  /// Ambient floor, as a fraction of albedo.
  final double ambient;

  /// Diffuse wrap — how far light bleeds past the geometric terminator. High
  /// for every sea glass: the frosted surface scatters in all directions and
  /// the body is translucent, so there is no hard terminator anywhere.
  final double wrap;

  /// Broad frosted sheen: strength and how wide it spreads. Never a hotspot.
  final double sheen;

  /// Light leaking through the thin edge of the piece, and its colour.
  final double edgeGlow;
  final Color glowColor;

  /// Soft light rim where the piece thins out. Sits under the glow.
  final double rim;

  /// Warm bounce off the wood, on the shadow side only.
  final double bounce;

  /// Cool sky fill on the upper half.
  final double sky;

  /// Cloudy internal luminosity — the milkiness inside tumbled glass.
  final double cloud;
  final Color cloudColor;

  /// Strength of the frosting stipple over the body.
  final double frost;

  const _Material({
    required this.albedo,
    required this.ambient,
    required this.wrap,
    required this.sheen,
    required this.edgeGlow,
    required this.glowColor,
    required this.rim,
    required this.bounce,
    required this.sky,
    required this.cloud,
    required this.cloudColor,
    required this.frost,
  });
}

/// Albedos sit below the colour you actually want to see: the lighting terms
/// (ambient, wrap, sky, bounce, glow) all add on top, so the rendered body lands
/// near the original palette — white 0xFFEDEDE8, black 0xFF45454B, blue
/// 0xFF4C7FD9 — while still being a lit form rather than a flat fill.
const _materials = <MarbleMaterial, _Material>{
  MarbleMaterial.white: _Material(
    albedo: Color(0xFFD2D2CE),
    ambient: 0.22,
    wrap: 0.34,
    sheen: 0.10,
    edgeGlow: 0.18,
    glowColor: Color(0xFFFFFDF6),
    rim: 0.11,
    bounce: 0.13,
    sky: 0.10,
    cloud: 0.10,
    cloudColor: Color(0xFFFFFFFF),
    frost: 1.0,
  ),
  // Charcoal has to be handled differently: the same ambient/wrap that flatters
  // a pale stone turns a dark one into mud. Keep the fills low and let the
  // frosting and a slightly stronger rim describe the shape instead.
  MarbleMaterial.black: _Material(
    albedo: Color(0xFF3B3B41),
    ambient: 0.10,
    wrap: 0.20,
    sheen: 0.13,
    edgeGlow: 0.13,
    glowColor: Color(0xFF9C9CA6),
    rim: 0.20,
    bounce: 0.10,
    sky: 0.09,
    cloud: 0.06,
    cloudColor: Color(0xFFB4B4BE),
    frost: 0.85,
  ),
  MarbleMaterial.blue: _Material(
    albedo: Color(0xFF3F6CC2),
    ambient: 0.17,
    wrap: 0.30,
    sheen: 0.11,
    edgeGlow: 0.24,
    glowColor: Color(0xFFBFD6FA),
    rim: 0.13,
    bounce: 0.11,
    sky: 0.12,
    cloud: 0.13,
    cloudColor: Color(0xFFCFE0FB),
    frost: 1.0,
  ),
};

// ---------------------------------------------------------------------------
// Vectors — tiny, local, screen-space (x right, y down, z at viewer).
// ---------------------------------------------------------------------------

class _V3 {
  final double x, y, z;
  const _V3(this.x, this.y, this.z);

  double dot(_V3 o) => x * o.x + y * o.y + z * o.z;

  _V3 get unit {
    final l = math.sqrt(x * x + y * y + z * z);
    return l < 1e-12 ? const _V3(0, 0, 1) : _V3(x / l, y / l, z / l);
  }
}

final _V3 _light = _V3(kBoardLight.dx, kBoardLight.dy, _lightZ).unit;
final _V3 _bounceDir = _V3(_kBounce.dx, _kBounce.dy, _bounceZ).unit;

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

double _smoothstep(double a, double b, double x) {
  final t = _clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
}

/// Deterministic hash in `[0, 1)`.
double _hash(int a, int b) {
  var n = (a * 374761393) ^ (b * 668265263);
  n = (n ^ (n >> 13)) * 1274126177;
  n = n ^ (n >> 16);
  return (n & 0x3fffffff) / 0x3fffffff;
}

/// Accumulator in 0..1 float channels, so terms add without repeated 8-bit
/// rounding.
class _Rgb {
  double r = 0, g = 0, b = 0;

  void addScaled(Color c, double k) {
    if (k <= 0) return;
    // ignore: deprecated_member_use
    r += (c.red / 255) * k;
    // ignore: deprecated_member_use
    g += (c.green / 255) * k;
    // ignore: deprecated_member_use
    b += (c.blue / 255) * k;
  }

  int get argb {
    final ri = (_clamp01(r) * 255).round();
    final gi = (_clamp01(g) * 255).round();
    final bi = (_clamp01(b) * 255).round();
    return 0xFF000000 | (ri << 16) | (gi << 8) | bi;
  }
}

// ---------------------------------------------------------------------------
// The worn silhouette
// ---------------------------------------------------------------------------

/// One tumbled outline: a rotated ellipse with a couple of low harmonics laid
/// over it, plus the blobs that make its internal cloud.
///
/// Harmonics 2 and 3 only. The first harmonic would just translate the shape,
/// and anything above the third stops reading as "worn smooth" and starts
/// reading as "chipped".
class _Shape {
  final double rot;
  final double squash;
  final double a2, p2, a3, p3;
  final List<(double, double, double)> clouds;

  const _Shape({
    required this.rot,
    required this.squash,
    required this.a2,
    required this.p2,
    required this.a3,
    required this.p3,
    required this.clouds,
  });

  double radiusAt(double theta) {
    final t = theta - rot;
    final ct = math.cos(t);
    final st = math.sin(t);
    final ellipse = 1 / math.sqrt(ct * ct + (st * st) / (squash * squash));
    return ellipse * (1 + a2 * math.cos(2 * t + p2) + a3 * math.cos(3 * t + p3));
  }
}

final List<_Shape> _shapes = List.generate(MarbleSpec.shapeCount, (v) {
  return _Shape(
    rot: _hash(v, 1) * math.pi,
    // Flattened, and never quite the same amount twice.
    squash: 0.80 + _hash(v, 2) * 0.14,
    a2: 0.030 + _hash(v, 3) * 0.055,
    p2: _hash(v, 4) * math.pi * 2,
    a3: 0.014 + _hash(v, 5) * 0.032,
    p3: _hash(v, 6) * math.pi * 2,
    clouds: [
      for (var i = 0; i < 3; i++)
        (
          (_hash(v * 7 + i, 11) - 0.5) * 1.05,
          (_hash(v * 7 + i, 13) - 0.5) * 1.05,
          0.12 + _hash(v * 7 + i, 17) * 0.34,
        ),
    ],
  );
});

/// Normalising factor so the widest point of a shape lands at radius 1 — which
/// keeps `paintMarble(centre, radius)` meaning what it says whatever the piece.
final List<double> _shapeNorm = [
  for (final s in _shapes)
    () {
      var m = 0.0;
      for (var i = 0; i < 180; i++) {
        final r = s.radiusAt(2 * math.pi * i / 180);
        if (r > m) m = r;
      }
      return m;
    }()
];

// ---------------------------------------------------------------------------
// The shading model
// ---------------------------------------------------------------------------

/// Colour of the pebble at normalised shape position ([ux], [uy]) — a point on
/// the unit disc, mapped onto the worn outline by the caller — where [u] is its
/// distance from the centre (0 at the crown, 1 at the edge).
int _shade(_Material m, _Shape shape, double ux, double uy, double u) {
  // Surface normal of a squat dome. Dividing the z component by the thickness
  // tips the normals toward the viewer, which broadens the lit crown and
  // crowds the whole falloff into the last of the width — the difference
  // between a pebble and a ball.
  final nzRaw = math.sqrt(math.max(0.0, 1 - u * u)) / _thickness;
  final len = math.sqrt(ux * ux + uy * uy + nzRaw * nzRaw);
  final n = _V3(ux / len, uy / len, nzRaw / len);
  final nz = n.z;

  final ndl = n.dot(_light);
  final out = _Rgb();

  // --- diffuse body ------------------------------------------------------
  // Heavily wrapped: a frosted, translucent stone scatters light right around
  // its own terminator, so there is no hard shadow line anywhere on it.
  final wrapped = _clamp01((ndl + m.wrap) / (1 + m.wrap));
  final diffuse = _smoothstep(-0.05, 1.0, wrapped) * (1 - m.ambient);
  out.addScaled(m.albedo, m.ambient + diffuse);

  // --- cloudy interior ----------------------------------------------------
  // Tumbled glass is milky rather than clear. A few soft blobs of internal
  // scatter, strongest where the piece is thickest, give it depth without
  // giving it a clear core to look into.
  if (m.cloud > 0) {
    var c = 0.0;
    for (final (cx, cy, cr) in shape.clouds) {
      final dx = ux - cx;
      final dy = uy - cy;
      c += math.exp(-(dx * dx + dy * dy) / cr);
    }
    out.addScaled(m.cloudColor, m.cloud * _clamp01(c * 0.6) * nz);
  }

  // --- light through the thin edge ---------------------------------------
  // The piece tapers to almost nothing at its rim, so the light behind and
  // around it comes straight through there. This is the sea-glass tell: it is
  // brightest where it is thinnest, the opposite of a solid marble.
  final thin = math.pow(u, 5.0).toDouble();
  out.addScaled(m.glowColor, m.edgeGlow * thin);
  out.addScaled(m.glowColor, m.rim * math.pow(u, 12.0).toDouble());

  // --- sky fill on the upper half ----------------------------------------
  if (m.sky > 0) {
    out.addScaled(
      _skyFill,
      m.sky * _clamp01(-uy * 0.5 + 0.5) * (0.35 + nz * 0.65),
    );
  }

  // --- wood bounce, shadow side only -------------------------------------
  // What stops a form reading as a flat cut-out: the dark side is not dark,
  // it is picking up the pit it sits in.
  if (m.bounce > 0) {
    final ndb = _clamp01(n.dot(_bounceDir));
    out.addScaled(
      _woodBounce,
      m.bounce * math.pow(ndb, 1.9).toDouble() * (1 - _clamp01(ndl)),
    );
  }

  // --- broad frosted sheen ------------------------------------------------
  // Not a specular. A frosted surface has no mirror direction, so what you get
  // is a wide, weak brightening toward the light with no core to it at all.
  // A `pow()` hotspot here would instantly read as polished glass.
  out.addScaled(Colors.white, m.sheen * math.pow(_clamp01(ndl), 1.6).toDouble());

  return out.argb;
}

// ---------------------------------------------------------------------------
// Mesh — geometry per shape, colours per (material, shape).
// ---------------------------------------------------------------------------

class _Mesh {
  final Float32List positions;
  final Uint16List indices;

  /// Normalised (unit-disc) coordinates and radius per vertex, for the shader.
  final Float32List unit;
  final Float32List radius;

  const _Mesh(this.positions, this.indices, this.unit, this.radius);
}

final Map<int, _Mesh> _meshes = {};

_Mesh _meshFor(int variant) => _meshes.putIfAbsent(variant, () {
      final shape = _shapes[variant];
      final norm = _shapeNorm[variant];
      final vertexCount = 1 + _rings * _sectors;
      final positions = Float32List(vertexCount * 2);
      final unit = Float32List(vertexCount * 2);
      final radius = Float32List(vertexCount);
      final indices = <int>[];

      for (var ring = 1; ring <= _rings; ring++) {
        // sin() crowds rings toward the edge, where the normal swings fastest
        // and a uniform mesh visibly facets the falloff.
        final u = math.sin(math.pi / 2 * (ring / _rings));
        for (var s = 0; s < _sectors; s++) {
          final a = 2 * math.pi * s / _sectors;
          final i = 1 + (ring - 1) * _sectors + s;
          final rr = shape.radiusAt(a) / norm;
          unit[i * 2] = u * math.cos(a);
          unit[i * 2 + 1] = u * math.sin(a);
          radius[i] = u;
          positions[i * 2] = u * rr * math.cos(a) * _refR;
          positions[i * 2 + 1] = u * rr * math.sin(a) * _refR;
        }
      }

      for (var s = 0; s < _sectors; s++) {
        indices.addAll([0, 1 + s, 1 + (s + 1) % _sectors]);
      }
      for (var ring = 1; ring < _rings; ring++) {
        final base = 1 + (ring - 1) * _sectors;
        final next = 1 + ring * _sectors;
        for (var s = 0; s < _sectors; s++) {
          final s2 = (s + 1) % _sectors;
          indices.addAll([base + s, next + s, next + s2]);
          indices.addAll([base + s, next + s2, base + s2]);
        }
      }

      return _Mesh(
        positions,
        Uint16List.fromList(indices),
        unit,
        radius,
      );
    });

/// The worn outline as a closed path, sampled finely enough that the silhouette
/// never shows the mesh's facets.
Path _outline(int variant, {double scale = 1}) {
  final shape = _shapes[variant];
  final norm = _shapeNorm[variant];
  final path = Path();
  const n = 128;
  for (var i = 0; i < n; i++) {
    final a = 2 * math.pi * i / n;
    final r = shape.radiusAt(a) / norm * _refR * scale;
    final p = Offset(math.cos(a) * r, math.sin(a) * r);
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

// ---------------------------------------------------------------------------
// Recorded pebbles
// ---------------------------------------------------------------------------

final Map<int, ui.Picture> _pictures = {};

int _key(MarbleMaterial m, int variant) =>
    m.index * MarbleSpec.shapeCount + (variant % MarbleSpec.shapeCount);

ui.Picture _recordPebble(MarbleMaterial material, int variant) {
  final m = _materials[material]!;
  final shape = _shapes[variant];
  final mesh = _meshFor(variant);

  final n = mesh.radius.length;
  final colors = Int32List(n);
  for (var i = 0; i < n; i++) {
    colors[i] = _shade(
      m,
      shape,
      mesh.unit[i * 2],
      mesh.unit[i * 2 + 1],
      mesh.radius[i],
    );
  }

  final verts = ui.Vertices.raw(
    ui.VertexMode.triangles,
    mesh.positions,
    colors: colors,
    indices: mesh.indices,
  );

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final outline = _outline(variant);

  canvas.save();
  canvas.clipPath(outline, doAntiAlias: true);
  canvas.drawVertices(verts, BlendMode.srcOver, Paint());

  // Frosting. Decades of sand have left the surface finely pitted, and that
  // texture is most of what says "sea glass" rather than "moulded plastic".
  // Two scales: a coarse mottle, then a dense stipple.
  if (m.frost > 0) {
    final mottle = Paint();
    for (var i = 0; i < 26; i++) {
      final a = _hash(variant * 31 + i, 101) * math.pi * 2;
      final rr = math.sqrt(_hash(variant * 31 + i, 103)) * _refR * 0.94;
      final size = _refR * (0.10 + _hash(variant * 31 + i, 107) * 0.16);
      final light = _hash(variant * 31 + i, 109) > 0.42;
      mottle
        ..color = (light ? Colors.white : const Color(0xFF6B6A63))
            .withValues(alpha: (0.035 + _hash(i, 113) * 0.045) * m.frost)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.7);
      canvas.drawCircle(
        Offset(math.cos(a) * rr, math.sin(a) * rr),
        size,
        mottle,
      );
    }
    final pit = Paint();
    for (var i = 0; i < 1500; i++) {
      final a = _hash(variant * 97 + i, 211) * math.pi * 2;
      final rr = math.sqrt(_hash(variant * 97 + i, 223)) * _refR * 0.99;
      final j = _hash(variant * 97 + i, 227);
      // Slightly more dark pits than light ones, and weaker: a frosted
      // surface scatters, it does not sparkle. Balanced energy keeps the
      // stipple from bleaching the body it sits on.
      final light = j > 0.55;
      pit.color = (light ? Colors.white : const Color(0xFF3E3D39))
          .withValues(alpha: (light ? 0.05 + j * 0.07 : 0.05 + j * 0.11) *
              m.frost);
      canvas.drawCircle(
        Offset(math.cos(a) * rr, math.sin(a) * rr),
        _refR * (0.006 + j * 0.013),
        pit,
      );
    }
  }

  // The broad sheen: one wide, soft, low-contrast wash toward the light. No
  // core, no hard edge — deliberately the opposite of a specular highlight.
  final sc = Offset(kBoardLight.dx * _refR * 0.44, kBoardLight.dy * _refR * 0.44);
  canvas.drawCircle(
    sc,
    _refR * 0.66,
    Paint()
      ..shader = ui.Gradient.radial(
        sc,
        _refR * 0.66,
        [
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.045),
          Colors.white.withValues(alpha: 0),
        ],
        const [0.0, 0.45, 1.0],
      )
      ..blendMode = BlendMode.plus,
  );
  canvas.restore();

  // Soft edge, not an outline: a faint light halo just inside the silhouette
  // where the piece thins to nothing, blurred so there is no drawn line.
  canvas.save();
  canvas.clipPath(outline, doAntiAlias: true);
  canvas.drawPath(
    _outline(variant, scale: 0.955),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _refR * 0.075
      ..color = Colors.white.withValues(alpha: 0.10)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, _refR * 0.05),
  );
  canvas.restore();

  return recorder.endRecording();
}

ui.Picture _pebblePicture(MarbleMaterial material, int variant) =>
    _pictures.putIfAbsent(
      _key(material, variant),
      () => _recordPebble(material, variant),
    );

/// Warms the picture cache. Optional — [paintMarble] records on demand — but
/// worth calling once so the first sow does not record a set mid-hop.
void primeMarbles() {
  for (final m in MarbleMaterial.values) {
    for (var v = 0; v < MarbleSpec.shapeCount; v++) {
      _pebblePicture(m, v);
    }
  }
}

/// Paints one pebble of half-width [radius] centred at [centre].
///
/// [occlusion] darkens it where it is buried in a pile (0 = open, 1 = wedged),
/// applied as a soft wash from the crowded side.
void paintMarble(
  Canvas canvas,
  Offset centre,
  double radius,
  MarbleSpec spec, {
  double opacity = 1,
  double occlusion = 0,
  Offset occlusionFrom = Offset.zero,
}) {
  if (radius < 0.4 || opacity <= 0.01) return;
  final variant = spec.variant % MarbleSpec.shapeCount;
  final picture = _pebblePicture(spec.material, variant);

  canvas.save();
  canvas.translate(centre.dx, centre.dy);
  canvas.scale(radius / _refR);
  if (opacity < 1) {
    canvas.saveLayer(
      Rect.fromCircle(center: Offset.zero, radius: _refR * 1.2),
      Paint()..color = Colors.black.withValues(alpha: opacity),
    );
  }
  canvas.drawPicture(picture);

  if (occlusion > 0.01) {
    // Ambient occlusion from neighbours: a soft dark gradient pushed in from
    // the crowded side, clipped to the pebble so it never fringes.
    final dir = occlusionFrom == Offset.zero
        ? const Offset(0, 1)
        : occlusionFrom / occlusionFrom.distance;
    final at = Offset(dir.dx * _refR * 0.95, dir.dy * _refR * 0.95);
    canvas.save();
    canvas.clipPath(_outline(variant), doAntiAlias: true);
    canvas.drawCircle(
      at,
      _refR * 1.10,
      Paint()
        ..shader = ui.Gradient.radial(
          at,
          _refR * 1.10,
          [
            Colors.black.withValues(alpha: 0.44 * occlusion.clamp(0.0, 1.0)),
            Colors.black.withValues(alpha: 0),
          ],
          const [0.0, 1.0],
        ),
    );
    canvas.restore();
  }

  if (opacity < 1) canvas.restore();
  canvas.restore();
}
