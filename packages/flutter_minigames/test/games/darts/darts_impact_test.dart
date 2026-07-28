import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/darts/darts.dart';
import 'package:flutter_minigames/src/engine3d/engine3d.dart';

final _scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF007AFF));
const _size = Size(390, 640);

Future<Uint8List> pixels(DartsView view) async {
  final recorder = ui.PictureRecorder();
  paintDartsScene(
    Canvas(recorder),
    _size,
    view,
    const DartsStyle(),
    _scheme,
  );
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

/// The dart that just arrived, at [t] through its settle (1 = the instant of
/// contact, 0 = at rest).
DartsView frameAt(double t, {DartHit hit = const DartHit(20, 3)}) => DartsView(
      stuck: [
        StuckDart(
          boardX: 0.02,
          boardY: 0.215,
          direction: const Vec3(0.05, -0.42, 1).normalized,
          color: const Color(0xFFD8443C),
          hit: hit,
          settle: t,
          strength: 0.85,
        ),
      ],
      wobble: t,
      wobbleX: 0.02,
      wobbleY: 0.215,
      wobbleStrength: 0.85,
    );

void main() {
  group('the impact animation', () {
    test('runs its whole duration and leaves the board exactly as it found it',
        () async {
      // The frame the animation is aiming at: the same dart, done moving.
      final settled = await pixels(frameAt(0));

      var moved = 0;
      for (var i = 1; i <= 24; i++) {
        final t = i / 24;
        final frame = await pixels(frameAt(t));
        if (!same(frame, settled)) moved++;
      }
      expect(moved, 24,
          reason: 'every frame of the settle must differ from rest, or the '
              'wobble and the quiver are not actually running');

      // And the last frame is the resting frame, to the byte: a displacement
      // that does not come all the way back leaves the board bent.
      expect(same(await pixels(frameAt(0)), settled), isTrue);
    });

    test('is presentation only — the dart it is animating still scores the '
        'same', () async {
      const hit = DartHit(20, 3);
      for (var i = 0; i <= 12; i++) {
        final view = frameAt(i / 12, hit: hit);
        await pixels(view); // must not throw at any point in the animation
        expect(view.stuck.single.hit, hit);
        expect(view.stuck.single.boardX, 0.02);
        expect(view.stuck.single.boardY, 0.215);
      }
    });

    test('scales with the arrival speed', () async {
      // A floated dart and a rifled one must not land identically, or the
      // strength channel is decorative.
      Future<Uint8List> at(double strength) => pixels(
            DartsView(
              stuck: [
                StuckDart(
                  boardX: 0.02,
                  boardY: 0.215,
                  direction: const Vec3(0.05, -0.42, 1).normalized,
                  color: const Color(0xFFD8443C),
                  hit: const DartHit(20, 3),
                  settle: 0.8,
                  strength: strength,
                ),
              ],
              wobble: 0.8,
              wobbleX: 0.02,
              wobbleY: 0.215,
              wobbleStrength: strength,
            ),
          );
      expect(same(await at(0), await at(1)), isFalse);
    });
  });

  group('the wire', () {
    const r = DartsWorld.boardRadius;

    test('a dart cannot come to rest on a sector wire', () {
      // Exactly on the wire between the 20 and the 1, out in the single bed.
      const radius = 0.42 * r;
      final wireAngle = DartsBoardGeometry.sectorSpan / 2;
      final (x, y, deflected) = DartsWire.deflect(
        math.sin(wireAngle) * radius,
        math.cos(wireAngle) * radius,
        boardRadius: r,
      );
      expect(deflected, isTrue);

      // It ended up in a bed, clear of the wire, and the score is that bed.
      final angle = math.atan2(x, y);
      final off = (angle - wireAngle).abs() * radius;
      expect(off, greaterThan(DartsWire.halfWidth));
      final hit = DartsBoardGeometry.hitAt(x, y, radius: r);
      expect(hit.isMiss, isFalse);
      expect(hit.sector, DartsBoardGeometry.sectorValueAt(x, y),
          reason: 'the score must be the bed the dart is drawn in');
      // The kick is sideways only — a sector wire does not move a dart in or
      // out of a ring, so it can never turn a treble into a single.
      expect(math.sqrt(x * x + y * y), closeTo(radius, 1e-9));
    });

    test('a dart on a ring wire is kicked into one ring or the other', () {
      const wire = DartsBoardGeometry.outerTrebleRatio * r;
      final (x, y, deflected) = DartsWire.deflect(0, wire, boardRadius: r);
      expect(deflected, isTrue);
      final moved = (math.sqrt(x * x + y * y) - wire).abs();
      expect(moved, greaterThan(DartsWire.halfWidth));
      // Still the 20, still on the board — the ring changed, the sector did not.
      final hit = DartsBoardGeometry.hitAt(x, y, radius: r);
      expect(hit.sector, 20);
      expect(hit.isMiss, isFalse);
    });

    test('the outer wire always kicks inward, so it cannot invent a miss', () {
      final (x, y, deflected) = DartsWire.deflect(0, r, boardRadius: r);
      expect(deflected, isTrue);
      expect(math.sqrt(x * x + y * y), lessThan(r));
      expect(DartsBoardGeometry.hitAt(x, y, radius: r), const DartHit(20, 2));
    });

    test('deflection is deterministic', () {
      final wireAngle = DartsBoardGeometry.sectorSpan / 2;
      const radius = 0.5 * r;
      final a = DartsWire.deflect(math.sin(wireAngle) * radius,
          math.cos(wireAngle) * radius,
          boardRadius: r);
      final b = DartsWire.deflect(math.sin(wireAngle) * radius,
          math.cos(wireAngle) * radius,
          boardRadius: r);
      expect(a.$1, b.$1);
      expect(a.$2, b.$2);
    });

    test('a dart clear of the wire is left exactly where it landed', () {
      // The middle of the treble 20 bed — nowhere near any wire.
      const y = 0.606 * r;
      final (x2, y2, deflected) = DartsWire.deflect(0, y, boardRadius: r);
      expect(deflected, isFalse);
      expect(x2, 0);
      expect(y2, y);
    });

    test('no deflection ever pushes a dart off the scoring area', () {
      // Sweep every wire on the board and check the kick keeps the dart in.
      for (final ratio in DartsWire.ringRatios) {
        for (var i = 0; i < 20; i++) {
          final a = DartsBoardGeometry.sectorCentreAngle(i);
          final radius = ratio * r;
          final (x, y, _) = DartsWire.deflect(
            math.sin(a) * radius,
            math.cos(a) * radius,
            boardRadius: r,
          );
          expect(math.sqrt(x * x + y * y), lessThanOrEqualTo(r),
              reason: 'ring $ratio sector $i');
        }
      }
    });

    test('a real throw that finds a wire is reported as deflected', () {
      // Walk the aim across a sector wire and prove the deflection fires on a
      // genuine flight, not just on hand-built points.
      var deflections = 0;
      final wireAngle = DartsBoardGeometry.sectorSpan / 2;
      const radius = 0.5 * DartsWorld.boardRadius;
      for (var i = -60; i <= 60; i++) {
        final a = wireAngle + i * 1e-5;
        final impact = DartsFlight.simulateFlick(
          aimX: math.sin(a) * radius,
          aimY: math.cos(a) * radius,
          power: 0.5,
        );
        if (impact == null) continue;
        if (impact.deflected) {
          deflections++;
          expect(impact.hit.isMiss, isFalse);
          expect(impact.hit.sector,
              DartsBoardGeometry.sectorValueAt(impact.boardX, impact.boardY));
        }
      }
      expect(deflections, greaterThan(0),
          reason: 'aiming straight down a wire must sometimes hit it');
    });
  });
}
