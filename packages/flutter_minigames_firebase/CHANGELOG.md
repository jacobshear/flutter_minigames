## Unreleased

- `FirebaseGameTransport` now stores `Match.prevState` the same way it stores
  `state`: JSON-encoded to an opaque string on write, decoded back to a map
  on read, and omitted entirely when null. Supports the core library's new
  `MatchController.connect(replayLastTurn:)` cold-open replay, which relies
  on `prevState`/`lastMoverId` surviving a round-trip through RTDB.

## 0.1.0

- Initial release: `FirebaseGameTransport`, a `GameTransport` backed by Firebase
  Realtime Database (transactional turns, opaque JSON state storage, `onValue`
  watching).
