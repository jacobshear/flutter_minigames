import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_cup_pong/minigame_cup_pong.dart';
import 'package:minigames_3d/minigames_3d.dart';

const _size = Size(340, 470);
final _scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF007AFF));

CupPongView _viewOf({BallView? ball, AimView? aim, int count = 10}) {
  final cups = CupPongGame.rackFor([for (var i = 0; i < count; i++) i]);
  return CupPongView(
    cups: [
      for (final c in cups)
        CupView(
          id: c.id,
          mouth: CupPongWorld.mouthOf(c),
          mouthRadius: CupPongWorld.cupMouthRadius,
          baseRadius: CupPongWorld.cupBaseRadius,
          height: CupPongWorld.cupHeight,
        ),
    ],
    ball: ball,
    aim: aim,
  );
}

/// Paints [view] into a recorder — the whole scene, no widget tree.
void _paint(CupPongView view, {Size size = _size}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paintCupPongTable(canvas, size, view, const CupPongStyle(), _scheme);
  recorder.endRecording().dispose();
}

/// Rasterises [view] so a test can look at what the player would actually see.
/// The painter is a pure function, so this needs no widget tree either.
Future<ByteData> _raster(CupPongView view) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paintCupPongTable(canvas, _size, view, const CupPongStyle(), _scheme);
  final picture = recorder.endRecording();
  final image =
      await picture.toImage(_size.width.toInt(), _size.height.toInt());
  final bytes = (await image.toByteData())!;
  picture.dispose();
  image.dispose();
  return bytes;
}

int _index(int x, int y) => ((y * _size.width.toInt()) + x) * 4;

double _luma(ByteData px, int x, int y) {
  final i = _index(x, y);
  return (0.2126 * px.getUint8(i) +
          0.7152 * px.getUint8(i + 1) +
          0.0722 * px.getUint8(i + 2)) /
      255;
}

/// The furthest any pixel differs between two renders, measured from [from].
/// Returns -1 when the two are identical.
double _diffReach(ByteData a, ByteData b, Offset from) {
  var worst = -1.0;
  for (var y = 0; y < _size.height.toInt(); y++) {
    for (var x = 0; x < _size.width.toInt(); x++) {
      final i = _index(x, y);
      var changed = false;
      for (var ch = 0; ch < 3; ch++) {
        if ((a.getUint8(i + ch) - b.getUint8(i + ch)).abs() > 2) {
          changed = true;
          break;
        }
      }
      if (!changed) continue;
      final d = (Offset(x.toDouble(), y.toDouble()) - from).distance;
      if (d > worst) worst = d;
    }
  }
  return worst;
}

CupPongView _rest() => _viewOf(
      ball: const BallView(
        position: CupPongWorld.launchPoint,
        radius: CupPongWorld.ballRadius,
        inHand: true,
      ),
    );

/// Width/height of a projected horizontal circle — the "squash" of a cup mouth.
double _mouthAspect(Camera3 camera, Vec3 mouth) {
  final path = camera.horizontalCirclePath(
    mouth,
    CupPongWorld.cupMouthRadius,
    segments: 48,
  )!;
  final b = path.getBounds();
  return b.height / b.width;
}

