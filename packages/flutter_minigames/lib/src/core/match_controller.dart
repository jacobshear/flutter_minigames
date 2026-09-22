import 'dart:async';

import 'game_outcome.dart';
import 'match.dart';
import 'transport.dart';
import 'turn_game.dart';

/// Drives one match: owns the [TurnGame] + [GameTransport] pairing, exposes the
/// live decoded state to the UI, and turns local moves into transported turns.
///
/// This is the object a screen holds. Subscribe to [stateStream] to render;
/// call [submitMove] on a tap.
class MatchController<S, M> {
  final TurnGame<S, M> game;
  final GameTransport transport;
  final String matchId;

  /// The player this client acts as. In [hotSeat] mode this is ignored for
  /// turn-gating (the acting player is always whoever's turn it is).
  final String localPlayerId;

  /// When true, a single device plays every seat (pass-and-play). Moves are
  /// attributed to the current player rather than [localPlayerId].
  final bool hotSeat;

  MatchController({
    required this.game,
    required this.transport,
    required this.matchId,
    required this.localPlayerId,
    this.hotSeat = false,
  });

  final StreamController<S> _stateController = StreamController<S>.broadcast();
  StreamSubscription<Match>? _sub;
  Match? _match;

  /// The authoritative snapshot held back while a replay is pending — see
  /// [connect]. Null whenever no replay is in flight.
  Match? _replayTarget;

  /// The frames still to land, oldest first; the last one is [_replayTarget].
  List<Match> _replayQueue = const [];
  Timer? _replayTimer;

  /// When [_replayTimer] fires and what it runs — what [setReplaySpeed]
  /// needs to rescale the wait in flight.
  DateTime? _replayTimerDue;
  void Function()? _replayTimerCallback;

  /// True after the last replayed frame has landed while its animation is
  /// still playing out — see [isReplayPlaybackActive].
  bool _inTail = false;

  double _replaySpeed = 1.0;

  final StreamController<bool> _replayActivity =
      StreamController<bool>.broadcast();

  /// How long a replay shows the pre-turn snapshot before landing the first
  /// frame. Long enough for a board's entrance animation to finish so the
  /// replayed move reads as a move, not a flash.
  static const Duration replayDelay = Duration(milliseconds: 700);

  /// Fast-forward factor for the replay in flight: 1 is real time, 2 twice
  /// as fast. Scales the controller's own frame spacing ([replayDelay],
  /// [TurnGame.replayStepDelay]); a board's animations are scaled by the
  /// host through `ReplayTimeDilation` (ui layer), since this class is
  /// Flutter-free. Resets to 1 when a replay ends, so every replay starts
  /// in real time.
  double get replaySpeed => _replaySpeed;

  /// Emits true when a replay starts and false when its playback ends (the
  /// tail after the last frame ran out, skipped, superseded by a newer
  /// snapshot, or disposed) — see [isReplayPlaybackActive]. Hosts use it to
  /// show and hide fast-forward controls and to reset time dilation.
  Stream<bool> get replayActivity => _replayActivity.stream;

  /// Emits the decoded game state on every change.
  Stream<S> get stateStream => _stateController.stream;

  /// The latest raw match metadata, or `null` before [connect].
  Match? get match => _match;

  /// The latest decoded game state, or `null` before [connect].
  S? get state {
    final m = _match;
    return m == null ? null : game.decodeState(m.state, m.schemaVersion);
  }

  /// The current outcome, or `null` if the game is ongoing.
  GameOutcome? get outcome {
    final s = state;
    return s == null ? null : game.outcome(s);
  }

  /// Whether it's this client's move (always true in [hotSeat] while open).
  bool get canActLocally {
    final m = _match;
    if (m == null || !m.isOpen || isReplayingLastTurn) return false;
    return hotSeat || m.currentPlayerId == localPlayerId;
  }

  /// True when it's specifically [localPlayerId]'s turn (ignores hot-seat).
  bool get isLocalPlayersTurn =>
      _match != null &&
      _match!.isOpen &&
      _match!.currentPlayerId == localPlayerId;

  /// True while a replay is in flight: the visible snapshot is a rolled-back
  /// one and the real snapshot has not landed yet.
  bool get isReplayingLastTurn => _replayTarget != null;

  /// True from the start of a replay until the last replayed frame has
  /// finished animating: [isReplayingLastTurn], then a TAIL as long as the
  /// game's step delay for that frame. The match is live during the tail
  /// ([canActLocally] may be true) — this only says a replay is still on
  /// screen, which is what fast-forward controls and time dilation follow.
  bool get isReplayPlaybackActive => _replayTarget != null || _inTail;

  /// Whether [replayLastTurn] would do anything right now: a turn has been
  /// recorded with its pre-turn snapshot and no replay is already running.
  bool get canReplayLastTurn =>
      !isReplayingLastTurn && _match?.previousTurn != null;

