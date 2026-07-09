import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Demo-app SFX mixer. Fail-soft: missing assets or platform limits never crash
/// a game. The tic-tac-toe package only receives callbacks — no audio dep.
class DemoSfx {
  DemoSfx._();
  static final DemoSfx instance = DemoSfx._();

  final AudioPlayer _place = AudioPlayer();
  final AudioPlayer _win = AudioPlayer();
  final AudioPlayer _draw = AudioPlayer();
  final AudioPlayer _newGame = AudioPlayer();

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      await Future.wait([
        _configure(_place, 'sfx/place.wav', volume: 0.55),
        _configure(_win, 'sfx/win.wav', volume: 0.7),
        _configure(_draw, 'sfx/draw.wav', volume: 0.55),
        _configure(_newGame, 'sfx/new_game.wav', volume: 0.5),
      ]);
      _ready = true;
    } catch (e, st) {
      debugPrint('DemoSfx.init failed (sounds disabled): $e\n$st');
    }
  }

  Future<void> _configure(
    AudioPlayer player,
    String asset, {
    required double volume,
  }) async {
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setVolume(volume);
    await player.setSource(AssetSource(asset));
  }

  Future<void> _fire(AudioPlayer player) async {
    if (!_ready) return;
    try {
      await player.stop();
      await player.seek(Duration.zero);
      await player.resume();
    } catch (e) {
      debugPrint('DemoSfx play failed: $e');
    }
  }

  void place() => _fire(_place);
  void win() => _fire(_win);
  void draw() => _fire(_draw);
  void newGame() => _fire(_newGame);

  Future<void> dispose() async {
    await Future.wait([
      _place.dispose(),
      _win.dispose(),
      _draw.dispose(),
      _newGame.dispose(),
    ]);
    _ready = false;
  }
}
