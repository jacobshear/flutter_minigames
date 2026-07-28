import 'dart:ui' show Canvas;

import 'camera3.dart';
import 'vec3.dart';

/// One drawable anchored at a world position.
class DepthItem {
  /// World position used for depth sorting.
  final Vec3 anchor;

  /// Draws the item, given the projection of its [anchor].
  final void Function(Canvas canvas, Projected at) draw;

  const DepthItem({required this.anchor, required this.draw});
}

/// Collects drawables and paints them back-to-front (the painter's algorithm).
///
/// There is no depth buffer available to `Canvas`, so correct occlusion comes
/// from draw order alone: furthest first. Sorting by the anchor's camera-space
/// depth is exact for well-separated props (a rack of cups, balls on a floor).
///
/// Where two pieces of one object straddle the ball — a hoop's near and far rim
/// — split them into separate items with their own anchors so they sort around
/// the ball individually, instead of the whole hoop landing on one side of it.
class Scene3 {
  final Camera3 camera;
  final List<DepthItem> _items = [];

  Scene3(this.camera);

  void add(Vec3 anchor, void Function(Canvas canvas, Projected at) draw) =>
      _items.add(DepthItem(anchor: anchor, draw: draw));

  /// Number of queued drawables.
  int get length => _items.length;

  void clear() => _items.clear();

  /// The queued items in paint order (furthest first).
  List<DepthItem> get sorted {
    final withDepth = <(DepthItem, Projected)>[
      for (final it in _items) (it, camera.project(it.anchor)),
    ];
    withDepth.removeWhere((e) => !e.$2.visible);
    withDepth.sort((a, b) => b.$2.depth.compareTo(a.$2.depth));
    return [for (final e in withDepth) e.$1];
  }

  /// Paint everything, furthest first. Items behind the camera are skipped.
  void paint(Canvas canvas) {
    final withDepth = <(DepthItem, Projected)>[
      for (final it in _items) (it, camera.project(it.anchor)),
    ];
    withDepth.removeWhere((e) => !e.$2.visible);
    withDepth.sort((a, b) => b.$2.depth.compareTo(a.$2.depth));
    for (final (item, at) in withDepth) {
      item.draw(canvas, at);
    }
  }
}
