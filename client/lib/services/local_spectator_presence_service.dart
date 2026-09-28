import 'package:shared_preferences/shared_preferences.dart';

/// Persisted spectator seat — deliberately a completely separate model,
/// storage keys, and service from LocalPresenceData/LocalPresenceService
/// (player presence). Keeping these two fully independent (not, say, a
/// shared "role" field on one model) is what makes it structurally
/// impossible for a spectator-presence read/write to ever touch, overwrite,
/// or race with player presence data — mirrors the same separation
/// principle already used server-side and client-side for Spectator vs
/// Player (see MULTIPLAYER_ROOMS_DESIGN.md, FLUTTER_CLIENT_AUDIT.md).
///
/// Only ever saved for a room that has actually started (see
/// GameNotifier's spectator branch) — mirrors LocalPresenceData's own rule
/// that lobby-only presence is never persisted, for the same reason: a
/// spectator watching an empty, not-yet-started lobby has nothing worth
/// resuming after a refresh.
class LocalSpectatorPresenceData {
  const LocalSpectatorPresenceData({
    required this.spectatorId,
    required this.roomCode,
    required this.displayName,
    this.reconnectToken,
  });

  final String spectatorId;
  final String roomCode;
  final String displayName;

  /// Signed server-issued token required to resume via spectator_reconnect.
  /// Nullable for the same reason LocalPresenceData.reconnectToken is: a
  /// spectator_reconnect with no token is rejected (INVALID_TOKEN), which is
  /// treated the same as NOT_FOUND — clear presence, spectate again manually.
  final String? reconnectToken;
}

class LocalSpectatorPresenceService {
  static const _keySpectatorId = 'spectator_presence_id';
  static const _keyRoomCode = 'spectator_presence_room_code';
  static const _keyDisplayName = 'spectator_presence_display_name';
  static const _keyReconnectToken = 'spectator_presence_reconnect_token';

  Future<LocalSpectatorPresenceData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final spectatorId = prefs.getString(_keySpectatorId);
    final roomCode = prefs.getString(_keyRoomCode);
    final displayName = prefs.getString(_keyDisplayName);
    final reconnectToken = prefs.getString(_keyReconnectToken);

    if (spectatorId == null || roomCode == null || displayName == null) {
      return null;
    }

    return LocalSpectatorPresenceData(
      spectatorId: spectatorId,
      roomCode: roomCode,
      displayName: displayName,
      reconnectToken: reconnectToken,
    );
  }

  Future<void> save(LocalSpectatorPresenceData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySpectatorId, data.spectatorId);
    await prefs.setString(_keyRoomCode, data.roomCode);
    await prefs.setString(_keyDisplayName, data.displayName);
    if (data.reconnectToken != null) {
      await prefs.setString(_keyReconnectToken, data.reconnectToken!);
    } else {
      await prefs.remove(_keyReconnectToken);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySpectatorId);
    await prefs.remove(_keyRoomCode);
    await prefs.remove(_keyDisplayName);
    await prefs.remove(_keyReconnectToken);
  }
}
