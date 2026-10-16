import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_minigames/src/games/archery/archery.dart';
import 'package:flutter_test/flutter_test.dart';

// The view carries two clocks. [ArcheryView.time] drives the ambient motion
// (grass, wind flag) and the host holds it at 0 under Reduce Motion;
// [ArcheryView.shakeTime] drives the impact wobble and the focus-break shake,
// which carry state and stay live. One shared clock made the grass and flag
// snap from rest to a live phase the moment a shake began.

final _scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF007AFF));
const _size = Size(390, 640);
const _windy =
    TargetConditions(index: 1, distance: 22, windSpeed: 6, windAngle: 1.2);

Future<Uint8List> _pixels(ArcheryView view) async {
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

/// The foreground grass: the bottom fifth of the frame, well clear of the
/// target butt the wobble rocks.
Uint8List _grass(Uint8List rgba) {
  final w = _size.width.round();
  final h = _size.height.round();
  return Uint8List.sublistView(rgba, (h * 4 ~/ 5) * w * 4);
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

ArcheryView _view({
  double time = 0,
  double shakeTime = 0,
  double wobble = 0,
}) =>
    ArcheryView(
      conditions: _windy,
      showReticle: false,
      zoom: 0,
      time: time,
      shakeTime: shakeTime,
      targetWobble: wobble,
      impactX: 0.02,
      impactY: 0.03,
    );

void main() {
  test('the impact wobble rides the shake clock, not the ambient one',
      () async {
    final a = await _pixels(_view(wobble: 1, shakeTime: 0.30));
    final b = await _pixels(_view(wobble: 1, shakeTime: 0.71));
    expect(_same(a, b), isFalse,
        reason: 'the butt must rock while the ambient clock is held at 0');
  });

  test('the ambient scene does not move with the shake clock', () async {
    // Reduce Motion: time held at 0, shake clock running through a wobble.
    final a = await _pixels(_view(wobble: 1, shakeTime: 0.30));
    final b = await _pixels(_view(wobble: 1, shakeTime: 0.71));
    expect(_same(_grass(a), _grass(b)), isTrue,
        reason: 'the grass must not snap to a live phase during a shake');
  });

  test('the grass and the flag still ride the ambient clock', () async {
    final a = await _pixels(_view(time: 0.30));
    final b = await _pixels(_view(time: 0.71));
    expect(_same(_grass(a), _grass(b)), isFalse);
    expect(_same(a, b), isFalse);
  });

  test('with nothing shaking the shake clock draws nothing', () async {
    final a = await _pixels(_view(time: 0.5, shakeTime: 0.30));
    final b = await _pixels(_view(time: 0.5, shakeTime: 0.71));
    expect(_same(a, b), isTrue);
  });
}
