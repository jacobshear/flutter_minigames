# flutter_minigames

Async turn-based mini-games for Flutter — 24 board, card, word and physics
games, plus the two machines they are built on.

The point of the package is not the games. It is that every game is a **pure
reducer** behind a **swappable transport**, so the same game runs pass-and-play
in your app today and networked over your own backend tomorrow with no change
to the game code.

```yaml
dependencies:
  flutter_minigames: ^0.1.0
```

## The two machines

**A turn engine.** Every game implements `TurnGame<S, M>`:

```dart
S applyMove(S state, M move);          // pure: no timers, no Random, no I/O
bool validateMove(S state, M move, String playerId);
GameOutcome? outcome(S state);
```

`applyMove` is a pure function. Randomness comes from the match seed, so a
match replays exactly from `(seed, moves)` — which is also what makes state
cheap to verify and impossible to desync.

**A transport seam.** `GameTransport` is four methods. `LocalTransport` ships
in the box for hot-seat; [`flutter_minigames_firebase`][fb] implements the same
interface over Realtime Database. The engine never imports a backend.

```dart
final controller = await MatchController.create<TicTacToeState, TicTacToeMove>(
  game: const TicTacToeGame(),
  transport: LocalTransport(),   // or your own
  matchId: 'abc',
  playerIds: const ['me', 'them'],
  localPlayerId: 'me',
  hotSeat: true,
  seed: 1,
);

return TicTacToeBoard(controller: controller);
```

## Import only what you use

The top-level barrel reaches every game, which means **nothing tree-shakes**:

```dart
import 'package:flutter_minigames/flutter_minigames.dart';  // all 24 games
```

Taking three games? Import three:

```dart
import 'package:flutter_minigames/core.dart';
import 'package:flutter_minigames/games/mancala.dart';
import 'package:flutter_minigames/games/gin_rummy.dart';
```

Use the barrel when you want the whole catalog (a launcher grid); use the
per-game entry points when you want three games' worth of app size.

## The games

| | |
|---|---|
| **Board** | Chess · Checkers · Reversi · Gomoku · Mancala (capture + avalanche) · 4 in a Row · Dots & Boxes · Tic-Tac-Toe · Sea Battle · Filler |
| **Card** | Gin Rummy · Go Fish · Crazy 8s |
| **Word** | Anagrams · Word Hunt · Word Bites |
| **Physics** | 8-Ball · Shuffleboard · Knockout · Mini Golf · Darts · Archery · Basketball · Cup Pong |

## Physics games and the network

A pure reducer cannot run a physics simulation — it would have to be
bit-identical on both devices. So physics games **simulate locally and
serialize the outcome**: the shooter runs the simulation, the move carries the
settled positions, and the receiver replays the recorded result rather than
re-simulating. `applyMove` stays pure and a desync is structurally impossible.

Two harnesses back these. `flame.dart` is a Forge2D top-down table for sliding
games. `engine3d.dart` is a hand-rolled perspective renderer for the throwing
games — painter's-algorithm depth sorting, ballistic launch solving, and a
near/far rim split so a ball sorts *between* the halves of a hoop.

## Shared layers

| Entry point | What it gives you |
|---|---|
| `core.dart` | `TurnGame`, `GameTransport`, `MatchController`, `LocalTransport` |
| `ui.dart` | `GameNotice`, `GamePill` — floating table chrome |
| `cards.dart` | Playing-card model, seeded shuffle, vector card faces |
| `words.dart` | Dictionary and word scoring (bundles the ENABLE list) |
| `flame.dart` | Forge2D table harness |
| `engine3d.dart` | Perspective camera, projectile integrator, launch solver |

## Status

`0.1.x`. The engine and transport seam are stable; individual games' `Style`
and `Sounds` classes are still moving. Pin a version if that matters to you.

Licensed under Apache-2.0.

[fb]: https://pub.dev/packages/flutter_minigames_firebase
