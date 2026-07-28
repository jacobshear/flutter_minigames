import 'dart:math' as math;

import 'package:flutter_minigames/src/core/core.dart';

/// Board side length (cells per row/column).
const int seaBattleBoardSize = 10;

/// Which stage of the match the state is in.
enum SeaBattlePhase {
  /// One or both players still need to place their fleet.
  placement,

  /// Both fleets are down; players are exchanging shots.
  battle,
}

/// One ship on the grid: an anchor cell (top-left), a length, and an
/// orientation. Cells run right when [horizontal], down otherwise.
class ShipPlacement {
  final int row;
  final int col;
  final int length;
  final bool horizontal;

  const ShipPlacement({
    required this.row,
    required this.col,
    required this.length,
    required this.horizontal,
  });

  /// The board cell indices (`row * 10 + col`) this ship occupies.
  List<int> get cells => List.generate(
        length,
        (i) => horizontal
            ? row * seaBattleBoardSize + col + i
            : (row + i) * seaBattleBoardSize + col,
      );

  ShipPlacement copyWith({int? row, int? col, bool? horizontal}) =>
      ShipPlacement(
        row: row ?? this.row,
        col: col ?? this.col,
        length: length,
        horizontal: horizontal ?? this.horizontal,
      );

  List<dynamic> toJson() => [row, col, length, horizontal];

  factory ShipPlacement.fromJson(List<dynamic> json) => ShipPlacement(
        row: json[0] as int,
        col: json[1] as int,
        length: json[2] as int,
        horizontal: json[3] as bool,
      );

  @override
  bool operator ==(Object other) =>
      other is ShipPlacement &&
      other.row == row &&
      other.col == col &&
      other.length == length &&
      other.horizontal == horizontal;

  @override
  int get hashCode => Object.hash(row, col, length, horizontal);

  @override
  String toString() =>
      'ShipPlacement(r$row c$col len$length ${horizontal ? 'H' : 'V'})';
}

/// A move: either laying down a whole fleet (placement phase) or firing one
/// shot at the opponent's grid (battle phase).
sealed class SeaBattleMove {
  const SeaBattleMove();
}

/// Commit the acting player's full fleet layout.
class PlaceFleetMove extends SeaBattleMove {
  final List<ShipPlacement> ships;

  const PlaceFleetMove(this.ships);
}

/// Fire at [cell] on the opponent's grid.
class FireMove extends SeaBattleMove {
  final int cell;

  const FireMove(this.cell);
}

/// Serializable Sea Battle state.
///
/// `shots[playerId]` is every *resolved* cell on that player's own grid —
/// cells actually fired at plus water auto-revealed around sunk ships. A
/// resolved cell that is also a ship cell is a hit.
class SeaBattleState {
  final List<String> playerIds;

  /// Fleet per player; `null` until that player has placed.
  final Map<String, List<ShipPlacement>?> fleets;

  /// Resolved cells on each player's own grid.
  final Map<String, Set<int>> shots;

  final String currentPlayerId;

  /// The most recent fired cell (excludes auto-revealed water), for UI juice.
  final int? lastShotCell;

  /// Whose grid [lastShotCell] landed on.
  final String? lastShotTarget;

  const SeaBattleState({
    required this.playerIds,
    required this.fleets,
    required this.shots,
    required this.currentPlayerId,
    this.lastShotCell,
    this.lastShotTarget,
  });

  SeaBattlePhase get phase => fleets.values.any((f) => f == null)
      ? SeaBattlePhase.placement
      : SeaBattlePhase.battle;

  String opponentOf(String playerId) =>
      playerIds.firstWhere((id) => id != playerId);

  /// Every cell occupied by [playerId]'s ships (empty if not yet placed).
  Set<int> shipCellsOf(String playerId) {
    final fleet = fleets[playerId];
    if (fleet == null) return const {};
    return {for (final ship in fleet) ...ship.cells};
  }

  /// The ship of [playerId] occupying [cell], if any.
  ShipPlacement? shipAt(String playerId, int cell) {
    final fleet = fleets[playerId];
    if (fleet == null) return null;
    for (final ship in fleet) {
      if (ship.cells.contains(cell)) return ship;
    }
    return null;
  }

  /// Ships of [playerId] whose every cell has been hit.
  List<ShipPlacement> sunkShipsOf(String playerId) {
    final fleet = fleets[playerId];
    if (fleet == null) return const [];
    final resolved = shots[playerId] ?? const <int>{};
    return [
      for (final ship in fleet)
        if (ship.cells.every(resolved.contains)) ship,
    ];
  }

