import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/room_socket_service.dart';

/// Coverage for the active-player refresh/reconnect bug: game.turn.candidates
/// used to be omitted from every game_state snapshot ("candidates
/// intentionally omitted" — see game.service.ts's buildSnapshot), so a
/// refresh mid selecting_card had no way to ever see the candidate pool
/// again — the only place it was ever sent was the one-off slot_candidates
/// event fired live, once, as the direct response to the pick_slot request
/// that created it. This exercises both halves of the fix:
///   1. _parseGameState now parses turn.candidates from the durable payload.
///   2. SlotCandidatesNotifier restores from that durable state instead of
///      waiting forever for a live event that will never come again.
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

GameState _baseGameState({required GameTurn turn}) => GameState(
  sessionId: 's1',
  roomCode: 'RM1',
  formationName: '4-4-2',
  players: const [],
  pitches: const {},
  baseTurnOrder: const ['p1', 'p2'],
  currentRound: 1,
  totalRounds: 11,
  currentTurnOrder: const ['p1', 'p2'],
  currentTurnIndex: 0,
  currentRoundSlotIndex: turn.activeSlotIndex,
  turn: turn,
  status: 'drafting',
  isFinished: false,
);

const _sampleCard = CandidateCard(
  cardId: 'card-1',
  playerName: 'Test Player',
  basePositionType: 'ST',
  rating: 88,
);

void main() {
  group(
    '_parseGameState — turn.candidates parsing (durable restore payload)',
    () {
      test('parses turn.candidates into CandidateCard entries', () {
        final json = {
          'event': 'game_state',
          'data': {
            'sessionId': 's1',
            'roomCode': 'RM1',
            'turn': {
              'turnId': 't1',
              'phase': 'selecting_card',
              'activePlayerId': 'p1',
              'activeSlotIndex': 3,
              'candidates': [
                {
                  'cardId': 'card-1',
                  'playerName': 'Test Player',
                  'basePositionType': 'ST',
                  'rating': 88,
                },
              ],
            },
            'localPlayerId': 'p1',
          },
        };

        final event = parseServerEvent(json, null) as GameStateReceived;

        expect(event.state.turn.candidates, hasLength(1));
        expect(event.state.turn.candidates.single.cardId, 'card-1');
        expect(event.state.turn.candidates.single.rating, 88);
      });

      test(
        'a missing/empty candidates field parses to an empty list (other players, other phases)',
        () {
          final json = {
            'event': 'game_state',
            'data': {
              'sessionId': 's1',
              'roomCode': 'RM1',
              'turn': {
                'turnId': 't1',
                'phase': 'selecting_position',
                'activePlayerId': 'p1',
              },
              'localPlayerId': 'p2',
            },
          };

          final event = parseServerEvent(json, null) as GameStateReceived;

          expect(event.state.turn.candidates, isEmpty);
        },
      );
    },
  );

  group('SlotCandidatesNotifier — restores from durable game_state on reconnect', () {
    late _RecordingSocketService fakeService;
    late ProviderContainer container;

    setUp(() {
      fakeService = _RecordingSocketService();
      container = ProviderContainer(
        overrides: [roomSocketServiceProvider.overrideWithValue(fakeService)],
      );
    });

    tearDown(() {
      container.dispose();
      fakeService.disposeFake();
    });

    test(
      'refresh during selecting_card: a game_state with no prior live slot_candidates event still restores the candidate panel',
      () async {
        container.read(
          slotCandidatesProvider,
        ); // subscribe, mirrors GameScreen watching it
        expect(container.read(slotCandidatesProvider), isNull);

        // The exact sequence a refresh mid selecting_card produces: check_presence's
        // reconnect ack delivers a fresh game_state — no slot_candidates event
        // precedes it, because that one-off event already fired (and was lost)
        // before this client existed.
        fakeService.emit(
          GameStateReceived(
            _baseGameState(
              turn: const GameTurn(
                turnId: 't1',
                phase: 'selecting_card',
                activePlayerId: 'p1',
                activeSlotIndex: 3,
                candidates: [_sampleCard],
              ),
            ),
            'p1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final restored = container.read(slotCandidatesProvider);
        expect(restored, isNotNull);
        expect(restored!.turnId, 't1');
        expect(restored.candidates.single.cardId, 'card-1');
      },
    );

    test(
      'refresh during selecting_position: no candidates exist yet, so nothing is (falsely) restored',
      () async {
        container.read(slotCandidatesProvider);

        fakeService.emit(
          GameStateReceived(
            _baseGameState(
              turn: const GameTurn(
                turnId: 't1',
                phase: 'selecting_position',
                activePlayerId: 'p1',
                // No slot chosen yet — durable candidates are genuinely empty at
                // this point, exactly like the real session.turn.candidates.
                candidates: [],
              ),
            ),
            'p1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(container.read(slotCandidatesProvider), isNull);
      },
    );

    test(
      'does not clobber state already set by a live slot_candidates ack (normal, non-reconnect flow unchanged)',
      () async {
        container.read(slotCandidatesProvider);

        fakeService.emit(const SlotCandidatesReceived('t1', [_sampleCard]));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          container.read(slotCandidatesProvider)?.candidates.single.cardId,
          'card-1',
        );

        // The game_state broadcast that always follows a pick_slot response —
        // must not overwrite the already-correct live state with a duplicate
        // (harmless) or, worse, stale copy.
        fakeService.emit(
          GameStateReceived(
            _baseGameState(
              turn: const GameTurn(
                turnId: 't1',
                phase: 'selecting_card',
                activePlayerId: 'p1',
                activeSlotIndex: 3,
                candidates: [_sampleCard],
              ),
            ),
            'p1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final state = container.read(slotCandidatesProvider);
        expect(state?.turnId, 't1');
        expect(state?.candidates, hasLength(1));
      },
    );

    test(
      'clears stale candidates once the turn moves on (no stale previous phase after the pick completes)',
      () async {
        container.read(slotCandidatesProvider);

        fakeService.emit(const SlotCandidatesReceived('t1', [_sampleCard]));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(container.read(slotCandidatesProvider), isNotNull);

        // Turn advances (card picked, new turn begins) — a fresh turnId with a
        // phase that carries no candidates of its own.
        fakeService.emit(
          GameStateReceived(
            _baseGameState(
              turn: const GameTurn(
                turnId: 't2',
                phase: 'selecting_position',
                activePlayerId: 'p2',
              ),
            ),
            'p2',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(container.read(slotCandidatesProvider), isNull);
      },
    );

    test(
      'build()-time seed: a fresh SlotCandidatesNotifier picks up an already-loaded selecting_card game',
      () async {
        // Seeds gameProvider directly (bypassing the socket) to simulate this
        // notifier being (re)built after game state already exists — the
        // defensive seed path in SlotCandidatesNotifier.build().
        container.read(gameProvider.notifier).state = _baseGameState(
          turn: const GameTurn(
            turnId: 't1',
            phase: 'selecting_card',
            activePlayerId: 'p1',
            activeSlotIndex: 3,
            candidates: [_sampleCard],
          ),
        );

        final seeded = container.read(slotCandidatesProvider);

        expect(seeded, isNotNull);
        expect(seeded!.turnId, 't1');
        expect(seeded.candidates.single.cardId, 'card-1');
      },
    );
  });
}
