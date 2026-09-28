import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/lobby/models/room_state.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/room_socket_service.dart';
import 'package:hidden_eleven/services/local_presence_service.dart';
import 'package:hidden_eleven/services/local_spectator_presence_service.dart';
import 'package:hidden_eleven/shared/providers/local_presence_provider.dart';
import 'package:hidden_eleven/shared/providers/local_spectator_presence_provider.dart';

/// Whether a `RoomUpdated` identity value (a player id OR a spectator id) is
/// safe to cache. A null or empty value means the client has no seat of that
/// kind right now, and caching it would overwrite a real, previously-cached
/// id with garbage the next time this socket needs to resolve who it is on
/// a subsequent broadcast. Extracted as a standalone function so this
/// decision is directly unit-testable without needing to drive RoomNotifier's
/// full reactive pipeline (Riverpod + a live socket).
bool isCacheableId(String? id) => id != null && id.isNotEmpty;

/// A reconnect attempt (check_presence or spectator_reconnect) came back
/// definitively rejected — see [SessionDesyncData]'s doc comment for the
/// full failure chain this closes.
class SessionDesyncData {
  const SessionDesyncData({
    required this.code,
    required this.isSpectator,
    required this.detectedAt,
  });

  /// 'NOT_FOUND' (the room/seat is gone — most commonly a server restart,
  /// which wipes the in-memory session store; see PROJECT_OVERVIEW.md) or
  /// 'INVALID_TOKEN' (the reconnect token was missing/tampered/for a
  /// different room).
  final String code;

  /// Which local identity this rejection belongs to — a player's
  /// check_presence or a spectator's spectator_reconnect.
  final bool isSpectator;

  final DateTime detectedAt;
}

/// Fires when RoomNotifier receives a definitive reconnect rejection. A
/// non-null value here is a HARD, terminal state for the client's CURRENT
/// local room/game/presence — by the time this fires, RoomNotifier has
/// already wiped all of it (see [RoomNotifier._handleReconnectRejection]).
///
/// This is the fix for a real production bug: previously, a rejected
/// reconnect only cleared the local-presence "resume card" cache. It never
/// cleared `roomProvider`'s own RoomState or `gameProvider`'s GameState, and
/// `GameScreen`'s own ad hoc NOT_FOUND listener only acted when
/// `roomProvider` was ALREADY null — which is never true in the exact
/// scenario that matters (a client already mid-game whose socket drops,
/// auto-reopens, and gets rejected). The result: that client kept silently
/// rendering its last-known-good, now-orphaned room/game snapshot forever,
/// with zero error shown anywhere, while a DIFFERENT client (or the same
/// user after manually returning home) was free to Host/Join a brand new
/// room — two clients permanently diverged into two different rooms with no
/// warning to either.
///
/// `HiddenElevenApp`'s root `builder` watches this provider and preempts
/// EVERY route with `SessionDesyncedScreen` the instant it's set —
/// deliberately not scoped to any one screen, since the underlying socket
/// drop can happen while the user is on any of them. Cleared by exactly one
/// path: that screen's "Return to Home" button — the single explicit
/// recovery path this fix requires. Nothing else clears it.
class SessionDesyncNotifier extends Notifier<SessionDesyncData?> {
  @override
  SessionDesyncData? build() => null;

  void trigger(SessionDesyncData data) => state = data;

  /// The single explicit recovery path — called only from
  /// SessionDesyncedScreen's "Return to Home" button.
  void acknowledge() => state = null;
}

final sessionDesyncedProvider =
    NotifierProvider<SessionDesyncNotifier, SessionDesyncData?>(
      SessionDesyncNotifier.new,
    );

class RoomNotifier extends Notifier<RoomState?> {
  StreamSubscription<ServerEvent>? _sub;

  /// True while a spectator_reconnect this notifier just sent is awaiting its
  /// server response. NOT_FOUND/INVALID_TOKEN are shared error codes emitted
  /// by both check_presence and spectator_reconnect — this flag is the only
  /// way to tell which outstanding request an error actually belongs to, so
  /// a failed spectator resume can never clear a valid, unrelated player
  /// presence (and vice versa), and so a successful/failed response can be
  /// correctly attributed for logging. Reset on the very next RoomUpdated or
  /// rejection, which — because jumpInAsSpectator() always opens a
  /// brand-new socket first — is guaranteed to be that request's own
  /// response, not some unrelated broadcast arriving first.
  bool _spectatorReconnectPending = false;

