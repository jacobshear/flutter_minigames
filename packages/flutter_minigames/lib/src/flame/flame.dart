/// Flame + Forge2D physics harness for flutter_minigames physics games
/// (shuffleboard, pool, darts, mini golf…).
///
/// ## The seam: simulate locally, serialize the outcome
///
/// Physics games do **not** try to run deterministic physics on both devices.
/// Instead, the player taking the shot runs the simulation locally and sends
/// the *resting positions* as authoritative state:
///
/// ```
///   drag/flick ──▶ AimToImpulse ──▶ TableSimulation.launch(disc, impulse)
///        step() each frame (or runUntilSettled headless)
///                     │
///          SettleDetector fires once, at rest
///                     ▼
///              SimOutcome  (id + world x/y/angle + removed, JSON-safe)
///                     │
///        game maps bodies ──▶ its own TurnGame move ──▶ MatchController
/// ```
///
/// The receiving client never re-simulates — it trusts the settled positions
/// (`applyMove` stays a pure reducer over those positions). This sidesteps
/// cross-device float determinism entirely; the only thing crossing the wire is
/// the outcome.
///
/// ## What this package provides
///
/// * [TableSimulation] — a zero-gravity, damped top-down Forge2D world with
///   helpers to add circular pieces ([TableSimulation.addDisc]) and static
///   walls ([TableSimulation.addWall] / [TableSimulation.addBounds]). Headless:
///   no Flame game loop or widget required, so shots can be simulated in tests.
/// * [SettleDetector] — the "is it at rest yet?" primitive: N consecutive calm
///   steps or a hard step budget, firing once.
/// * [AimToImpulse] — drag/flick vector → capped launch impulse (+ a 0..1 power
///   value for a UI meter).
/// * [SimOutcome] / [SettledBody] — the serializable settled state the game
///   converts into a move.
///
/// The package intentionally stays out of the widget layer: it depends on
/// Flame/Forge2D but renders nothing. Games own their `GameWidget` and draw the
/// table themselves, driving a [TableSimulation] from the game loop.
library;

export 'aim.dart';
export 'settle_detector.dart';
export 'sim_outcome.dart';
export 'table_simulation.dart';
