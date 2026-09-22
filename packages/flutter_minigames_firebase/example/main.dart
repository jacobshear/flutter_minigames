// A two-device tic-tac-toe match over Firebase Realtime Database.
//
// Run this on two devices signed in as different users, with your app's
// Firebase configuration in place (`flutterfire configure`). Each device
// passes its own uid as `me`; whoever creates the match moves first.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_minigames/core.dart';
import 'package:flutter_minigames/games/tictactoe.dart';
import 'package:flutter_minigames_firebase/flutter_minigames_firebase.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MaterialApp(home: MatchScreen(me: 'alice', them: 'bob')));
}

class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key, required this.me, required this.them});

  final String me;
  final String them;

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  // Same path on both devices; lock it down with your RTDB security rules.
  final transport = FirebaseGameTransport(
    database: FirebaseDatabase.instance,
    rootPath: 'minigames/matches',
  );
  MatchController<TicTacToeState, TicTacToeMove>? controller;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    const matchId = 'alice-vs-bob';
    const game = TicTacToeGame();
    final existing = await transport.loadMatch(matchId);
    final c = existing == null
        ? await MatchController.create<TicTacToeState, TicTacToeMove>(
            game: game,
            transport: transport,
            matchId: matchId,
            playerIds: [widget.me, widget.them],
            localPlayerId: widget.me,
            seed: 42,
          )
        : MatchController<TicTacToeState, TicTacToeMove>(
            game: game,
            transport: transport,
            matchId: matchId,
            localPlayerId: widget.me,
          );
    if (existing != null) await c.connect(replayLastTurn: true);
    // A write the database refused (the other device moved first) is
    // reported here, never thrown.
    c.turnRejected.listen((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The other player moved first')),
      );
    });
    if (mounted) setState(() => controller = c);
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      body: Center(
        child: c == null
            ? const CircularProgressIndicator()
            : TicTacToeBoard(controller: c),
      ),
    );
  }
}