  /// Same purpose as [_spectatorReconnectPending], for the player
  /// check_presence side — used only for accept/reject logging clarity
  /// (presence-clearing itself doesn't need it: the absence of
  /// [_spectatorReconnectPending] already means "this was a player
  /// attempt", which is the existing, tested precedence rule).
  bool _playerReconnectPending = false;

  @override
  RoomState? build() {
    final service = ref.watch(roomSocketServiceProvider);
    service.connect();
    _sub = service.stream.listen(_onEvent);
    ref.onDispose(() => _sub?.cancel());
    return null;
  }

  void _onEvent(ServerEvent event) {
    switch (event) {
      case RoomUpdated(
        :final room,
        :final localPlayerId,
        :final localSpectatorId,
        :final reconnectToken,
      ):
        // Any room_update settles whichever outstanding reconnect attempt
        // this socket had in flight — see the flag's doc comment.
        if (_spectatorReconnectPending) {
          debugPrint(
            '[RoomNotifier] spectator_reconnect ACCEPTED '
            'roomCode=${room.code}',
          );
        } else if (_playerReconnectPending) {
          debugPrint(
            '[RoomNotifier] check_presence ACCEPTED '
            'roomCode=${room.code} playerId=$localPlayerId',
          );
        }
        _spectatorReconnectPending = false;
        _playerReconnectPending = false;
        final service = ref.read(roomSocketServiceProvider);
        if (isCacheableId(localPlayerId)) {
          service.setCachedPlayerId(localPlayerId!);
        }
        if (isCacheableId(localSpectatorId)) {
          service.setCachedSpectatorId(localSpectatorId);
        }
        if (reconnectToken != null) {
          service.setCachedReconnectToken(reconnectToken);
        }
        // Required alongside playerId/reconnectToken for an automatic-retry
        // reconnect to re-authenticate itself — see setCachedRoomCode's doc.
        service.setCachedRoomCode(room.code);
        final newRoom = room.copyWith(
          localPlayerId: localPlayerId,
          localSpectatorId: localSpectatorId,
        );
        state = newRoom;
        _savePresence(newRoom, localPlayerId, reconnectToken);

      case GameStateReceived():
        break;

      case JoinPending():
      case JoinRequest():
      case JoinRejected():
        break;

      case Kicked():
        break;

      case ServerError(code: 'NOT_FOUND'):
        // Room no longer exists, or the seat was fully removed. Shared by
        // check_presence (player) and spectator_reconnect (spectator) — see
        // _handleReconnectRejection for the full (now hard-blocking) fix.
        _handleReconnectRejection('NOT_FOUND');

      case ServerError(code: 'INVALID_TOKEN'):
        // Reconnect token missing/tampered/for a different room — same
        // fatal outcome as NOT_FOUND: this saved seat can never be resumed.
        _handleReconnectRejection('INVALID_TOKEN');

      case ServerError():
        break;

      case SlotCandidatesReceived():
      case FirstPlayerOrderPromptReceived():
      case HiddenPickPromptReceived():
      case CardRevealedReceived():
      case TurnTimerStarted():
      case TurnAutoPicked():
      case SubSpinResult():
        break;

      // Tournament events are consumed by GameNotifier / tournament providers,
      // not here — listed so this exhaustive switch stays complete.
      case TournamentStateReceived():
      case TournamentMatchEventReceived():
      case TournamentMatchResultReceived():
      case TournamentCompleteReceived():
      case TournamentAutoReadyReceived():
        break;

      case SocketDisconnected():
        break;

      case SocketReconnecting():
        break;
    }
  }