  /// Whether [playerId]'s entire fleet is sunk.
  bool allSunk(String playerId) {
    final fleet = fleets[playerId];
    if (fleet == null) return false;
    final resolved = shots[playerId] ?? const <int>{};
    return shipCellsOf(playerId).every(resolved.contains);
  }
}

/// GamePigeon-rules Sea Battle (Russian battleship fleet).
///
/// 10×10 grid, fleet of 1×4 + 2×3 + 3×2 + 4×1. Ships are straight lines and
/// may not touch — not even diagonally. A hit grants another shot; sinking a
/// ship auto-reveals all surrounding water as misses. First player to sink
/// the whole enemy fleet wins.
class SeaBattleGame extends TurnGame<SeaBattleState, SeaBattleMove> {
  const SeaBattleGame();

  /// Ship lengths in the fleet, longest first.
  static const List<int> shipLengths = [4, 3, 3, 2, 2, 2, 1, 1, 1, 1];

  static const int boardSize = seaBattleBoardSize;

  @override
  String get id => 'sea_battle';

  @override
  SeaBattleState initialState({
    required int seed,
    required List<String> playerIds,
  }) {
    assert(playerIds.length == 2, 'Sea Battle is a 2-player game');
    return SeaBattleState(
      playerIds: List.of(playerIds),
      fleets: {for (final id in playerIds) id: null},
      shots: {for (final id in playerIds) id: const {}},
      currentPlayerId: playerIds[0],
    );
  }

  @override
  String currentPlayer(SeaBattleState state) => state.currentPlayerId;

  // -------------------------------------------------------------------------
  // Fleet legality
  // -------------------------------------------------------------------------

