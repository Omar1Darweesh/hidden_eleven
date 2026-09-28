import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider lives in the legacy export in Riverpod 3.x (the rest of the
// app uses NotifierProvider, so this is the first place that needs it).
import 'package:flutter_riverpod/legacy.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/room_socket_service.dart';
import '../models/tournament_models.dart';

/// Full tournament snapshot. Updated on every tournament_state event from server.
final tournamentStateProvider = StateProvider<TournamentStateModel?>(
  (ref) => null,
);

/// Live events per match during simulation. Key = matchId.
final liveMatchEventsProvider =
    StateProvider<Map<String, List<LiveMatchEvent>>>((ref) => {});

/// Completed match results. Key = matchId. Populated when tournament_match_result arrives.
final completedMatchResultsProvider =
    StateProvider<Map<String, TournamentMatchResult>>((ref) => {});

/// Champion + awards. Set when tournament_complete event arrives.
final tournamentCompleteProvider = StateProvider<TournamentAwardsModel?>(
  (ref) => null,
);

/// This player's participantId in the tournament bracket.
/// Set once when tournament_state first arrives and our playerId is found.
final myParticipantIdProvider = StateProvider<String?>((ref) => null);

/// Derived: has this player already pressed Ready this round?
final myReadyStatusProvider = Provider<bool>((ref) {
  final state = ref.watch(tournamentStateProvider);
  final myId = ref.watch(myParticipantIdProvider);
  if (state == null || myId == null) return false;
  return state.readyPlayerIds.contains(myId);
});

/// Stream of auto-ready notices (AI participants, or a real player auto-readied
/// by the 60s timeout). A Phase 3B widget listens to this and shows the
/// "⏰ … was auto-readied" toast via `ScaffoldMessenger.of(context)` — the same
/// stream-provider + widget-listener pattern the codebase already uses for
/// `kickedProvider` / `serverErrorProvider`. (There is no global messenger /
/// navigator key for showing toasts from non-widget code, and Phase 3A adds no
/// UI, so the notice is surfaced here for a later screen to render.)
final tournamentAutoReadyProvider = StreamProvider<TournamentAutoReadyReceived>(
  (ref) {
    return ref
        .watch(roomSocketServiceProvider)
        .stream
        .where((e) => e is TournamentAutoReadyReceived)
        .cast<TournamentAutoReadyReceived>();
  },
);