  /// A rejected check_presence/spectator_reconnect (NOT_FOUND — the room/
  /// seat is gone, most commonly a server restart wiping the in-memory
  /// session store — or INVALID_TOKEN) is FATAL and unrecoverable for this
  /// client's CURRENT identity: the room/game the UI may currently be
  /// showing can never be resumed, and this exact identity must never be
  /// silently retried again.
  ///
  /// See [sessionDesyncedProvider]'s doc comment for the full bug this
  /// closes — previously this only cleared the local-presence "resume card"
  /// cache, never `state` (this notifier's own RoomState) or `gameProvider`,
  /// which is how a client already mid-game could keep silently rendering
  /// its last-known-good, now-orphaned snapshot forever after a rejected
  /// reconnect, with zero error shown anywhere.
  void _handleReconnectRejection(String code) {
    final isSpectator = _spectatorReconnectPending;
    debugPrint(
      '[RoomNotifier] reconnect REJECTED code=$code '
      'identity=${isSpectator ? 'spectator' : 'player'} — wiping local '
      'room/game state and forcing recovery UI',
    );
    _spectatorReconnectPending = false;
    _playerReconnectPending = false;

    // Never let RoomSocketService's automatic reconnect-after-drop retry
    // this same now-known-dead identity again.
    ref.read(roomSocketServiceProvider).clearCachedIdentity();

    // Wipe every piece of local state that could otherwise let a stale UI
    // keep rendering, or let a stray action reach the server under an
    // identity the server has explicitly rejected. `state = null` here is
    // the fix's core addition — previously untouched, so a client already
    // mid-game (roomProvider non-null) never reacted to this at all (see
    // game_screen.dart's now-removed guarded NOT_FOUND handler).
    state = null;
    ref.read(gameProvider.notifier).reset();

    // Only the identity that actually failed is cleared — a failed
    // spectator resume must never clear a valid, unrelated player presence
    // (and vice versa); this precedence rule predates this fix and is
    // covered by existing tests in spectator_presence_test.dart.
    if (isSpectator) {
      ref.read(localSpectatorPresenceProvider.notifier).clear();
    } else {
      ref.read(localPresenceProvider.notifier).clear();
    }

    debugPrint(
      '[RoomNotifier] session desynced — showing recovery UI '
      '(single explicit recovery path: SessionDesyncedScreen)',
    );
    ref
        .read(sessionDesyncedProvider.notifier)
        .trigger(
          SessionDesyncData(
            code: code,
            isSpectator: isSpectator,
            detectedAt: DateTime.now(),
          ),
        );
  }

  // Presence is saved only when the game is running, and only for an actual
  // player seat — a null localPlayerId (no seat, or spectating) has no
  // player to look up, and `room.players.where((p) => p.id == null)` would
  // never match anyway, but the explicit null check documents that this is
  // an expected, normal case rather than something falling through by luck.
  void _savePresence(
    RoomState room,
    String? localPlayerId,
    String? reconnectToken,
  ) {
    if (!room.isStarted) return;
    if (localPlayerId == null) return;
    final player = room.players.where((p) => p.id == localPlayerId).firstOrNull;
    if (player == null) return;
    // This room_update may be a broadcast that carries no token of its own
    // (see RoomUpdated.reconnectToken) — fall back to whatever was already
    // saved, and finally to the token the socket service cached at
    // create/join, rather than overwrite a real token with null.
    final token =
        reconnectToken ??
        ref.read(localPresenceProvider)?.reconnectToken ??
        ref.read(roomSocketServiceProvider).cachedReconnectToken;
    ref
        .read(localPresenceProvider.notifier)
        .save(
          LocalPresenceData(
            playerId: localPlayerId,
            roomCode: room.code,
            displayName: player.displayName,
            status: LocalPresenceStatus.inGame,
            reconnectToken: token,
          ),
        );
    // Player presence always takes precedence over spectator presence (see
    // jumpInAsSpectator's doc comment). A real, freshly-confirmed player
    // seat means any lingering spectator presence is stale — most likely
    // this device spectated a room earlier and is now actually playing in
    // one. Clear it so HomeScreen never has to choose which resume card to
    // show, and so a later jumpInAsSpectator() can't fire against it.
    if (ref.read(localSpectatorPresenceProvider) != null) {
      ref.read(localSpectatorPresenceProvider.notifier).clear();
    }
  }