  /// [ship]'s cells plus every in-bounds neighbor (8-directional halo).
  static Set<int> haloCells(ShipPlacement ship) {
    final halo = <int>{};
    for (final cell in ship.cells) {
      final r = cell ~/ boardSize;
      final c = cell % boardSize;
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          final nr = r + dr;
          final nc = c + dc;
          if (nr < 0 || nr >= boardSize || nc < 0 || nc >= boardSize) continue;
          halo.add(nr * boardSize + nc);
        }
      }
    }
    return halo;
  }

  /// Whether [ships] is a complete legal fleet: exact GP ship counts, every
  /// ship in bounds, no overlaps, no two ships touching (diagonals included).
  static bool isFleetValid(List<ShipPlacement> ships) {
    if (ships.length != shipLengths.length) return false;
    final counts = <int, int>{};
    for (final ship in ships) {
      counts[ship.length] = (counts[ship.length] ?? 0) + 1;
      if (ship.length < 1) return false;
      if (ship.row < 0 || ship.col < 0) return false;
      final endRow = ship.horizontal ? ship.row : ship.row + ship.length - 1;
      final endCol = ship.horizontal ? ship.col + ship.length - 1 : ship.col;
      if (endRow >= boardSize || endCol >= boardSize) return false;
    }
    final expected = <int, int>{};
    for (final len in shipLengths) {
      expected[len] = (expected[len] ?? 0) + 1;
    }
    if (counts.length != expected.length) return false;
    for (final entry in expected.entries) {
      if (counts[entry.key] != entry.value) return false;
    }

    // Overlap + adjacency: each ship's halo may not contain another's cells.
    for (var i = 0; i < ships.length; i++) {
      final halo = haloCells(ships[i]);
      for (var j = 0; j < ships.length; j++) {
        if (i == j) continue;
        if (ships[j].cells.any(halo.contains)) return false;
      }
    }
    return true;
  }

  /// A random legal fleet, fully determined by [seed].
  static List<ShipPlacement> randomFleet(int seed) {
    final rnd = math.Random(seed);
    while (true) {
      final ships = <ShipPlacement>[];
      final blocked = <int>{};
      var stuck = false;
      for (final len in shipLengths) {
        ShipPlacement? placed;
        for (var attempt = 0; attempt < 200; attempt++) {
          final horizontal = rnd.nextBool();
          final row = rnd.nextInt(horizontal ? boardSize : boardSize - len + 1);
          final col = rnd.nextInt(horizontal ? boardSize - len + 1 : boardSize);
          final candidate = ShipPlacement(
            row: row,
            col: col,
            length: len,
            horizontal: horizontal,
          );
          if (candidate.cells.any(blocked.contains)) continue;
          placed = candidate;
          break;
        }
        if (placed == null) {
          stuck = true;
          break;
        }
        ships.add(placed);
        blocked.addAll(haloCells(placed));
      }
      if (!stuck) return ships;
    }
  }

  // -------------------------------------------------------------------------
  // Moves
  // -------------------------------------------------------------------------

  @override
  bool validateMove(
    SeaBattleState state,
    SeaBattleMove move,
    String playerId,
  ) {
    if (outcome(state) != null) return false;
    if (playerId != state.currentPlayerId) return false;
    switch (move) {
      case PlaceFleetMove(:final ships):
        if (state.phase != SeaBattlePhase.placement) return false;
        if (state.fleets[playerId] != null) return false;
        return isFleetValid(ships);
      case FireMove(:final cell):
        if (state.phase != SeaBattlePhase.battle) return false;
        if (cell < 0 || cell >= boardSize * boardSize) return false;
        final target = state.opponentOf(playerId);
        return !(state.shots[target] ?? const <int>{}).contains(cell);
    }
  }

  @override
  SeaBattleState applyMove(SeaBattleState state, SeaBattleMove move) {
    final actor = state.currentPlayerId;
    switch (move) {
      case PlaceFleetMove(:final ships):
        final fleets = Map<String, List<ShipPlacement>?>.of(state.fleets);
        fleets[actor] = List.of(ships);
        // Next unplaced player places; once everyone is down, player 1 fires.
        final next = state.playerIds.firstWhere(
          (id) => fleets[id] == null,
          orElse: () => state.playerIds[0],
        );
        return SeaBattleState(
          playerIds: state.playerIds,
          fleets: fleets,
          shots: state.shots,
          currentPlayerId: next,
        );
      case FireMove(:final cell):
        final target = state.opponentOf(actor);
        final resolved = Set<int>.of(state.shots[target] ?? const <int>{})
          ..add(cell);
        final hitShip = state.shipAt(target, cell);
        if (hitShip != null && hitShip.cells.every(resolved.contains)) {
          // Sunk: ships never touch, so the whole halo is water — reveal it.
          resolved.addAll(
            haloCells(hitShip).where((c) => !hitShip.cells.contains(c)),
          );
        }
        final shots = Map<String, Set<int>>.of(state.shots);
        shots[target] = resolved;
        return SeaBattleState(
          playerIds: state.playerIds,
          fleets: state.fleets,
          shots: shots,
          // Hit (including sink) grants another shot; miss passes the turn.
          currentPlayerId: hitShip != null ? actor : target,
          lastShotCell: cell,
          lastShotTarget: target,
        );
    }
  }

  @override
  GameOutcome? outcome(SeaBattleState state) {
    if (state.phase != SeaBattlePhase.battle) return null;
    for (final id in state.playerIds) {
      if (state.allSunk(id)) return GameOutcome.win(state.opponentOf(id));
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  @override
  Map<String, dynamic> encodeState(SeaBattleState state) => {
        'playerIds': state.playerIds,
        'fleets': {
          for (final entry in state.fleets.entries)
            entry.key: entry.value?.map((s) => s.toJson()).toList(),
        },
        'shots': {
          for (final entry in state.shots.entries)
            entry.key: entry.value.toList()..sort(),
        },
        'current': state.currentPlayerId,
        if (state.lastShotCell != null) 'lastShotCell': state.lastShotCell,
        if (state.lastShotTarget != null)
          'lastShotTarget': state.lastShotTarget,
      };

  @override
  SeaBattleState decodeState(Map<String, dynamic> json, int version) {
    final playerIds =
        (json['playerIds'] as List).map((e) => e as String).toList();
    final rawFleets = (json['fleets'] as Map?) ?? const {};
    final rawShots = (json['shots'] as Map?) ?? const {};
    return SeaBattleState(
      playerIds: playerIds,
      fleets: {
        for (final id in playerIds)
          id: rawFleets[id] == null
              ? null
              : (rawFleets[id] as List)
                  .map((s) => ShipPlacement.fromJson(s as List))
                  .toList(),
      },
      shots: {
        for (final id in playerIds)
          id: ((rawShots[id] as List?) ?? const [])
              .map((e) => e as int)
              .toSet(),
      },
      currentPlayerId: json['current'] as String,
      lastShotCell: json['lastShotCell'] as int?,
      lastShotTarget: json['lastShotTarget'] as String?,
    );
  }

  @override
  Map<String, dynamic> encodeMove(SeaBattleMove move) => switch (move) {
        PlaceFleetMove(:final ships) => {
            'type': 'place',
            'ships': ships.map((s) => s.toJson()).toList(),
          },
        FireMove(:final cell) => {'type': 'fire', 'cell': cell},
      };

  @override
  SeaBattleMove decodeMove(Map<String, dynamic> json) =>
      switch (json['type'] as String) {
        'place' => PlaceFleetMove(
            (json['ships'] as List)
                .map((s) => ShipPlacement.fromJson(s as List))
                .toList(),
          ),
        'fire' => FireMove(json['cell'] as int),
        final other => throw ArgumentError('Unknown move type: $other'),
      };
}
