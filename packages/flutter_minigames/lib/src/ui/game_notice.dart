import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// What a notice is telling you. Tone drives the tint, the accent hairline and
/// the entrance — a score lands with a bounce, a rejection shakes.
enum GameNoticeTone {
  /// Neutral state: whose turn it is, what phase you're in.
  info,

  /// Points were scored. The common case, and the one worth celebrating.
  score,

  /// Something was refused — an illegal move, a burst, a miss.
  warn,

  /// The match is decided.
  win,
}

/// A floating message over a board.
///
/// Deliberately **not** an [AnimatedSwitcher]. A switcher keeps its outgoing
/// child mounted alongside the incoming one and keys both by the child's key
/// inside a [Stack], so any message that repeats — including the empty state
/// between two messages — collides with its own still-animating corpse and
/// throws "Duplicate keys found". Boards flip through short messages far
/// faster than a 220ms exit, so that is not a rare race. Here a single node
/// animates: swapping text can never produce two nodes, whatever the sequence.
///
/// Pass `message: null` to hide. Set [autoDismiss] to have the notice retract
/// on its own after it has been read — the caller keeps passing the same
/// message and does not have to run a timer.
class GameNotice extends StatefulWidget {
  /// Text to show, or null for nothing.
  final String? message;

  final GameNoticeTone tone;

  /// Overrides the tone's accent — use the acting seat's colour so a notice
  /// says who as well as what.
  final Color? accent;

  /// Retract this long after the message appears. Null keeps it up until the
  /// caller clears it.
  final Duration? autoDismiss;

  /// Larger type and a heavier fill, for the moments that deserve it.
  final bool strong;

  /// Distinguishes two occurrences that say the same thing.
  ///
  /// Identity is normally the [message] text, which is what lets a caller hold
  /// a message up across rebuilds without it re-firing. But some events repeat
  /// verbatim and each one still deserves its own beat — jabbing an illegal
  /// card twice should shake twice. Pass anything that changes per occurrence
  /// (a move counter, a rejection tally) and each becomes a fresh notice.
  final Object? token;

  const GameNotice({
    super.key,
    required this.message,
    this.tone = GameNoticeTone.info,
    this.accent,
    this.autoDismiss,
    this.strong = false,
    this.token,
  });

  @override
  State<GameNotice> createState() => _GameNoticeState();
}

