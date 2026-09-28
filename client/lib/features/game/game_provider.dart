import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/features/lobby/room_socket_service.dart';
import 'package:hidden_eleven/features/tournament/models/tournament_models.dart';
import 'package:hidden_eleven/features/tournament/providers/tournament_provider.dart';
import 'package:hidden_eleven/services/local_presence_service.dart';
import 'package:hidden_eleven/shared/providers/local_presence_provider.dart';

export 'package:hidden_eleven/features/lobby/models/server_event.dart'
    show TurnTimerStarted, TurnAutoPicked;

// ── Local player identity ─────────────────────────────────────────────────────
// Client-only context — not part of the shared GameState model.

class _LocalPlayerIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}

final localPlayerIdProvider = NotifierProvider<_LocalPlayerIdNotifier, String?>(
  _LocalPlayerIdNotifier.new,
);

// ── Derived: is it the local player's turn? ───────────────────────────────────

final isLocalPlayerTurnProvider = Provider<bool>((ref) {
  final game = ref.watch(gameProvider);
  final localId = ref.watch(localPlayerIdProvider);
  if (game == null || localId == null) return false;
  return game.turn.activePlayerId == localId;
});

// ── Game state notifier ───────────────────────────────────────────────────────

class GameNotifier extends Notifier<GameState?> {
  StreamSubscription<ServerEvent>? _sub;

  @override
  GameState? build() {
    final service = ref.watch(roomSocketServiceProvider);
    _sub = service.stream.listen(_onEvent);
    ref.onDispose(() => _sub?.cancel());
    return null;
  }

  void _onEvent(ServerEvent event) {
    if (event is GameStateReceived) {
      ref.read(localPlayerIdProvider.notifier).set(event.localPlayerId);
      state = event.state;
      _savePresence(event.state, event.localPlayerId);
      _saveSpectatorPresenceIfWatching();
    } else if (event is TournamentStateReceived) {
      _onTournamentState(event.state);
    } else if (event is TournamentMatchEventReceived) {
      final live = event.event;
      final current = Map<String, List<LiveMatchEvent>>.from(
        ref.read(liveMatchEventsProvider),
      );
      current[live.matchId] = [...(current[live.matchId] ?? []), live];
      ref.read(liveMatchEventsProvider.notifier).state = current;
    } else if (event is TournamentMatchResultReceived) {
      final result = event.result;
      final current = Map<String, TournamentMatchResult>.from(
        ref.read(completedMatchResultsProvider),
      );
      current[result.matchId] = result;
      ref.read(completedMatchResultsProvider.notifier).state = current;
    } else if (event is TournamentCompleteReceived) {
      ref.read(tournamentCompleteProvider.notifier).state = event.awards;
    }
    // tournament_auto_ready is surfaced via tournamentAutoReadyProvider
    // (a StreamProvider a Phase 3B widget listens to for the toast).
  }

  void _onTournamentState(TournamentStateModel model) {
    ref.read(tournamentStateProvider.notifier).state = model;
    // Resolve this player's participantId once, the first time we can match it.
    if (ref.read(myParticipantIdProvider) == null) {
      final myId = ref.read(localPlayerIdProvider);
      if (myId != null) {
        for (final round in model.rounds) {
          for (final match in round.matches) {
            for (final p in [match.participantA, match.participantB]) {
              if (p.kind == TournamentParticipantKind.real &&
                  p.participantId == myId) {
                ref.read(myParticipantIdProvider.notifier).state =
                    p.participantId;
                return;
              }
            }
          }
        }
      }
    }
  }