  /// Mirrors _savePresence's player-side rule exactly: only persist a
  /// spectator seat once the room the spectator is watching is actually
  /// live (a game_state has arrived), never for an unstarted lobby. Called
  /// from GameNotifier when isSpectating is true, since spectators — unlike
  /// players — receive game_state directly and RoomNotifier alone can't see
  /// that a game has started for them without duplicating that plumbing.
  void saveSpectatorPresence(String displayName) {
    final room = state;
    if (room == null || !room.isSpectating) return;
    final spectatorId = room.localSpectatorId;
    if (spectatorId == null) return;
    // spectator_reconnect's own success response carries no reconnectToken
    // of its own (the server only stamps one on the original spectate_room
    // ack — the token has no expiry, so there's nothing to reissue), so
    // service.cachedReconnectToken is null on every device that just
    // resumed from a cold start (a fresh RoomSocketService never had one
    // set). Falling back to it directly — without first checking the
    // seat already persisted — would silently null out a still-good,
    // previously-saved token on the very next game_state, permanently
    // breaking every reconnect after the first. Mirrors _savePresence's
    // (player) identical fallback-order fix for the same reason.
    final token =
        ref.read(localSpectatorPresenceProvider)?.reconnectToken ??
        ref.read(roomSocketServiceProvider).cachedReconnectToken;
    ref
        .read(localSpectatorPresenceProvider.notifier)
        .save(
          LocalSpectatorPresenceData(
            spectatorId: spectatorId,
            roomCode: room.code,
            displayName: displayName,
            reconnectToken: token,
          ),
        );
  }

  // ── Jump In ───────────────────────────────────────────────────────────────

  /// Opens a fresh socket and sends check_presence.
  /// Navigation is handled by the caller (HomeScreen) once roomProvider
  /// becomes non-null.
  void jumpIn() {
    final presence = ref.read(localPresenceProvider);
    if (presence == null) return;
    // Defence-in-depth: a null/empty reconnect token fails check_presence
    // validation server-side and closes the socket. Skip the emit entirely —
    // the caller (HomeScreen._jumpIn) surfaces the "session expired" message
    // and clears the stale seat.
    final token = presence.reconnectToken;
    if (token == null || token.trim().isEmpty) return;
    final service = ref.read(roomSocketServiceProvider);
    // Re-subscribe before opening the new socket so no events are missed.
    // _sub may be null if exitGameToHome() cancelled it, or if the app
    // restarted and build() was never re-triggered.
    _sub?.cancel();
    _sub = service.stream.listen(_onEvent);
    service.reconnect();
    _playerReconnectPending = true;
    debugPrint(
      '[RoomNotifier] check_presence REQUEST '
      'playerId=${presence.playerId} roomCode=${presence.roomCode}',
    );
    service.send('check_presence', {
      'playerId': presence.playerId,
      'roomCode': presence.roomCode,
      'reconnectToken': token,
    });
  }

  /// Spectator equivalent of jumpIn() — opens a fresh socket and sends
  /// spectator_reconnect. Deliberately does NOT touch player presence or
  /// _sub in any way jumpIn() doesn't already: this is the same method,
  /// same defensive checks, same re-subscribe pattern, just for the
  /// separate spectator identity/token pair. Navigation is handled by the
  /// caller once roomProvider becomes non-null, exactly like jumpIn().
  void jumpInAsSpectator() {
    final presence = ref.read(localSpectatorPresenceProvider);
    if (presence == null) return;
    final token = presence.reconnectToken;
    if (token == null || token.trim().isEmpty) return;
    final service = ref.read(roomSocketServiceProvider);
    _sub?.cancel();
    _sub = service.stream.listen(_onEvent);
    service.reconnect();
    // Marks _handleReconnectRejection to clear spectator presence, not
    // player presence, if this attempt fails.
    _spectatorReconnectPending = true;
    debugPrint(
      '[RoomNotifier] spectator_reconnect REQUEST '
      'spectatorId=${presence.spectatorId} roomCode=${presence.roomCode}',
    );
    service.send('spectator_reconnect', {
      'roomCode': presence.roomCode,
      'spectatorId': presence.spectatorId,
      'reconnectToken': token,
    });
  }

  // ── Room actions ──────────────────────────────────────────────────────────

