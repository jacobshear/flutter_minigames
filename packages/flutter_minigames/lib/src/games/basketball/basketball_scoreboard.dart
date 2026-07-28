import 'package:flutter/material.dart';

/// The arcade scoreboard strip: `YOU 05 | 00:32 | OPPONENT 00`.
///
/// Digits are drawn as real seven-segment glyphs rather than set in a font.
/// Two reasons: it is the shipped look, and it means the readout renders
/// identically everywhere — including under the test font, where ordinary text
/// collapses into placeholder boxes and a snapshot tells you nothing.
class BasketballScoreboard extends StatelessWidget {
  /// Label over the left (shooting) score.
  final String leftLabel;

  /// Label over the right (waiting) score.
  final String rightLabel;

  /// Left score, zero-padded to two digits.
  final int leftScore;

  /// Right score, zero-padded to two digits.
  final int rightScore;

  /// Whole seconds left in the round.
  final int secondsLeft;

  /// Accent for the left label chip.
  final Color leftAccent;

  /// Accent for the right label chip.
  final Color rightAccent;

  /// Pulses the left score when it has just gone up.
  final double flash;

  /// Under ten seconds the clock goes hot.
  bool get urgent => secondsLeft <= 10;

  const BasketballScoreboard({
    super.key,
    required this.leftLabel,
    required this.rightLabel,
    required this.leftScore,
    required this.rightScore,
    required this.secondsLeft,
    required this.leftAccent,
    required this.rightAccent,
    this.flash = 0,
  });

  @override
  Widget build(BuildContext context) {
    final minutes = (secondsLeft ~/ 60).clamp(0, 99);
    final seconds = (secondsLeft % 60).clamp(0, 59);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF11151C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _side(
            label: leftLabel,
            score: leftScore,
            accent: leftAccent,
            glow: Color.lerp(
              const Color(0xFFFF7A3D),
              Colors.white,
              flash.clamp(0.0, 1.0) * 0.7,
            )!,
            align: CrossAxisAlignment.start,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Segments(
                text: '${_pad(minutes)}:${_pad(seconds)}',
                height: 26,
                color:
                    urgent ? const Color(0xFFFF5A4E) : const Color(0xFF5FE3A1),
              ),
            ],
          ),
          _side(
            label: rightLabel,
            score: rightScore,
            accent: rightAccent,
            glow: const Color(0xFF7FA6FF),
            align: CrossAxisAlignment.end,
          ),
        ],
      ),
    );
  }

  static String _pad(int v) => v.toString().padLeft(2, '0');

  Widget _side({
    required String label,
    required int score,
    required Color accent,
    required Color glow,
    required CrossAxisAlignment align,
  }) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
            ),
            const SizedBox(width: 5),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontWeight: FontWeight.w800,
                fontSize: 9.5,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        _Segments(text: _pad(score.clamp(0, 99)), height: 22, color: glow),
      ],
    );
  }
}

/// Draws a short string as seven-segment glyphs. Supports `0`-`9`, `:` and
/// space; anything else renders blank.
class _Segments extends StatelessWidget {
  final String text;
  final double height;
  final Color color;

  const _Segments({
    required this.text,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final painter = _SegmentPainter(text: text, color: color);
    return SizedBox(
      width: painter.widthFor(height),
      height: height,
      child: CustomPaint(painter: painter),
    );
  }
}

class _SegmentPainter extends CustomPainter {
  final String text;
  final Color color;

  _SegmentPainter({required this.text, required this.color});

  /// Segment lit-map per glyph, in `abcdefg` order.
  static const Map<String, String> _map = {
    '0': 'abcdef',
    '1': 'bc',
    '2': 'abged',
    '3': 'abgcd',
    '4': 'fgbc',
    '5': 'afgcd',
    '6': 'afgecd',
    '7': 'abc',
    '8': 'abcdefg',
    '9': 'abcdfg',
  };

  double _advance(String ch, double h) =>
      ch == ':' ? h * 0.26 : (ch == ' ' ? h * 0.30 : h * 0.62);

  double widthFor(double h) {
    var w = 0.0;
    for (final ch in text.split('')) {
      w += _advance(ch, h);
    }
    return w;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final t = h * 0.15;
    var x = 0.0;
    for (final ch in text.split('')) {
      final adv = _advance(ch, h);
      if (ch == ':') {
        final r = t * 0.42;
        canvas.drawCircle(
          Offset(x + adv / 2, h * 0.34),
          r,
          Paint()..color = color,
        );
        canvas.drawCircle(
          Offset(x + adv / 2, h * 0.70),
          r,
          Paint()..color = color,
        );
      } else if (_map.containsKey(ch)) {
        _digit(canvas, x, adv - h * 0.12, h, t, _map[ch]!);
      }
      x += adv;
    }
  }

  void _digit(
      Canvas canvas, double x, double w, double h, double t, String on) {
    final x0 = x + t * 0.62;
    final x1 = x + w - t * 0.62;
    final y0 = t * 0.62;
    final ym = h / 2;
    final y1 = h - t * 0.62;

    final lit = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = t
      ..color = color;
    final off = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = t
      ..color = color.withValues(alpha: 0.09);

    void seg(String id, Offset a, Offset b) =>
        canvas.drawLine(a, b, on.contains(id) ? lit : off);

    seg('a', Offset(x0, y0), Offset(x1, y0));
    seg('b', Offset(x1, y0), Offset(x1, ym));
    seg('c', Offset(x1, ym), Offset(x1, y1));
    seg('d', Offset(x0, y1), Offset(x1, y1));
    seg('e', Offset(x0, ym), Offset(x0, y1));
    seg('f', Offset(x0, y0), Offset(x0, ym));
    seg('g', Offset(x0, ym), Offset(x1, ym));
  }

  @override
  bool shouldRepaint(_SegmentPainter old) =>
      old.text != text || old.color != color;
}
