# flutter_minigames

A library of **async turn-based mini-games** for Flutter — 24 board, card, word
and physics games, plus the two machines they're built on.

```yaml
dependencies:
  flutter_minigames: ^0.1.0
```

## Why this exists

I was building a social app and wanted GamePigeon-style games playable inside a
chat. Every option I found was either a single game hard-wired to one backend,
or a full game engine that wanted to own the whole app. What I actually needed
was a way to write a game **once** and have it work pass-and-play on one phone,
over my own backend, or over someone else's — without touching the game code.

So the interesting part isn't the 24 games. It's that each one is a **pure
reducer behind a swappable transport**:

1. **A turn engine** — `TurnGame` is a pure, serializable contract,
   `applyMove(state, move) -> newState`. No timers, no `Random`, no I/O.
   Randomness derives from the match seed, so a match replays exactly from
   `(seed, moves)` and a desync is structurally impossible.
2. **A transport seam** — `GameTransport` is four methods. `LocalTransport`
   ships for hot-seat; there's a Firebase Realtime Database adapter; yours
   plugs in the same way. The engine never imports a backend.

Write a game once; it plays on one device, over Firebase, over anything.

## The state of it

It's a side project, and it's rough in places — the games work and are well
tested, but plenty of boards and animations could be better, and the per-game
styling APIs are still moving. It's on `0.1.x` for a reason.

It's also **my first open source project**, published because the turn-engine
and transport seam seem genuinely reusable and I'd rather find out than sit on
them.

**Anyone is welcome to hop aboard.** Adding a game is the contribution this is
built to accept — a pure reducer plus a widget, with a ~900-test suite as the
safety net and everything hard (turns, sync, resume, serialization) already
handled. Bug reports and "this board looks flat" are just as welcome; that's
where it's weakest. Start with [CONTRIBUTING.md](CONTRIBUTING.md).

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
grid, quiet iOS-light chrome). Host apps (a chat sheet, your own launcher) embed
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

That's the entire loop — everything hard (turns, sync, resume) lives in the
engine. The full walkthrough, including how physics games differ, is in
[CONTRIBUTING.md](CONTRIBUTING.md#adding-a-game).

## Licensing

Code is **Apache-2.0** (`LICENSE`).

Bundled assets are licensed separately from the code, and both are original or
public domain: the sound effects are procedurally generated tones (see
`packages/example_app/assets/sfx/CREDITS.md`) and the word games use the
public-domain ENABLE word list. No third-party samples ship here.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Good places to start are labelled
[`good first issue`](https://github.com/jacobshear/flutter_minigames/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22).
