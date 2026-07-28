import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/game.dart' as flame show Vector2;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/games/eight_ball/eight_ball.dart';

/// The aiming aid — the prediction behind it and the pixels it puts on the
/// cloth.
///
/// The whole feature is a *display* of a guess, so the two things worth pinning
/// down are (a) the geometry is the real thing a player would work out with a
/// ghost ball in their head, and (b) it exists only while a finger is down.
void main() {
  const r = EightBallGame.ballR;
  const size = Size(318, 582); // what a 390pt phone actually gives the board
  const game = EightBallGame();
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A4D));

  /// A ball entry for the solver.
  ({int number, Offset centre}) at(int number, double x, double y) =>
      (number: number, centre: Offset(x, y));

  group('the board box', () {
    test('sizes to a felt that is exactly as long as the world says', () {
      // The rail band is a fraction of the *width* but insets the height too,
      // so the outer box is not 1:2. Give a box of boardAspect and the felt
      // inside it has to come out at tableL : tableW.
      const w = 318.0;
      final felt = poolFeltRect(Size(w, w / EightBallScene.boardAspect));
      expect(
        felt.height / felt.width,
        closeTo(EightBallGame.tableL / EightBallGame.tableW, 1e-9),
      );
      // Which is what makes one world unit the same number of pixels on both
      // axes — the assumption the aim assist is drawn on.
      expect(
        felt.width / EightBallGame.tableW,
        closeTo(felt.height / EightBallGame.tableL, 1e-9),
      );
      // The old 1:2 box stretched the felt by ~10%; keep the regression named.
      final old = poolFeltRect(const Size(w, w * 2));
      expect(old.height / old.width, greaterThan(2.15));
    });
  });

  group('the ray-cast', () {
    test('takes the nearest ball on the line, not the first in the list', () {
      final shot = predictPoolShot(
        cue: const Offset(0, 12),
        aim: const Offset(0, -1),
        balls: [
          at(9, 0, 3), // far
          at(2, 0, 7), // near — this is the one
          at(5, 3, 7), // off the line entirely
        ],
      );
      expect(shot.ballNumber, 2);
      expect(shot.objectCentre, const Offset(0, 7));
    });

    test('the contact sits exactly one ball diameter back along the aim', () {
      for (final offset in [0.0, 0.2, 0.5, 0.75]) {
        final shot = predictPoolShot(
          cue: Offset(offset, 12),
          aim: const Offset(0, -1),
          balls: [at(4, 0, 6)],
        );
        expect(shot.ballNumber, 4, reason: 'offset $offset should still clip');
        expect(
          (shot.objectCentre! - shot.contact).distance,
          closeTo(2 * r, 1e-9),
        );
        // …and the contact is on the aim line, not merely near the ball.
        expect(shot.contact.dx, closeTo(offset, 1e-9));
        expect(shot.contact.dy, lessThan(12));
      }
    });

    test('a full-ball hit is a straight pot; a thin clip is a big cut', () {
      final straight = predictPoolShot(
        cue: const Offset(0, 12),
        aim: const Offset(0, -1),
        balls: [at(4, 0, 6)],
      );
      expect(straight.cut, closeTo(0, 1e-6));

      final thin = predictPoolShot(
        cue: const Offset(0, 12),
        aim: const Offset(0, -1),
        balls: [at(4, 2 * r * 0.8, 6)],
      );
      expect(thin.cut, greaterThan(0.9)); // > 50°
    });

    test('the object leaves down the centre line and the cue takes the tangent',
        () {
      final shot = predictPoolShot(
        cue: const Offset(0, 12),
        aim: const Offset(0, -1),
        balls: [at(4, 0.5, 6)],
      );
      final centreLine = shot.objectCentre! - shot.contact;
      final unit = centreLine / centreLine.distance;
      expect(shot.objectDir.dx, closeTo(unit.dx, 1e-9));
      expect(shot.objectDir.dy, closeTo(unit.dy, 1e-9));

      // Perpendicular, unit, and thrown to the side the cue was heading.
      final dot = shot.cueDir.dx * shot.objectDir.dx +
          shot.cueDir.dy * shot.objectDir.dy;
      expect(dot, closeTo(0, 1e-9));
      expect(shot.cueDir.distance, closeTo(1, 1e-9));
      // Aiming up the table with the ball off to the right throws the cue left.
      expect(shot.cueDir.dx, lessThan(0));
    });

    test('with nothing in the way the line dies on the cushion', () {
      final shot = predictPoolShot(
        cue: const Offset(0, 12),
        aim: const Offset(0, -1),
        balls: const [],
      );
      expect(shot.hitsBall, isFalse);
      expect(shot.objectDir, Offset.zero);
      // One radius short of the foot rail — where the ball would actually stop.
      expect(shot.contact.dy, closeTo(r, 1e-9));

      final sideways = predictPoolShot(
        cue: const Offset(0, 12),
        aim: const Offset(1, 0),
        balls: const [],
      );
      expect(sideways.contact.dx,
          closeTo(EightBallGame.tableW / 2 - r, 1e-9));
    });

    test('a ball behind the cue is not a hit', () {
      final shot = predictPoolShot(
        cue: const Offset(0, 12),
        aim: const Offset(0, -1),
        balls: [at(4, 0, 14)],
      );
      expect(shot.hitsBall, isFalse);
    });
  });

  group('what gets drawn', () {
    PoolAimAssist assistAt(double power) => poolAimAssist(
          cue: const Offset(0, 12),
          aim: const Offset(0, -1),
          balls: [at(4, 0.5, 6)],
          power: power,
        );

    test('power stretches both legs of the V', () {
      final soft = assistAt(0.05);
      final hard = assistAt(1.0);
      expect(hard.objectLen, greaterThan(soft.objectLen * 2.5));
      expect(hard.cueLen, greaterThan(soft.cueLen * 2.5));
      // Monotone, not just different at the ends.
      var last = -1.0;
      for (var i = 0; i <= 10; i++) {
        final len = assistAt(i / 10).objectLen;
        expect(len, greaterThan(last));
        last = len;
      }
    });

    test('the cut angle splits the reach between the two legs', () {
      // Dead straight: the object takes nearly everything and the cue stalls.
      final straight = poolAimAssist(
        cue: const Offset(0, 12),
        aim: const Offset(0, -1),
        balls: [at(4, 0, 6)],
        power: 1,
      );
      expect(straight.objectLen, greaterThan(straight.cueLen * 3));

      // A thin clip: the cue runs and the object barely goes.
      final thin = poolAimAssist(
        cue: const Offset(0, 12),
        aim: const Offset(0, -1),
        balls: [at(4, 2 * r * 0.92, 6)],
        power: 1,
      );
      expect(thin.cueLen, greaterThan(thin.objectLen));
    });

    test('a rail-only line has no V to draw', () {
      final a = poolAimAssist(
        cue: const Offset(0, 12),
        aim: const Offset(0, -1),
        balls: const [],
        power: 1,
      );
      expect(a.objectLen, 0);
      expect(a.cueLen, 0);
    });
  });

  group('pixels', () {
    Future<ByteData> raster(PoolView view) async {
      final recorder = ui.PictureRecorder();
      paintPoolTable(
        Canvas(recorder),
        size,
        view,
        const EightBallStyle(),
        scheme,
      );
      final picture = recorder.endRecording();
      final image =
          await picture.toImage(size.width.toInt(), size.height.toInt());
      final bytes = (await image.toByteData())!;
      picture.dispose();
      image.dispose();
      return bytes;
    }

    final w = size.width.toInt();

    bool differs(ByteData a, ByteData b, int i) {
      for (var ch = 0; ch < 3; ch++) {
        if (a.getUint8(i + ch) != b.getUint8(i + ch)) return true;
      }
      return false;
    }

    /// How many pixels differ between two renders, optionally only above [maxY]
    /// — the cue *stick* swings the other way with power (a hard stroke pulls it
    /// off the bottom of the frame), so a whole-image count measures the stick,
    /// not the guide.
    int changedPixels(ByteData a, ByteData b, {int maxY = 1 << 30}) {
      var n = 0;
      final rows = math.min(size.height.toInt(), maxY);
      for (var y = 0; y < rows; y++) {
        for (var x = 0; x < w; x++) {
          if (differs(a, b, ((y * w) + x) * 4)) n++;
        }
      }
      return n;
    }

    /// The topmost row that changed — how far up the cloth the guide reaches.
    int highestChangedRow(ByteData a, ByteData b) {
      for (var y = 0; y < size.height.toInt(); y++) {
        for (var x = 0; x < w; x++) {
          if (differs(a, b, ((y * w) + x) * 4)) return y;
        }
      }
      return size.height.toInt();
    }

    const cueBall = RenderBall(
      nx: 0.35,
      ny: 0.78,
      number: 0,
      radiusFrac: r / EightBallGame.tableW,
      isCue: true,
    );
    const objectBall = RenderBall(
      nx: 0.62,
      ny: 0.42,
      number: 3,
      radiusFrac: r / EightBallGame.tableW,
    );

    PoolView aiming(double power) {
      final cue = EightBallScene.simPos(cueBall.nx, cueBall.ny);
      final obj = EightBallScene.simPos(objectBall.nx, objectBall.ny);
      final direct = Offset(obj.x - cue.x, obj.y - cue.y);
      final straight = direct / direct.distance;
      const phi = 0.095; // rotate off dead-straight into a real cut
      final dir = Offset(
        straight.dx * math.cos(phi) - straight.dy * math.sin(phi),
        straight.dx * math.sin(phi) + straight.dy * math.cos(phi),
      );
      return PoolView(
        balls: const [cueBall, objectBall],
        aim: PoolAim(
          nx: cueBall.nx,
          ny: cueBall.ny,
          dir: dir,
          power: power,
          assist: poolAimAssist(
            cue: Offset(cue.x, cue.y),
            aim: dir,
            balls: [(number: 3, centre: Offset(obj.x, obj.y))],
            power: power,
          ),
        ),
      );
    }

    test('nothing is on the table when nobody is aiming', () async {
      // The table at rest and the same table with the aim removed must be the
      // *identical* image — the assist has to leave nothing behind on release.
      final rest = await raster(const PoolView(balls: [cueBall, objectBall]));
      final alsoRest =
          await raster(const PoolView(balls: [cueBall, objectBall]));
      expect(changedPixels(rest, alsoRest), 0);

      // …and while aiming it is unmistakably there.
      final aimed = await raster(aiming(0.7));
      expect(changedPixels(rest, aimed), greaterThan(400),
          reason: 'the guide should be plainly visible while dragging');
    });

    test('power reads on the cloth, in reach and in weight', () async {
      final rest = await raster(const PoolView(balls: [cueBall, objectBall]));
      final softImg = await raster(aiming(0.05));
      final hardImg = await raster(aiming(1.0));

      // Reach: the V climbs visibly further up the table on a hard stroke.
      final softTop = highestChangedRow(rest, softImg);
      final hardTop = highestChangedRow(rest, hardImg);
      expect(hardTop, lessThan(softTop - 60),
          reason: 'soft reached row $softTop, hard only $hardTop');

      // Weight: above the object ball — where the stick never goes — a hard
      // stroke lays down far more ink than a tap.
      const above = 230;
      final soft = changedPixels(rest, softImg, maxY: above);
      final hard = changedPixels(rest, hardImg, maxY: above);
      expect(hard, greaterThan(soft * 1.5),
          reason: 'soft $soft vs hard $hard — power is not reading');
    });

    test('the live scene puts the guide up and takes it away again', () async {
      // The painter tests above prove the drawing; this proves the wiring —
      // the scene solving the assist off its own live bodies while a finger is
      // down, and nothing at all once it lifts.
      final state = game
          .initialState(seed: 0, playerIds: const ['p1', 'p2'])
          .copyWith(balls: [
        const Ball(number: 0, nx: 0.5, ny: 0.78, pocketed: false),
        const Ball(number: 1, nx: 0.5, ny: 0.30, pocketed: false),
        for (var n = 2; n <= 15; n++)
          Ball(number: n, nx: 0.5, ny: 0.05, pocketed: true),
      ]);
      final scene =
          EightBallScene(style: const EightBallStyle(), scheme: scheme);
      scene.onGameResize(flame.Vector2(size.width, size.height));
      scene.applyState(state, 'p1');

      Future<ByteData> frame() async {
        final rec = ui.PictureRecorder();
        scene.render(Canvas(rec));
        final pic = rec.endRecording();
        final img = await pic.toImage(w, size.height.toInt());
        final bytes = (await img.toByteData())!;
        pic.dispose();
        img.dispose();
        return bytes;
      }

      final before = await frame();
      scene.beginAim(const Offset(160, 400));
      scene.updateAim(const Offset(160, 520)); // drag down → shoot up the table
      expect(scene.isAiming, isTrue);
      final aiming = await frame();
      expect(changedPixels(before, aiming), greaterThan(400),
          reason: 'the scene drew no guide while aiming');

      scene.endAim();
      expect(scene.isAiming, isFalse);
      final after = await frame();
      // Byte-identical to the untouched table: no ghost, no line, no residue.
      expect(changedPixels(before, after), 0);
    });

    test('the move arrows only exist with a placement ghost', () async {
      final bare = await raster(const PoolView(balls: [objectBall]));
      final ghosted = await raster(const PoolView(
        balls: [objectBall],
        ghost: PoolGhost(
          nx: 0.42,
          ny: 0.66,
          radiusFrac: r / EightBallGame.tableW,
        ),
      ));
      expect(changedPixels(bare, ghosted), greaterThan(400));

      // The arrows sit outside the ghost, at the diagonals: sample a point on
      // the diagonal beyond the ball's rim and it must have lit up.
      final felt = poolFeltRect(size);
      final ballPx = (r / EightBallGame.tableW) * felt.width;
      final centre = Offset(
        felt.left + 0.42 * felt.width,
        felt.top + 0.66 * felt.height,
      );
      final probe = centre + const Offset(0.7071, 0.7071) * (ballPx * 1.7);
      final i = ((probe.dy.round() * size.width.toInt()) + probe.dx.round()) * 4;
      double luma(ByteData px) =>
          (0.2126 * px.getUint8(i) +
              0.7152 * px.getUint8(i + 1) +
              0.0722 * px.getUint8(i + 2)) /
          255;
      expect(luma(bare), lessThan(0.6));
      expect(luma(ghosted), greaterThan(0.75),
          reason: 'no arrowhead on the down-right diagonal');
    });
  });
}