  // Saves in-game presence so the rejoin card appears on HomeScreen after
  // exiting or after a cold start. Called on every game_state event so that
  // the very first delivery (on game start or reconnect) is captured.
  void _savePresence(GameState game, String? localPlayerId) {
    // No player seat to persist presence for — a spectator's game_state, or
    // a broadcast this socket couldn't resolve an identity for.
    if (localPlayerId == null || localPlayerId.isEmpty) return;
    final player = game.players.where((p) => p.id == localPlayerId).firstOrNull;
    if (player == null) return;
    // game_state carries no reconnectToken of its own (only room_update does,
    // at create_room/join_room/approve_join time) — this fires on every
    // game_state event, so it must carry the previously-saved token forward
    // rather than overwrite it with null. On the FIRST game_state (game start),
    // no presence has been persisted yet (lobby presence is never saved), so
    // fall back to the token the socket service cached at create/join. Without
    // this the seat is persisted with a null token and check_presence fails on
    // rejoin after a browser refresh.
    final existingToken =
        ref.read(localPresenceProvider)?.reconnectToken ??
        ref.read(roomSocketServiceProvider).cachedReconnectToken;
    ref
        .read(localPresenceProvider.notifier)
        .save(
          LocalPresenceData(
            playerId: localPlayerId,
            roomCode: game.roomCode,
            displayName: player.displayName,
            status: LocalPresenceStatus.inGame,
            reconnectToken: existingToken,
          ),
        );
  }

  // Mirrors _savePresence's own rule — only persist a spectator seat once
  // there is an actual live game to resume, i.e. a game_state has arrived —
  // by only ever being called from the GameStateReceived branch above. A
  // spectator watching an unstarted lobby never reaches this method.
  void _saveSpectatorPresenceIfWatching() {
    final room = ref.read(roomProvider);
    if (room == null || !room.isSpectating) return;
    final spectatorId = room.localSpectatorId;
    final me = room.spectators.where((s) => s.id == spectatorId).firstOrNull;
    if (me == null) return;
    ref.read(roomProvider.notifier).saveSpectatorPresence(me.displayName);
  }

  void reset() {
    ref.read(localPlayerIdProvider.notifier).set(null);
    // Tournament providers are session-scoped StateProviders — clear them here
    // too so a subsequent (possibly non-tournament) game never inherits the
    // previous tournament's bracket/awards/live state.
    ref.read(tournamentStateProvider.notifier).state = null;
    ref.read(tournamentCompleteProvider.notifier).state = null;
    ref.read(liveMatchEventsProvider.notifier).state = {};
    ref.read(completedMatchResultsProvider.notifier).state = {};
    ref.read(myParticipantIdProvider.notifier).state = null;
    state = null;
  }
}

final gameProvider = NotifierProvider<GameNotifier, GameState?>(
  GameNotifier.new,
);

// ── Slot candidates ───────────────────────────────────────────────────────────
// Received only by the active player after a successful pick_slot.
// Cleared automatically when the turnId changes in the next game_state.

class SlotCandidatesNotifier extends Notifier<SlotCandidatesData?> {
  StreamSubscription<ServerEvent>? _sub;

  @override
  SlotCandidatesData? build() {
    final service = ref.watch(roomSocketServiceProvider);
    _sub?.cancel();
    _sub = service.stream.listen(_onEvent);
    ref.onDispose(() => _sub?.cancel());

    // Seed from durable game state so a reconnect mid selecting_card (or any
    // rebuild of this notifier while a game is already loaded) doesn't wait
    // on an event that will never come again — see GameTurn.candidates'
    // docstring for why the live slot_candidates event alone isn't enough.
    return _fromGameTurn(ref.read(gameProvider)?.turn);
  }

  SlotCandidatesData? _fromGameTurn(GameTurn? turn) {
    if (turn == null ||
        turn.phase != 'selecting_card' ||
        turn.candidates.isEmpty) {
      return null;
    }
    return SlotCandidatesData(turnId: turn.turnId, candidates: turn.candidates);
  }

  void _onEvent(ServerEvent event) {
    switch (event) {
      case SlotCandidatesReceived():
        debugPrint(
          '[slot_candidates] received turnId=${event.turnId} '
          'cards=${event.candidates.map((c) => '${c.playerName}(${c.rating})').join(', ')}',
        );
        state = SlotCandidatesData(
          turnId: event.turnId,
          candidates: event.candidates,
        );
        debugPrint('[slot_candidates] slotCandidatesProvider updated');

      case GameStateReceived():
        final turn = event.state.turn;
        // Clear when the turn has moved on (different or empty turnId).
        if (state != null && state!.turnId != turn.turnId) {
          state = null;
        }
        // Restore from durable state whenever local state is missing for the
        // current selecting_card turn — the only path a refresh/reconnect
        // has, since the live slot_candidates ack already came and went
        // before this client existed.
        if (state == null) {
          final restored = _fromGameTurn(turn);
          if (restored != null) state = restored;
        }

      default:
        break;
    }
  }
}

