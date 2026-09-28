import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/room_socket_service.dart';

/// Coverage for the "refresh during my hidden-pick turn costs me that pick"
/// bug (room ENDFEC). The root cause was entirely server-side (see
/// rooms.gateway.ts's ACTIVE_TURN_DISCONNECT_GRACE_MS) — a refresh's
/// unavoidable disconnect-then-reconnect gap was letting the active
/// player's turn get silently reassigned before their new socket ever sent
/// check_presence. This file confirms the CLIENT side was never actually
/// broken for hidden-pick specifically:
///   - hidden_pick's own reconnect-restore already works via
///     _resendPhasePrompt (a live hidden_pick_prompt re-sent ON reconnect,
///     unlike selecting_card's one-off slot_candidates ack), so there's no
///     durable-vs-transient gap to fix here the way there was for
///     slotCandidatesProvider.
///   - _HiddenPickNotifier already clears stale state once the phase moves
///     on, so a reconnecting client can never show a hidden-pick prompt for
///     a turn that already resolved.
///   - pitches (drafted rosters) are always fully durable — never scoped or
///     omitted — so a reconnecting player's already-resolved hidden pick is
///     never lost by _parseGameState.
class _RecordingSocketService extends RoomSocketService {
  final _fakeController = StreamController<ServerEvent>.broadcast();

  @override
  Stream<ServerEvent> get stream => _fakeController.stream;

  @override
  void connect() {}

  @override
  void reconnect() {}

  @override
  void send(String event, [Map<String, dynamic>? data]) {}

  void emit(ServerEvent event) => _fakeController.add(event);

  void disposeFake() => _fakeController.close();
}

Map<String, dynamic> _gameStateJson({
  required String turnId,
  required String phase,
  required String activePlayerId,
  Map<String, dynamic>? p1Pitch,
}) => {
  'event': 'game_state',
  'data': {
    'sessionId': 's1',
    'roomCode': 'HPROOM',
    'turn': {
      'turnId': turnId,
      'phase': phase,
      'activePlayerId': activePlayerId,
    },
    'pitches': {if (p1Pitch != null) 'p1': p1Pitch},
    'localPlayerId': 'p1',
  },
};

void main() {
  group('_parseGameState — roster/squad consistency after reconnect', () {
    test(
      'an already-resolved hidden pick (a filled pitch slot) survives parsing intact',
      () {
        final json = _gameStateJson(
          turnId: 't2',
          phase: 'selecting_position',
          activePlayerId: 'p2',
          p1Pitch: {
            'slots': [
              {
                'index': 0,
                'label': 'GK',
                'basePositionType': 'GK',
                'card': {
                  'cardId': 'hidden-card-1',
                  'playerName': 'A. Areola',
                  'basePositionType': 'GK',
                  'rating': 82,
                },
              },
            ],
            'filledCount': 1,
          },
        );

        final event = parseServerEvent(json, null) as GameStateReceived;

        final p1Pitch = event.state.pitches['p1']!;
        expect(p1Pitch.filledCount, 1);
        expect(p1Pitch.slots.single.cardId, 'hidden-card-1');
        expect(p1Pitch.slots.single.cardPlayerName, 'A. Areola');
      },
    );
  });

  group('hiddenPickProvider — no stale hidden-pick UI after phase advances', () {
    late _RecordingSocketService fakeService;
    late ProviderContainer container;

    setUp(() {
      fakeService = _RecordingSocketService();
      container = ProviderContainer(
        overrides: [roomSocketServiceProvider.overrideWithValue(fakeService)],
      );
      container.read(
        hiddenPickProvider,
      ); // subscribe, mirrors game_screen watching it
    });

    tearDown(() {
      container.dispose();
      fakeService.disposeFake();
    });

    test(
      'a live hidden_pick_prompt populates state normally (unaffected by the reconnect fix)',
      () async {
        fakeService.emit(
          const HiddenPickPromptReceived(
            turnId: 't1',
            totalSlots: 5,
            availableSlots: [0, 1, 2, 3, 4],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final data = container.read(hiddenPickProvider);
        expect(data, isNotNull);
        expect(data!.turnId, 't1');
        expect(data.availableSlots, [0, 1, 2, 3, 4]);
      },
    );

    test(
      'a reconnecting client (fresh, no prior event) never shows a hidden-pick prompt once the phase has already advanced past hidden_pick',
      () async {
        // Nothing was ever received live — mirrors a cold-started client whose
        // check_presence ack landed after the hidden-pick round already
        // resolved and moved on (e.g. into selecting_position for the next
        // round's first picker).
        fakeService.emit(
          GameStateReceived(
            _emptyGameState(
              turnId: 't2',
              phase: 'selecting_position',
              activePlayerId: 'p2',
            ),
            'p1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(container.read(hiddenPickProvider), isNull);
      },
    );

    test(
      'a stale hidden-pick prompt is cleared the moment game_state shows the turn has moved on',
      () async {
        fakeService.emit(
          const HiddenPickPromptReceived(
            turnId: 't1',
            totalSlots: 5,
            availableSlots: [0, 1, 2, 3, 4],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(container.read(hiddenPickProvider), isNotNull);

        // The pick resolved and the round wrapped into the next phase.
        fakeService.emit(
          GameStateReceived(
            _emptyGameState(
              turnId: 't2',
              phase: 'selecting_position',
              activePlayerId: 'p2',
            ),
            'p1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(container.read(hiddenPickProvider), isNull);
      },
    );

    test(
      'a stale hidden-pick prompt is cleared once the SAME phase moves to a new turnId (next picker\'s turn)',
      () async {
        fakeService.emit(
          const HiddenPickPromptReceived(
            turnId: 't1',
            totalSlots: 5,
            availableSlots: [0, 1, 2, 3, 4],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(container.read(hiddenPickProvider), isNotNull);

        // Still hidden_pick overall, but it's now a DIFFERENT player's turn —
        // this client's own prompt (turnId t1) must not linger.
        fakeService.emit(
          GameStateReceived(
            _emptyGameState(
              turnId: 't2',
              phase: 'hidden_pick',
              activePlayerId: 'p2',
            ),
            'p1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(container.read(hiddenPickProvider), isNull);
      },
    );
  });
}

GameState _emptyGameState({
  required String turnId,
  required String phase,
  required String activePlayerId,
}) {
  final json = _gameStateJson(
    turnId: turnId,
    phase: phase,
    activePlayerId: activePlayerId,
  );
  return (parseServerEvent(json, null) as GameStateReceived).state;
}
