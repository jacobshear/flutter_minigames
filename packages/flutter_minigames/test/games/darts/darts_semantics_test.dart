import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/darts/darts.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every semantics label currently in the tree.
List<String> _labels(WidgetTester tester) {
  final labels = <String>[];
  void walk(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  // ignore: deprecated_member_use
  walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return labels;
}

// The controller is never disposed, only the widget is unmounted — see
// test/games/cup_pong/cup_pong_board_test.dart for why.

void main() {
  testWidgets(
      'the scene is labelled on its own; the scores and darts left are read '
      'once, off the chips and the pill', (tester) async {
    final semantics = tester.ensureSemantics();
    final c = await MatchController.create<DartsState, DartsMove>(
      game: const DartsGame(),
      transport: LocalTransport(),
      matchId: 'semantics',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: false,
      seed: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 620,
              child: DartsBoardWidget(controller: c),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final labels = _labels(tester);
    expect(
      labels.where((l) => l.startsWith('Darts. Dartboard')),
      hasLength(1),
    );
    // The container no longer repeats what the chips and the pill say...
    expect(labels.where((l) => l.contains('left for')), isEmpty);
    expect(labels.where((l) => l.contains('left in this visit')), isEmpty);
    // ...and the darts left in the visit are read exactly once, off the pill.
    expect(
      labels.where((l) => RegExp(r'\b3 darts left\b').hasMatch(l)),
      hasLength(1),
    );
    semantics.dispose();
  });
}
