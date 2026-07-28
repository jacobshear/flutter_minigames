# Contributing

Thanks for looking. This is a side project, and help is genuinely welcome —
whether that's a whole new game, a bug report, or telling me a doc paragraph
made no sense.

I'm not precious about it. If you're unsure whether something is worth doing,
open an issue and ask; that's cheaper for both of us than you building
something I then have opinions about.

## Ways to help, roughly by effort

| | |
|---|---|
| **Report a bug** | Especially anything visual. A screenshot beats a paragraph. |
| **Fix a rough edge** | Look for [`good first issue`][gfi]. Several are cosmetic and self-contained. |
| **Improve a game's feel** | Physics that don't land right, animations that snap, boards that read as flat. This is where the project is weakest and the bar to improve it is low. |
| **Add a game** | The big one. See below — the contract makes this much more tractable than it sounds. |
| **Add a transport** | Implement `GameTransport` over your backend of choice and it works with every game. There's a conformance suite that proves it. |

[gfi]: https://github.com/jacobshear/flutter_minigames/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22

## Getting set up

```bash
git clone https://github.com/jacobshear/flutter_minigames.git
cd flutter_minigames
flutter pub get                                   # one lockfile, whole workspace
(cd packages/example_app && flutter run)          # the launcher, every game
```

Before you open a PR:

```bash
flutter analyze                                            # must be clean
dart format packages                                       # CI enforces this
(cd packages/flutter_minigames && flutter test)            # ~900 tests, ~10s
(cd packages/example_app && flutter test test/)
```

`flutter test test/` for `example_app` — pointing at the whole package picks up
`integration_test/`, which needs a device.

## Adding a game

This is the contribution the project is built to accept. A game is a **pure
reducer plus a widget**, and everything hard — turns, sync, resume,
serialization — already lives in the engine.

### 1. The rules, as a pure function

Create `packages/flutter_minigames/lib/src/games/<name>/` and implement
`TurnGame<YourState, YourMove>`:

```dart
class YourGame implements TurnGame<YourState, YourMove> {
  const YourGame();

  @override
  YourState applyMove(YourState state, YourMove move) { /* ... */ }

  @override
  bool validateMove(YourState state, YourMove move, String playerId) { /* ... */ }

  @override
  GameOutcome? outcome(YourState state) { /* ... */ }
}
```

**`applyMove` must be pure.** No `DateTime.now()`, no `Random()`, no timers, no
I/O, no rendering. Every shuffle and every deal derives from the match `seed`,
so a match replays exactly from `(seed, moves)`. This is not style — it's what
makes a match verifiable and a desync impossible. If you find yourself wanting
randomness mid-game, derive it from the seed plus the move count.

State and moves must survive a JSON round-trip, because that's what crosses the
network.

### 2. The widget

Write a widget that takes a `MatchController<YourState, YourMove>`, renders
`stateStream`, and calls `submitMove` on input. Keep the rules out of it: if the
widget knows a rule, the server can't enforce it.

Also add a `<Name>TileArt` widget for the launcher grid.

### 3. Wire it up

- Give the folder a barrel, `<name>.dart`, exporting its public files.
- Export it from `lib/flutter_minigames.dart`.
- Add `lib/games/<name>.dart` so it can be imported on its own — this is what
  lets an app take three games and ship three games.
- Add a row to `packages/example_app/lib/catalog/game_catalog.dart` and a play
  screen alongside the others.

### 4. Physics games are different

If your game has physics, do **not** put the simulation in `applyMove`. It
would have to be bit-identical on every device.

Instead: **simulate locally, serialize the outcome.** The shooter runs the
simulation, the move carries the settled positions, and the receiver replays
the recorded result rather than re-deriving it. Two harnesses exist for this —
`src/flame/` (Forge2D, top-down sliding) and `src/engine3d/` (a hand-rolled
perspective renderer for throwing games). Read an existing game first;
Shuffleboard is the clearest sliding example and Darts the clearest throwing
one.

### 5. Tests

Games are pure functions, so their tests are unusually easy and unusually
worth writing. At minimum:

- every rule that isn't obvious from the code
- illegal moves are rejected, including out-of-turn
- the game reaches an outcome (a full playout, not just the happy path)
- state and move survive a JSON round-trip
- the edges you had to think about — those are the ones that break later

Aim to make the test read like the rule it's checking.

## House rules

These exist because each one caused a real bug here.

- **Build every `AnimationController` in `initState`.** Never
  `late final x = AnimationController(...)` — the field initialiser can first
  run during `dispose()`, which looks up a deactivated widget's ancestor and
  throws.
- **Never wrap a message in an `AnimatedSwitcher`.** It keeps the outgoing
  child mounted beside the incoming one and keys both by the child's key inside
  a `Stack`, so a message that repeats inside its own exit — "MISS" twice
  running is ordinary play — throws `Duplicate keys found`. Use `GameNotice`
  from `ui.dart`, which animates a single node.
- **Cancel every `Timer` in `dispose()`.** Better: use `GameNotice`'s
  `autoDismiss` and don't run one.
- **Sounds fire from real events**, never `Future.delayed`. Use the nullable
  callback hooks in each game's `Sounds` class.
- **`RepaintBoundary.toImage` must be wrapped in `tester.runAsync`** or the
  test hangs until the 10-minute timeout.
- The test font renders text as black boxes. If you're screenshotting a board
  to judge it, load a real font in the test, or use `CardGlyphs` for numerals.

## Pull requests

Small and focused beats large and complete. A PR that adds one game or fixes
one thing is easy to review; a PR that does both is not.

Explain **why**, not just what — the diff already says what. If you made a
judgement call, say which way you went and what you traded off.

I'll try to respond within a couple of days. If I've gone quiet for a week,
ping the PR; it means I lost it, not that I'm ignoring you.

## Conduct

Be decent. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Licence

Contributions are licensed under Apache-2.0, matching the project.
