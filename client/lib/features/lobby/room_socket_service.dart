import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/app/config.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _maxRetries = 3;
const _retryBaseMs = 1000;

class RoomSocketService {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  final _controller = StreamController<ServerEvent>.broadcast();
  String? _cachedPlayerId;
  String? _cachedReconnectToken;
  // Needed alongside playerId/reconnectToken to re-authenticate an
  // automatic-retry socket via check_presence — the server's handler
  // requires all three (see rooms.gateway.ts's CheckPresenceDto). Without
  // this, an auto-reopened socket never gets re-associated with the
  // player's room/session, which is exactly what "checkpresence not found"
  // in the server logs means: the reconnect request arrived without (or
  // with a stale) roomCode.
  String? _cachedRoomCode;
  // Mirrors _cachedPlayerId exactly, for the same reason: a generic room
  // broadcast carries localSpectatorId: null for every recipient (only the
  // spectate_room ack itself carries the real value), so a spectator's own
  // identity needs to survive those broadcasts the same way a player's does.
  // In-memory only — does NOT survive an app restart/refresh (that's the
  // spectator_reconnect persistence work, deliberately not done here yet).
  String? _cachedSpectatorId;

  int _retryCount = 0;
  bool _intentionalClose = false;

  Stream<ServerEvent> get stream => _controller.stream;

  void setCachedPlayerId(String id) => _cachedPlayerId = id;

  void setCachedSpectatorId(String? id) => _cachedSpectatorId = id;

  /// Cached the same way as playerId/reconnectToken — required so an
  /// automatic-retry reconnect (see [_onClosed]) can re-authenticate itself
  /// without needing anything from the caller.
  void setCachedRoomCode(String? code) => _cachedRoomCode = code;

  /// Cached so it survives broadcasts that only echo `localPlayerId`/identity
  /// to the room as a whole (other players' room_update payloads never carry
  /// a reconnectToken — it's private to the player it was issued for).
  void setCachedReconnectToken(String? token) => _cachedReconnectToken = token;

  /// The reconnect token the server issued at create/join/approve time. Used as
  /// a fallback when persisting presence at game start (the game_state broadcast
  /// that triggers persistence carries no token of its own).
  String? get cachedReconnectToken => _cachedReconnectToken;

  bool get isConnected => _channel != null;

  /// Opens the socket if not already open. No-op if already connected.
  void connect() {
    if (_channel != null) return;
    _intentionalClose = false;
    _retryCount = 0;
    _open();
  }

  /// Closes and re-opens a fresh socket.
  /// Use for Jump In and Leave Permanently (need a fresh handshake).
  void reconnect() {
    _intentionalClose = false;
    _retryCount = 0;
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _open();
  }

  /// Closes the socket intentionally without auto-retry.
  /// Server will detect the disconnect and mark the player as disconnected
  /// (NOT permanently removed). Used by "Leave to Home" so the player can
  /// Jump In later.
  void closeGracefully() {
    _intentionalClose = true;
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void _open() {
    final channel = WebSocketChannel.connect(Uri.parse(AppConfig.socketUrl));
    _channel = channel;
    debugPrint('[RoomSocketService] socket OPENING -> ${AppConfig.socketUrl}');
    _sub = channel.stream.listen(
      _onData,
      onError: (_) => _onClosed(),
      onDone: _onClosed,
    );
    // A failed TCP connect (e.g. "Connection refused" — dev server not
    // running, wrong host/port) rejects `channel.ready`, NOT necessarily
    // `channel.stream` — `WebSocketChannel.connect()`'s lazy connection
    // means a rejected `.ready` with no listener becomes an UNHANDLED
    // exception in the Dart zone (exactly the crash-log symptom this
    // fixes), and critically: neither onError nor onDone above ever fires
    // for it. `_channel` stayed non-null (looking "connected" to every
    // other check in this class), `_onClosed()` was never called, so no
    // retry/backoff ever kicked in and the caller was left waiting forever
    // on a socket that was actually dead — the exact "black screen stuck
    // on loading after rejoin" failure mode. Routes any such failure
    // through the same `_onClosed()` retry/give-up path as a normal drop.
    // The `identical` guard prevents double-handling if the stream's own
    // onError/onDone ALSO fires for the same failure (whichever fires
    // first sets `_channel = null`, so the second one's identity check
    // fails and it's a no-op).
    channel.ready.then(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[RoomSocketService] socket OPEN FAILED: $error');
        if (identical(_channel, channel)) _onClosed();
      },
    );
    debugPrint('[RoomSocketService] socket OPENED -> ${AppConfig.socketUrl}');
  }

