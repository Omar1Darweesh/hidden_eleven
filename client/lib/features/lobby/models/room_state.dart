import 'package:flutter/foundation.dart';
import 'package:hidden_eleven/features/lobby/models/player.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/models/spectator.dart';

@immutable
class RoomState {
  const RoomState({
    required this.code,
    required this.players,
    this.spectators = const [],
    this.isStarted = false,
    this.isLocked = false,
    this.pendingCount = 0,
    this.localPlayerId,
    this.localSpectatorId,
    this.leagues = const [],
    this.tournamentEnabled = false,
    this.minRating,
    this.maxRating,
    this.poolShortages = const [],
  });

  final String code;
  final List<Player> players;

  /// Read-only room observers. Empty by default — absent entirely from
  /// server payloads older than the spectator protocol, or simply a room
  /// with nobody watching.
  final List<Spectator> spectators;
  final bool isStarted;
  final bool isLocked;
  final int pendingCount;

  /// Null when there is no local player — either this client hasn't been
  /// assigned a seat yet, or it's spectating (see Spectator model). Never
  /// coerced to an empty string: `''` is not a valid player id and must not
  /// be treated as one (see server_event.dart's _parseRoomUpdate).
  final String? localPlayerId;

  /// Non-null once this client has successfully spectate_room'd this room
  /// (see server_event.dart's _parseRoomUpdate). A player and a spectator id
  /// are never both non-null for the same client — the server never assigns
  /// both to one socket.
  final String? localSpectatorId;

  /// League slugs selected when the room was created.
  final List<String> leagues;

  /// Whether a knockout tournament runs after the draft.
  final bool tournamentEnabled;

  /// Host-tunable draft rating window. Null on either end = no bound there
  /// (full 1–99 range). Adjustable live in the lobby by the host.
  final int? minRating;
  final int? maxRating;

  /// Live pool-sufficiency check from the server for the CURRENT player count.
  /// Empty = the current league + rating filter can fill every position (safe
  /// to start). Non-empty names the short positions.
  final List<PoolShortage> poolShortages;

  bool get poolOk => poolShortages.isEmpty;
  bool get ratingRestricted =>
      (minRating != null && minRating! > 1) ||
      (maxRating != null && maxRating! < 99);

  Player? get localPlayer =>
      players.where((p) => p.id == localPlayerId).firstOrNull;

  bool get isSpectating => localSpectatorId != null;

  RoomState copyWith({
    String? code,
    List<Player>? players,
    List<Spectator>? spectators,
    bool? isStarted,
    bool? isLocked,
    int? pendingCount,
    String? localPlayerId,
    String? localSpectatorId,
    List<String>? leagues,
    bool? tournamentEnabled,
    int? minRating,
    int? maxRating,
    List<PoolShortage>? poolShortages,
  }) {
    return RoomState(
      code: code ?? this.code,
      players: players ?? this.players,
      spectators: spectators ?? this.spectators,
      isStarted: isStarted ?? this.isStarted,
      isLocked: isLocked ?? this.isLocked,
      pendingCount: pendingCount ?? this.pendingCount,
      localPlayerId: localPlayerId ?? this.localPlayerId,
      localSpectatorId: localSpectatorId ?? this.localSpectatorId,
      leagues: leagues ?? this.leagues,
      tournamentEnabled: tournamentEnabled ?? this.tournamentEnabled,
      minRating: minRating ?? this.minRating,
      maxRating: maxRating ?? this.maxRating,
      poolShortages: poolShortages ?? this.poolShortages,
    );
  }

  /// A separate method from copyWith specifically to CLEAR localSpectatorId
  /// back to null — copyWith's `??` convention (standard Dart limitation)
  /// can't distinguish "leave this field alone" from "set it to null", and
  /// stop_spectating is the one place that genuinely needs to clear rather
  /// than leave alone (see RoomNotifier.stopSpectating).
  RoomState clearLocalSpectatorId() => RoomState(
    code: code,
    players: players,
    spectators: spectators,
    isStarted: isStarted,
    isLocked: isLocked,
    pendingCount: pendingCount,
    localPlayerId: localPlayerId,
    leagues: leagues,
    tournamentEnabled: tournamentEnabled,
    minRating: minRating,
    maxRating: maxRating,
    poolShortages: poolShortages,
  );
}
