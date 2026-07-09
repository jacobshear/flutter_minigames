import 'dart:async';
import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:minigames_core/minigames_core.dart';

/// A [GameTransport] backed by Firebase Realtime Database.
///
/// One match is one RTDB node at `<rootPath>/<matchId>`. Turn hand-off is a
/// `runTransaction` guarded by [Match.turnCount] so two clients can't both
/// write the same turn (optimistic concurrency). Watching a match is a plain
/// `onValue` listener — RTDB's offline cache handles reconnection and resume.
///
/// The core library never imports Firebase; this adapter is the only place the
/// two meet, which is what keeps every game reusable on any backend. Inject a
/// [FirebaseDatabase] (e.g. a region- or emulator-specific instance) or let it
/// default to [FirebaseDatabase.instance].
///
/// ### Why game state is stored as a JSON string
/// RTDB silently mangles arrays that contain nulls or are sparse (it turns them
/// into integer-keyed maps, and drops all-null arrays entirely). Game state is
/// arbitrary and often contains exactly those shapes (e.g. tic-tac-toe's 9-cell
/// board that starts all-null). So the opaque `state` map is stored as a single
/// JSON string and decoded on read — games stay backend-agnostic and never have
/// to know RTDB's quirks. Scalar metadata (currentPlayerId, turnCount, …) stays
/// as native fields so server-side rules / "your turn" functions can read them.
class FirebaseGameTransport implements GameTransport {
  final FirebaseDatabase database;

  /// Root node under which matches live. Point this at whatever fits your data
  /// model / security rules.
  final String rootPath;

  FirebaseGameTransport({
    FirebaseDatabase? database,
    this.rootPath = 'minigames/matches',
  }) : database = database ?? FirebaseDatabase.instance;

  DatabaseReference _ref(String matchId) =>
      database.ref('$rootPath/$matchId');

  @override
  Future<void> createMatch(Match match) => _ref(match.id).set(_toNode(match));

  @override
  Future<void> submitTurn(Match updatedMatch) async {
    final result = await _ref(updatedMatch.id).runTransaction((currentData) {
      if (currentData != null) {
        final current = _coerceMap(currentData);
        final currentTurn = (current['turnCount'] as num?)?.toInt() ?? 0;
        // We must be exactly one turn ahead of what's stored; otherwise the
        // opponent (or a retry) already advanced it — abort rather than clobber.
        if (currentTurn != updatedMatch.turnCount - 1) {
          return Transaction.abort();
        }
      }
      return Transaction.success(_toNode(updatedMatch));
    });

    if (!result.committed) {
      throw StateError(
        'Turn rejected for match ${updatedMatch.id}: it advanced concurrently.',
      );
    }
  }

  @override
  Stream<Match> watchMatch(String matchId) => _ref(matchId)
      .onValue
      .where((event) => event.snapshot.value != null)
      .map((event) => _fromNode(event.snapshot.value));

  @override
  Future<Match?> loadMatch(String matchId) async {
    final snapshot = await _ref(matchId).get();
    final value = snapshot.value;
    return value == null ? null : _fromNode(value);
  }

  // --- serialization -------------------------------------------------------

  Map<String, dynamic> _toNode(Match match) {
    final node = match.toJson();
    node['state'] = jsonEncode(match.state); // opaque blob — see class doc
    node.removeWhere((_, value) => value == null); // RTDB omits nulls anyway
    return node;
  }

  Match _fromNode(Object? value) {
    final node = _coerceMap(value);
    final rawState = node['state'];
    if (rawState is String) {
      node['state'] = jsonDecode(rawState) as Map<String, dynamic>;
    }
    return Match.fromJson(node);
  }

  /// RTDB hands values back as `Map<Object?, Object?>` / `List<Object?>`;
  /// recursively coerce to the `Map<String, dynamic>` the core models expect.
  Map<String, dynamic> _coerceMap(Object? value) {
    final map = value as Map;
    return map.map((k, v) => MapEntry(k.toString(), _coerceValue(v)));
  }

  dynamic _coerceValue(Object? value) {
    if (value is Map) return _coerceMap(value);
    if (value is List) return value.map(_coerceValue).toList();
    return value;
  }
}
