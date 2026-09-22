import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// One shared, throttled clock for a GRID of animated tile arts.
///
/// Every tile art loops its own diorama. Alone, each owns an
/// [AnimationController] ticking at display rate (120Hz on ProMotion); a
/// picker showing sixteen of them ran sixteen tickers and repainted sixteen
/// scenes every vsync. Under a [TileArtClock] they all follow ONE ticker that
/// publishes at [fps] (30 by default — a looping diorama reads the same at
/// 30 and costs a quarter of 120), and each tile only repaints on a publish.
///
/// Tile arts opt in through [TileArtDriver]; outside a clock they behave
/// exactly as before. The clock mutes with [TickerMode] like any ticker, so a
/// sheet under a covering route stops ticking.
class TileArtClock extends StatefulWidget {
  final Widget child;

  /// Publish rate. 30 is plenty for the dioramas.
  final int fps;

  const TileArtClock({super.key, required this.child, this.fps = 30});

  /// The nearest clock's elapsed-time listenable, or null outside one.
  static ValueListenable<Duration>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TileArtClockScope>()?.elapsed;

  @override
  State<TileArtClock> createState() => _TileArtClockState();
}

class _TileArtClockState extends State<TileArtClock>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);
  late final Ticker _ticker;
  Duration _lastPublish = Duration.zero;

  @override
  void initState() {
    super.initState();
    // Eager, not a lazy field initializer: nothing reads the ticker until
    // dispose, so a lazy one would never start.
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    // 10% under the step: frames arrive on a vsync grid, and a strict
    // threshold skips the frame that lands a hair early — at 120Hz that is
    // every 5th frame (24fps) instead of every 4th (30).
    final step = Duration(microseconds: 900000 ~/ widget.fps);
    if (elapsed - _lastPublish < step) return;
    _lastPublish = elapsed;
    _elapsed.value = elapsed;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _TileArtClockScope(elapsed: _elapsed, child: widget.child);
}

class _TileArtClockScope extends InheritedWidget {
  final ValueListenable<Duration> elapsed;

  const _TileArtClockScope({required this.elapsed, required super.child});

  @override
  bool updateShouldNotify(_TileArtClockScope oldWidget) =>
      oldWidget.elapsed != elapsed;
}

/// A tile art's loop position, from a [TileArtClock] when one is above it,
/// else from its own repeating controller.
///
/// Usage in a tile art's State (which mixes in
/// `SingleTickerProviderStateMixin`):
/// ```dart
/// late final _driver = TileArtDriver(vsync: this, period: _period);
/// void didChangeDependencies() { super.didChangeDependencies(); _driver.attach(context); }
/// void dispose() { _driver.dispose(); super.dispose(); }
/// // build: AnimatedBuilder(animation: _driver, builder: ... _driver.value ...)
/// ```
class TileArtDriver extends ChangeNotifier {
  final Duration period;
  final AnimationController _own;
  ValueListenable<Duration>? _clock;
  bool _animate;

  TileArtDriver({
    required TickerProvider vsync,
    required this.period,
    bool animate = true,
  })  : _animate = animate,
        _own = AnimationController(vsync: vsync, duration: period) {
    _own.addListener(notifyListeners);
  }

  /// Loop position in [0, 1).
  double get value {
    final clock = _clock;
    if (clock == null) return _own.value;
    final us = period.inMicroseconds;
    if (us <= 0) return 0;
    return (clock.value.inMicroseconds % us) / us;
  }

  /// Bind to the nearest [TileArtClock], or run the own controller when
  /// there is none. Call from `didChangeDependencies`.
  void attach(BuildContext context) {
    final clock = TileArtClock.maybeOf(context);
    if (identical(clock, _clock) && (clock != null || _own.isAnimating)) {
      return;
    }
    _clock?.removeListener(notifyListeners);
    _clock = clock;
    if (clock != null) {
      _own.stop();
      if (_animate) clock.addListener(notifyListeners);
    } else if (_animate) {
      _own.repeat();
    }
  }

  /// Start or stop looping (a still frame shows loop position 0).
  set animate(bool value) {
    if (value == _animate) return;
    _animate = value;
    final clock = _clock;
    if (clock != null) {
      value
          ? clock.addListener(notifyListeners)
          : clock.removeListener(notifyListeners);
    } else {
      value ? _own.repeat() : _own.stop();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _clock?.removeListener(notifyListeners);
    _own.dispose();
    super.dispose();
  }
}