  void createRoom(
    String displayName, {
    List<String> leagues = const [],
    String? leagueBundleId,
    int? turnTimerSeconds,
    int? subsTimerSeconds,

    /// Seconds each player has to use/discard their drafted ability. Null =
    /// server falls back to turnTimerSeconds, then a fixed safety-net default.
    int? abilityTimerSeconds,
    String? formationSlug,
    bool tournamentEnabled = false,

    /// Host-chosen tournament live-event pacing: 'fast' | 'normal' | 'slow'.
    /// Presentation speed only — never changes the simulated result. Absent
    /// or 'normal' preserves the pre-existing pacing as the default.
    String simulationSpeed = 'normal',

    /// Card-rating window for the draft/substitution pool. Null on either end
    /// = no bound there (full range). The server rejects an inverted range
    /// and blocks start if the filter leaves too few players per position.
    int? minRating,
    int? maxRating,

    /// Solo mode: seat this many server-driven AI opponents at creation, so
    /// the room is immediately startable without waiting for a human to join.
    /// Null/0 = a normal room.
    int? botCount,
  }) {
    _resetStaleSession();
    ref.read(roomSocketServiceProvider).send('create_room', {
      'displayName': displayName,
      'botCount': ?botCount,
      // XOR: bundle id OR manual league names — never both with content.
      if (leagueBundleId != null)
        'leagueBundleId': leagueBundleId
      else
        'leagues': leagues,
      'turnTimerSeconds': ?turnTimerSeconds,
      'subsTimerSeconds': ?subsTimerSeconds,
      'abilityTimerSeconds': ?abilityTimerSeconds,
      'formationSlug': ?formationSlug,
      'tournamentEnabled': tournamentEnabled,
      'simulationSpeed': simulationSpeed,
      'minRating': ?minRating,
      'maxRating': ?maxRating,
    });
  }

  void joinRoom(String roomCode, String displayName) {
    _resetStaleSession();
    ref.read(roomSocketServiceProvider).send('join_room', {
      'roomCode': roomCode,
      'displayName': displayName,
    });
  }

  /// Belt-and-suspenders before a brand-new host/join: wipe any leftover
  /// game/room state from a previous session so nothing stale (an ended
  /// game, an abandoned room) can bleed into the new one and trigger a stray
  /// navigation into the old game/result. Presence is intentionally left
  /// alone — the explicit leave/end paths own that, and a legitimately
  /// resumable seat must survive an unrelated create/join.
  void _resetStaleSession() {
    final existing = ref.read(gameProvider);
    if (existing != null) ref.read(gameProvider.notifier).reset();
    state = null;
    ref.invalidate(serverErrorProvider);
  }

  void startGame() => ref.read(roomSocketServiceProvider).send('start_game');

  /// Host adjusts the draft rating window live in the lobby. Null on either
  /// end = no bound (full range). The server re-broadcasts room_update with
  /// the new range + live pool-sufficiency for the current player count.
  void setRatingRange(int? minRating, int? maxRating) =>
      ref.read(roomSocketServiceProvider).send('set_rating_range', {
        'minRating': ?minRating,
        'maxRating': ?maxRating,
      });

  /// Host adds `count` AI opponents to the lobby — works in a normal room
  /// with real players just as well as a solo one; a bot simply takes one
  /// of the seats nobody's joined yet. Same room_update broadcast as every
  /// other lobby action, so the new bot(s) just appear in the player list.
  void addBot(int count) =>
      ref.read(roomSocketServiceProvider).send('add_bot', {'count': count});

  // ── Spectating ────────────────────────────────────────────────────────────
  // First client-side plumbing for the spectator protocol (see
  // MULTIPLAYER_ROOMS_DESIGN.md). Unlike joinRoom, the server accepts
  // spectate_room even after the room has started — watching a live game is
  // the primary real use case, not just an empty lobby.

  void spectateRoom(String roomCode, String displayName) =>
      ref.read(roomSocketServiceProvider).send('spectate_room', {
        'roomCode': roomCode,
        'displayName': displayName,
      });

  /// The server does not ack stop_spectating back to the leaving socket
  /// (only broadcasts the updated room to everyone else still in it — by
  /// the time that broadcast is built, this socket has already been removed
  /// from the room's spectator list), so this clears local spectating state
  /// optimistically. Same pattern leaveLobby() already uses for its own
  /// send-then-clear flow, for the same reason: no response is coming.
  void stopSpectating() {
    final service = ref.read(roomSocketServiceProvider);
    service.send('stop_spectating');
    service.setCachedSpectatorId(null);
    final current = state;
    if (current != null) {
      state = current.clearLocalSpectatorId();
    }
    // Spectating has definitively ended — nothing left to resume.
    ref.read(localSpectatorPresenceProvider.notifier).clear();
  }