class _GameNoticeState extends State<GameNotice>
    with SingleTickerProviderStateMixin {
  // Built in initState, never as a `late final` initialiser: a field
  // initialiser that first runs during dispose() looks up a deactivated
  // element's ancestor and throws.
  AnimationController? _ctrl;
  Timer? _dismiss;

  /// The message actually painted. Lags [GameNotice.message] by one exit so
  /// text does not change while the old notice is still on screen.
  String? _shown;
  GameNoticeTone _shownTone = GameNoticeTone.info;
  Color? _shownAccent;
  Object? _shownToken;

  /// A message waiting for the current one to finish retracting.
  String? _pending;

  /// A message [autoDismiss] has already retracted. Callers hold the same
  /// message up indefinitely — without this, the next rebuild would see a live
  /// `widget.message` against a cleared `_shown` and present it again, blinking
  /// on a loop forever. Cleared when the caller changes or clears the message,
  /// so re-firing the same text later still shows.
  String? _dismissed;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    )..addStatusListener(_onStatus);
    _shown = widget.message;
    _shownTone = widget.tone;
    _shownAccent = widget.accent;
    _shownToken = widget.token;
    if (_shown != null) {
      _ctrl!.forward();
      _armDismiss();
    }
  }

  @override
  void didUpdateWidget(GameNotice old) {
    super.didUpdateWidget(old);
    final next = widget.message;
    // A new token makes this a different occurrence of the same sentence, so
    // it re-fires exactly like fresh text would.
    final sameEvent = widget.token == _shownToken;
    // The caller moved on from whatever autoDismiss retracted, so the same
    // text may show again later.
    if (next != _dismissed || !sameEvent) _dismissed = null;
    if (next == _shown && widget.tone == _shownTone && sameEvent) {
      // Re-raised while it was leaving — message → null → same message inside
      // the exit. Without this the early return below lets it finish
      // retracting and the new copy is swallowed.
      if (next != null &&
          next != _dismissed &&
          _ctrl!.status == AnimationStatus.reverse) {
        _ctrl!.forward();
        _armDismiss();
        return;
      }
      // Same text, but the caller may have re-armed the timer by rebuilding
      // with a fresh autoDismiss.
      if (old.autoDismiss != widget.autoDismiss) _armDismiss();
      return;
    }
    if (next == null) {
      _pending = null;
      _retract();
      return;
    }
    // Already auto-dismissed and the caller is still holding it up: stay down.
    if (next == _dismissed) return;
    if (_shown == null || _ctrl!.isDismissed) {
      _present(next);
    } else {
      // Something is already up: retract it, then present this. One node, so
      // the two never coexist.
      _pending = next;
      _retract();
    }
  }

  void _onStatus(AnimationStatus s) {
    if (s != AnimationStatus.dismissed) return;
    final pending = _pending;
    if (pending == null) {
      if (_shown != null && mounted) setState(() => _shown = null);
      return;
    }
    _pending = null;
    _present(pending);
  }

  void _present(String message) {
    if (!mounted) return;
    setState(() {
      _shown = message;
      _shownTone = widget.tone;
      _shownAccent = widget.accent;
      _shownToken = widget.token;
    });
    _ctrl!.forward();
    _armDismiss();
  }

  void _retract() {
    _dismiss?.cancel();
    _dismiss = null;
    _ctrl!.reverse();
  }

  void _armDismiss() {
    _dismiss?.cancel();
    _dismiss = null;
    final after = widget.autoDismiss;
    if (after == null) return;
    _dismiss = Timer(after, () {
      if (!mounted) return;
      _dismissed = _shown;
      _retract();
    });
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = _shown;
    if (message == null) return const SizedBox.shrink();

    final palette = _NoticePalette.of(_shownTone, _shownAccent);
    final strong = widget.strong || _shownTone == GameNoticeTone.win;

    return AnimatedBuilder(
      animation: _ctrl!,
      builder: (context, child) {
        final v = _ctrl!.value;
        // Overshoot on the way in, straight fade on the way out — a notice
        // should arrive with weight and leave without asking for attention.
        final grow = _ctrl!.status == AnimationStatus.reverse
            ? Curves.easeIn.transform(v)
            : Curves.easeOutBack.transform(v);
        // A refusal shakes: two decaying swings, damped to nothing by the time
        // the entrance settles.
        final shake = _shownTone == GameNoticeTone.warn &&
                _ctrl!.status != AnimationStatus.reverse
            ? math.sin(v * math.pi * 4) * 9 * (1 - v)
            : 0.0;
        return Opacity(
          opacity: Curves.easeOut.transform(v.clamp(0.0, 1.0)),
          child: Transform.translate(
            offset: Offset(shake, (1 - grow) * 14),
            child: Transform.scale(
              scale: 0.88 + 0.12 * grow,
              child: child,
            ),
          ),
        );
      },
      child: _NoticeBody(
        message: message,
        palette: palette,
        strong: strong,
      ),
    );
  }

}

class _NoticePalette {
  final Color fill;
  final Color accent;
  final Color text;

  const _NoticePalette(this.fill, this.accent, this.text);

  static _NoticePalette of(GameNoticeTone tone, Color? override) {
    final base = switch (tone) {
      GameNoticeTone.info => const _NoticePalette(
          Color(0xE6101418), Color(0x33FFFFFF), Colors.white),
      GameNoticeTone.score => const _NoticePalette(
          Color(0xE6121A14), Color(0xFF6FD08C), Colors.white),
      GameNoticeTone.warn => const _NoticePalette(
          Color(0xE61C1113), Color(0xFFE2705F), Colors.white),
      GameNoticeTone.win => const _NoticePalette(
          Color(0xF01A1408), Color(0xFFE9B44C), Colors.white),
    };
    return override == null
        ? base
        : _NoticePalette(base.fill, override, base.text);
  }
}

/// The chrome itself. A capsule that reads as glass over felt: a blurred
/// backdrop so the board shows through, a bright top hairline for the lit
/// edge, and a tone-coloured underline that carries the meaning.
class _NoticeBody extends StatelessWidget {
  final String message;
  final _NoticePalette palette;
  final bool strong;

  const _NoticeBody({
    required this.message,
    required this.palette,
    required this.strong,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(strong ? 15 : 12);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(Colors.white.withValues(alpha: 0.07),
                    palette.fill),
                palette.fill,
              ],
            ),
            border: Border.all(
              color: palette.accent.withValues(alpha: 0.55),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.34),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: palette.accent.withValues(alpha: 0.20),
                blurRadius: 20,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: strong ? 18 : 14,
              vertical: strong ? 11 : 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: strong ? 15.5 : 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: strong ? 0.9 : 0.6,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 5),
                // The meaning-carrying stroke: colour without tinting the text.
                // Fixed width on purpose — a childless Container with only a
                // height expands to its incoming constraints, which stretched
                // the whole capsule across the board inside a Positioned.fill.
                SizedBox(
                  width: strong ? 34 : 26,
                  height: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
