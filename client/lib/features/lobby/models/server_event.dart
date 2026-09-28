import 'package:flutter/foundation.dart';
import 'package:hidden_eleven/features/lobby/models/player.dart';
import 'package:hidden_eleven/features/lobby/models/room_state.dart';
import 'package:hidden_eleven/features/lobby/models/spectator.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/models/chemistry_bonus.dart';
import 'package:hidden_eleven/features/game/models/user_chemistry_challenge.dart';
import 'package:hidden_eleven/features/tournament/models/tournament_models.dart';

sealed class ServerEvent {
  const ServerEvent();
}

final class RoomUpdated extends ServerEvent {
  const RoomUpdated(
    this.room,
    this.localPlayerId,
    this.localSpectatorId,
    this.reconnectToken,
  );
  final RoomState room;

  /// Null when this client has no player seat — either a plain room
  /// broadcast that didn't resolve a cached identity, or this socket is
  /// spectating (the server sends `localPlayerId: null` on a spectator's
  /// room_update). Never an empty string — see _parseRoomUpdate.
  final String? localPlayerId;

  /// Non-null once this client has spectate_room'd this room. Resolved the
  /// same way as localPlayerId — the server only stamps the real value on
  /// the ack sent directly to the spectating socket; every other broadcast
  /// carries null, so a cached fallback (see RoomSocketService) is required
  /// for a spectator's own identity to survive subsequent room broadcasts.
  final String? localSpectatorId;

  /// Only present on the response sent to the player it was issued for
  /// (create_room/join_room/approve_join) — null on broadcasts to roommates.
  final String? reconnectToken;
}

final class GameStateReceived extends ServerEvent {
  const GameStateReceived(this.state, this.localPlayerId);
  final GameState state;

  /// Null when this client has no player seat in the session — a
  /// spectator's game_state (the server sends `localPlayerId: null`), or a
  /// broadcast this socket couldn't resolve an identity for. Never an empty
  /// string — mirrors the same fix already applied to RoomUpdated.localPlayerId
  /// in _parseRoomUpdate.
  final String? localPlayerId;
}

// Sent to a player waiting for host approval to join a locked room.
final class JoinPending extends ServerEvent {
  const JoinPending(this.requestId, this.roomCode, this.displayName);
  final String requestId;
  final String roomCode;
  final String displayName;
}

// Sent to the host when someone requests to join a locked room.
final class JoinRequest extends ServerEvent {
  const JoinRequest(this.requestId, this.displayName);
  final String requestId;
  final String displayName;
}

// Sent to the waiting player if the host rejects their request.
final class JoinRejected extends ServerEvent {
  const JoinRejected();
}

// Sent to the kicked player.
final class Kicked extends ServerEvent {
  const Kicked(this.reason);
  final String reason;
}

final class ServerError extends ServerEvent {
  const ServerError(this.code, {this.shortages = const []});
  final String code;

  /// Per-position pool shortfalls that accompany an INSUFFICIENT_DRAFT_POOL
  /// error, so the UI can tell the host exactly which positions are short and
  /// by how much. Empty for every other error.
  final List<PoolShortage> shortages;
}

/// One short position from an INSUFFICIENT_DRAFT_POOL error payload.
final class PoolShortage {
  const PoolShortage({
    required this.position,
    required this.available,
    required this.needed,
  });
  final String position;
  final int available;
  final int needed;

  factory PoolShortage.fromJson(Map<String, dynamic> j) => PoolShortage(
    position: j['position'] as String? ?? '?',
    available: (j['available'] as num?)?.toInt() ?? 0,
    needed: (j['needed'] as num?)?.toInt() ?? 0,
  );
}

final class SlotCandidatesReceived extends ServerEvent {
  const SlotCandidatesReceived(this.turnId, this.candidates);
  final String turnId;
  final List<CandidateCard> candidates;
}

final class SocketDisconnected extends ServerEvent {
  const SocketDisconnected();
}

final class SocketReconnecting extends ServerEvent {
  const SocketReconnecting();
}

// ── Hidden-draft events ───────────────────────────────────────────────────────

/// Sent privately to the first player after they pick their card.
/// Contains the remaining cards they must order.
final class FirstPlayerOrderPromptReceived extends ServerEvent {
  const FirstPlayerOrderPromptReceived(this.turnId, this.cards);
  final String turnId;
  final List<CandidateCard> cards;
}

