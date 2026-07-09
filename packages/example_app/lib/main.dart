import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:minigame_tictactoe/minigame_tictactoe.dart';
import 'package:minigames_core/minigames_core.dart';

// Warm editorial palette — the demo's brand, injected into the reusable board.
const _ink = Color(0xFF2E2A26);
const _coral = Color(0xFFEE5D50); // X
const _teal = Color(0xFF14A08D); // O
const _paperTop = Color(0xFFFBF5EA);
const _paperBottom = Color(0xFFF1E4CF);
const _card = Color(0xFFFFFDF8);

const _boardStyle = TicTacToeStyle(
  xColor: _coral,
  oColor: _teal,
  gridColor: Color(0xD12E2A26), // ink at ~82% for softer lines
);

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _coral,
      brightness: Brightness.light,
    ).copyWith(surface: _card, tertiary: _teal);

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);

    return MaterialApp(
      title: 'flutter_minigames',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: _paperTop,
        textTheme: GoogleFonts.frauncesTextTheme(base.textTheme)
            .apply(bodyColor: _ink, displayColor: _ink),
      ),
      home: const TicTacToeScreen(),
    );
  }
}

/// Hot-seat tic-tac-toe: one device, two players, everything routed through the
/// exact same [MatchController] + [LocalTransport] a networked game would use.
class TicTacToeScreen extends StatefulWidget {
  const TicTacToeScreen({super.key});

  @override
  State<TicTacToeScreen> createState() => _TicTacToeScreenState();
}

class _TicTacToeScreenState extends State<TicTacToeScreen> {
  final LocalTransport _transport = LocalTransport();
  final TicTacToeGame _game = const TicTacToeGame();
  MatchController<TicTacToeState, TicTacToeMove>? _controller;
  int _round = 0; // rebuild key so a new game restages entrance animations

  @override
  void initState() {
    super.initState();
    _startNewGame();
  }

  Future<void> _startNewGame() async {
    await _controller?.dispose();
    final controller =
        await MatchController.create<TicTacToeState, TicTacToeMove>(
      game: _game,
      transport: _transport,
      matchId: 'local-match-$_round',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: true,
      seed: _round,
    );
    if (mounted) setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _transport.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_paperTop, _paperBottom],
          ),
        ),
        child: Stack(
          children: [
            // Soft warm bloom behind the board for depth.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.15),
                    radius: 0.9,
                    colors: [
                      _coral.withValues(alpha: 0.10),
                      _coral.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    const _Header(),
                    const Spacer(),
                    if (controller == null)
                      const CircularProgressIndicator()
                    else
                      _BoardCard(
                        child: TicTacToeBoard(
                          key: ValueKey(_round),
                          controller: controller,
                          style: _boardStyle,
                        ),
                      ),
                    const Spacer(),
                    _NewGameButton(onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _round++);
                      _startNewGame();
                    }),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Tic · Tac · Toe',
          textAlign: TextAlign.center,
          style: GoogleFonts.fraunces(
            fontSize: 40,
            fontWeight: FontWeight.w700,
            color: _ink,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'a flutter_minigames demo',
          style: GoogleFonts.fraunces(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontStyle: FontStyle.italic,
            color: _ink.withValues(alpha: 0.55),
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _BoardCard extends StatelessWidget {
  final Widget child;
  const _BoardCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 30),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: _ink.withValues(alpha: 0.10),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: _ink.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _NewGameButton extends StatefulWidget {
  final VoidCallback onTap;
  const _NewGameButton({required this.onTap});

  @override
  State<_NewGameButton> createState() => _NewGameButtonState();
}

class _NewGameButtonState extends State<_NewGameButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 110),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 15),
          decoration: BoxDecoration(
            color: _ink,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: _ink.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            'New game',
            style: GoogleFonts.fraunces(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: _paperTop,
            ),
          ),
        ),
      ),
    );
  }
}