final slotCandidatesProvider =
    NotifierProvider<SlotCandidatesNotifier, SlotCandidatesData?>(
      SlotCandidatesNotifier.new,
    );

// ── First-player order prompt ─────────────────────────────────────────────────
// Received only by the first player after they pick their card.
// Contains the remaining cards they must order before other players can pick.

@immutable
class FirstPlayerOrderData {
  const FirstPlayerOrderData({required this.turnId, required this.cards});
  final String turnId;
  final List<CandidateCard> cards;
}

class _FirstPlayerOrderNotifier extends Notifier<FirstPlayerOrderData?> {
  StreamSubscription<ServerEvent>? _sub;

  @override
  FirstPlayerOrderData? build() {
    final service = ref.watch(roomSocketServiceProvider);
    _sub?.cancel();
    _sub = service.stream.listen(_onEvent);
    ref.onDispose(() => _sub?.cancel());
    return null;
  }

  void _onEvent(ServerEvent event) {
    switch (event) {
      case FirstPlayerOrderPromptReceived():
        state = FirstPlayerOrderData(turnId: event.turnId, cards: event.cards);
      case GameStateReceived():
        // Clear when we move away from first_player_order phase
        if (state != null && event.state.turn.phase != 'first_player_order') {
          state = null;
        }
      default:
        break;
    }
  }
}

final firstPlayerOrderProvider =
    NotifierProvider<_FirstPlayerOrderNotifier, FirstPlayerOrderData?>(
      _FirstPlayerOrderNotifier.new,
    );

// ── Hidden pick prompt ────────────────────────────────────────────────────────
// Received only by the active hidden picker.
// totalSlots/availableSlots carry no card identity — see previewCards' own
// doc comment for the one deliberate exception.

@immutable
class HiddenPickData {
  const HiddenPickData({
    required this.turnId,
    required this.totalSlots,
    required this.availableSlots,
    this.previewCards = const [],
  });
  final String turnId;
  final int totalSlots;
  final List<int> availableSlots;

  /// The remaining hidden-deck cards, server-sorted by cardId — NOT by the
  /// real slot order — so this can drive the "magician" intro animation's
  /// face-up preview without ever exposing which card is in which slot.
  /// See HiddenPickPromptReceived's doc comment for the full explanation.
  final List<CandidateCard> previewCards;
}

class _HiddenPickNotifier extends Notifier<HiddenPickData?> {
  StreamSubscription<ServerEvent>? _sub;

  @override
  HiddenPickData? build() {
    final service = ref.watch(roomSocketServiceProvider);
    _sub?.cancel();
    _sub = service.stream.listen(_onEvent);
    ref.onDispose(() => _sub?.cancel());
    return null;
  }

  void _onEvent(ServerEvent event) {
    switch (event) {
      case HiddenPickPromptReceived():
        state = HiddenPickData(
          turnId: event.turnId,
          totalSlots: event.totalSlots,
          availableSlots: event.availableSlots,
          previewCards: event.previewCards,
        );
      case GameStateReceived():
        // Clear when the active player changes or we leave hidden_pick
        if (state != null) {
          final phase = event.state.turn.phase;
          if (phase != 'hidden_pick' ||
              state!.turnId != event.state.turn.turnId) {
            state = null;
          }
        }
      default:
        break;
    }
  }
}

final hiddenPickProvider =
    NotifierProvider<_HiddenPickNotifier, HiddenPickData?>(
      _HiddenPickNotifier.new,
    );

// ── Revealed card ─────────────────────────────────────────────────────────────
// Set when the server sends card_revealed after a hidden pick.
// Cleared by the UI after the flip animation completes.

class _RevealedCardNotifier extends Notifier<CandidateCard?> {
  StreamSubscription<ServerEvent>? _sub;

  /// The turnId that was active when the current reveal was shown. Used to
  /// detect a reveal that's gone stale (the round moved on without anyone
  /// dismissing it) so it can be cleared automatically — see [_onEvent]'s
  /// `GameStateReceived` case. `null` whenever [state] is `null`.
  String? _revealedTurnId;