/// Sent privately to the active hidden picker each time it is their turn.
/// `totalSlots`/`availableSlots` carry no card identity — the slot-to-card
/// mapping itself is never sent to the client.
///
/// `previewCards` is the one deliberate exception: the full set of
/// remaining cards, sorted server-side by `cardId` — NOT by the real slot
/// order (see rooms.gateway.ts's `_previewCardsFor` doc comment). Used only
/// to drive the client's "magician" reveal-conceal-shuffle intro animation
/// before the face-down slots appear; it can never be used to infer which
/// card ended up in which slot.
final class HiddenPickPromptReceived extends ServerEvent {
  const HiddenPickPromptReceived({
    required this.turnId,
    required this.totalSlots,
    required this.availableSlots,
    this.previewCards = const [],
  });
  final String turnId;
  final int totalSlots;
  final List<int> availableSlots;
  final List<CandidateCard> previewCards;
}

/// Sent privately to a player immediately after they pick a hidden slot.
/// Reveals only the card that was assigned to them.
final class CardRevealedReceived extends ServerEvent {
  const CardRevealedReceived(this.card);
  final CandidateCard card;
}

/// Broadcast to all players at the start of each timed decision point.
final class TurnTimerStarted extends ServerEvent {
  const TurnTimerStarted({
    required this.turnId,
    required this.turnDurationSeconds,
    required this.activePlayerId,
    required this.startedAt,
  });
  final String turnId;
  final int turnDurationSeconds;
  final String activePlayerId;

  /// Server wall-clock time when the timer started (used to correct for latency).
  final DateTime startedAt;
}

/// Sent privately to the requesting player after a sub spin.
final class SubSpinResult extends ServerEvent {
  const SubSpinResult({
    required this.positionGroup,
    required this.clubName,
    required this.players,
  });
  final String positionGroup;
  final String clubName;

  /// Full player cards — same structure as draft candidates (image, stats, chemistry).
  final List<CandidateCard> players;
}

/// Broadcast to all players when the server auto-picks because time ran out.
final class TurnAutoPicked extends ServerEvent {
  const TurnAutoPicked({required this.playerId, required this.reason});
  final String playerId;
  final String reason;
}

// ── Tournament events ─────────────────────────────────────────────────────────

/// Full tournament snapshot — the tournament-mode analogue of game_state.
final class TournamentStateReceived extends ServerEvent {
  const TournamentStateReceived(this.state);
  final TournamentStateModel state;
}

/// One live simulation event (goal/card/chance) during the `simulating` phase.
final class TournamentMatchEventReceived extends ServerEvent {
  const TournamentMatchEventReceived(this.event);
  final LiveMatchEvent event;
}

/// Full result of one match, sent once its event stream ends.
final class TournamentMatchResultReceived extends ServerEvent {
  const TournamentMatchResultReceived(this.result);
  final TournamentMatchResult result;
}

/// Final tournament result (champion, awards, points).
final class TournamentCompleteReceived extends ServerEvent {
  const TournamentCompleteReceived(this.awards);
  final TournamentAwardsModel awards;
}

/// Cosmetic notice that a participant was auto-readied (AI, or 60s timeout).
final class TournamentAutoReadyReceived extends ServerEvent {
  const TournamentAutoReadyReceived(this.participantId, this.reason);
  final String participantId;
  final String reason;
}

// ── JSON parsing ─────────────────────────────────────────────────────────────

