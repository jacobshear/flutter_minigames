import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/src/cards/cards.dart';

/// Paints [body] into a throwaway picture, so a painter can be exercised
/// without a widget tree.
ui.Picture _record(Size size, void Function(Canvas) body) {
  final recorder = ui.PictureRecorder();
  body(Canvas(recorder, Offset.zero & size));
  return recorder.endRecording();
}

void main() {
  setUp(clearPlayingCardCache);

  group('paintPlayingCard', () {
    test('renders all 52 faces at a range of sizes', () {
      for (final w in <double>[18, 40, 72, 140, 320]) {
        final size = Size(w, w * kCardAspectRatio);
        for (var i = 0; i < 52; i++) {
          final card = PlayingCard.fromIndex(i);
          expect(
            () => _record(
              size,
              (c) => paintPlayingCard(c, Offset.zero & size, card),
            ).dispose(),
            returnsNormally,
            reason: '${card.code} at ${w}px',
          );
        }
      }
    });

    test('renders the back at a range of sizes', () {
      for (final w in <double>[18, 40, 72, 140, 320]) {
        final size = Size(w, w * kCardAspectRatio);
        expect(
          () => _record(
            size,
            (c) => paintCardBack(c, Offset.zero & size),
          ).dispose(),
          returnsNormally,
        );
      }
    });

    test('faceUp: false paints the back instead of the face', () {
      const size = Size(60, 84);
      clearPlayingCardCache();
      _record(
        size,
        (c) => paintPlayingCard(
          c,
          Offset.zero & size,
          PlayingCard.parse('AS'),
          faceUp: false,
        ),
      ).dispose();
      final backOnlyKeys = playingCardCacheSize;
      _record(size, (c) => paintCardBack(c, Offset.zero & size)).dispose();
      // Same cache entry — the face was never recorded.
      expect(playingCardCacheSize, backOnlyKeys);
      expect(backOnlyKeys, 1);
    });

    test('degenerate rects are a no-op, not a crash', () {
      expect(
        () => _record(
          const Size(10, 10),
          (c) => paintPlayingCard(c, Rect.zero, PlayingCard.parse('AS')),
        ).dispose(),
        returnsNormally,
      );
      expect(playingCardCacheSize, 0);
    });
  });

  group('picture cache', () {
    test('reuses a recording for the same card, size and style', () {
      const size = Size(60, 84);
      final card = PlayingCard.parse('7H');
      for (var i = 0; i < 5; i++) {
        _record(size, (c) => paintPlayingCard(c, Offset.zero & size, card))
            .dispose();
      }
      expect(playingCardCacheSize, 1);
    });

    test('quantises size so sub-pixel jitter does not thrash it', () {
      final card = PlayingCard.parse('7H');
      for (final w in <double>[60.0, 60.1, 60.2]) {
        final size = Size(w, 84);
        _record(size, (c) => paintPlayingCard(c, Offset.zero & size, card))
            .dispose();
      }
      expect(playingCardCacheSize, 1);
    });

    test('a different style records separately', () {
      const size = Size(60, 84);
      final card = PlayingCard.parse('7H');
      _record(size, (c) => paintPlayingCard(c, Offset.zero & size, card))
          .dispose();
      _record(
        size,
        (c) => paintPlayingCard(
          c,
          Offset.zero & size,
          card,
          style: const PlayingCardStyle(red: Color(0xFFFF0000)),
        ),
      ).dispose();
      expect(playingCardCacheSize, 2);
    });

    test('is bounded — a size sweep cannot grow it without limit', () {
      final card = PlayingCard.parse('7H');
      for (var i = 0; i < 400; i++) {
        final size = Size(20 + i.toDouble(), 84);
        _record(size, (c) => paintPlayingCard(c, Offset.zero & size, card))
            .dispose();
      }
      expect(playingCardCacheSize, lessThanOrEqualTo(128));
    });
  });

  group('CardView', () {
    testWidgets('lays out at the standard aspect ratio', (tester) async {
      await tester.pumpWidget(
        Center(
          child: CardView(card: PlayingCard.parse('QS'), width: 80),
        ),
      );
      final size = tester.getSize(find.byType(CardView));
      expect(size.width, 80);
      expect(size.height, closeTo(80 * kCardAspectRatio, 0.01));
    });

    testWidgets('face-down needs no card', (tester) async {
      await tester.pumpWidget(
        const Center(child: CardView(card: null, width: 60, faceUp: false)),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('CardGlyphs', () {
    test('every rank label has strokes', () {
      for (final r in Rank.values) {
        for (final ch in r.label.split('')) {
          expect(CardGlyphs.strokes(ch), isNotEmpty, reason: r.label);
        }
      }
    });

    test('unknown glyphs are silently empty', () {
      expect(CardGlyphs.strokes('%'), isEmpty);
    });

    test('run width grows with the label', () {
      expect(
        CardGlyphs.runWidth('10', 10),
        greaterThan(CardGlyphs.runWidth('1', 10)),
      );
    });
  });

  group('CardSuits', () {
    test('every suit yields a non-empty path inside its rect', () {
      const rect = Rect.fromLTWH(0, 0, 10, 10);
      for (final s in Suit.values) {
        final path = CardSuits.path(s, rect);
        expect(path.computeMetrics().isEmpty, isFalse, reason: s.name);
        expect(rect.inflate(0.01).contains(path.getBounds().topLeft), isTrue);
      }
    });
  });
}
