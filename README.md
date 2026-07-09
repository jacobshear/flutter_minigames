# flutter_minigames

A transport-agnostic library of **async turn-based mini-games** for Flutter — GamePigeon-style games (board, card, and physics) that you can drop into any app.

The whole framework is two reusable machines:

1. **A turn engine** — a pure, serializable `TurnGame` contract (`applyMove(state, move) -> newState`). Implement it once per game.
2. **A transport seam** — a 4-method `GameTransport` interface. The same game runs hot-seat in the example app and networked inside your app with zero code changes. The core never imports any backend.

Build a game once; it plays pass-and-play, over Firebase, over anything.

## Repo layout (Dart pub workspace + Melos)

```
packages/
  minigames_core/         # pure Dart: TurnGame, Match, GameTransport, LocalTransport, MatchController
  minigames_test/         # shared conformance suite any GameTransport can run
  minigame_tictactoe/     # reference game: logic + animated board
  minigame_connect_four/    # connect four: gravity drops + animated board
  minigame_dots_and_boxes/   # dots and boxes: edges, box chains, extra turns
  minigame_reversi/           # reversi/othello: flips, passes, scores
  minigames_firebase/        # GameTransport backed by Firebase Realtime Database
  example_app/               # GP-style launcher + local hot-seat; multiplayer seam ready
```

- `minigames_core` imports **nothing** — no Flutter, no Firebase, no Flame.
- Per-game packages depend only on `minigames_core` (+ Flutter for their widget).
- Backend adapters (e.g. `minigames_firebase`) are optional standalone packages —
  consumers who don't use Firebase never pull it. The core stays backend-free.
- Physics games (later) add a `minigames_flame` adapter so board-game consumers don't pull Flame.

### Reusability guarantees

- **Dependency inversion:** games depend on the `GameTransport` interface, never a
  backend. Swap `LocalTransport` ↔ `FirebaseGameTransport` with no game changes.
- **Conformance suite:** `minigames_test` exposes `runGameTransportConformanceTests`
  — every transport (Local, Firebase, yours) proves it meets the same contract.
- **Private implementation:** only barrel files are public API; the rest is `src/`.

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
# unit / widget (run inside each package)
(cd packages/minigames_core   && dart test)      # turn engine
(cd packages/minigames_test   && dart test)      # transport conformance (LocalTransport)
(cd packages/minigame_tictactoe    && flutter test) # tic-tac-toe logic
(cd packages/minigame_connect_four    && flutter test) # connect four
(cd packages/minigame_dots_and_boxes  && flutter test) # dots and boxes
(cd packages/example_app              && flutter test test/)  # widget smoke
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

1. In a new `minigame_<name>` package, implement `TurnGame<YourState, YourMove>`.
2. Write a widget that takes a `MatchController<YourState, YourMove>`, renders
   `stateStream`, and calls `submitMove` on input.
3. Add a row to `example_app/lib/catalog/game_catalog.dart` and a play screen
   that uses `PlaySession.localHotSeat()`.

That's the entire loop — everything hard (turns, sync, resume) lives in core.

## Licensing

Code is **Apache-2.0** (`LICENSE`). Bundled game assets, when added, will be
licensed separately (see `assets/CREDITS.md`) — asset and code licenses are
kept distinct.

## Status

Early. Skeleton + tic-tac-toe reference game. See the roadmap for the build
order (easiest games first; 8-ball last).
