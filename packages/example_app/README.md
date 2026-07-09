# example_app

Standalone **full-screen GamePigeon-style launcher** for `flutter_minigames`.

## What it is

- Static **3-column grid** of illustrated game tiles (quiet iOS light chrome)
- Local hot-seat play via `PlaySession.localHotSeat()` / `LocalTransport`
- Thin play shells so the board is the product
- Integration tests for Firebase transport vs RTDB emulator

## What it is not

- Not the host app. Production goal is an **inline chat sheet**; this app is a faithful
  full-screen interpretation of that picker so you can develop games alone.
- Multiplayer is not wired in the menu. Hosts inject transport via
  `PlaySession.networked(...)` in `lib/multiplayer/play_session.dart`.

## Embedding later (the host app / third parties)

1. Depend on `minigames_core` + the game packages you need.
2. Reuse `gameCatalog` entries (or your own list of the same builders).
3. Present `HomeMenuScreen` (or only its grid) inside a sheet / nested navigator.
4. Pass `PlaySession.networked(yourTransport)` into play screens.

The demo's `MaterialApp` is disposable; packages and play screens are not.

## Run

```bash
flutter pub get
cd packages/example_app && flutter run
```

## Layout

```
lib/
  main.dart
  theme/demo_theme.dart           # quiet GP-like shell tokens
  widgets/game_chrome.dart        # thin back / badge / button
  widgets/game_tile_art.dart      # launcher dioramas
  audio/demo_sfx.dart
  multiplayer/play_session.dart
  catalog/game_catalog.dart
  screens/home_menu_screen.dart   # grid launcher
  screens/*_play_screen.dart
assets/sfx/
```
