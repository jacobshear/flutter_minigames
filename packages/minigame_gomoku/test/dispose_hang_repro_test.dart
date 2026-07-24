import 'package:flutter_test/flutter_test.dart';
import 'package:minigame_gomoku/minigame_gomoku.dart';
import 'package:minigames_core/minigames_core.dart';

void main() {
  test('dispose completes while a listener is still subscribed', () async {
    final transport = LocalTransport();
    final controller = await MatchController.create<GomokuState, GomokuMove>(
      game: const GomokuGame(),
      transport: transport,
      matchId: 'm1',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: true,
      seed: 0,
    );

    // Simulate the board: an active, uncancelled subscription.
    controller.stateStream.listen((_) {});

    // If dispose() deadlocks while subscribed, this future never completes and
    // the test times out. Guard with an explicit timeout to prove the point.
    await controller.dispose().timeout(
      const Duration(seconds: 2),
      onTimeout: () => fail('dispose() hung while a listener was subscribed'),
    );

    expect(true, isTrue);
  });
}