void main() {
  group('painter', () {
    test('paints a full scene without throwing', () {
      _paint(_viewOf(
        ball: const BallView(
          position: Vec3(0, 0.35, 0.4),
          radius: CupPongWorld.ballRadius,
          spin: 2,
        ),
      ));
    });

    test('paints mid-removal cups, splashes and the aim overlay', () {
      final cups = CupPongGame.rackFor([for (var i = 0; i < 10; i++) i]);
      final view = CupPongView(
        cups: [
          for (final c in cups)
            CupView(
              id: c.id,
              mouth: CupPongWorld.mouthOf(c),
              mouthRadius: CupPongWorld.cupMouthRadius,
              baseRadius: CupPongWorld.cupBaseRadius,
              height: CupPongWorld.cupHeight,
              removal: c.id == 3 ? 0.6 : 0,
              splash: c.id == 4 ? 0.4 : 0,
            ),
        ],
        ball: const BallView(
          position: CupPongWorld.launchPoint,
          radius: CupPongWorld.ballRadius,
          inHand: true,
        ),
        restingBalls: const [
          BallView(
            position: Vec3(0.2, CupPongWorld.ballRadius, 0.4),
            radius: CupPongWorld.ballRadius,
          ),
        ],
        aim: const AimView(power: 0.6, flick: Offset(38, -130)),
      );
      _paint(view);
    });

    test('survives degenerate and extreme canvas sizes', () {
      for (final s in const [
        Size.zero,
        Size(1, 1),
        Size(60, 60),
        Size(1200, 300),
        Size(300, 1600),
      ]) {
        _paint(_viewOf(), size: s);
      }
    });

    test('paints re-racked and empty racks', () {
      _paint(_viewOf(count: 6));
      _paint(_viewOf(count: 3));
      _paint(const CupPongView(cups: []));
    });
  });

  group('the ball at rest', () {
    final camera = CupPongWorld.cameraFor(_size);
    final at = camera.project(CupPongWorld.launchPoint);
    final centre = at.screen;
    final trueRadius = CupPongWorld.ballRadius * at.scale;

    test('sits in the near foreground as an unmistakable bright ball',
        () async {
      final rest = await _raster(_rest());
      final bare = await _raster(_viewOf());
      final cx = centre.dx.round();
      final cy = centre.dy.round();

      // Bare felt where the ball will be; a bright ball once it is there.
      expect(_luma(bare, cx, cy), lessThan(0.55));
      expect(_luma(rest, cx, cy), greaterThan(0.75));

      // Measure the bright disc across its widest row. It has to be visibly
      // fatter than true perspective scale — a ~19 px dot is the thing the
      // player could not find.
      var span = 0;
      for (var x = 0; x < _size.width.toInt(); x++) {
        if (_luma(rest, x, cy) > 0.6) span++;
      }
      expect(span, greaterThan(2 * trueRadius * 1.15));
      expect(span, lessThan(2 * trueRadius * 1.9));
      expect(span, greaterThan(40),
          reason: 'a foreground ball, not a speck on the felt');
    });

    test('adds nothing to the table — no reticle, no marker, no overlay',
        () async {
      final rest = await _raster(_rest());
      final bare = await _raster(_viewOf());
      final reach = _diffReach(rest, bare, centre);
      // Everything the resting state draws is the ball and its contact pool.
      // If a hint ever creeps back onto the felt or onto a cup, this fails.
      expect(reach, greaterThan(0), reason: 'the ball is drawn at all');
      expect(
        reach,
        lessThan(trueRadius * CupPongWorld.heldDrawScale * 3.2),
        reason: 'nothing may hover on the table while the player is idle',
      );
    });
  });

  group('the swipe cue', () {
    final camera = CupPongWorld.cameraFor(_size);
    final at = camera.project(CupPongWorld.launchPoint);
    final radius =
        CupPongWorld.ballRadius * at.scale * CupPongWorld.heldDrawScale;

    Future<ByteData> swipe(double power, Offset flick) => _raster(
          _viewOf(
            ball: const BallView(
              position: CupPongWorld.launchPoint,
              radius: CupPongWorld.ballRadius,
              inHand: true,
            ),
            aim: AimView(power: power, flick: flick),
          ),
        );

    test('never reaches further than 2.75 ball radii from the ball', () async {
      // 2.75 is the tightest bound the shipped cue satisfies — measured worst
      // case is 2.65 radii, at full power. This is the regression guard on
      // "the gesture and nothing else": the predicted arc that used to be
      // drawn here ran the length of the table and would blow this bound by
      // roughly an order of magnitude.
      final rest = await _raster(_rest());
      var worst = 0.0;
      for (final flick in const [
        Offset(0, -240),
        Offset(240, -240),
        Offset(-240, -240),
        Offset(300, -60),
      ]) {
        final reach = _diffReach(await swipe(1, flick), rest, at.screen);
        expect(reach, greaterThan(radius),
            reason: 'a full-power swipe draws a ring and a trail');
        if (reach > worst) worst = reach;
      }
      expect(worst, lessThan(radius * 2.75),
          reason: 'measured worst case 2.65 radii');
    });

    test('leaves the table and the rack completely unmarked', () async {
      // Everything from the horizon down to 2.75 radii above the ball is
      // scene: the far rail, the whole rack, and most of the felt. Not one
      // pixel of it may change because a finger is on the screen, at any
      // power, steered any way.
      final rest = await _raster(_rest());
      final ceiling = (at.screen.dy - radius * 2.75).floor();
      expect(ceiling, greaterThan(camera.horizonY),
          reason: 'the band under test has to actually contain the rack');
      // Sanity: the deepest cup's base is well inside the band being checked.
      final rackFoot = camera.project(CupPongWorld.baseOf(
        CupPongGame.rackFor([for (var i = 0; i < 10; i++) i]).first,
      ));
      expect(rackFoot.screen.dy, lessThan(ceiling),
          reason: 'the nearest cup has to sit inside the untouched band');
      for (final flick in const [
        Offset(0, -240),
        Offset(-300, -240),
        Offset(300, -240),
      ]) {
        final cue = await swipe(1, flick);
        for (var y = 0; y < ceiling; y++) {
          for (var x = 0; x < _size.width.toInt(); x++) {
            final i = _index(x, y);
            for (var ch = 0; ch < 3; ch++) {
              expect(
                cue.getUint8(i + ch),
                rest.getUint8(i + ch),
                reason: 'flick $flick painted onto the scene at ($x, $y)',
              );
            }
          }
        }
      }
    });

    test('power reads as a bigger cue, and steering rotates it', () async {
      final rest = await _raster(_rest());
      final soft = await swipe(0.15, const Offset(0, -30));
      final hard = await swipe(1, const Offset(0, -240));
      expect(
        _diffReach(hard, rest, at.screen),
        greaterThan(_diffReach(soft, rest, at.screen)),
      );
      // Same power, mirrored steering ⇒ a different picture.
      final left = await swipe(1, const Offset(-240, -240));
      final right = await swipe(1, const Offset(240, -240));
      expect(_diffReach(left, right, at.screen), greaterThan(0));
    });
  });

  group('perspective', () {
    final camera = CupPongWorld.cameraFor(_size);
    final cups = CupPongGame.rackFor([for (var i = 0; i < 10; i++) i]);

    test('the horizon sits inside the frame and above the whole rack', () {
      expect(camera.horizonY, greaterThanOrEqualTo(0));
      expect(camera.horizonY, lessThan(_size.height * 0.25));
      for (final c in cups) {
        final at = camera.project(CupPongWorld.mouthOf(c));
        expect(at.visible, isTrue);
        expect(at.screen.dy, greaterThan(camera.horizonY));
        expect(at.screen.dx, inInclusiveRange(0, _size.width));
      }
    });

    test('the table rails converge toward the vanishing point', () {
      double railGap(double z) {
        final l = camera.project(Vec3(-CupPongWorld.halfWidth, 0, z));
        final r = camera.project(Vec3(CupPongWorld.halfWidth, 0, z));
        return (r.screen.dx - l.screen.dx).abs();
      }

      final near = railGap(CupPongWorld.nearZ);
      final mid = railGap(CupPongWorld.rackApexZ);
      final far = railGap(CupPongWorld.farZ);
      expect(mid, lessThan(near));
      expect(far, lessThan(mid));
    });

    test('cup mouths are true conics — the squash varies with depth', () {
      // Rule 3 of the rebuild: the old board hardcoded `mouthRy = rx * 0.42`,
      // a constant squash, and that alone stopped the scene reading as 3-D.
      // A horizontal circle projects to a conic whose aspect changes with
      // depth, and that variation IS the depth cue. Guard it.
      final apex = _mouthAspect(camera, CupPongWorld.mouthOf(cups.first));
      final back = _mouthAspect(camera, CupPongWorld.mouthOf(cups.last));
      expect(apex, greaterThan(back));
      expect(apex / back, greaterThan(1.08),
          reason: 'a constant squash would give exactly 1.0');
      // Sanity: both are foreshortened, neither is a circle or a line.
      for (final a in [apex, back]) {
        expect(a, inExclusiveRange(0.05, 0.85));
      }
    });

    test('a ball shrinks as it flies away', () {
      double radiusAt(double z) =>
          CupPongWorld.ballRadius *
          camera.project(Vec3(0, 0.2, z)).scale;

      final hand = radiusAt(CupPongWorld.launchPoint.z);
      final mid = radiusAt(CupPongWorld.rackApexZ / 2);
      final rack = radiusAt(CupPongWorld.rackApexZ);
      expect(mid, lessThan(hand));
      expect(rack, lessThan(mid));
      expect(hand / rack, greaterThan(2.0),
          reason: 'the size cue has to be obvious, not subtle');
    });

    test('the shadow anchor is the ball projected onto the table plane', () {
      const ball = Vec3(0.08, 0.36, 0.45);
      final shadow = camera.project(const Vec3(0.08, 0, 0.45));
      final air = camera.project(ball);
      expect(shadow.visible, isTrue);
      // A shadow below the ball on screen is what makes the arc readable.
      expect(shadow.screen.dy, greaterThan(air.screen.dy));
      // The two are not at the same depth, so their x differs slightly — the
      // shadow must not be a naive vertical offset.
      expect(shadow.screen.dx, isNot(closeTo(air.screen.dx, 1e-6)));
    });

    test('screenToGround inverts the ground projection', () {
      const spot = Vec3(0.15, 0, 0.7);
      final back = camera.screenToGround(camera.project(spot).screen)!;
      expect(back.x, closeTo(spot.x, 1e-6));
      expect(back.z, closeTo(spot.z, 1e-6));
    });
  });

  group('tile art', () {
    testWidgets('builds, animates and disposes cleanly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(width: 96, height: 96, child: CupPongTileArt()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('honours the phase offset', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 96,
              height: 96,
              child: CupPongTileArt(phase: 0.4),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    });
  });
}
