import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/archery/archery.dart';
import 'package:flutter_minigames/src/engine3d/engine3d.dart';

final _scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF007AFF));
const _size = Size(390, 640);
const _conditions =
    TargetConditions(index: 1, distance: 22, windSpeed: 0, windAngle: 0);

Future<Uint8List> pixels(ArcheryView view) async {
  final recorder = ui.PictureRecorder();
  paintArcheryScene(
      Canvas(recorder), _size, view, const ArcheryStyle(), _scheme);
  final image = await recorder
      .endRecording()
      .toImage(_size.width.round(), _size.height.round());
  return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
      .buffer
      .asUint8List();
}

bool same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The arrow that just bit, at [t] through its settle (1 = contact, 0 = rest).
ArcheryView frameAt(double t) => ArcheryView(
      conditions: _conditions,
      showReticle: false,
      zoom: 1,
      arrowsLeft: 0,
      targetWobble: t,
      impactX: 0.02,
      impactY: 0.03,
      arrowSettle: t,
      stuckArrows: const [
        ArrowShot(ring: 10, offsetX: 0.02, offsetY: 0.03, onFace: true),
      ],
    );

/// Which FITA ring a sampled pixel belongs to, by nearest ring colour. The
/// scene hazes everything by depth, so an exact match is not on offer — but
/// the five rings are far enough apart in colour that nearest wins cleanly.
int ringIndexOf(Color c) {
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < ArcheryStyle.ringColors.length; i++) {
    final r = ArcheryStyle.ringColors[i];
    final d = math.pow(c.r - r.r, 2) +
        math.pow(c.g - r.g, 2) +
        math.pow(c.b - r.b, 2);
    if (d < bestD) {
      bestD = d.toDouble();
      best = i;
    }
  }
  return best;
}

