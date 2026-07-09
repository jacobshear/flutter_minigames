import 'dart:async';

import 'match.dart';
import 'transport.dart';

/// In-memory [GameTransport] for hot-seat play and tests.
///
/// Two [MatchController]s sharing one [LocalTransport] and match id behave
/// exactly like two networked clients — moves made through one surface on the
/// other — which is what makes it a faithful stand-in for a real backend
/// while you build games. No persistence, no network.
class LocalTransport implements GameTransport {
  final Map<String, Match> _matches = {};
  final Map<String, StreamController<Match>> _controllers = {};

  StreamController<Match> _controllerFor(String id) => _controllers.putIfAbsent(
        id,
        () => StreamController<Match>.broadcast(),
      );

  @override
  Future<void> createMatch(Match match) async {
    _matches[match.id] = match;
    _controllerFor(match.id).add(match);
  }

  @override
  Future<void> submitTurn(Match updatedMatch) async {
    _matches[updatedMatch.id] = updatedMatch;
    _controllerFor(updatedMatch.id).add(updatedMatch);
  }

  @override
  Stream<Match> watchMatch(String matchId) => _controllerFor(matchId).stream;

  @override
  Future<Match?> loadMatch(String matchId) async => _matches[matchId];

  /// Close all streams. Call when the transport is no longer needed.
  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
    _matches.clear();
  }
}
