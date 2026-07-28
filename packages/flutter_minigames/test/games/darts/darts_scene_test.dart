import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/darts/darts.dart';
import 'package:flutter_minigames/src/engine3d/engine3d.dart';

final _scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF007AFF));

/// Rasterise the scene and hand back the pixels, so the tests can assert on
/// what actually got drawn rather than on the fact that nothing threw.
Future<ui.Image> render(DartsView view, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paintDartsScene(canvas, size, view, const DartsStyle(), _scheme);
  return recorder
      .endRecording()
      .toImage(size.width.round(), size.height.round());
}

Future<Color Function(double bx, double by)> boardSampler(
  DartsView view,
  Size size,
) async {
  final image = await render(view, size);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
      .buffer
      .asUint8List();
  final camera = DartsCamera.forSize(size);
  return (double bx, double by) {
    final p = camera.project(DartsWorld.boardPoint(bx, by));
    final i = (p.screen.dy.round() * image.width + p.screen.dx.round()) * 4;
    return Color.fromARGB(255, data[i], data[i + 1], data[i + 2]);
  };
}

/// Rough colour identity — the scene applies a lighting wash over the board.
String family(Color c) {
  final r = c.r, g = c.g, b = c.b;
  final maxC = math.max(r, math.max(g, b));
  final minC = math.min(r, math.min(g, b));
  if (maxC < 0.18) return 'black';
  if (minC > 0.6) return 'cream';
  if (r > g + 0.12 && r > b + 0.12) return 'red';
  if (g > r + 0.08 && g > b + 0.05) return 'green';
  if (maxC - minC < 0.12) return 'cream';
  return 'other';
}

