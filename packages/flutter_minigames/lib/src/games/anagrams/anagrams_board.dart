import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'anagrams_game.dart';
import 'anagrams_style.dart';

/// One player's timed Anagrams round, GP-style: wooden letter tiles on a
/// maroon felt table, a staging row the tapped tiles rise into, a big
/// countdown, live score ticker, and the found-word strip.
///
/// Self-contained: paints its own felt backdrop (repo convention) and runs
/// its own round timer off an [AnimationController]. When the timer expires
/// (or the player ends early) it calls [onRoundComplete] exactly once with
/// the raw found-word list — the pure game logic re-validates on submit.
class AnagramsRoundBoard extends StatefulWidget {
  final AnagramsGame game;
  final AnagramsState state;

  /// Label shown on the player chip (e.g. `'Player 1'`).
  final String playerLabel;

  final AnagramsStyle style;

  final ValueChanged<List<String>> onRoundComplete;

  const AnagramsRoundBoard({
    super.key,
    required this.game,
    required this.state,
    required this.playerLabel,
    required this.onRoundComplete,
    this.style = const AnagramsStyle(),
  });

  @override
  State<AnagramsRoundBoard> createState() => _AnagramsRoundBoardState();
}

class _AnagramsRoundBoardState extends State<AnagramsRoundBoard>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..forward();

  /// Round countdown: value 0 → 1 over the whole round.
  late final AnimationController _timer = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.game.roundSeconds),
  );

  /// Valid-word juice: green flash + rising score popup.
  late final AnimationController _valid = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  /// Invalid-word juice: staging-row shake + red flash.
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// Display order of letter indices in the rack (shuffle reorders).
  late final List<int> _rackOrder =
      List.generate(widget.state.letters.length, (i) => i);

  /// Letter indices currently staged, in tap order.
  final List<int> _staged = [];

  /// Accepted words, most recent first.
  final List<String> _found = [];

  int _score = 0;
  int _lastPoints = 0;
  bool _completed = false;
  final math.Random _rnd = math.Random();

  @override
  void initState() {
    super.initState();
    _timer.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finishRound(timedOut: true);
    });
    _timer.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _timer.dispose();
    _valid.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _finishRound({required bool timedOut}) {
    if (_completed) return;
    _completed = true;
    _timer.stop();
    if (timedOut) widget.style.sounds.onRoundEnd?.call();
    widget.onRoundComplete(List.of(_found));
  }

  String get _stagedWord =>
      _staged.map((i) => widget.state.letters[i]).join();

  void _tapTile(int letterIndex) {
    if (_completed) return;
    widget.style.sounds.onTap?.call();
    if (widget.style.haptics) HapticFeedback.selectionClick();
    setState(() {
      if (_staged.contains(letterIndex)) {
        _staged.remove(letterIndex);
      } else {
        _staged.add(letterIndex);
      }
    });
  }

  void _backspace() {
    if (_staged.isEmpty || _completed) return;
    widget.style.sounds.onTap?.call();
    if (widget.style.haptics) HapticFeedback.selectionClick();
    setState(() => _staged.removeLast());
  }

  void _shuffle() {
    if (_completed) return;
    widget.style.sounds.onTap?.call();
    if (widget.style.haptics) HapticFeedback.selectionClick();
    setState(() => _rackOrder.shuffle(_rnd));
  }

  void _submit() {
    if (_completed) return;
    final word = _stagedWord;
    if (word.isEmpty) return;
    final ok =
        widget.game.isAcceptableWord(widget.state, word) &&
            !_found.contains(word);
    if (ok) {
      final points = AnagramsGame.scoreForWord(word);
      widget.style.sounds.onValid?.call();
      if (widget.style.haptics) HapticFeedback.mediumImpact();
      setState(() {
        _found.insert(0, word);
        _score += points;
        _lastPoints = points;
        _staged.clear();
      });
      _valid.forward(from: 0);
    } else {
      widget.style.sounds.onInvalid?.call();
      if (widget.style.haptics) HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
    }
  }

  String _clock() {
    final total = widget.game.roundSeconds;
    final left = (total * (1 - _timer.value)).ceil().clamp(0, total);
    final m = left ~/ 60;
    final s = left % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  bool get _urgent =>
      widget.game.roundSeconds * (1 - _timer.value) <= 10 && !_completed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final table = style.resolveTable(scheme);

    return AnimatedBuilder(
      animation: Listenable.merge([_entrance, _timer, _valid, _shake]),
      builder: (context, _) {
        final enter = Curves.easeOutCubic.transform(_entrance.value);
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: RadialGradient(
              center: const Alignment(0, -0.35),
              radius: 1.5,
              colors: [
                Color.lerp(table, Colors.white, 0.07)!,
                table,
                Color.lerp(table, Colors.black, 0.26)!,
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                offset: const Offset(0, 6),
                blurRadius: 18,
              ),
            ],
          ),
          child: Opacity(
            opacity: enter.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.96 + 0.04 * enter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _header(),
                  const SizedBox(height: 10),
                  _timerBar(),
                  const SizedBox(height: 12),
                  _foundStrip(),
                  const SizedBox(height: 14),
                  _stagingRow(),
                  const SizedBox(height: 16),
                  _rack(),
                  const SizedBox(height: 16),
                  _actions(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header() {
    final style = widget.style;
    return Row(
      children: [
        // Player chip + live score.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.playerLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$_score',
                style: TextStyle(
                  color: style.validColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Big countdown.
        Text(
          _clock(),
          style: TextStyle(
            color: _urgent ? const Color(0xFFFF6B5E) : Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 30,
            letterSpacing: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _timerBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 5,
        child: LinearProgressIndicator(
          value: (1 - _timer.value).clamp(0.0, 1.0),
          backgroundColor: Colors.black.withValues(alpha: 0.25),
          valueColor: AlwaysStoppedAnimation(
            _urgent
                ? const Color(0xFFFF6B5E)
                : Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }

  Widget _foundStrip() {
    final style = widget.style;
    return SizedBox(
      height: 30,
      child: _found.isEmpty
          ? Center(
              child: Text(
                'Words you find appear here',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _found.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final w = _found[i];
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                    border: i == 0 && _valid.isAnimating
                        ? Border.all(
                            color: style.validColor.withValues(
                              alpha: 1 - _valid.value,
                            ),
                            width: 1.5,
                          )
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        w.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${AnagramsGame.scoreForWord(w)}',
                        style: TextStyle(
                          color: style.validColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _stagingRow() {
    final style = widget.style;
    final scheme = Theme.of(context).colorScheme;

    // Shake offset: damped sine while _shake runs.
    final shakeT = _shake.value;
    final dx = _shake.isAnimating
        ? math.sin(shakeT * math.pi * 6) * 9 * (1 - shakeT)
        : 0.0;

    final validGlow = _valid.isAnimating ? (1 - _valid.value) : 0.0;
    final invalidGlow = _shake.isAnimating ? (1 - shakeT) : 0.0;

    return LayoutBuilder(
      builder: (context, c) {
        final tile = _tileSize(c.maxWidth);
        return SizedBox(
          height: tile + 26,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Slot line the staged word sits on.
              Positioned(
                bottom: 6,
                left: c.maxWidth * 0.12,
                right: c.maxWidth * 0.12,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      Color.lerp(
                        Colors.black.withValues(alpha: 0.30),
                        style.validColor,
                        validGlow,
                      ),
                      style.invalidColor,
                      invalidGlow,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(dx, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final i in _staged) ...[
                      _LetterTile(
                        letter: widget.state.letters[i],
                        identity: i,
                        size: tile * 0.92,
                        style: style,
                        scheme: scheme,
                        onTap: () => _tapTile(i),
                        raised: true,
                        tint: invalidGlow > 0
                            ? style.invalidColor.withValues(
                                alpha: 0.22 * invalidGlow,
                              )
                            : null,
                      ),
                      const SizedBox(width: 5),
                    ],
                  ],
                ),
              ),
              // Rising score popup on valid submit.
              if (_valid.isAnimating && _lastPoints > 0)
                Positioned(
                  top: -6 - 26 * Curves.easeOutCubic.transform(_valid.value),
                  child: Opacity(
                    opacity: (1 - _valid.value).clamp(0.0, 1.0),
                    child: Text(
                      '+$_lastPoints',
                      style: TextStyle(
                        color: style.validColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        shadows: const [
                          Shadow(color: Colors.black38, blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  double _tileSize(double width) {
    final n = widget.state.letters.length;
    return math.min((width - (n - 1) * 8) / n, 58);
  }

  Widget _rack() {
    final style = widget.style;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final tile = _tileSize(c.maxWidth);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var k = 0; k < _rackOrder.length; k++) ...[
              if (k > 0) const SizedBox(width: 8),
              _staged.contains(_rackOrder[k])
                  ? _EmptySocket(size: tile)
                  : _LetterTile(
                      letter: widget.state.letters[_rackOrder[k]],
                      identity: _rackOrder[k],
                      size: tile,
                      style: style,
                      scheme: scheme,
                      onTap: () => _tapTile(_rackOrder[k]),
                    ),
            ],
          ],
        );
      },
    );
  }

  Widget _actions() {
    final style = widget.style;
    final hasStage = _staged.isNotEmpty;
    return Row(
      children: [
        _RoundIconButton(
          icon: Icons.shuffle_rounded,
          onTap: _shuffle,
        ),
        const SizedBox(width: 8),
        _RoundIconButton(
          icon: Icons.backspace_outlined,
          onTap: _backspace,
          enabled: hasStage,
        ),
        const Spacer(),
        // End round early (hot-seat convenience; GP just lets the clock run).
        GestureDetector(
          onTap: () => _finishRound(timedOut: false),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              'Done',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Submit.
        GestureDetector(
          onTap: _submit,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: hasStage ? 1 : 0.45,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 26, vertical: 11),
              decoration: BoxDecoration(
                color: style.validColor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    offset: const Offset(0, 3),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: const Text(
                'Enter',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A single wooden letter tile: rounded, subtle vertical gradient, dark glyph,
/// soft contact shadow. [raised] renders the slightly lifted staging look.
class _LetterTile extends StatelessWidget {
  final String letter;

  /// Letter index in the round letters — keeps keys unique when the same
  /// letter appears twice.
  final int identity;

  final double size;
  final AnagramsStyle style;
  final ColorScheme scheme;
  final VoidCallback onTap;
  final bool raised;
  final Color? tint;

  const _LetterTile({
    required this.letter,
    required this.identity,
    required this.size,
    required this.style,
    required this.scheme,
    required this.onTap,
    this.raised = false,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final top = style.resolveTileTop(scheme);
    final bottom = style.resolveTileBottom(scheme);
    final glyph = style.resolveGlyph(scheme);
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        key: ValueKey('tile-$identity-$raised'),
        tween: Tween(begin: 0.7, end: 1),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        builder: (context, pop, child) =>
            Transform.scale(scale: pop, child: child),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.22),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [top, bottom],
            ),
            border: Border.all(
              color: glyph.withValues(alpha: 0.35),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: raised ? 0.32 : 0.24),
                offset: Offset(0, raised ? 4 : 2.5),
                blurRadius: raised ? 8 : 5,
              ),
              // Inner-ish top highlight.
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.5),
                offset: const Offset(0, 1),
                blurRadius: 0,
                spreadRadius: -1,
              ),
            ],
          ),
          foregroundDecoration: tint == null
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 0.22),
                  color: tint,
                ),
          alignment: Alignment.center,
          child: Text(
            letter.toUpperCase(),
            style: TextStyle(
              color: glyph,
              fontSize: size * 0.52,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Recessed socket left behind in the rack while a tile is staged.
class _EmptySocket extends StatelessWidget {
  final double size;

  const _EmptySocket({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        color: Colors.black.withValues(alpha: 0.22),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: enabled ? 0.28 : 0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: enabled ? 0.9 : 0.4),
          size: 20,
        ),
      ),
    );
  }
}
