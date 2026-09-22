# Changelog

## Unreleased

- Opponent shot replay for the physics games. Eight ball, knockout,
  shuffleboard, mini golf, cup pong, darts and archery record the shot's
  input in state (`lastShot` / `lastThrow` / `lastStroke` /
  `lastResolution`; older states decode it as null) and the receiving board
  replays it through its own local shot path, landing on the authoritative
  result. Darts previously showed no opponent dart at all.
- Replay fast-forward. `MatchController.setReplaySpeed` (rescales the wait in
  flight), `skipReplay`, `replayActivity`, and `isReplayPlaybackActive`
  (the replayed frames plus a tail as long as the last frame's
  `replayStepDelay`, so a single-move turn stays fast-forwarded until its
  animation ends). `ReplayTimeDilation` speeds every board animation via
  the scheduler's `timeDilation`; fixed-step sims read `stepsPerTick`.
- Round replays: `AnagramsRoundReplay`, `WordHuntRoundReplay` (Word Hunt now
  stores traced paths, with a DFS fallback for older states),
  `WordBitesRoundReplay` and `BasketballRoundReplay` (Basketball now logs
  each shot) — compressed reels of the opponent's round, driven by
  `RoundReplayController`.
- `TileArtClock` / `TileArtDriver`: a grid of animated tile arts shares one
  30fps ticker instead of one display-rate ticker per tile. Every tile art
  uses the driver and behaves as before outside a clock.
- Mini Golf and Knockout reframe on tall phones (#7, fixes #4).
- Word Hunt: the scored-word notice sits in its own strip above the grid
  instead of over the top row (fixes #1).
- Mancala: the board sizes to the height it is given, clamped to 360–720pt,
  instead of a fixed 560pt cap (fixes #2).
- Basketball: a miss now says so — `RIM OUT` or `AIRBALL` — from a new
  `BasketballHitKind.missed` sim signal, live and in the round replay
  (fixes #3).
- Go Fish: a hand spread across many ranks wraps to a second row instead of
  shrinking cards below 52pt (fixes #6).
- `forge2d` lower bound raised to `^0.13.1` (`CircleShape(radius:)`); the
  package analyzes and tests clean at every dependency's lower bound.
- Whole-turn replay. `TurnGame.replaysWholeTurn` (default false) opts a
  game into chaining consecutive sub-moves by one player into a single
  recorded turn: `Match.prevState` then holds the board before the FIRST
  sub-move and the new `Match.turnSteps` the snapshots in between, and a
  replay lands every frame in order, waiting
  `TurnGame.replayStepDelay(from, to)` (default 700ms) after each so the
  board's animation for that frame can finish. Every game whose turn can
  span several moves opts in with a beat sized from its board: checkers,
  dots-and-boxes, mancala (from the sow that just landed), eight ball,
  knockout, cup pong, mini golf, archery, darts, sea battle, crazy eights,
  go fish and gin rummy (the card games per action). A cold open of a
  checkers double jump previously replayed only the last leg.
  `Match.replayFrames` lists the frames; `previousTurn` rolls the turn
  count back past every step.
- Archery: the receiving face now mirrors the other archer's arrows per
  state (they previously appeared only on a remount).
- `MatchController.replayLastTurn()` re-watches the last recorded turn on
  demand, with `canReplayLastTurn` to gate the affordance. It rewinds
  `state`/`match` WITHOUT emitting on `stateStream` (a mounted board must
  not animate backwards) — rebuild the board widget after calling so it
  mounts against the rewound snapshot; the frames then land as on a cold
  open. `isReplayingLastTurn` / `canActLocally` / `submitMove` gate the
  same way as the connect-time replay.


- `Match` gains `prevState` and `lastMoverId`, plus a `previousTurn` getter
  that reconstructs the match as it stood before the most recent turn
  (metadata rolled back too — turn count, mover, open status).
  `MatchController.submitMove` now writes both fields alongside the new
  state.
- `MatchController.connect` takes a `replayLastTurn` flag. When true and the
  stored match's last move was made by someone other than the local player,
  `connect` first emits `previousTurn`, then lands the real snapshot through
  `stateStream` after `MatchController.replayDelay` (700ms) — so a cold open
  can animate the opponent's move instead of showing it as a fait accompli.
- While a replay is pending, `isReplayingLastTurn` is true and both
  `canActLocally` and `submitMove` are gated off. A newer turn arriving from
  the transport during the window abandons the replay and lands immediately;
  a duplicate of the held snapshot (e.g. a transport's replay-on-subscribe)
  is swallowed and left to the replay timer.

## 0.1.0

First release.

- **Turn engine.** `TurnGame` is a pure, serializable contract —
  `applyMove(state, move) -> newState`, with no rendering, no timers, and no
  randomness beyond the match seed. `MatchController` drives it.
- **Transport seam.** `GameTransport` is four methods. `LocalTransport` ships
  for hot-seat; `flutter_minigames_firebase` adds Realtime Database. The engine
  never imports a backend.
- **24 games** — board (Chess, Checkers, Reversi, Gomoku, Mancala,
  Connect Four, Dots & Boxes, Tic-Tac-Toe, Sea Battle, Filler), card
  (Gin Rummy, Go Fish, Crazy 8s), word (Anagrams, Word Hunt, Word Bites), and
  physics (8-Ball, Shuffleboard, Knockout, Mini Golf, Darts, Archery,
  Basketball, Cup Pong).
- **Two physics harnesses.** A Forge2D top-down table for sliding games, and a
  hand-rolled perspective renderer for the throwing games — painter's-algorithm
  depth sorting, ballistic launch solving, and a near/far rim split so a ball
  sorts between the halves of a hoop.
- **Shared chrome.** `GameNotice` and `GamePill` for floating table messages,
  and a playing-card kit with seeded shuffling and vector card faces.

Games are pure reducers, so a move is serializable and a match replays from its
seed. Physics games follow "simulate locally, serialize the outcome": the
shooter runs the simulation and the move carries the settled positions, so a
receiver never re-simulates and cannot diverge.