  /// Load the current snapshot (if any) and start listening for updates.
  ///
  /// With [replayLastTurn], a match whose most recent turn was taken by
  /// someone other than [localPlayerId] is first exposed as it stood BEFORE
  /// that turn ([Match.previousTurn]); after [replayDelay] the turn's frames
  /// land through [stateStream] exactly as live turns would — one frame for
  /// a single move, several for a multi-step turn ([Match.turnSteps]),
  /// spaced by [TurnGame.replayStepDelay]. Boards diff consecutive states
  /// to animate a move, so this makes a cold open replay the opponent's
  /// whole turn with no board-level support. A snapshot that arrives from
  /// the transport during the window either duplicates the held one
  /// (swallowed — the timer lands it) or supersedes it (a newer turn: the
  /// replay is abandoned and the newer snapshot wins). While the window is
  /// open [canActLocally] is false and [submitMove] refuses, since the
  /// visible board is not the one a move would be validated against.
  Future<void> connect({bool replayLastTurn = false}) async {
    final existing = await transport.loadMatch(matchId);
    if (existing != null) {
      final replay = replayLastTurn &&
          existing.lastMoverId != localPlayerId &&
          existing.previousTurn != null;
      if (replay) {
        _startReplay(existing, emitFirst: true);
      } else {
        _emit(existing);
      }
    }
    _sub = transport.watchMatch(matchId).listen(_onTransportMatch);
  }

  /// Re-watch the most recent turn on demand.
  ///
  /// Rewinds [match] / [state] to the pre-turn snapshot WITHOUT emitting it
  /// on [stateStream] — a board that is already showing the current position
  /// must not be asked to animate backwards, and every board knows how to
  /// initialise from [state]. So a host calls this, then rebuilds its board
  /// widget (a fresh key) so it mounts against the rewound snapshot; after
  /// [replayDelay] the turn's frames land through [stateStream] exactly as
  /// on a cold open. Same gating as [connect]'s replay while it runs.
  ///
  /// Returns false, doing nothing, when there is no recorded turn to replay
  /// or a replay is already in flight.
  bool replayLastTurn() {
    final m = _match;
    if (m == null || !canReplayLastTurn) return false;
    _startReplay(m, emitFirst: false);
    return true;
  }

  void _startReplay(Match target, {required bool emitFirst}) {
    final frames = target.replayFrames;
    assert(frames.length >= 2, 'replayFrames must bracket the turn');
    _endPlayback(); // a re-watch can start inside the previous tail
    _replayTarget = target;
    _replayQueue = frames.sublist(1);
    final first = frames.first;
    if (emitFirst) {
      _emit(first);
    } else {
      _match = first;
    }
    if (!_replayActivity.isClosed) _replayActivity.add(true);
    _armPlaybackTimer(replayDelay, _landNextFrame);
  }

  /// Arms [onFire] [realTime] from now at the current speed.
  void _armPlaybackTimer(Duration realTime, void Function() onFire) {
    final scaled = realTime * (1 / _replaySpeed);
    _replayTimerDue = DateTime.now().add(scaled);
    _replayTimerCallback = onFire;
    _replayTimer = Timer(scaled, onFire);
  }

  /// Set the fast-forward factor (clamped to 1–8) for the playback in
  /// flight — the replayed frames AND the tail after the last one (see
  /// [isReplayPlaybackActive]). The pending wait is rescaled, so tapping
  /// fast-forward mid-hold shortens that hold rather than the next one.
  /// A no-op when no playback is active.
  void setReplaySpeed(double speed) {
    if (!isReplayPlaybackActive) return;
    final next = speed.clamp(1.0, 8.0).toDouble();
    if (next == _replaySpeed) return;
    final previous = _replaySpeed;
    _replaySpeed = next;
    final due = _replayTimerDue;
    final timer = _replayTimer;
    final onFire = _replayTimerCallback;
    if (timer == null || due == null || onFire == null) return;
    timer.cancel();
    var remaining = due.difference(DateTime.now());
    if (remaining.isNegative) remaining = Duration.zero;
    final rescaled = remaining * (previous / next);
    _replayTimerDue = DateTime.now().add(rescaled);
    _replayTimer = Timer(rescaled, onFire);
  }

  /// Jump to the end of the playback in flight: any frames still held back
  /// land at once as the authoritative snapshot, and the playback (tail
  /// included) ends.
  ///
  /// The board sees ONE transition from whatever frame it was showing to the
  /// final one — for a multi-step turn that is a jump, not the remaining
  /// steps, and during the tail the final frame's animation is still
  /// running. A host that wants the board to simply show the final position
  /// should remount it (fresh key) after calling this, the same way it does
  /// for [replayLastTurn].
  ///
  /// Returns false when no playback is active.
  bool skipReplay() {
    if (!isReplayPlaybackActive) return false;
    final target = _replayTarget;
    _abandonReplay();
    if (target != null) _emit(target);
    return true;
  }

