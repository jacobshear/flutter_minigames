import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/archery/archery.dart';
import 'package:flutter_minigames/src/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';

// The controller is never disposed, only the widget is unmounted — see
// test/games/cup_pong/cup_pong_board_test.dart for why.

/// Labels made only of whitespace: an empty node a screen reader can land on.
List<String> _blankLabels(WidgetTester tester) {
  final blanks = <String>[];
  void walk(SemanticsNode node) {
    if (node.label.isNotEmpty && node.label.trim().isEmpty) {
      blanks.add(node.label);
    }
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  // ignore: deprecated_member_use
  walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return blanks;
}

/// A match that is already over, loaded the way a finished game is reopened.
Future<MatchController<ArcheryState, ArcheryMove>> _finished() async {
  const game = ArcheryGame();
  final transport = LocalTransport();
  final c = await MatchController.create<ArcheryState, ArcheryMove>(
    game: game,
    transport: transport,
    matchId: 'end-hint',
    playerIds: const ['p1', 'p2'],
    localPlayerId: 'p1',
    hotSeat: false,
    seed: 0,
  );
  final start = c.state!;
  final over = ArcheryState(
    playerIds: start.playerIds,
    seed: start.seed,
    shots: {
      'p1': [
        for (var i = 0; i < ArcheryGame.arrowsPerPlayer; i++)
          const ArrowShot(ring: 10, offsetX: 0, offsetY: 0, onFace: true),
      ],
      'p2': [
        for (var i = 0; i < ArcheryGame.arrowsPerPlayer; i++)
          const ArrowShot(ring: 5, offsetX: 0.3, offsetY: 0, onFace: true),
      ],
    },
  );
  await transport.submitTurn(
    Match(
      id: 'end-hint',
      gameId: game.id,
      playerIds: const ['p1', 'p2'],
      currentPlayerId: 'p1',
      status: MatchStatus.ended,
      turnCount: 1,
      state: game.encodeState(over),
      schemaVersion: game.stateSchemaVersion,
    ),
  );
  expect(c.outcome, isNotNull, reason: 'the fixture is a finished match');
  return c;
}

Widget _host(
  MatchController<ArcheryState, ArcheryMove> c, {
  bool? hostOwnsStatus,
}) {
  Widget board = ArcheryRange(controller: c);
  if (hostOwnsStatus != null) {
    board = GameHostChrome(hostOwnsStatus: hostOwnsStatus, child: board);
  }
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, height: 640, child: board)),
    ),
  );
}

void main() {
  testWidgets('the blank end hint under a host is not an empty node',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final c = await _finished();
    await tester.pumpWidget(_host(c, hostOwnsStatus: true));
    await tester.pump(const Duration(seconds: 1));

    // The line is still laid out, so the range keeps its height...
    expect(find.text(' '), findsOneWidget);
    // ...but a screen reader has nothing to land on.
    expect(_blankLabels(tester), isEmpty);
    expect(find.bySemanticsLabel(RegExp('Tap New game')), findsNothing);
    semantics.dispose();
  });

  testWidgets('without a host the end hint is still read', (tester) async {
    final semantics = tester.ensureSemantics();
    final c = await _finished();
    await tester.pumpWidget(_host(c));
    await tester.pump(const Duration(seconds: 1));

    expect(find.bySemanticsLabel('Tap New game to shoot again'), findsOneWidget);
    expect(_blankLabels(tester), isEmpty);
    semantics.dispose();
  });
}
