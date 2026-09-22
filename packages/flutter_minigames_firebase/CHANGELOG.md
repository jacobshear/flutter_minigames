## 0.1.0

- Initial release: `FirebaseGameTransport`, a `GameTransport` backed by Firebase
  Realtime Database (transactional turns, opaque JSON state storage, `onValue`
  watching).
- `FirebaseGameTransport` now stores `Match.prevState` the same way it stores
  `state`: JSON-encoded to an opaque string on write, decoded back to a map
  on read, and omitted entirely when null. Supports the core library's new
  `MatchController.connect(replayLastTurn:)` cold-open replay, which relies
  on `prevState`/`lastMoverId` surviving a round-trip through RTDB.
- `FirebaseGameTransport` stores `Match.turnSteps` as one JSON-encoded string
  (the list of intermediate snapshots of a multi-step turn) and decodes it
  on read, mirroring `state` / `prevState`. Needed for the core library's
  whole-turn replay. Backends with schema validation must allow the new
  `turnSteps` string child on the match node.
- `example/main.dart`: a two-device tic-tac-toe match over RTDB.