void main() {
  const size = Size(390, 600);

  group('camera', () {
    test('the board sits inside the frame with floor showing below it', () {
      final camera = DartsCamera.forSize(size);
      final centre =
          camera.project(Vec3(0, DartsWorld.boardCentreY, DartsWorld.boardZ));
      expect(centre.visible, isTrue);
      final radiusPx = DartsWorld.surroundRadius * centre.scale;
      expect(centre.screen.dy - radiusPx, greaterThan(0),
          reason: 'the surround must not run off the top of the frame');
      expect(centre.screen.dy + radiusPx, lessThan(size.height * 0.75));
      // The board reads big enough to aim at: ~40 % of the frame height.
      final diameter = 2 * DartsWorld.boardRadius * centre.scale;
      expect(diameter / size.height, greaterThan(0.3));
      expect(diameter / size.height, lessThan(0.55));
    });

    test('the horizon sits below the bull and above the floor line', () {
      final camera = DartsCamera.forSize(size);
      final centre =
          camera.project(Vec3(0, DartsWorld.boardCentreY, DartsWorld.boardZ));
      final junction =
          camera.project(Vec3(0, DartsWorld.floorY, DartsWorld.wallZ));
      expect(camera.horizonY, greaterThan(centre.screen.dy));
      expect(camera.horizonY, lessThan(junction.screen.dy));
      expect(junction.screen.dy, lessThan(size.height),
          reason: 'the wall/floor junction must be on screen — it is the '
              'depth cue the room is built around');
    });

    test('screenToBoard inverts project', () {
      final camera = DartsCamera.forSize(size);
      for (final point in const [(0.0, 0.0), (0.2, 0.15), (-0.25, -0.2)]) {
        final screen =
            camera.project(DartsWorld.boardPoint(point.$1, point.$2)).screen;
        final back = DartsCamera.screenToBoard(camera, screen)!;
        expect(back.dx, closeTo(point.$1, 1e-6));
        expect(back.dy, closeTo(point.$2, 1e-6));
      }
    });

    test('a tap above the horizon still resolves onto the board plane', () {
      final camera = DartsCamera.forSize(size);
      expect(
          DartsCamera.screenToBoard(camera, const Offset(195, 10)), isNotNull);
      expect(
          DartsCamera.screenToBoard(camera, const Offset(10, 580)), isNotNull);
    });
  });

  group('board art', () {
    test('the beds and rings are painted where the scorer says they are',
        () async {
      final sample = await boardSampler(const DartsView(), size);
      const r = DartsWorld.boardRadius;
      // 20 is a black bed with red rings; 6 and 11 are cream with green.
      expect(family(sample(0, 0.40 * r)), 'black');
      expect(family(sample(0, 0.606 * r)), 'red', reason: 'treble 20');
      expect(family(sample(0, 0.976 * r)), 'red', reason: 'double 20');
      expect(family(sample(0.606 * r, 0)), 'green', reason: 'treble 6');
      expect(family(sample(-0.606 * r, 0)), 'green', reason: 'treble 11');
      expect(family(sample(0, -0.606 * r)), 'red', reason: 'treble 3');
      // The bull is red inside green.
      expect(family(sample(0, 0)), 'red');
      expect(family(sample(0, 0.065 * r)), 'green');
    });

    test('the art agrees with the scorer on every sector', () async {
      final sample = await boardSampler(const DartsView(), size);
      for (var i = 0; i < 20; i++) {
        final a = DartsBoardGeometry.sectorCentreAngle(i);
        const treble = 0.606 * DartsWorld.boardRadius;
        final x = math.sin(a) * treble;
        final y = math.cos(a) * treble;
        final hit =
            DartsBoardGeometry.hitAt(x, y, radius: DartsWorld.boardRadius);
        expect(hit.multiplier, 3, reason: 'sector $i treble');
        // Dark beds carry red rings, cream beds green — a real board's rule.
        expect(family(sample(x, y)), i.isEven ? 'red' : 'green',
            reason: 'sector ${DartsBoardGeometry.sectorOrder[i]}');
      }
    });
  });

  group('swipe feedback', () {
    /// Raw pixels, so "did anything get drawn here" is answerable.
    Future<Uint8List> pixels(DartsView view) async {
      final image = await render(view, size);
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
    }

    final camera = DartsCamera.forSize(size);

    /// Every pixel index the board face and its surround cover, on a polar
    /// grid dense enough that a marker a few pixels across cannot slip through.
    final boardPixels = <int>{};
    for (var ri = 0; ri <= 48; ri++) {
      final radius = DartsWorld.surroundRadius * ri / 48;
      for (var ai = 0; ai < 180; ai++) {
        final a = 2 * math.pi * ai / 180;
        final p = camera.project(
          DartsWorld.boardPoint(math.sin(a) * radius, math.cos(a) * radius),
        );
        if (!p.visible) continue;
        final x = p.screen.dx.round(), y = p.screen.dy.round();
        if (x < 0 || y < 0 || x >= size.width || y >= size.height) continue;
        boardPixels.add((y * size.width.round() + x) * 4);
      }
    }

    /// Pixel indices where [a] and [b] differ in colour.
    Set<int> diff(Uint8List a, Uint8List b) {
      final out = <int>{};
      for (var i = 0; i < a.length; i += 4) {
        if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
          out.add(i);
        }
      }
      return out;
    }

    // A swipe that stays entirely below the board: origin low, thumb still on
    // the floor band. Any change at all on the board face is therefore
    // something board-anchored, which is exactly what must not exist.
    const swiping = DartsView(
      swipeFrom: Offset(195, 600),
      swipeTo: Offset(232, 452),
      power: 0.66,
    );

    test('nothing is ever drawn on the board face — at rest OR mid-swipe',
        () async {
      final rest = await pixels(const DartsView());
      final live = await pixels(swiping);
      final changed = diff(rest, live);

      // 1. The board face is byte-identical between the two.
      final onBoard = changed.intersection(boardPixels);
      expect(onBoard, isEmpty,
          reason: 'a swipe must not mark the board: no reticle, no landing '
              'prediction, no ghost — the only thing that lands on a dartboard '
              'is a dart');

      // 2. And the swipe is visible somewhere, or the check above is vacuous.
      expect(changed.length, greaterThan(1200),
          reason: 'the arrow and the power bar must be drawn');

      // 3. Every changed pixel is below the bottom of the surround — the
      //    feedback lives with the gesture, not on the target.
      final bottom = camera
          .project(DartsWorld.boardPoint(0, -DartsWorld.surroundRadius))
          .screen
          .dy;
      final highest =
          changed.map((i) => (i ~/ 4) ~/ size.width.round()).reduce(math.min);
      expect(highest, greaterThan(bottom),
          reason: 'feedback strayed up onto the board');
    });

    test('the board-face check has teeth: a stuck dart does trip it', () async {
      // The control for the test above. A dart in the board is a *result*, not
      // an aiming aid, so it is allowed — and it proves the polar sample grid
      // would catch anything drawn on the face.
      final rest = await pixels(const DartsView());
      final withDart = await pixels(
        DartsView(
          stuck: [
            StuckDart(
              boardX: 0,
              boardY: 0.12,
              direction: const Vec3(0, -0.3, 1).normalized,
              color: const Color(0xFFD8443C),
              hit: const DartHit(20, 1),
            ),
          ],
        ),
      );
      expect(diff(rest, withDart).intersection(boardPixels), isNotEmpty);
    });

    test('at rest the bull and its surroundings are plain board', () async {
      // Belt and braces on the pixel diff, in board coordinates: the old
      // reticle drew a white ring 0.042 m out from the bull with ticks reaching
      // 0.08 m. Those points are plain bed colour now — black in the 20 above
      // the bull, cream in the 6 beside it.
      final sample = await boardSampler(const DartsView(), size);
      const r = DartsWorld.boardRadius;
      expect(family(sample(0, 0)), 'red', reason: 'the bull, uncovered');
      expect(family(sample(0, 0.042)), 'black');
      expect(family(sample(0, 0.080)), 'black');
      expect(family(sample(0.042, 0)), 'cream');
      expect(family(sample(0.080, 0)), 'cream');
      expect(family(sample(0, 0.606 * r)), 'red', reason: 'treble 20 clear');
    });
  });

  group('painting', () {
    test('every scene state paints without throwing, at any size', () {
      final states = <DartsView>[
        const DartsView(),
        // A swipe barely past the dead zone.
        const DartsView(
          swipeFrom: Offset(180, 520),
          swipeTo: Offset(196, 480),
          power: 0.2,
        ),
        DartsView(
          swipeFrom: const Offset(180, 520),
          swipeTo: const Offset(230, 300),
          power: 0.7,
          wobble: 0.6,
          wobbleX: 0.1,
          wobbleY: 0.1,
          stuck: [
            StuckDart(
              boardX: 0,
              boardY: 0.2,
              direction: const Vec3(0, -0.3, 1).normalized,
              color: const Color(0xFFD8443C),
              hit: const DartHit(20, 3),
            ),
          ],
          dartPosition: const Vec3(0.05, 1.1, 1.4),
          dartVelocity: const Vec3(0.1, -1, 5),
        ),
      ];
      for (final view in states) {
        for (final size in const [
          Size(390, 600),
          Size(320, 400),
          Size(700, 300),
          Size(1, 1),
          Size.zero,
        ]) {
          final recorder = ui.PictureRecorder();
          paintDartsScene(
            Canvas(recorder),
            size,
            view,
            const DartsStyle(),
            _scheme,
          );
          recorder.endRecording();
        }
      }
    });

    test('a dart way off-screen does not blow up the painter', () {
      final recorder = ui.PictureRecorder();
      paintDartsScene(
        Canvas(recorder),
        size,
        const DartsView(
          dartPosition: Vec3(0, 0.5, -50),
          dartVelocity: Vec3(0, 0, 1),
        ),
        const DartsStyle(),
        _scheme,
      );
      recorder.endRecording();
    });
  });
}
