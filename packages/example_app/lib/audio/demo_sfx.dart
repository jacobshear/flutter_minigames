import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Demo-app SFX mixer. Fail-soft: missing assets or platform limits never crash
/// a game. Game packages only receive callbacks — no audio dependency.
///
/// Assets (procedural, 44.1 kHz mono):
/// - [mark] — soft ink tick (tic-tac-toe place)
/// - [drop] / [dropLong] — plastic disc clack (connect four land)
/// - [invalid] — muted buzz (full column / illegal)
/// - [win] / [draw] / [newGame]
class DemoSfx {
  DemoSfx._();
  static final DemoSfx instance = DemoSfx._();

  final AudioPlayer _mark = AudioPlayer();
  final AudioPlayer _drop = AudioPlayer();
  final AudioPlayer _dropLong = AudioPlayer();
  final AudioPlayer _invalid = AudioPlayer();
  final AudioPlayer _win = AudioPlayer();
  final AudioPlayer _draw = AudioPlayer();
  final AudioPlayer _newGame = AudioPlayer();

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      await Future.wait([
        _configure(_mark, 'sfx/mark.wav', volume: 0.58),
        _configure(_drop, 'sfx/drop.wav', volume: 0.72),
        _configure(_dropLong, 'sfx/drop_long.wav', volume: 0.75),
        _configure(_invalid, 'sfx/invalid.wav', volume: 0.45),
        _configure(_win, 'sfx/win.wav', volume: 0.78),
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

  /// Tic-tac-toe mark placement.
  void mark() => _fire(_mark);

  /// Connect Four disc land. Use [longDrop] for tall falls (deeper thud).
  void drop({bool longDrop = false}) =>
      _fire(longDrop ? _dropLong : _drop);

  void invalid() => _fire(_invalid);
  void win() => _fire(_win);
  void draw() => _fire(_draw);
  void newGame() => _fire(_newGame);

  /// Back-compat alias used by older call sites.
  void place() => mark();

  Future<void> dispose() async {
    await Future.wait([
      _mark.dispose(),
      _drop.dispose(),
      _dropLong.dispose(),
      _invalid.dispose(),
      _win.dispose(),
      _draw.dispose(),
      _newGame.dispose(),
    ]);
    _ready = false;
  }
}
