import 'package:example_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Drives a real game on a device and captures key visual states. Run with:
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/screenshots_test.dart -d DEVICE_ID
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Pump real frames without pumpAndSettle (the board breathes forever).
  Future<void> play(WidgetTester tester, int ms) async {
    var elapsed = 0;
    while (elapsed < ms) {
      await tester.pump(const Duration(milliseconds: 16));
      elapsed += 16;
    }
  }

  Offset cell(WidgetTester tester, int i) {
    final r = tester.getRect(find.byType(GridView));
    final cs = r.width / 3;
    return r.topLeft + Offset((i % 3 + 0.5) * cs, (i ~/ 3 + 0.5) * cs);
  }

  testWidgets('capture tic-tac-toe states', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // Main menu → open tic-tac-toe.
    await tester.tap(find.text('Tic-tac-toe'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await binding.convertFlutterSurfaceToImage();

    await play(tester, 1000); // grid entrance
    await binding.takeScreenshot('01_idle');

    await tester.tapAt(cell(tester, 0)); // X
    await play(tester, 640);
    await tester.tapAt(cell(tester, 4)); // O
    await play(tester, 640);
    await tester.tapAt(cell(tester, 1)); // X
    await play(tester, 640);
    await tester.tapAt(cell(tester, 5)); // O
    await play(tester, 640);
    await binding.takeScreenshot('02_midgame');

    await tester.tapAt(cell(tester, 2)); // X wins top row
    await play(tester, 420); // mid confetti / win line
    await binding.takeScreenshot('03_win_burst');

    await play(tester, 1200); // settled
    await binding.takeScreenshot('04_win_settled');
  });
}
