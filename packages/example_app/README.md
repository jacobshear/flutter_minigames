# example_app

Standalone **demo catalog** for `flutter_minigames` — not the production host.

## What it is

- Main menu of every shipped mini-game (+ "coming soon" placeholders)
- **Local hot-seat** play via `LocalTransport` / `PlaySession.localHotSeat()`
- Themed juice (Fraunces, coral/teal, SFX) so you can feel the bar
- Integration tests for the Firebase transport against the RTDB emulator

## What it is not

- Not the host app. Multiplayer is not wired here on purpose.
- The hook for multiplayer is `lib/multiplayer/play_session.dart`:
  - `TransportFactory` → return your `GameTransport` (e.g. `FirebaseGameTransport`)
  - `PlaySession.networked(transport)` → same game screens, shared match

## Run

```bash
# from monorepo root
flutter pub get
cd packages/example_app && flutter run
```

## Layout

```
lib/
  main.dart
  theme/demo_theme.dart
  audio/demo_sfx.dart          # place / win / draw / new-game
  multiplayer/play_session.dart  # LocalTransport today; inject later
  catalog/game_catalog.dart    # add a package → add a row
  screens/
    home_menu_screen.dart
    tictactoe_play_screen.dart
assets/sfx/                    # procedural WAV (see CREDITS.md)
```