  /// Picks a face-down ability card during the `ability_draft` phase.
  void pickAbility(int cardId) => ref.read(roomSocketServiceProvider).send(
    'pick_ability',
    {'cardId': cardId},
  );

  /// Activates the local player's ability with a target (`ability_activation`).
  void activateAbility({
    int? ownSlotIndex,
    String? targetUserId,
    int? targetSlotIndex,
    String? coachedPosition,
    String? targetBenchGroup,
    String? ownBenchGroup,
  }) => ref.read(roomSocketServiceProvider).send('activate_ability', {
    'ownSlotIndex': ?ownSlotIndex,
    'targetUserId': ?targetUserId,
    'targetSlotIndex': ?targetSlotIndex,
    'coachedPosition': ?coachedPosition,
    'targetBenchGroup': ?targetBenchGroup,
    'ownBenchGroup': ?ownBenchGroup,
  });

  /// Discards the local player's ability without using it.
  void discardAbility() =>
      ref.read(roomSocketServiceProvider).send('discard_ability');

  void pickSlot(String turnId, int slotIndex) => ref
      .read(roomSocketServiceProvider)
      .send('pick_slot', {'turnId': turnId, 'slotIndex': slotIndex});

  void pickCard(String turnId, String cardId) => ref
      .read(roomSocketServiceProvider)
      .send('pick_card', {'turnId': turnId, 'cardId': cardId});

  void orderHiddenDeck(String turnId, List<String> orderedCardIds) =>
      ref.read(roomSocketServiceProvider).send('order_hidden_deck', {
        'turnId': turnId,
        'orderedCardIds': orderedCardIds,
      });

  void pickHiddenSlot(String turnId, int slotIndex) => ref
      .read(roomSocketServiceProvider)
      .send('pick_hidden_slot', {'turnId': turnId, 'slotIndex': slotIndex});

  void confirmHiddenReveal(String turnId) => ref
      .read(roomSocketServiceProvider)
      .send('confirm_hidden_reveal', {'turnId': turnId});

  void requestSubSpin(String positionGroup) => ref
      .read(roomSocketServiceProvider)
      .send('request_sub_spin', {'positionGroup': positionGroup});

  void pickSub(String positionGroup, String playerId) => ref
      .read(roomSocketServiceProvider)
      .send('pick_sub', {'positionGroup': positionGroup, 'playerId': playerId});

  void swapSub(String positionGroup, String starterId) =>
      ref.read(roomSocketServiceProvider).send('swap_sub', {
        'positionGroup': positionGroup,
        'starterId': starterId,
      });

  /// Unified "swap any card with any card" during the subs phase. Each endpoint
  /// is either a pitch slot (`{'kind': 'pitch', 'index': i}`) or a bench sub
  /// (`{'kind': 'bench', 'group': 'att'|'mid'|'def'}`). No position restriction —
  /// only the final lineup is validated at confirm time.
  void swapRoster(Map<String, dynamic> a, Map<String, dynamic> b) =>
      ref.read(roomSocketServiceProvider).send('swap_roster', {'a': a, 'b': b});

  void confirmLineup() =>
      ref.read(roomSocketServiceProvider).send('confirm_lineup', {});

  // ── Tournament ────────────────────────────────────────────────────────────

  /// Presses Ready for the local player's current-round tournament match.
  void sendTournamentReady() =>
      ref.read(roomSocketServiceProvider).send('tournament_ready', {});

  // ── Host moderation ───────────────────────────────────────────────────────

  void kickPlayer(String targetPlayerId) => ref
      .read(roomSocketServiceProvider)
      .send('kick_player', {'targetPlayerId': targetPlayerId});

  void transferHost(String targetPlayerId) => ref
      .read(roomSocketServiceProvider)
      .send('transfer_host', {'targetPlayerId': targetPlayerId});

  void lockRoom() => ref.read(roomSocketServiceProvider).send('lock_room');
  void unlockRoom() => ref.read(roomSocketServiceProvider).send('unlock_room');

  void approveJoin(String requestId) => ref
      .read(roomSocketServiceProvider)
      .send('approve_join', {'requestId': requestId});

