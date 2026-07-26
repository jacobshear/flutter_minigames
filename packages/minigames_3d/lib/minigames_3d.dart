/// Perspective-3D harness for flutter_minigames throw games.
///
/// ## Why this exists
///
/// Cup Pong and Basketball are **first-person throws into depth**: you look
/// down-range and the ball recedes away from you under gravity. `minigames_flame`
/// wraps Forge2D, which is a strictly 2-D engine — it has no depth axis, so those
/// games cannot be built on it without becoming a different (much worse) game.
///
/// ## What it provides
///
/// * [Vec3] — world vectors: +x right, +y up, +z down-range.
/// * [Camera3] — a pinhole camera: [Camera3.project] maps a world point to a
///   canvas position plus the depth and scale a painter needs, and
///   [Camera3.screenToGround] turns a touch back into a spot on the floor.
/// * [Projectile] / [ThrowConfig] — a fixed-step ballistic integrator (gravity,
///   drag, spin, restitution) that runs headlessly, so a whole shot can be
///   simulated in a unit test.
/// * [ThrowAim] — maps a swipe to a launch velocity: flick up-screen to throw
///   down-range, diagonal to steer, longer/faster to throw harder and flatter.
/// * [Surfaces] — swept analytic collision: descending passes through a disc
///   (in the cup / through the hoop), rim rattles, backboards, cup walls.
/// * [LaunchSolver] — solves the speed that actually lands in the target, so a
///   flick can be mapped to a narrow band around it. Read its docs before
///   tuning: at true physical scale these games have a ~1% make window and a
///   naive speed range can miss every time.
/// * [Scene3] — painter's-algorithm depth sorting.
///
/// Rendering stays plain `Canvas` work driven by [Camera3] and the painter's
/// algorithm (sort by [Projected.depth] descending), which keeps every scene
/// snapshot-testable.
library;

export 'src/camera3.dart';
export 'src/launch_solver.dart';
export 'src/projectile.dart';
export 'src/scene3.dart';
export 'src/surfaces.dart';
export 'src/vec3.dart';
