# Changelog

## Unreleased

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

## Unreleased

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
