import 'package:minigames_core/minigames_core.dart';

/// How a match is hosted for the UI.
///
/// The demo only exercises [PlayMode.localHotSeat] today. [PlayMode.networked]
/// is the seam host apps (the host app, third parties) plug into later by supplying a
/// real [GameTransport] via [TransportFactory].
enum PlayMode {
  /// Pass-and-play on one device. Uses [LocalTransport] under the hood.
  localHotSeat,

  /// Reserved: two clients, shared transport. Not offered in the menu yet —
  /// wiring lives in [TransportFactory] so games never branch on mode.
  networked,
}

/// Creates the [GameTransport] for a new session.
///
/// Default: a fresh [LocalTransport] (local hot-seat / tests).
/// Multiplayer: return e.g. `FirebaseGameTransport(rootPath: '…')` pointed at
/// your RTDB. Games never import Firebase — only this factory does.
typedef TransportFactory = GameTransport Function();

/// Default demo factory — in-memory, no network, perfect for local play.
GameTransport localTransportFactory() => LocalTransport();

/// Disposable session wrapping a transport for one run of a game screen.
///
/// Screens create a [PlaySession], build a [MatchController] against
/// [transport], and call [dispose] when leaving the route. That keeps the
/// multiplayer swap a one-line factory change rather than a rewrite.
class PlaySession {
  final PlayMode mode;
  final GameTransport transport;
  final bool ownsTransport;

  PlaySession({
    required this.mode,
    required this.transport,
    this.ownsTransport = true,
  });

  /// Local hot-seat session (what the demo menu launches).
  factory PlaySession.localHotSeat({TransportFactory? factory}) {
    return PlaySession(
      mode: PlayMode.localHotSeat,
      transport: (factory ?? localTransportFactory)(),
    );
  }

  /// Networked session — host app provides the transport (Firebase, custom…).
  factory PlaySession.networked(GameTransport transport) {
    return PlaySession(
      mode: PlayMode.networked,
      transport: transport,
      ownsTransport: false,
    );
  }

  /// Whether this session attributes every seat to the device (pass-and-play).
  bool get hotSeat => mode == PlayMode.localHotSeat;

  Future<void> dispose() async {
    if (ownsTransport && transport is LocalTransport) {
      (transport as LocalTransport).dispose();
    }
  }
}