  void rejectJoin(String requestId) => ref.read(roomSocketServiceProvider).send(
    'reject_join',
    {'requestId': requestId},
  );

  // ── Leave: four distinct cases ────────────────────────────────────────────

  /// Case 1 & 2: Player or host leaves the lobby intentionally.
  /// Permanent removal — no card shown after. Server auto-promotes host.
  void leaveLobby() {
    final service = ref.read(roomSocketServiceProvider);
    service.send('leave_lobby');
    // Clear stale player ID so the next join parses room_update correctly.
    service.setCachedPlayerId('');
    // Reset the error cache so a stale error doesn't appear in JoinRoomScreen.
    ref.invalidate(serverErrorProvider);
    // Socket stays open for the next room action.
    state = null;
    // No presence to clear — lobby presence is never saved.
  }

  /// Case 3 & 4: Player or host leaves the game screen intentionally.
  /// Sends explicit event so server marks them as disconnected but keeps
  /// them in the game session. Presence is kept → card shown on HomeScreen.
  void exitGameToHome() {
    final service = ref.read(roomSocketServiceProvider);
    // Send explicit event while socket is still open. Do NOT close the socket
    // immediately — the message must reach the server before the connection
    // drops, otherwise handleDisconnect fires first and permanently removes
    // the player (lobby path) instead of temporarily disconnecting them.
    service.send('exit_game_to_home');
    // Stop processing incoming events so stale server broadcasts (room_update,
    // game_state to others) don't accidentally update our local state.
    // The socket stays open and drains; it will be closed by reconnect() or
    // dispose(), whichever comes first.
    _sub?.cancel();
    _sub = null;
    // Reset game state so that on rejoin the null→non-null transition fires
    // the LobbyScreen listener that routes to /game.
    ref.read(gameProvider.notifier).reset();
    // Keep presence — card will appear on HomeScreen.
    state = null;
  }

  /// Case 3 & 4 continued: Player chooses "Leave Permanently" from the card.
  /// Fully removes them from the room and game session.
  void leaveGamePermanently() {
    final presence = ref.read(localPresenceProvider);
    final service = ref.read(roomSocketServiceProvider);
    // Open a fresh socket so the server receives the event even after a cold
    // start (no existing connection) or after exitGameToHome (socket idle).
    service.reconnect();
    service.send('leave_game_permanently', {
      if (presence != null) 'playerId': presence.playerId,
      if (presence != null) 'roomCode': presence.roomCode,
    });
    // Re-subscribe so subsequent Host/Join actions receive their room_update.
    // The server sends no response back to the leaving player for this event,
    // so re-subscribing here causes no stale-state risk.
    _sub?.cancel();
    _sub = service.stream.listen(_onEvent);
    ref.read(localPresenceProvider.notifier).clear();
    ref.invalidate(serverErrorProvider);
    state = null;
    // Wipe the finished/abandoned game too — otherwise gameProvider keeps a
    // stale (often `isFinished`) GameState, and the next time any game route
    // builds it immediately navigates to that old game's result screen
    // ("opening the ended game"). Only the result screen's own Back-home
    // button used to do this, so every OTHER exit path leaked it.
    ref.read(gameProvider.notifier).reset();
  }

  /// Case 5: Server has already removed this player (kicked).
  /// No server message needed — just clear local state.
  void clearAfterKick() {
    ref.read(localPresenceProvider.notifier).clear();
    state = null;
    ref.read(gameProvider.notifier).reset();
  }

  /// Case 6: Game ended normally or by forfeit.
  /// Room is already deleted server-side; only local state needs clearing.
  void clearAfterGameEnd() {
    ref.read(localPresenceProvider.notifier).clear();
    ref.invalidate(serverErrorProvider);
    state = null;
    ref.read(gameProvider.notifier).reset();
    // _sub stays active for the next room action.
  }
}

final roomProvider = NotifierProvider<RoomNotifier, RoomState?>(
  RoomNotifier.new,
);

final serverErrorProvider = StreamProvider<ServerError>((ref) {
  return ref
      .watch(roomSocketServiceProvider)
      .stream
      .where((e) => e is ServerError)
      .cast<ServerError>();
});

final socketDisconnectedProvider = StreamProvider<SocketDisconnected>((ref) {
  return ref
      .watch(roomSocketServiceProvider)
      .stream
      .where((e) => e is SocketDisconnected)
      .cast<SocketDisconnected>();
});

