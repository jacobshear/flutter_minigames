import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Demo-app SFX mixer. Fail-soft: missing assets or platform limits never crash
/// a game. Game packages only receive callbacks — no audio dependency.
///
/// Paths are relative to the Flutter asset root (`assets/…` in pubspec).
/// [AssetSource] adds the `assets/` prefix used by [AudioCache].
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

  final Set<AudioPlayer> _readyPlayers = {};

  bool get _anyReady => _readyPlayers.isNotEmpty;

  Future<void> init() async {
    if (_anyReady) return;
    // Load each asset independently so one missing file does not kill the bank.
    await Future.wait([
      _configure(_mark, 'sfx/mark.wav', volume: 0.58),
      _configure(_drop, 'sfx/drop.wav', volume: 0.72),
      _configure(_dropLong, 'sfx/drop_long.wav', volume: 0.75),
      _configure(_invalid, 'sfx/invalid.wav', volume: 0.45),
      _configure(_win, 'sfx/win.wav', volume: 0.78),
      _configure(_draw, 'sfx/draw.wav', volume: 0.55),
      _configure(_newGame, 'sfx/new_game.wav', volume: 0.5),
    ]);
    if (!_anyReady) {
      debugPrint(
        'DemoSfx: no SFX loaded. Do a full rebuild (not hot restart) '
        'after adding assets — AssetManifest is only rebuilt on full run.',
      );
    } else {
      debugPrint('DemoSfx: ready (${_readyPlayers.length}/7 clips)');
    }
  }

  Future<void> _configure(
    AudioPlayer player,
    String asset, {
    required double volume,
  }) async {
    try {
      // Prove the asset is in the bundle before handing it to the native player.
      await rootBundle.load('assets/$asset');
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setPlayerMode(PlayerMode.lowLatency);
      await player.setVolume(volume);
      await player.setSource(AssetSource(asset));
      _readyPlayers.add(player);
    } catch (e) {
      debugPrint('DemoSfx: skip $asset — $e');
    }
  }

  Future<void> _fire(AudioPlayer player) async {
    if (!_readyPlayers.contains(player)) return;
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
    _readyPlayers.clear();
  }
}
