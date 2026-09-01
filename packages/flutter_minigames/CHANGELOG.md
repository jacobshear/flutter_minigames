# Changelog

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
