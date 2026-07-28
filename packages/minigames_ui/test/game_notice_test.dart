import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minigames_ui/minigames_ui.dart';

Widget _host(String? message, {Duration? autoDismiss}) => MaterialApp(
      home: Scaffold(
        // A Stack is what AnimatedSwitcher used internally and where the
        // duplicate-key assert fired, so the regression tests sit in one too.
        body: Stack(
          alignment: Alignment.center,
          children: [
            const SizedBox.expand(),
            GameNotice(message: message, autoDismiss: autoDismiss),
          ],
        ),
      ),
    );

void main() {
  group('the duplicate-key crash', () {
    // The real Mancala sequence: 'AGAIN!' fires on consecutive extra turns, so
    // the same text comes back before the previous one has finished leaving.
    testWidgets('the same message may repeat mid-exit', (tester) async {
      await tester.pumpWidget(_host('AGAIN!'));
      await tester.pumpAndSettle();

      for (var i = 0; i < 6; i++) {
        await tester.pumpWidget(_host(null));
        await tester.pump(const Duration(milliseconds: 40)); // mid-exit
        await tester.pumpWidget(_host('AGAIN!'));
        await tester.pump(const Duration(milliseconds: 40)); // mid-entrance
      }
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.text('AGAIN!'), findsOneWidget);
    });

    testWidgets('messages may alternate faster than the animation',
        (tester) async {
      await tester.pumpWidget(_host('A'));
      await tester.pump();
      for (final m in ['B', 'A', 'B', null, 'A', 'A', null, 'B']) {
        await tester.pumpWidget(_host(m));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);
    });

    // A board that clears then immediately re-raises the same event inside the
    // 180ms exit — the early return on `next == _shown` used to let it finish
    // retracting and swallow the new copy entirely.
    testWidgets('a message re-raised during its own exit comes back',
        (tester) async {
      await tester.pumpWidget(_host('MISS'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_host(null));
      await tester.pump(const Duration(milliseconds: 60)); // mid-exit
      await tester.pumpWidget(_host('MISS'));
      await tester.pumpAndSettle();

      expect(find.text('MISS'), findsOneWidget,
          reason: 'the re-raised message was swallowed by the exit');
    });

    testWidgets('only ever one notice is mounted', (tester) async {
      await tester.pumpWidget(_host('one'));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pumpWidget(_host('two'));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pumpWidget(_host('three'));
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.byType(GameNotice), findsOneWidget);
      expect(find.text('two'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('three'), findsOneWidget);
    });
  });

  group('behaviour', () {
    testWidgets('a null message renders nothing once it has retracted',
        (tester) async {
      await tester.pumpWidget(_host('gone'));
      await tester.pumpAndSettle();
      expect(find.text('gone'), findsOneWidget);
      await tester.pumpWidget(_host(null));
      await tester.pumpAndSettle();
      expect(find.text('gone'), findsNothing);
    });

    testWidgets('a queued message is presented after the exit', (tester) async {
      await tester.pumpWidget(_host('first'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host('second'));
      // Still showing the first while it retracts — text must not swap under
      // a visible notice.
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('first'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);
    });

    testWidgets('autoDismiss retracts on its own', (tester) async {
      await tester.pumpWidget(
        _host('pegged 3', autoDismiss: const Duration(milliseconds: 500)),
      );
      await tester.pumpAndSettle();
      expect(find.text('pegged 3'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('pegged 3'), findsNothing);
    });

    testWidgets('a pending dismiss timer does not fire after dispose',
        (tester) async {
      await tester.pumpWidget(
        _host('bye', autoDismiss: const Duration(seconds: 5)),
      );
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
    });

    testWidgets('every tone builds', (tester) async {
      for (final tone in GameNoticeTone.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: GameNotice(message: tone.name, tone: tone)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(tone.name), findsOneWidget);
      }
    });
  });

  group('sizing', () {
    // The tone underline was a childless Container with only a height, which
    // takes its maximum incoming width — so inside the natural
    // Positioned.fill + Center usage the capsule spanned the whole board.
    testWidgets('the capsule hugs its text inside an unbounded parent',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(child: Center(child: GameNotice(message: 'X'))),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final w = tester.getSize(find.byType(GameNotice)).width;
      final screen = tester.getSize(find.byType(Scaffold)).width;
      expect(w, lessThan(screen / 2),
          reason: 'the notice stretched to fill its parent');
    });

    testWidgets('a long message still fits its parent', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: GameNotice(
                message: 'PLAYER TWO PEGS TWENTY THREE AND TAKES THE LEAD',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('autoDismiss', () {
    // Boards rebuild every tick while holding the same message up. Once the
    // timer retracted, _shown went null against a live widget.message, so the
    // next rebuild re-presented it — a notice blinking on a loop forever.
    testWidgets('stays down while the caller keeps holding the message',
        (tester) async {
      Widget host() => MaterialApp(
            home: Scaffold(
              body: Center(
                child: GameNotice(
                  // Non-const: a fresh instance every rebuild, like a real
                  // board. A const widget short-circuits didUpdateWidget and
                  // hides the bug entirely.
                  message: 'CUP!',
                  autoDismiss: const Duration(milliseconds: 600),
                ),
              ),
            ),
          );
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('CUP!'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('CUP!'), findsNothing);

      // Keep rebuilding with the same message, as a ticking board does.
      for (var i = 0; i < 20; i++) {
        await tester.pumpWidget(host());
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.text('CUP!'), findsNothing,
            reason: 'the notice came back on rebuild $i');
      }
    });

    testWidgets('the same message shows again after the caller clears it',
        (tester) async {
      Widget host(String? m) => MaterialApp(
            home: Scaffold(
              body: Center(
                child: GameNotice(
                  message: m,
                  autoDismiss: const Duration(milliseconds: 600),
                ),
              ),
            ),
          );
      await tester.pumpWidget(host('MISS'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('MISS'), findsNothing);

      await tester.pumpWidget(host(null));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host('MISS'));
      await tester.pumpAndSettle();
      expect(find.text('MISS'), findsOneWidget,
          reason: 'a re-fired message must not be suppressed forever');
    });

    testWidgets('a different message after a dismiss still shows',
        (tester) async {
      Widget host(String m) => MaterialApp(
            home: Scaffold(
              body: Center(
                child: GameNotice(
                  message: m,
                  autoDismiss: const Duration(milliseconds: 600),
                ),
              ),
            ),
          );
      await tester.pumpWidget(host('MISS'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host('CUP!'));
      await tester.pumpAndSettle();
      expect(find.text('CUP!'), findsOneWidget);
    });
  });

  group('token', () {
    // Jabbing an illegal card twice should shake twice. Message equality alone
    // makes the second jab a no-op, because the text is identical.
    testWidgets('a new token re-fires an identical message', (tester) async {
      Widget host(int rejections) => MaterialApp(
            home: Scaffold(
              body: Center(
                child: GameNotice(
                  message: "CAN'T PLAY THAT",
                  tone: GameNoticeTone.warn,
                  token: rejections,
                  autoDismiss: const Duration(milliseconds: 600),
                ),
              ),
            ),
          );
      await tester.pumpWidget(host(1));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text("CAN'T PLAY THAT"), findsNothing);

      // Second jab: same sentence, new occurrence.
      await tester.pumpWidget(host(2));
      await tester.pumpAndSettle();
      expect(find.text("CAN'T PLAY THAT"), findsOneWidget,
          reason: 'the repeat jab was swallowed by message equality');
    });

    testWidgets('an unchanged token still holds the message down',
        (tester) async {
      Widget host() => MaterialApp(
            home: Scaffold(
              body: Center(
                child: GameNotice(
                  message: 'HELD',
                  token: 7,
                  autoDismiss: const Duration(milliseconds: 600),
                ),
              ),
            ),
          );
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.pumpWidget(host());
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.text('HELD'), findsNothing, reason: 'came back on $i');
      }
    });

    testWidgets('a token change mid-animation never doubles the node',
        (tester) async {
      Widget host(int t) => MaterialApp(
            home: Scaffold(
              body: Stack(alignment: Alignment.center, children: [
                const SizedBox.expand(),
                GameNotice(message: 'FOUL', token: t),
              ]),
            ),
          );
      await tester.pumpWidget(host(0));
      for (var i = 1; i < 8; i++) {
        await tester.pumpWidget(host(i));
        await tester.pump(const Duration(milliseconds: 30));
        expect(find.byType(GameNotice), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('GamePill', () {
    testWidgets('renders text, and a dot when it has an accent',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: GamePill(
                text: 'Player 1',
                accent: Color(0xFFE2705F),
                dot: true,
                strong: true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Player 1'), findsOneWidget);
    });

    testWidgets('a long label ellipsises rather than overflowing',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 80,
                child: GamePill(text: 'an extremely long seat label here'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
