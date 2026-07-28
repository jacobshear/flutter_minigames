# minigames_firebase

A [Firebase Realtime Database](https://firebase.google.com/docs/database) transport for [flutter_minigames](https://github.com/jacobshear/flutter_minigames). Implements `GameTransport`, so any async turn-based game plays over RTDB with no changes to the game code.

## Usage

```dart
import 'package:minigames_core/minigames_core.dart';
import 'package:flutter_minigames_firebase/flutter_minigames_firebase.dart';

// Anywhere you'd use LocalTransport, use this instead:
final transport = FirebaseGameTransport(
  // database: FirebaseDatabase.instanceFor(app: myApp),  // optional
  rootPath: 'minigames/matches',                          // fits your rules
);

final controller = await MatchController.create<MyState, MyMove>(
  game: MyGame(),
  transport: transport,
  matchId: matchId,
  playerIds: [meId, opponentId],
  localPlayerId: meId,
  seed: seed,
);
```

`MatchController` and your game widget are identical to the hot-seat setup — only the transport changes.

## How it maps to RTDB

- One match = one node at `<rootPath>/<matchId>` holding `Match` metadata.
- `submitTurn` is a `runTransaction` guarded by `turnCount` (optimistic
  concurrency) so two clients can't write the same turn.
- `watchMatch` is an `onValue` listener; RTDB's offline cache gives you
  reconnection and mid-game resume for free.
- Game state is stored as an **opaque JSON string**, deliberately: RTDB mangles
  arrays containing nulls (turns them into integer-keyed maps, drops all-null
  arrays). Encoding state as a string sidesteps that so games never have to know
  the backend's quirks. Scalar fields (`currentPlayerId`, `turnCount`, `status`)
  stay native so security rules and "your turn" Cloud Functions can read them.

## "Your turn" notifications

RTDB *is* the store, so persistence is inherent. To notify the next player,
trigger a function on write to `<rootPath>/<matchId>` and push to
`currentPlayerId`. (In the host app this is a `realtime-api` Lambda; the field is native,
not inside the JSON blob, precisely so the function can read it.)

## Verifying it

This package's Dart compiles and analyzes without any Firebase config. To verify
runtime behaviour, run the shared conformance suite against the
[Firebase Emulator](https://firebase.google.com/docs/emulator-suite):

```dart
// test/firebase_conformance_test.dart  (requires: firebase emulators:start)
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_minigames_firebase/flutter_minigames_firebase.dart';
import 'package:minigames_test/minigames_test.dart';

void main() {
  final db = FirebaseDatabase.instance..useDatabaseEmulator('localhost', 9000);
  runGameTransportConformanceTests(
    createTransport: () => FirebaseGameTransport(database: db),
  );
}
```

It runs the exact assertions `LocalTransport` passes — same contract, real
backend.

## Security rules (starting point)

```json
{
  "rules": {
    "minigames": {
      "matches": {
        "$matchId": {
          ".read":  "auth != null && data.child('playerIds').val().contains(auth.uid)",
          ".write": "auth != null && data.child('playerIds').val().contains(auth.uid)"
        }
      }
    }
  }
}
```

Tighten to taste — the transport doesn't assume any particular rule set.