ServerEvent? parseServerEvent(
  Map<String, dynamic> json,
  String? cachedPlayerId, [
  String? cachedReconnectToken,
  String? cachedSpectatorId,
]) {
  final event = json['event'] as String?;
  final data = json['data'] as Map<String, dynamic>? ?? {};

  return switch (event) {
    'room_update' => _parseRoomUpdate(
      data,
      cachedPlayerId,
      cachedReconnectToken,
      cachedSpectatorId,
    ),
    'game_state' => _parseGameState(data, cachedPlayerId),
    'join_pending' => JoinPending(
      data['requestId'] as String? ?? '',
      data['roomCode'] as String? ?? '',
      data['displayName'] as String? ?? '',
    ),
    'join_request' => JoinRequest(
      data['requestId'] as String? ?? '',
      data['displayName'] as String? ?? '',
    ),
    'slot_candidates' => _parseSlotCandidates(data),
    'first_player_order_prompt' => _parseFirstPlayerOrderPrompt(data),
    'hidden_pick_prompt' => _parseHiddenPickPrompt(data),
    'card_revealed' => _parseCardRevealed(data),
    'turn_timer_start' => _parseTurnTimerStarted(data),
    'turn_auto_picked' => TurnAutoPicked(
      playerId: data['playerId'] as String? ?? '',
      reason: data['reason'] as String? ?? 'timeout',
    ),
    'sub_spin_result' => _parseSubSpinResult(data),
    'tournament_state' => TournamentStateReceived(
      TournamentStateModel.fromJson(data),
    ),
    'tournament_match_event' => TournamentMatchEventReceived(
      LiveMatchEvent.fromJson(data),
    ),
    'tournament_match_result' => TournamentMatchResultReceived(
      TournamentMatchResult.fromJson(data),
    ),
    'tournament_complete' => TournamentCompleteReceived(
      TournamentAwardsModel.fromJson(data),
    ),
    'tournament_auto_ready' => TournamentAutoReadyReceived(
      data['participantId'] as String? ?? '',
      data['reason'] as String? ?? '',
    ),
    'join_rejected' => const JoinRejected(),
    'kicked' => Kicked(data['reason'] as String? ?? 'KICKED_BY_HOST'),
    'error' => ServerError(
      data['code'] as String? ?? 'UNKNOWN',
      shortages: (data['shortages'] as List<dynamic>? ?? [])
          .map((e) => PoolShortage.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
    _ => null,
  };
}

RoomUpdated _parseRoomUpdate(
  Map<String, dynamic> data,
  String? cachedPlayerId, [
  String? cachedReconnectToken,
  String? cachedSpectatorId,
]) {
  final rawPlayers = data['players'] as List<dynamic>? ?? [];
  // Deliberately NO `?? ''` fallback here. A spectator's room_update (and
  // any plain broadcast this client can't resolve an identity for) must
  // stay null — coercing to '' previously risked RoomNotifier caching an
  // empty string as if it were a real player id, corrupting a real player's
  // cached identity on the very next broadcast. See RoomNotifier's
  // RoomUpdated handler, which now guards against caching a null/empty value.
  final String? localPlayerId =
      (data['localPlayerId'] as String?) ?? cachedPlayerId;
  // Same fallback shape as localPlayerId above, and for the same reason: a
  // generic room broadcast (someone else joining/leaving/starting) carries
  // localSpectatorId: null for every recipient, including the spectator
  // themself — without falling back to the cached value, a spectator would
  // appear to instantly stop spectating the moment anyone else did anything.
  final String? localSpectatorId =
      (data['localSpectatorId'] as String?) ?? cachedSpectatorId;
  final reconnectToken =
      data['reconnectToken'] as String? ?? cachedReconnectToken;

  final players = rawPlayers.map((p) {
    final m = p as Map<String, dynamic>;
    return Player(
      id: m['id'] as String,
      displayName: m['displayName'] as String,
      isHost: m['isHost'] as bool,
      isConnected: m['isConnected'] as bool? ?? true,
      isBot: m['isBot'] as bool? ?? false,
    );
  }).toList();

  final rawSpectators = data['spectators'] as List<dynamic>? ?? [];
  final spectators = rawSpectators.map((s) {
    final m = s as Map<String, dynamic>;
    return Spectator(
      id: m['id'] as String,
      displayName: m['displayName'] as String,
      isConnected: m['isConnected'] as bool? ?? true,
    );
  }).toList();

  return RoomUpdated(
    RoomState(
      code: data['code'] as String,
      players: players,
      spectators: spectators,
      isStarted: data['isStarted'] as bool? ?? false,
      isLocked: data['isLocked'] as bool? ?? false,
      pendingCount: data['pendingCount'] as int? ?? 0,
      localPlayerId: localPlayerId,
      localSpectatorId: localSpectatorId,
      tournamentEnabled: data['tournamentEnabled'] as bool? ?? false,
      minRating: (data['minRating'] as num?)?.toInt(),
      maxRating: (data['maxRating'] as num?)?.toInt(),
      poolShortages: (data['poolShortages'] as List<dynamic>? ?? [])
          .map((e) => PoolShortage.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
    localPlayerId,
    localSpectatorId,
    reconnectToken,
  );
}

GameStateReceived _parseGameState(
  Map<String, dynamic> data,
  String? cachedPlayerId,
) {
  // Deliberately NO `?? ''` fallback — see _parseRoomUpdate's identical fix.
  // A spectator's game_state (and any broadcast this client can't resolve an
  // identity for) must stay null, not be coerced into an empty string that
  // downstream code could mistake for a real (if oddly-named) player id.
  final String? localPlayerId =
      (data['localPlayerId'] as String?) ?? cachedPlayerId;

  final players = (data['players'] as List<dynamic>? ?? []).map((p) {
    final m = p as Map<String, dynamic>;
    return GamePlayer(
      id: m['id'] as String,
      displayName: m['displayName'] as String,
      isHost: m['isHost'] as bool,
      isConnected: m['isConnected'] as bool? ?? true,
    );
  }).toList();

  final baseTurnOrder = (data['baseTurnOrder'] as List<dynamic>? ?? [])
      .map((e) => e as String)
      .toList();

  final currentTurnOrder = (data['currentTurnOrder'] as List<dynamic>? ?? [])
      .map((e) => e as String)
      .toList();

  final rawTurn = data['turn'] as Map<String, dynamic>? ?? {};
  final rawStartedAtMs = rawTurn['turnStartedAtMs'] as int?;
  final rawTurnCandidates = rawTurn['candidates'] as List<dynamic>? ?? [];
  final turn = GameTurn(
    turnId: rawTurn['turnId'] as String? ?? '',
    phase: rawTurn['phase'] as String? ?? 'selecting_position',
    activePlayerId: rawTurn['activePlayerId'] as String? ?? '',
    activeSlotIndex: rawTurn['activeSlotIndex'] as int?,
    revealPickerPlayerId: rawTurn['revealPickerPlayerId'] as String?,
    turnStartedAt: rawStartedAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(rawStartedAtMs)
        : null,
    turnDurationSeconds: rawTurn['turnDurationSeconds'] as int?,
    // Durable restore path — see GameTurn.candidates' docstring. Only ever
    // non-empty on the active player's own snapshot; reuses the exact same
    // card-parsing helper _parseSlotCandidates already relies on so both
    // paths produce identical CandidateCard shapes.
    candidates: rawTurnCandidates
        .map((c) => _parseCard(c as Map<String, dynamic>))
        .toList(),
  );

  final rawPitches = data['pitches'] as Map<String, dynamic>? ?? {};
  final pitches = <String, PlayerPitch>{};
  for (final entry in rawPitches.entries) {
    final pMap = entry.value as Map<String, dynamic>;
    final rawSlots = pMap['slots'] as List<dynamic>? ?? [];
    final slots = rawSlots.map((s) {
      final sMap = s as Map<String, dynamic>;
      final rawCard = sMap['card'] as Map<String, dynamic>?;
      return PitchSlot(
        index: sMap['index'] as int? ?? 0,
        label: sMap['label'] as String? ?? '',
        basePositionType: sMap['basePositionType'] as String? ?? '',
        cardPlayerName: rawCard?['playerName'] as String?,
        cardRating: rawCard == null ? null : _asInt(rawCard['rating']),
        cardId: rawCard?['cardId'] as String?,
        cardImageUrl: rawCard?['imageUrl'] as String?,
        cardClub: rawCard?['club'] as String?,
        cardClubLogoUrl: rawCard?['clubLogoUrl'] as String?,
        cardPrimaryColor: rawCard?['primaryColor'] as String?,
        cardSecondaryColor: rawCard?['secondaryColor'] as String?,
        cardTertiaryColor: rawCard?['tertiaryColor'] as String?,
        cardKitPattern: rawCard?['kitPattern'] as String?,
        cardStyle: rawCard?['cardStyle'] as String?,
        cardKitNumber: (rawCard?['kitNumber'] as num?)?.toInt(),
        cardNationality: rawCard?['nationality'] as String?,
        cardAltPositions: rawCard == null
            ? const []
            : (rawCard['altPositions'] as List<dynamic>? ?? [])
                  .map((e) => e as String)
                  .toList(),
        cardNaturalPositions: rawCard == null
            ? const []
            : (rawCard['naturalPositions'] as List<dynamic>? ?? [])
                  .map((e) => e as String)
                  .toList(),
        cardPace: rawCard == null ? 0 : _asInt(rawCard['pace']),
        cardShooting: rawCard == null ? 0 : _asInt(rawCard['shooting']),
        cardPassing: rawCard == null ? 0 : _asInt(rawCard['passing']),
        cardDribbling: rawCard == null ? 0 : _asInt(rawCard['dribbling']),
        cardDefending: rawCard == null ? 0 : _asInt(rawCard['defending']),
        cardPhysical: rawCard == null ? 0 : _asInt(rawCard['physical']),
        cardLeague: rawCard?['league'] as String?,
        cardChemistryBonuses: rawCard == null
            ? const []
            : _parseChemistryBonuses(rawCard['chemistryBonuses']),
        isCaptain: sMap['captain'] as bool? ?? false,
        isRedCarded: sMap['redCarded'] as bool? ?? false,
        isSubSwapped: sMap['subSwapped'] as bool? ?? false,
        isCoached: sMap['coached'] as bool? ?? false,
      );
    }).toList();
    pitches[entry.key] = PlayerPitch(
      playerId: entry.key,
      slots: slots,
      filledCount: pMap['filledCount'] as int? ?? 0,
    );
  }

  GameResult? result;
  final rawResult = data['result'] as Map<String, dynamic>?;
  if (rawResult != null) {
    final rawResultPlayers = rawResult['players'] as List<dynamic>? ?? [];
    result = GameResult(
      reason: rawResult['reason'] as String? ?? 'completed',
      players: rawResultPlayers.map((p) {
        final m = p as Map<String, dynamic>;
        return PlayerResult(
          playerId: m['playerId'] as String? ?? '',
          displayName: m['displayName'] as String? ?? '',
          rank: m['rank'] as int? ?? 0,
          score: m['score'] as int?,
          scoreBreakdown: _parseScoreBreakdown(m['scoreBreakdown']),
        );
      }).toList(),
    );
  }

  final formationName =
      (data['formation'] as Map<String, dynamic>?)?['name'] as String? ?? '';

  return GameStateReceived(
    GameState(
      sessionId: data['sessionId'] as String? ?? '',
      roomCode: data['roomCode'] as String? ?? '',
      formationName: formationName,
      players: players,
      pitches: pitches,
      baseTurnOrder: baseTurnOrder,
      currentRound: data['currentRound'] as int? ?? 1,
      totalRounds: data['totalRounds'] as int? ?? 11,
      currentTurnOrder: currentTurnOrder,
      currentTurnIndex: data['currentTurnIndex'] as int? ?? 0,
      currentRoundSlotIndex: data['currentRoundSlotIndex'] as int?,
      turn: turn,
      status: data['status'] as String? ?? 'drafting',
      isFinished: data['isFinished'] as bool? ?? false,
      subsPhase: _parseSubsPhase(data['subsPhase']),
      subsTimerSeconds: data['subsTimerSeconds'] as int?,
      subsDeadlineAtMs: (data['subsDeadlineAt'] as num?)?.toInt(),
      hiddenDeckSize: data['hiddenDeckSize'] as int? ?? 0,
      hiddenSlotsTaken: (data['hiddenSlotsTaken'] as List<dynamic>? ?? [])
          .map((e) => e as int)
          .toList(),
      hiddenSlots: _parseHiddenSlots(data['hiddenSlots']),
      lastRoundLeftovers: (data['lastRoundLeftovers'] as List<dynamic>? ?? [])
          .map((e) => _parseCard(e as Map<String, dynamic>))
          .toList(),
      result: result,
      scoringPreview: _parseScoringPreview(data['scoringPreview']),
      abilityDraft: _parseAbilityDraft(data['abilityDraft']),
      myAbility: _parsePlayerAbility(data['myAbility']),
      abilityActivations: _parseAbilityActivations(data['abilityActivations']),
      abilityActivationResolved: _parseActivationResolved(
        data['abilityActivation'],
      ),
      abilityActivationRevealed:
          data['abilityActivationRevealed'] as bool? ?? false,
      yellowPenalties: _parseYellowPenalties(data['yellowPenalties']),
      subSwappedCardIds: (data['subSwappedCardIds'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toSet(),
    ),
    localPlayerId,
  );
}

Map<String, int> _parseYellowPenalties(dynamic raw) {
  if (raw is! Map<String, dynamic>) return const {};
  return raw.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
}

List<AbilityActivation> _parseAbilityActivations(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .map((e) {
        final m = e as Map<String, dynamic>;
        final type = abilityTypeFromString(m['type'] as String?);
        if (type == null) return null;
        return AbilityActivation(
          byPlayerId: m['byPlayerId'] as String? ?? '',
          byName: m['byName'] as String? ?? '',
          type: type,
          summary: m['summary'] as String? ?? '',
          targetUserId: m['targetUserId'] as String?,
          targetSlotIndex: m['targetSlotIndex'] as int?,
        );
      })
      .whereType<AbilityActivation>()
      .toList();
}

Map<String, bool>? _parseActivationResolved(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  final resolved = raw['resolved'] as Map<String, dynamic>? ?? {};
  return resolved.map((k, v) => MapEntry(k, v == true));
}

AbilityDraftState? _parseAbilityDraft(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  final rawCards = raw['cards'] as List<dynamic>? ?? [];
  return AbilityDraftState(
    poolCount: raw['poolCount'] as int? ?? 0,
    pickOrder: (raw['pickOrder'] as List<dynamic>? ?? [])
        .map((e) => e as String)
        .toList(),
    currentPickIndex: raw['currentPickIndex'] as int? ?? 0,
    currentPickerId: raw['currentPickerId'] as String?,
    cards: rawCards.map((c) {
      final m = c as Map<String, dynamic>;
      return AbilityCardInfo(
        id: m['id'] as int? ?? 0,
        pickedBy: m['pickedBy'] as String?,
        type: abilityTypeFromString(m['type'] as String?),
      );
    }).toList(),
  );
}

PlayerAbility? _parsePlayerAbility(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  final type = abilityTypeFromString(raw['type'] as String?);
  if (type == null) return null;
  return PlayerAbility(
    type: type,
    status: raw['status'] as String? ?? 'pending',
    pendingSummary: raw['pendingSummary'] as String?,
  );
}

List<ChemistryBonus> _parseChemistryBonuses(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((e) {
    final m = e as Map<String, dynamic>;
    return ChemistryBonus.fromJson(m);
  }).toList();
}

// Numeric fields go through `_asInt` (num → int) rather than a direct
// `as int?` cast. A direct cast throws a TypeError the instant the server
// ever sends one of these as a JSON float (e.g. an averaged/derived rating
// arriving as `85.0` instead of `85` — jsonDecode gives Dart a double for
// that, not an int) — and because this whole record is built inline inside
// a `.map()` over the raw player list (see _parseSubSpinResult), a single
// bad field on ONE player throws for the entire batch, discarding every
// other player in the same response. This is the fix for exactly that class
// of crash (reported as "Invalid argument: 240" right after a sub-spin
// event) — every numeric field here now safely coerces instead of casting.
int _asInt(dynamic v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;

CandidateCard _parseCard(Map<String, dynamic> m) => CandidateCard(
  cardId: m['cardId'] as String? ?? '',
  playerName: m['playerName'] as String? ?? '',
  basePositionType: m['basePositionType'] as String? ?? '',
  rating: _asInt(m['rating']),
  nationality: m['nationality'] as String?,
  club: m['club'] as String?,
  clubLogoUrl: m['clubLogoUrl'] as String?,
  primaryColor: m['primaryColor'] as String?,
  secondaryColor: m['secondaryColor'] as String?,
  tertiaryColor: m['tertiaryColor'] as String?,
  kitPattern: m['kitPattern'] as String?,
  cardStyle: m['cardStyle'] as String?,
  kitNumber: (m['kitNumber'] as num?)?.toInt(),
  altPositions: (m['altPositions'] as List<dynamic>? ?? [])
      .map((e) => e as String)
      .toList(),
  naturalPositions: (m['naturalPositions'] as List<dynamic>? ?? [])
      .map((e) => e as String)
      .toList(),
  imageUrl: m['imageUrl'] as String?,
  pace: _asInt(m['pace']),
  shooting: _asInt(m['shooting']),
  passing: _asInt(m['passing']),
  dribbling: _asInt(m['dribbling']),
  defending: _asInt(m['defending']),
  physical: _asInt(m['physical']),
  league: m['league'] as String?,
  chemistryBonuses: _parseChemistryBonuses(m['chemistryBonuses']),
);

/// A visibly-placeholder card used when one player record in a batch (e.g. a
/// sub-spin's candidate list) fails to parse — see _parseSubSpinResult. Kept
/// distinguishable (name says so plainly) rather than silently rendering a
/// blank/zeroed card that looks like real, pickable data.
CandidateCard _malformedCardPlaceholder(String cardId) => CandidateCard(
  cardId: cardId,
  playerName: 'Unavailable player',
  basePositionType: '',
  rating: 0,
);

ScoringPreview? _parseScoringPreview(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  final rawChallenges = raw['userChallenges'] as List<dynamic>? ?? [];
  return ScoringPreview(
    defAvg: raw['defAvg'] as int? ?? 0,
    midAvg: raw['midAvg'] as int? ?? 0,
    atkAvg: raw['atkAvg'] as int? ?? 0,
    linesTotal: (raw['linesTotal'] as num? ?? 0).toInt(),
    userChallenges: rawChallenges
        .map((e) => UserChemistryChallenge.fromJson(e as Map<String, dynamic>))
        .toList(),
    userChemTotal: raw['userChemTotal'] as int? ?? 0,
    cardChemTotal: raw['cardChemTotal'] as int? ?? 0,
    lineLeaderBonus: raw['lineLeaderBonus'] as int? ?? 0,
    estimatedScore: (raw['estimatedScore'] as num? ?? 0).toDouble(),
  );
}

ScoreBreakdown? _parseScoreBreakdown(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  return ScoreBreakdown(
    defAvg: raw['defAvg'] as int? ?? 0,
    midAvg: raw['midAvg'] as int? ?? 0,
    atkAvg: raw['atkAvg'] as int? ?? 0,
    linesTotal: (raw['linesTotal'] as num? ?? 0).toInt(),
    userChemTotal: raw['userChemTotal'] as int? ?? 0,
    cardChemTotal: raw['cardChemTotal'] as int? ?? 0,
    lineLeaderBonus: raw['lineLeaderBonus'] as int? ?? 0,
    captainBonus: raw['captainBonus'] as int? ?? 0,
    yellowPenalty: raw['yellowPenalty'] as int? ?? 0,
    redApplied: raw['redApplied'] as bool? ?? false,
    finalScore: (raw['finalScore'] as num? ?? 0).toDouble(),
    scoringConfigVersion: (raw['scoringConfigVersion'] as num?)?.toInt() ?? 0,
    lines: _parseScoreBreakdownLines(raw['lines']),
  );
}

List<ScoreBreakdownLine> _parseScoreBreakdownLines(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .map((e) {
        if (e is! Map<String, dynamic>) return null;
        final key = e['key'] as String?;
        final label = e['label'] as String?;
        final amount = e['amount'] as num?;
        if (key == null || label == null || amount == null) return null;
        return ScoreBreakdownLine(
          key: key,
          label: label,
          amount: amount.toInt(),
          detail: e['detail'] as String?,
        );
      })
      .whereType<ScoreBreakdownLine>()
      .toList();
}

List<HiddenSlotInfo> _parseHiddenSlots(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((s) {
    final m = s as Map<String, dynamic>;
    final rawCard = m['card'] as Map<String, dynamic>?;
    return HiddenSlotInfo(
      slotIndex: m['slotIndex'] as int? ?? 0,
      pickedByPlayerName: m['pickedByPlayerName'] as String?,
      card: rawCard == null ? null : _parseCard(rawCard),
    );
  }).toList();
}

SlotCandidatesReceived _parseSlotCandidates(Map<String, dynamic> data) {
  final turnId = data['turnId'] as String? ?? '';
  final rawCandidates = data['candidates'] as List<dynamic>? ?? [];
  final candidates = rawCandidates
      .map((c) => _parseCard(c as Map<String, dynamic>))
      .toList();
  return SlotCandidatesReceived(turnId, candidates);
}

FirstPlayerOrderPromptReceived _parseFirstPlayerOrderPrompt(
  Map<String, dynamic> data,
) {
  final turnId = data['turnId'] as String? ?? '';
  final rawCards = data['cards'] as List<dynamic>? ?? [];
  final cards = rawCards
      .map((c) => _parseCard(c as Map<String, dynamic>))
      .toList();
  return FirstPlayerOrderPromptReceived(turnId, cards);
}

HiddenPickPromptReceived _parseHiddenPickPrompt(Map<String, dynamic> data) {
  return HiddenPickPromptReceived(
    turnId: data['turnId'] as String? ?? '',
    totalSlots: data['totalSlots'] as int? ?? 0,
    availableSlots: (data['availableSlots'] as List<dynamic>? ?? [])
        .map((e) => e as int)
        .toList(),
    previewCards: (data['previewCards'] as List<dynamic>? ?? [])
        .map((c) => _parseCard(c as Map<String, dynamic>))
        .toList(),
  );
}

CardRevealedReceived _parseCardRevealed(Map<String, dynamic> data) {
  final m = data['card'] as Map<String, dynamic>? ?? {};
  return CardRevealedReceived(_parseCard(m));
}

TurnTimerStarted _parseTurnTimerStarted(Map<String, dynamic> data) {
  final startedAtMs =
      data['startedAtMs'] as int? ?? DateTime.now().millisecondsSinceEpoch;
  return TurnTimerStarted(
    turnId: data['turnId'] as String? ?? '',
    turnDurationSeconds: data['turnDurationSeconds'] as int? ?? 30,
    activePlayerId: data['activePlayerId'] as String? ?? '',
    startedAt: DateTime.fromMillisecondsSinceEpoch(startedAtMs),
  );
}

SubSpinResult _parseSubSpinResult(Map<String, dynamic> data) {
  final rawPlayers = data['players'] as List<dynamic>? ?? [];
  debugPrint(
    '[SubSpin] event received: club=${data['clubName']}, '
    'positionGroup=${data['positionGroup']}, players=${rawPlayers.length}',
  );

  final players = <CandidateCard>[];
  for (var i = 0; i < rawPlayers.length; i++) {
    // Each player is parsed in its own try/catch — one malformed record
    // (e.g. a numeric field arriving as an unexpected type/shape) must not
    // discard the entire batch. Previously this ran inline inside a single
    // `.map().toList()` with no isolation, so any one bad player card threw
    // for all of them, and the whole club-roulette flow died right after
    // logging the line above — the exact "picked one sub, the rest vanish"
    // symptom this fixes.
    try {
      final m = rawPlayers[i] as Map<String, dynamic>;
      debugPrint(
        '[SubSpin] player[$i] raw: id=${m['id']} name=${m['name']} '
        'rating=${m['rating']} (${m['rating'].runtimeType}) '
        'pace=${m['pace']} shooting=${m['shooting']} passing=${m['passing']} '
        'dribbling=${m['dribbling']} defending=${m['defending']} '
        'physical=${m['physical']}',
      );
      // Remap server field names → CandidateCard field names
      players.add(
        _parseCard({
          'cardId': m['id'] ?? '',
          'playerName': m['name'] ?? '',
          'basePositionType': m['position'] ?? '',
          'rating': m['rating'] ?? 0,
          'imageUrl': m['imageUrl'],
          'club': m['club'],
          'clubLogoUrl': m['clubLogoUrl'],
          'primaryColor': m['primaryColor'],
          'secondaryColor': m['secondaryColor'],
          'tertiaryColor': m['tertiaryColor'],
          'kitPattern': m['kitPattern'],
          'kitNumber': m['kitNumber'],
          'nationality': m['nationality'],
          'altPositions': m['altPositions'] ?? [],
          'pace': m['pace'] ?? 0,
          'shooting': m['shooting'] ?? 0,
          'passing': m['passing'] ?? 0,
          'dribbling': m['dribbling'] ?? 0,
          'defending': m['defending'] ?? 0,
          'physical': m['physical'] ?? 0,
          'chemistryBonuses': m['chemistryBonuses'] ?? [],
        }),
      );
    } catch (e, st) {
      debugPrint(
        '[SubSpin] player[$i] failed to parse — using placeholder. '
        'error=$e\n$st',
      );
      players.add(_malformedCardPlaceholder('malformed-$i'));
    }
  }

  return SubSpinResult(
    positionGroup: data['positionGroup'] as String? ?? '',
    clubName: data['clubName'] as String? ?? '',
    players: players,
  );
}

SubsPhase? _parseSubsPhase(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  final rawUserSubs = raw['userSubs'] as Map<String, dynamic>? ?? {};
  final userSubs = <String, UserSubstitutions>{};
  for (final entry in rawUserSubs.entries) {
    final m = entry.value as Map<String, dynamic>? ?? {};
    userSubs[entry.key] = UserSubstitutions(
      isComplete: m['isComplete'] as bool? ?? false,
      lineupConfirmed: m['lineupConfirmed'] as bool? ?? false,
      hasExtraBench: m['hasExtraBench'] as bool? ?? false,
      att: _parseSubSlot(m['att'], 'att'),
      mid: _parseSubSlot(m['mid'], 'mid'),
      def: _parseSubSlot(m['def'], 'def'),
      extra: _parseSubSlot(m['extra'], 'extra'),
    );
  }
  return SubsPhase(userSubs: userSubs);
}

SubSlot? _parseSubSlot(dynamic raw, String group) {
  if (raw is! Map<String, dynamic>) return null;
  return SubSlot(
    positionGroup: raw['positionGroup'] as String? ?? group,
    spinResultClub: raw['spinResultClub'] as String?,
    chosenPlayerId: raw['chosenPlayerId'] as String?,
    chosenPlayerName: raw['chosenPlayerName'] as String?,
    chosenPlayerRating: raw['chosenPlayerRating'] as int?,
    chosenPlayerPosition: raw['chosenPlayerPosition'] as String?,
    swappedSlotIndex: raw['swappedSlotIndex'] as int?,
    benchedPlayerId: raw['benchedPlayerId'] as String?,
    benchedPlayerName: raw['benchedPlayerName'] as String?,
    benchedPlayerRating: raw['benchedPlayerRating'] as int?,
    benchedPlayerPosition: raw['benchedPlayerPosition'] as String?,
    benchedImageUrl: raw['benchedImageUrl'] as String?,
    benchedClub: raw['benchedClub'] as String?,
    benchedClubLogoUrl: raw['benchedClubLogoUrl'] as String?,
    benchedPrimaryColor: raw['benchedPrimaryColor'] as String?,
    benchedSecondaryColor: raw['benchedSecondaryColor'] as String?,
    benchedTertiaryColor: raw['benchedTertiaryColor'] as String?,
    benchedKitPattern: raw['benchedKitPattern'] as String?,
    benchedCardStyle: raw['benchedCardStyle'] as String?,
    benchedKitNumber: (raw['benchedKitNumber'] as num?)?.toInt(),
    benchedNationality: raw['benchedNationality'] as String?,
    benchedPace: raw['benchedPace'] as int?,
    benchedShooting: raw['benchedShooting'] as int?,
    benchedPassing: raw['benchedPassing'] as int?,
    benchedDribbling: raw['benchedDribbling'] as int?,
    benchedDefending: raw['benchedDefending'] as int?,
    benchedPhysical: raw['benchedPhysical'] as int?,
    benchedAltPositions:
        (raw['benchedAltPositions'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [],
    benchedNaturalPositions:
        (raw['benchedNaturalPositions'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [],
    benchedChemistryBonuses: _parseChemistryBonuses(
      raw['benchedChemistryBonuses'],
    ),
    benchHoldsStarter: raw['benchHoldsStarter'] as bool? ?? false,
    benchedCaptain: raw['benchedCaptain'] as bool? ?? false,
    benchedRedCarded: raw['benchedRedCarded'] as bool? ?? false,
    benchedCoached: raw['benchedCoached'] as bool? ?? false,
  );
}
