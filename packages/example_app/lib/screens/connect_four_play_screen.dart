import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:minigame_connect_four/minigame_connect_four.dart';
import 'package:minigames_core/minigames_core.dart';

import '../audio/demo_sfx.dart';
import '../multiplayer/play_session.dart';
import '../theme/demo_theme.dart';

/// Local hot-seat Connect Four via [PlaySession] (same multiplayer seam).
class ConnectFourPlayScreen extends StatefulWidget {
  final PlaySession? session;

  const ConnectFourPlayScreen({super.key, this.session});

  @override
  State<ConnectFourPlayScreen> createState() => _ConnectFourPlayScreenState();
}

class _ConnectFourPlayScreenState extends State<ConnectFourPlayScreen> {
  late final PlaySession _session;
  final ConnectFourGame _game = const ConnectFourGame();
  MatchController<ConnectFourState, ConnectFourMove>? _controller;
  int _round = 0;

  late final ConnectFourStyle _boardStyle = ConnectFourStyle(
    player0Color: DemoColors.coral,
    player1Color: DemoColors.teal,
    boardColor: const Color(0xFF2F5DA8),
    holeColor: const Color(0xFFF7F0E4),
    sounds: ConnectFourSounds(
      onDrop: (rows) => DemoSfx.instance.drop(longDrop: rows >= 4),
      onWin: DemoSfx.instance.win,
      onDraw: DemoSfx.instance.draw,
      onInvalid: DemoSfx.instance.invalid,
    ),
  );

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? PlaySession.localHotSeat();
    _startNewGame();
  }

  Future<void> _startNewGame() async {
    await _controller?.dispose();
    final controller =
        await MatchController.create<ConnectFourState, ConnectFourMove>(
      game: _game,
      transport: _session.transport,
      matchId: 'local-c4-$_round',
      playerIds: const ['p1', 'p2'],
      localPlayerId: 'p1',
      hotSeat: _session.hotSeat,
      seed: _round,
    );
    if (mounted) setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _session.dispose();
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
            colors: [DemoColors.paperTop, DemoColors.paperBottom],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.1),
                    radius: 0.95,
                    colors: [
                      DemoColors.teal.withValues(alpha: 0.12),
                      DemoColors.teal.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    _TopBar(onBack: () => Navigator.of(context).maybePop()),
                    const SizedBox(height: 8),
                    Text(
                      'Connect four',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.fraunces(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: DemoColors.ink,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _session.hotSeat
                          ? 'Hot seat · tap a column to drop'
                          : 'Networked match',
                      style: GoogleFonts.fraunces(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: DemoColors.ink.withValues(alpha: 0.5),
                      ),
                    ),
                    const Spacer(),
                    if (controller == null)
                      const CircularProgressIndicator()
                    else
                      _BoardCard(
                        child: ConnectFourBoard(
                          key: ValueKey(_round),
                          controller: controller,
                          style: _boardStyle,
                        ),
                      ),
                    const Spacer(),
                    _NewGameButton(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        DemoSfx.instance.newGame();
                        setState(() => _round++);
                        _startNewGame();
                      },
                    ),
                    const SizedBox(height: 20),
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

class _TopBar extends StatelessWidget {
  final VoidCallback onBack;
  const _TopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            onBack();
          },
          icon: const Icon(Icons.arrow_back_rounded),
          color: DemoColors.ink,
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: DemoColors.ink.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Local',
            style: GoogleFonts.fraunces(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DemoColors.ink.withValues(alpha: 0.55),
            ),
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
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 22),
      decoration: BoxDecoration(
        color: DemoColors.card,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: DemoColors.ink.withValues(alpha: 0.10),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: DemoColors.ink.withValues(alpha: 0.04),
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
            color: DemoColors.ink,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: DemoColors.ink.withValues(alpha: 0.22),
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
              color: DemoColors.paperTop,
            ),
          ),
        ),
      ),
    );
  }
}
