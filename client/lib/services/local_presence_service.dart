import 'package:shared_preferences/shared_preferences.dart';

enum LocalPresenceStatus { none, inRoom, inGame }

class LocalPresenceData {
  const LocalPresenceData({
    required this.playerId,
    required this.roomCode,
    required this.displayName,
    required this.status,
    this.reconnectToken,
  });

  final String playerId;
  final String roomCode;
  final String displayName;
  final LocalPresenceStatus status;

  /// Signed server-issued token required to resume this seat via
  /// reconnect/check_presence. Nullable only for presence data persisted
  /// before this field existed — a check_presence with no token is rejected
  /// by the server (INVALID_TOKEN), which the UI treats the same as
  /// NOT_FOUND: clear presence and let the player rejoin manually.
  final String? reconnectToken;
}

class LocalPresenceService {
  static const _keyPlayerId = 'presence_player_id';
  static const _keyRoomCode = 'presence_room_code';
  static const _keyDisplayName = 'presence_display_name';
  static const _keyStatus = 'presence_status';
  static const _keyReconnectToken = 'presence_reconnect_token';

  Future<LocalPresenceData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final playerId = prefs.getString(_keyPlayerId);
    final roomCode = prefs.getString(_keyRoomCode);
    final displayName = prefs.getString(_keyDisplayName);
    final statusStr = prefs.getString(_keyStatus);
    final reconnectToken = prefs.getString(_keyReconnectToken);

    if (playerId == null || roomCode == null || displayName == null)
      return null;

    final status = LocalPresenceStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => LocalPresenceStatus.inRoom,
    );

    return LocalPresenceData(
      playerId: playerId,
      roomCode: roomCode,
      displayName: displayName,
      status: status,
      reconnectToken: reconnectToken,
    );
  }

  Future<void> save(LocalPresenceData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPlayerId, data.playerId);
    await prefs.setString(_keyRoomCode, data.roomCode);
    await prefs.setString(_keyDisplayName, data.displayName);
    await prefs.setString(_keyStatus, data.status.name);
    if (data.reconnectToken != null) {
      await prefs.setString(_keyReconnectToken, data.reconnectToken!);
    } else {
      await prefs.remove(_keyReconnectToken);
    }
  }

  Future<void> updateStatus(LocalPresenceStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStatus, status.name);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPlayerId);
    await prefs.remove(_keyRoomCode);
    await prefs.remove(_keyDisplayName);
    await prefs.remove(_keyStatus);
    await prefs.remove(_keyReconnectToken);
  }
}
