import 'package:flutter_minigames/src/core/core.dart';
import 'package:flutter_minigames/src/games/checkers/checkers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Flush pending microtasks so broadcast-stream listeners have run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  const game = CheckersGame();

  // Dark (a) at (5,0); red (b) at (4,1) and (2,3). Both landing squares
  // (3,2) and (1,4) are empty, so a jumps twice in one turn and wins.
  final from = CheckersState.index(5, 0);
  final mid1 = CheckersState.index(4, 1);
  final land1 = CheckersState.index(3, 2);
  final mid2 = CheckersState.index(2, 3);
  final land2 = CheckersState.index(1, 4);

  CheckersState doubleJumpPosition() {
    final cells = List<String?>.filled(64, null);
    cells[from] = 'a';
    cells[mid1] = 'b';
    cells[mid2] = 'b';
    return CheckersState(
      cells: cells,
      isKing: List<bool>.filled(64, false),
      playerIds: const ['a', 'b'],
      currentPlayerId: 'a',
    );
  }

  Future<MatchController<CheckersState, CheckersMove>> seeded(
    LocalTransport transport,
    String localPlayerId,
  ) async {
    final initial = doubleJumpPosition();
    final existing = await transport.loadMatch('dj');
    if (existing == null) {
      await transport.createMatch(Match(
        id: 'dj',
        gameId: game.id,
        playerIds: initial.playerIds,
        currentPlayerId: 'a',
        status: MatchStatus.open,
        turnCount: 0,
        state: game.encodeState(initial),
        schemaVersion: game.stateSchemaVersion,
      ));
    }
    final controller = MatchController<CheckersState, CheckersMove>(
      game: game,
      transport: transport,
      matchId: 'dj',
      localPlayerId: localPlayerId,
    );
    return controller;
  }

  group('checkers double jump replay', () {
    late LocalTransport transport;
    setUp(() => transport = LocalTransport());
    tearDown(() => transport.dispose());

    test('both legs are recorded as one turn', () async {
      final dark = await seeded(transport, 'a');
      await dark.connect();

      expect(
          await dark.submitMove(CheckersMove(from: from, to: land1)), isTrue);
      await _settle();
      expect(dark.state!.mustContinueFrom, land1);
      expect(
          await dark.submitMove(CheckersMove(from: land1, to: land2)), isTrue);
      await _settle();

      final stored = (await transport.loadMatch('dj'))!;
      expect(stored.isEnded, isTrue);
      expect(stored.winnerId, 'a');
      expect(stored.lastMoverId, 'a');
      expect(stored.turnSteps, hasLength(1));

      final preTurn = game.decodeState(stored.prevState!, stored.schemaVersion);
      expect(preTurn.cells[from], 'a', reason: 'piece back on its origin');
      expect(preTurn.cells[mid1], 'b');
      expect(preTurn.cells[mid2], 'b');

      final afterLeg1 =
          game.decodeState(stored.turnSteps!.single, stored.schemaVersion);
      expect(afterLeg1.cells[land1], 'a');
      expect(afterLeg1.cells[mid1], isNull);
      expect(afterLeg1.cells[mid2], 'b');
      expect(afterLeg1.mustContinueFrom, land1);

      await dark.dispose();
    });

    test('a cold open by the opponent replays leg one, then leg two', () async {
      final dark = await seeded(transport, 'a');
      await dark.connect();
      await dark.submitMove(CheckersMove(from: from, to: land1));
      await dark.submitMove(CheckersMove(from: land1, to: land2));
      await _settle();

      final red = await seeded(transport, 'b');
      final frames = <CheckersState>[];
      final sub = red.stateStream.listen(frames.add);
      await red.connect(replayLastTurn: true);
      await _settle();

      expect(frames, hasLength(1));
      expect(frames[0].cells[from], 'a');
      expect(frames[0].pieceCount('b'), 2);
      expect(red.match!.isOpen, isTrue);
      expect(red.isReplayingLastTurn, isTrue);

      await Future.delayed(
        MatchController.replayDelay + const Duration(milliseconds: 30),
      );
      expect(frames, hasLength(2));
      expect(frames[1].cells[land1], 'a');
      expect(frames[1].lastFrom, from);
      expect(frames[1].lastTo, land1);
      expect(frames[1].lastCaptured, mid1);
      expect(frames[1].pieceCount('b'), 1);
      expect(red.isReplayingLastTurn, isTrue);

      final step = game.replayStepDelay(frames[0], frames[1]);
      await Future.delayed(step + const Duration(milliseconds: 30));
      expect(frames, hasLength(3));
      expect(frames[2].cells[land2], 'a');
      expect(frames[2].lastFrom, land1);
      expect(frames[2].lastTo, land2);
      expect(frames[2].lastCaptured, mid2);
      expect(frames[2].pieceCount('b'), 0);
      expect(red.match!.isEnded, isTrue);
      expect(red.isReplayingLastTurn, isFalse);

      await sub.cancel();
      await dark.dispose();
      await red.dispose();
    });
  });
}