  @override
  CandidateCard? build() {
    final service = ref.watch(roomSocketServiceProvider);
    _sub?.cancel();
    _sub = service.stream.listen(_onEvent);
    ref.onDispose(() => _sub?.cancel());
    return null;
  }

  void _onEvent(ServerEvent event) {
    switch (event) {
      case CardRevealedReceived():
        // The turn that's still current right now (before this event's own
        // possible game_state follow-up lands) is the one this reveal
        // belongs to — mirrors _HiddenPickNotifier's turnId tracking below.
        _revealedTurnId = ref.read(gameProvider)?.turn.turnId;
        state = event.card;
      case GameStateReceived():
        if (state == null) break;

        // The server sends `card_revealed` BEFORE the `game_state` that
        // announces the reveal phase, and `pickHiddenSlot` mints a brand-new
        // turnId when it enters `hidden_pick_reveal`. So the turnId captured
        // above is necessarily the stale, pre-pick one, and the stale-guard
        // below would fire on the reveal's own game_state — destroying every
        // legitimate reveal in the same event batch, before the flip could
        // render. Adopt the reveal phase's turnId instead: this IS the turn
        // the reveal belongs to.
        if (event.state.turn.phase == 'hidden_pick_reveal') {
          _revealedTurnId = event.state.turn.turnId;
          break;
        }

        // Auto-timeout (or any other path that advances the round without a
        // manual dismiss()) never called dismiss() — without this, `state`
        // would stay non-null forever, leaving CardFlipReveal's opaque
        // overlay mounted over every later phase and absorbing every tap.
        // Same fix shape as _HiddenPickNotifier just above: a reveal is only
        // ever valid for the turn it was shown on.
        if (_revealedTurnId != event.state.turn.turnId) {
          state = null;
          _revealedTurnId = null;
        }
      default:
        break;
    }
  }

  void dismiss() {
    state = null;
    _revealedTurnId = null;
  }
}

final revealedCardProvider =
    NotifierProvider<_RevealedCardNotifier, CandidateCard?>(
      _RevealedCardNotifier.new,
    );

// ── Turn timer ────────────────────────────────────────────────────────────────
// Derives timer state from every game_state delivery (embedded in turn object).
// This avoids the race where turn_timer_start fires before game_screen mounts.
// GameNotifier is always subscribed, so game_state is never missed.

class _TurnTimerNotifier extends Notifier<TurnTimerStarted?> {
  StreamSubscription<ServerEvent>? _sub;

  @override
  TurnTimerStarted? build() {
    final service = ref.watch(roomSocketServiceProvider);
    _sub?.cancel();
    _sub = service.stream.listen(_onEvent);
    ref.onDispose(() => _sub?.cancel());

    // Seed from existing game state so a reconnecting player or late-mount
    // immediately shows the timer without waiting for the next game_state.
    final game = ref.read(gameProvider);
    if (game != null) {
      final turn = game.turn;
      if (turn.turnStartedAt != null && turn.turnDurationSeconds != null) {
        return TurnTimerStarted(
          turnId: turn.turnId,
          turnDurationSeconds: turn.turnDurationSeconds!,
          activePlayerId: turn.activePlayerId,
          startedAt: turn.turnStartedAt!,
        );
      }
    }
    return null;
  }

  void _onEvent(ServerEvent event) {
    switch (event) {
      case GameStateReceived(:final state):
        final turn = state.turn;
        if (state.isFinished) {
          this.state = null;
        } else if (turn.turnStartedAt != null &&
            turn.turnDurationSeconds != null) {
          // Only update if the turnId changed (avoid rebuilding on every game_state).
          final current = this.state;
          if (current?.turnId != turn.turnId) {
            this.state = TurnTimerStarted(
              turnId: turn.turnId,
              turnDurationSeconds: turn.turnDurationSeconds!,
              activePlayerId: turn.activePlayerId,
              startedAt: turn.turnStartedAt!,
            );
          }
        } else {
          // No timer for this room.
          if (this.state != null) this.state = null;
        }
      // Also handle explicit turn_timer_start events as a fallback.
      case TurnTimerStarted():
        state = event;
      default:
        break;
    }
  }
}

final turnTimerProvider =
    NotifierProvider<_TurnTimerNotifier, TurnTimerStarted?>(
      _TurnTimerNotifier.new,
    );