  void _landNextFrame() {
    _clearPlaybackTimer();
    if (_replayQueue.isEmpty) {
      _abandonReplay();
      return;
    }
    final before = state;
    final next = _replayQueue.first;
    _replayQueue = _replayQueue.sublist(1);
    if (_replayQueue.isEmpty) {
      // The real snapshot. The replay is over the instant it lands — the
      // listeners that read [canActLocally] on this emission see the truth —
      // but the board is only now STARTING to animate it, so playback runs
      // on through a tail as long as that animation (the game's own step
      // delay) and keeps the fast-forward speed until then. Without the
      // tail, a single-move turn (one shot, one piece) would drop back to
      // real time before the move even played.
      _replayTarget = null;
      _replayQueue = const [];
      _inTail = true;
      _emit(next);
      final after = state;
      _armPlaybackTimer(_stepDelay(before, after), _endPlayback);
      return;
    }
    _emit(next);
    _armPlaybackTimer(_stepDelay(before, state), _landNextFrame);
  }

  Duration _stepDelay(S? before, S? after) => before == null || after == null
      ? replayDelay
      : game.replayStepDelay(before, after);

  void _onTransportMatch(Match m) {
    final target = _replayTarget;
    if (target != null) {
      // Same turn we're already holding back (RTDB replays the current value
      // on subscribe): let the timer land it.
      if (m.turnCount <= target.turnCount && m.status == target.status) {
        return;
      }
      _abandonReplay();
    } else if (_inTail && m.turnCount > (_match?.turnCount ?? 0)) {
      // A genuinely newer turn arrived while the last replayed frame was
      // still animating: playback is over, the new move plays in real time.
      _endPlayback();
    }
    _emit(m);
  }

  void _clearPlaybackTimer() {
    _replayTimer?.cancel();
    _replayTimer = null;
    _replayTimerDue = null;
    _replayTimerCallback = null;
  }

  /// Ends the playback — frames, tail, speed — and reports it once.
  void _abandonReplay() => _endPlayback();

  void _endPlayback() {
    final wasActive = isReplayPlaybackActive;
    _clearPlaybackTimer();
    _replayTarget = null;
    _replayQueue = const [];
    _inTail = false;
    _replaySpeed = 1.0;
    if (wasActive && !_replayActivity.isClosed) _replayActivity.add(false);
  }

  void _emit(Match m) {
    _match = m;
    if (!_stateController.isClosed) {
      _stateController.add(game.decodeState(m.state, m.schemaVersion));
    }
  }

  /// Validate [move], apply it, and submit the resulting turn to the transport.
  ///
  /// Returns false (and does nothing) if there's no match yet, it isn't a
  /// legal move, or it isn't this client's turn.
  ///
  /// Records the replay trail: [Match.prevState] is the board before this
  /// player's turn began and [Match.turnSteps] the snapshots in between,
  /// when the same player is moving again and the game opted in through
  /// [TurnGame.replaysWholeTurn]; otherwise each sub-move stands alone.
  Future<bool> submitMove(M move) async {
    final m = _match;
    if (m == null || !m.isOpen || isReplayingLastTurn) return false;

    final current = game.decodeState(m.state, m.schemaVersion);
    final acting = hotSeat ? game.currentPlayer(current) : localPlayerId;

    if (!game.validateMove(current, move, acting)) return false;

    final next = game.applyMove(current, move);
    final outcome = game.outcome(next);

    final continuesTurn =
        game.replaysWholeTurn && m.lastMoverId == acting && m.prevState != null;

    final updated = Match(
      id: m.id,
      gameId: m.gameId,
      playerIds: m.playerIds,
      currentPlayerId: game.currentPlayer(next),
      status: outcome == null ? MatchStatus.open : MatchStatus.ended,
      turnCount: m.turnCount + 1,
      state: game.encodeState(next),
      schemaVersion: game.stateSchemaVersion,
      winnerId: outcome?.winnerId,
      isDraw: outcome?.isDraw ?? false,
      prevState: continuesTurn ? m.prevState : m.state,
      turnSteps: continuesTurn ? [...?m.turnSteps, m.state] : null,
      lastMoverId: acting,
    );

    await transport.submitTurn(updated);
    return true;
  }

  /// Create a fresh match on [transport] and return a connected controller.
  static Future<MatchController<S, M>> create<S, M>({
    required TurnGame<S, M> game,
    required GameTransport transport,
    required String matchId,
    required List<String> playerIds,
    required String localPlayerId,
    required int seed,
    bool hotSeat = false,
  }) async {
    final initial = game.initialState(seed: seed, playerIds: playerIds);
    final match = Match(
      id: matchId,
      gameId: game.id,
      playerIds: playerIds,
      currentPlayerId: game.currentPlayer(initial),
      status: MatchStatus.open,
      turnCount: 0,
      state: game.encodeState(initial),
      schemaVersion: game.stateSchemaVersion,
    );
    await transport.createMatch(match);

    final controller = MatchController<S, M>(
      game: game,
      transport: transport,
      matchId: matchId,
      localPlayerId: localPlayerId,
      hotSeat: hotSeat,
    );
    await controller.connect();
    return controller;
  }

  Future<void> dispose() async {
    _abandonReplay();
    await _sub?.cancel();
    await _stateController.close();
    await _replayActivity.close();
  }
}