  void _onData(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      final event = parseServerEvent(
        json,
        _cachedPlayerId,
        _cachedReconnectToken,
        _cachedSpectatorId,
      );
      if (event != null) {
        // A successfully parsed message is proof this socket is genuinely
        // live and talking to the server — reset the retry counter so a
        // LATER unrelated drop gets the full retry budget again, instead of
        // inheriting a partially-used count from an earlier, unrelated blip.
        _retryCount = 0;
        _controller.add(event);
      }
    } catch (e, st) {
      // Previously silently swallowed — a malformed/partial message during
      // a reconnect window used to vanish with zero signal that anything
      // had gone wrong.
      debugPrint(
        '[RoomSocketService] failed to parse incoming message: $e\n$st',
      );
    }
  }

  void _onClosed() {
    debugPrint(
      '[RoomSocketService] socket CLOSED '
      '(intentional=$_intentionalClose)',
    );
    _sub?.cancel();
    _channel = null;
    if (_intentionalClose) return;

    if (_retryCount < _maxRetries) {
      _retryCount++;
      _controller.add(const SocketReconnecting());
      final delay = Duration(milliseconds: _retryBaseMs * _retryCount);
      debugPrint(
        '[RoomSocketService] connection lost — reconnect attempt '
        '#$_retryCount/$_maxRetries in ${delay.inMilliseconds}ms',
      );
      Future.delayed(delay, _reopenAndReauthenticate);
    } else {
      debugPrint('[RoomSocketService] max retries exhausted — giving up');
      _controller.add(const SocketDisconnected());
    }
  }

  /// Reopens the socket after an UNINTENTIONAL drop and re-authenticates it.
  ///
  /// A freshly (re)opened WebSocketChannel is anonymous — the server has no
  /// way to know which player/room it belongs to until told. [connect] (the
  /// very first open) doesn't need this: the caller's own create/join/
  /// jumpIn flow establishes identity through its own explicit messages.
  /// The manual [reconnect] used by jumpIn()/jumpInAsSpectator() doesn't
  /// need this either — those callers already send their own
  /// check_presence/spectator_reconnect right after calling it.
  ///
  /// This automatic-retry path is the one gap: until this fix, it just
  /// reopened a raw socket and went silent, which is exactly what produced
  /// "check_presence: not found" server-side — the client was "connected"
  /// again but never told the server who it was, so game_state and action
  /// acks stopped routing back to it (visible client-side as the current
  /// phase's panel silently going stale/falling back to a generic waiting
  /// state, e.g. mid-substitutions after the first pick).
  void _reopenAndReauthenticate() {
    _open();
    final roomCode = _cachedRoomCode;
    final token = _cachedReconnectToken;
    if (roomCode == null || roomCode.isEmpty) return;
    if (token == null || token.isEmpty) return;

    final playerId = _cachedPlayerId;
    if (playerId != null && playerId.isNotEmpty) {
      debugPrint(
        '[RoomSocketService] check_presence REQUEST (auto-retry) '
        'playerId=$playerId roomCode=$roomCode',
      );
      send('check_presence', {
        'playerId': playerId,
        'roomCode': roomCode,
        'reconnectToken': token,
      });
      return;
    }

    final spectatorId = _cachedSpectatorId;
    if (spectatorId != null && spectatorId.isNotEmpty) {
      debugPrint(
        '[RoomSocketService] spectator_reconnect REQUEST (auto-retry) '
        'spectatorId=$spectatorId roomCode=$roomCode',
      );
      send('spectator_reconnect', {
        'spectatorId': spectatorId,
        'roomCode': roomCode,
        'reconnectToken': token,
      });
    }
  }

  /// Severs this socket's cached player/spectator identity entirely. Called
  /// by RoomNotifier the moment a reconnect attempt (check_presence /
  /// spectator_reconnect) comes back definitively rejected (NOT_FOUND /
  /// INVALID_TOKEN) — see RoomNotifier's SessionDesync handling.
  ///
  /// Without this, [_reopenAndReauthenticate] would keep re-sending
  /// check_presence with the exact same now-known-dead playerId/roomCode/
  /// token on every future unintentional disconnect, forever re-attempting
  /// a reconnect the server has already explicitly rejected — and could
  /// re-trigger the same silent-divergence failure mode this fix closes if
  /// any UI path were ever re-added that reacts to a bare `error` event
  /// without also consulting sessionDesyncedProvider.
  void clearCachedIdentity() {
    debugPrint(
      '[RoomSocketService] clearing cached identity '
      '(was playerId=$_cachedPlayerId roomCode=$_cachedRoomCode '
      'spectatorId=$_cachedSpectatorId)',
    );
    _cachedPlayerId = null;
    _cachedRoomCode = null;
    _cachedReconnectToken = null;
    _cachedSpectatorId = null;
  }

  /// Sends a message. If the socket died from max retries (not intentional
  /// close), reconnects automatically. web_socket_channel buffers the
  /// message until the connection opens.
  void send(String event, [Map<String, dynamic>? data]) {
    if (_channel == null && !_intentionalClose) {
      // Died from retries — reconnect so the message gets through.
      reconnect();
    }
    final payload = jsonEncode({'event': event, 'data': data ?? {}});
    _channel?.sink.add(payload);
  }

  void dispose() {
    _intentionalClose = true;
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _controller.close();
  }
}

final roomSocketServiceProvider = Provider<RoomSocketService>((ref) {
  final service = RoomSocketService();
  ref.onDispose(service.dispose);
  return service;
});
