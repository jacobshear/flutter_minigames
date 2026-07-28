# flutter_minigames

A transport-agnostic library of **async turn-based mini-games** for Flutter — GamePigeon-style games (board, card, and physics) that you can drop into any app.

The whole framework is two reusable machines:

1. **A turn engine** — a pure, serializable `TurnGame` contract (`applyMove(state, move) -> newState`). Implement it once per game.
2. **A transport seam** — a 4-method `GameTransport` interface. The same game runs hot-seat in the example app and networked inside your app with zero code changes. The core never imports any backend.

Build a game once; it plays pass-and-play, over Firebase, over anything.

## Repo layout (Dart pub workspace)

```
packages/
  flutter_minigames/          # the published package: engine, shared layers, 24 games
    lib/
      flutter_minigames.dart  # everything (reaches all games — defeats tree-shaking)
      core.dart ui.dart cards.dart words.dart flame.dart engine3d.dart
      games/<game>.dart       # per-game entry points, so 3 games cost 3 games
      src/{core,ui,cards,engine3d,flame,words}/
      src/games/<game>/
    example/                  # minimal one-game integration
  flutter_minigames_firebase/ # GameTransport over Realtime Database
  minigames_test/             # conformance suite any transport can run (not published)
  example_app/                # the full launcher: every game, hot-seat
```

Two published packages, not thirty. The earlier split meant a consumer needed a
`dependency_overrides` entry per transitive package — around thirty of them —
because inter-package deps resolved against pub.dev. One package, one
dependency, no overrides.

**The Firebase transport stays separate on purpose.** `firebase_core` and
`firebase_database` are the only native plugins in the tree; bundling them would
force a Firebase project onto every consumer and contradict the whole claim
below. Flame, Forge2D and the chess engine are pure Dart, so those bundle
freely and tree-shake.

### Reusability guarantees

- **Dependency inversion:** games depend on the `GameTransport` interface, never a
  backend. Swap `LocalTransport` for your own with no game changes.
- **Conformance suite:** `minigames_test` exposes `runGameTransportConformanceTests`
  — every transport (Local, Firebase, yours) proves it meets the same contract.
- **Purity:** `applyMove` has no timers, no `Random`, no I/O. Randomness derives
  from the match seed, so a match replays exactly from `(seed, moves)`.
- **Physics without desync:** simulate locally, serialize the outcome. The
  shooter runs the simulation and the move carries the settled positions; the
  receiver never re-simulates.
- **Private implementation:** only the entry points under `lib/` are public API;
  everything else lives in `lib/src/`.

## Architecture in one screen

```
        TurnGame<S,M>            GameTransport
        (per game)              (per backend)
             \                      /
              \                    /
               MatchController<S,M>   ← the object your UI holds
                     |
              stateStream / submitMove()
                     |
                 your widget
```

`MatchController` decodes state for the UI, validates local moves against the
game's own rules, and hands resulting turns to the transport. `LocalTransport`
(in-memory) ships in core; two controllers sharing one `LocalTransport` behave
exactly like two networked clients, which is how the example app runs and how
the tests prove the seam.

### Physics games (roadmap)

Physics games (pool, mini golf, shuffleboard, darts…) will use Flame +
flame_forge2d, and the turn is **simulate-locally, serialize-the-outcome**: the
shooter runs the sim and sends the resulting positions as authoritative state.
No cross-device deterministic physics required.

## Run it

```bash
flutter pub get                        # resolves the whole workspace
cd packages/example_app && flutter run # main menu → pick a game (local hot-seat)
```

The demo is a **full-screen GamePigeon-style launcher** (static illustrated
grid, quiet iOS-light chrome). Production hosts (e.g. the host app chat sheet) embed
the same catalog + play screens; multiplayer injects via
`example_app/lib/multiplayer/play_session.dart`
(`PlaySession.networked(yourTransport)`).

## Test

```bash
# everything: 912 tests across the engine, shared layers and all 24 games
(cd packages/flutter_minigames && flutter test)

# one area, or one game
(cd packages/flutter_minigames && flutter test test/core)
(cd packages/flutter_minigames && flutter test test/games/mancala)

(cd packages/minigames_test && dart test)             # transport conformance
(cd packages/example_app    && flutter test test/)    # launcher widget smoke
```

Note: run `flutter test test/` for `example_app` — pointing at the whole package
would also pick up `integration_test/`, which needs a device (below).

### Verifying the Firebase transport against the emulator

`minigames_firebase` compiles/analyzes without any Firebase config. To exercise
it against a real Realtime Database, run the shared conformance suite on the
emulator (config lives in `firebase.json` + `database.rules.json`):

```bash
# 1. start the emulator (needs a JRE + firebase-tools)
firebase emulators:start --only database --project demo-minigames

# 2. run the conformance suite on a device/simulator (iOS sim reaches 127.0.0.1)
cd packages/example_app
flutter test integration_test/firebase_conformance_test.dart -d "iPhone 17 Pro Max"
```

This runs the exact assertions `LocalTransport` passes — same contract, real
backend. (iOS FirebaseCore validates the app-id fingerprint as hex; the test
uses a well-formed placeholder so no real project is needed for emulator runs.)

## Adding a game

1. Under `packages/flutter_minigames/lib/src/games/<name>/`, implement
   `TurnGame<YourState, YourMove>` and give it a barrel `<name>.dart`.
2. Write a widget that takes a `MatchController<YourState, YourMove>`, renders
   `stateStream`, and calls `submitMove` on input.
3. Export it from `lib/flutter_minigames.dart` and add
   `lib/games/<name>.dart` so it can be imported on its own.
4. Add a row to `example_app/lib/catalog/game_catalog.dart` and a play screen
   that uses `PlaySession.localHotSeat()`.

That's the entire loop — everything hard (turns, sync, resume) lives in core.

## Licensing

Code is **Apache-2.0** (`LICENSE`). Bundled game assets, when added, will be
licensed separately (see `assets/CREDITS.md`) — asset and code licenses are
kept distinct.

## Status

Early. Skeleton + tic-tac-toe reference game. See the roadmap for the build
order (easiest games first; 8-ball last).
