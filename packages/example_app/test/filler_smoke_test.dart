import 'package:example_app/screens/filler_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_minigames/games/filler.dart';

void main() {
  testWidgets('filler play screen boots, accepts a move, restarts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: FillerPlayScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(FillerPlayScreen), findsOneWidget);
    expect(find.byType(FillerBoard), findsOneWidget);
    expect(find.text('Filler'), findsOneWidget);

    // All six swatches are on screen.
    for (var c = 0; c < 6; c++) {
      expect(find.byKey(ValueKey('filler_swatch_$c')), findsOneWidget);
    }

    // Let the entrance animation land, then tap every swatch: two are
    // forbidden (no-ops), at least one legal pick triggers the capture
    // animation. Pump generously through each so animations complete.
    await tester.pump(const Duration(milliseconds: 700));
    for (var c = 0; c < 6; c++) {
      await tester.tap(
        find.byKey(ValueKey('filler_swatch_$c')),
        warnIfMissed: false,
      );
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(FillerBoard), findsOneWidget);

    // New game resets cleanly.
    await tester.tap(find.text('New game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    expect(find.byType(FillerBoard), findsOneWidget);
  });
}