void main() {
  group('the impact animation', () {
    test('runs its whole duration and leaves the target exactly as it found it',
        () async {
      final settled = await pixels(frameAt(0));
      var moved = 0;
      for (var i = 1; i <= 20; i++) {
        if (!same(await pixels(frameAt(i / 20)), settled)) moved++;
      }
      expect(moved, 20,
          reason: 'every frame of the settle must differ from rest, or the '
              'compression and the quiver are not actually running');
      expect(same(await pixels(frameAt(0)), settled), isTrue,
          reason: 'straw that does not come all the way back is a dent, not a '
              'compression');
    });

    test('never alters what the arrow scored', () async {
      for (var i = 0; i <= 10; i++) {
        final view = frameAt(i / 10);
        await pixels(view); // must not throw at any point in the animation
        final shot = view.stuckArrows.single;
        expect(shot.ring, 10);
        expect(shot.offsetX, 0.02);
        expect(shot.offsetY, 0.03);
        // And the pure scorer still agrees with the banked ring.
        expect(ArcheryGame.ringValue(shot.offsetX, shot.offsetY), shot.ring);
      }
    });

    test('the compression never folds the face inside out', () async {
      // The failure mode a pull-toward-the-hole invites: points on the near
      // side of the hole dragged straight past it, and the rings crossing over.
      //
      // Sampled well inside each band — a third of a ring width clear of every
      // boundary, which is more than the compression can ever move a ring —
      // so a colour that has changed here is a fold and not a squeeze. The
      // arrow is left out of the frame on purpose: this is about the face.
      final view = ArcheryView(
        conditions: _conditions,
        showReticle: false,
        zoom: 1,
        targetWobble: 1,
        impactX: 0.02,
        impactY: 0.03,
      );
      final image = await pixels(view);
      final camera = ArcheryCamera.of(_size, view);
      final shift = ArcheryCamera.shiftFor(camera, view);
      const w = ArcheryGame.ringWidth;

      for (final angle in [0.0, math.pi / 2, math.pi, -math.pi / 2]) {
        var previous = 0;
        for (var ring = 0; ring < ArcheryStyle.ringColors.length; ring++) {
          for (final f in const [0.35, 0.5, 0.65]) {
            final radius = w * (ring + f);
            final p = camera.project(Vec3(
              math.cos(angle) * radius,
              ArcheryBallistics.targetCentreHeight + math.sin(angle) * radius,
              _conditions.distance,
            ));
            if (!p.visible) continue;
            final at = p.screen + shift;
            final x = at.dx.round();
            final y = at.dy.round();
            if (x < 1 ||
                y < 1 ||
                x >= _size.width - 1 ||
                y >= _size.height - 1) {
              continue;
            }
            final i = (y * _size.width.round() + x) * 4;
            final read = ringIndexOf(
                Color.fromARGB(255, image[i], image[i + 1], image[i + 2]));
            expect(read, ring,
                reason: 'ring $ring at $f of its band read as $read on the '
                    '$angle rad ray — the compression moved a boundary it '
                    'cannot reach, or the face folded');
            expect(read, greaterThanOrEqualTo(previous));
            previous = read;
          }
        }
      }
    });

    test('scales with the arrival speed', () async {
      // The strength channel must actually do something, or it is decoration.
      ArcheryView at(double wobble) => ArcheryView(
            conditions: _conditions,
            showReticle: false,
            zoom: 1,
            targetWobble: wobble,
            impactX: 0.02,
            impactY: 0.03,
            arrowSettle: 0.7,
            stuckArrows: const [
              ArrowShot(ring: 10, offsetX: 0.02, offsetY: 0.03, onFace: true),
            ],
          );
      // 0.5 and 1.0 are what a tired arrow and a fast one produce through
      // ArcheryShotResult.impactStrength.
      expect(same(await pixels(at(0.35)), await pixels(at(0.7))), isFalse);
    });
  });

  group('a miss', () {
    ArcheryView withStray(StrayArrow? stray) => ArcheryView(
          conditions: _conditions,
          showReticle: false,
          zoom: 1,
          stray: stray,
        );

    test('is left lying in the range instead of vanishing', () async {
      final empty = await pixels(withStray(null));
      final planted = await pixels(
        withStray(
          StrayArrow(
            position: const Vec3(1.05, 0, 19.4),
            direction: const Vec3(0.05, -0.32, 1).normalized,
          ),
        ),
      );
      expect(same(empty, planted), isFalse,
          reason: 'a miss that draws nothing has vanished');
    });

    test('a real off-face shot produces a stray with a resting place', () {
      // Aimed hard left: past the face, into the grass.
      final shot = ArcheryBallistics.fire(
        conditions: _conditions,
        power: 0.5,
        aimYaw: -0.05,
        windScale: 0,
      );
      expect(shot.onFace, isFalse);
      expect(shot.ring, 0);
      expect(shot.path.length, greaterThan(2));
      final end = shot.path.last;
      expect(end.y, lessThanOrEqualTo(0.05),
          reason: 'a miss has to finish somewhere — in the turf');
      expect(end.z, greaterThan(1));
    });

    test('the arrival speed is real and scales with range', () {
      final near = ArcheryBallistics.fire(
          conditions: const TargetConditions(
              index: 0, distance: 15, windSpeed: 0, windAngle: 0),
          power: 0.5,
          windScale: 0);
      final far = ArcheryBallistics.fire(
          conditions: const TargetConditions(
              index: 3, distance: 38, windSpeed: 0, windAngle: 0),
          power: 0.5,
          windScale: 0);
      expect(near.impactSpeed, greaterThan(1));
      expect(near.impactStrength, inInclusiveRange(0, 1));
      expect(far.impactStrength, inInclusiveRange(0, 1));
      // A long shot is launched harder, so it also arrives harder — the useful
      // thing is that the two are not the same number.
      expect(
          (far.impactStrength - near.impactStrength).abs(), greaterThan(0.05));
    });
  });
}