final socketReconnectingProvider = StreamProvider<SocketReconnecting>((ref) {
  return ref
      .watch(roomSocketServiceProvider)
      .stream
      .where((e) => e is SocketReconnecting)
      .cast<SocketReconnecting>();
});

final kickedProvider = StreamProvider<Kicked>((ref) {
  return ref
      .watch(roomSocketServiceProvider)
      .stream
      .where((e) => e is Kicked)
      .cast<Kicked>();
});

// ── Connection status ────────────────────────────────────────────────────────
//
// socketReconnectingProvider/socketDisconnectedProvider above are one-shot
// StreamProviders — good for firing a snackbar/dialog once, but nothing a
// widget can `ref.watch()` during build to ask "are we healthy right now".
// This is that: a persistent, watchable status, so screens (the in-game
// action panel in particular) can react to a lost connection declaratively
// instead of only finding out via a one-time side effect.
enum ConnectionStatus { connected, reconnecting, disconnected, sessionInvalid }

class ConnectionStatusNotifier extends Notifier<ConnectionStatus> {
  StreamSubscription<ServerEvent>? _sub;

  @override
  ConnectionStatus build() {
    final service = ref.watch(roomSocketServiceProvider);
    _sub = service.stream.listen((event) {
      if (event is SocketReconnecting) {
        state = ConnectionStatus.reconnecting;
      } else if (event is SocketDisconnected) {
        state = ConnectionStatus.disconnected;
      } else if (event is ServerError &&
          (event.code == 'NOT_FOUND' || event.code == 'INVALID_TOKEN')) {
        // A rejected check_presence/spectator_reconnect is NOT proof of a
        // healthy session — the raw socket may be open, but the server has
        // explicitly rejected this client's identity. Previously this fell
        // into the catch-all "any other event proves we're connected"
        // branch below, which silently flipped connectionStatus back to
        // `connected` and re-enabled every gameplay-action gate keyed off
        // it (see _ActionPanel's `connected: connectionStatus ==
        // ConnectionStatus.connected`) on a session the server had just
        // rejected. RoomNotifier._handleReconnectRejection handles the
        // actual state wipe + recovery UI for this same event; this only
        // needs to stop mis-reporting it as healthy.
        state = ConnectionStatus.sessionInvalid;
      } else if (state != ConnectionStatus.connected) {
        // Any other real event (room_update, game_state, …) is proof this
        // socket is genuinely talking to the server again.
        state = ConnectionStatus.connected;
      }
    });
    ref.onDispose(() => _sub?.cancel());
    return ConnectionStatus.connected;
  }
}

final connectionStatusProvider =
    NotifierProvider<ConnectionStatusNotifier, ConnectionStatus>(
      ConnectionStatusNotifier.new,
    );

final joinPendingProvider = StreamProvider<JoinPending>((ref) {
  return ref
      .watch(roomSocketServiceProvider)
      .stream
      .where((e) => e is JoinPending)
      .cast<JoinPending>();
});

final joinRequestProvider = StreamProvider<JoinRequest>((ref) {
  return ref
      .watch(roomSocketServiceProvider)
      .stream
      .where((e) => e is JoinRequest)
      .cast<JoinRequest>();
});

final joinRejectedProvider = StreamProvider<JoinRejected>((ref) {
  return ref
      .watch(roomSocketServiceProvider)
      .stream
      .where((e) => e is JoinRejected)
      .cast<JoinRejected>();
});

final turnTimerStartedProvider = StreamProvider<TurnTimerStarted>((ref) {
  return ref
      .watch(roomSocketServiceProvider)
      .stream
      .where((e) => e is TurnTimerStarted)
      .cast<TurnTimerStarted>();
});

final turnAutoPickedProvider = StreamProvider<TurnAutoPicked>((ref) {
  return ref
      .watch(roomSocketServiceProvider)
      .stream
      .where((e) => e is TurnAutoPicked)
      .cast<TurnAutoPicked>();
});

final subSpinResultProvider = StreamProvider<SubSpinResult>((ref) {
  return ref
      .watch(roomSocketServiceProvider)
      .stream
      .where((e) => e is SubSpinResult)
      .cast<SubSpinResult>();
});
