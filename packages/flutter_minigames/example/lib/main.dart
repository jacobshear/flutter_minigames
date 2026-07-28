// The smallest useful integration: one game, one transport, one widget.
//
// Note the imports — `core.dart` plus a single game, rather than the top-level
// barrel. The barrel reaches all 24 games, so importing it would keep every
// one of them alive through tree-shaking.
import 'package:flutter/material.dart';
import 'package:flutter_minigames/core.dart';
import 'package:flutter_minigames/games/mancala.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'flutter_minigames example',
        home: const _Table(),
      );
}

class _Table extends StatefulWidget {
  const _Table();

  @override
  State<_Table> createState() => _TableState();
}

class _TableState extends State<_Table> {
  MatchController<MancalaState, MancalaMove>? _controller;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // LocalTransport is hot-seat. Swap in a networked GameTransport — e.g.
    // flutter_minigames_firebase — and nothing else here changes.
    final controller = await MatchController.create<MancalaState, MancalaMove>(
      game: const MancalaGame(),
      transport: LocalTransport(),
      matchId: 'example',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: true,
      seed: 7,
    );
    if (mounted) setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Mancala')),
      body: Center(
        child: controller == null
            ? const CircularProgressIndicator()
            : MancalaBoard(controller: controller),
      ),
    );
  }
}
