import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/room_socket_service.dart';

/// Coverage for the reveal-overlay lockout bug: when a draft-card reveal
/// (CardFlipReveal, driven by revealedCardProvider) is never manually
/// dismissed before the round advances — the common case being an
/// auto-timeout pick, where no one is around to tap it — the provider used
/// to stay non-null forever. Since game_screen.dart renders the overlay
/// whenever `revealedCard != null`, that left a full-screen, opaque
/// GestureDetector mounted over every later phase, absorbing every tap
/// until the page was reloaded.
///
/// The fix mirrors _HiddenPickNotifier's existing turnId-based staleness
/// check just above it in game_provider.dart: capture the turnId active
/// when the reveal is shown, and clear automatically once a later
/// game_state reports a different turnId.
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

const _card = CandidateCard(
  cardId: 'c1',
  playerName: 'Test Player',
  basePositionType: 'ST',
  rating: 80,
);

Map<String, dynamic> _gameStateJson({
  required String turnId,
  required String phase,
  required String activePlayerId,
}) => {
  'event': 'game_state',
  'data': {
    'sessionId': 's1',
    'roomCode': 'RVROOM',
    'turn': {
      'turnId': turnId,
      'phase': phase,
      'activePlayerId': activePlayerId,
    },
    'pitches': <String, dynamic>{},
    'localPlayerId': 'p1',
  },
};

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

void main() {
  group('revealedCardProvider — no stale reveal-overlay lockout', () {
    late _RecordingSocketService fakeService;
    late ProviderContainer container;

    setUp(() {
      fakeService = _RecordingSocketService();
      container = ProviderContainer(
        overrides: [roomSocketServiceProvider.overrideWithValue(fakeService)],
      );
      container.read(gameProvider); // subscribe, so it tracks turnId below
      container.read(revealedCardProvider); // subscribe, mirrors game_screen
    });

    tearDown(() {
      container.dispose();
      fakeService.disposeFake();
    });

    /// Establishes the "current" turn before any reveal — mirrors the app
    /// always having a live game_state before a card_revealed can arrive.
    Future<void> seedCurrentTurn(String turnId) async {
      fakeService.emit(
        GameStateReceived(
          _emptyGameState(
            turnId: turnId,
            phase: 'drafting',
            activePlayerId: 'p1',
          ),
          'p1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    test('a card_revealed event populates state normally', () async {
      await seedCurrentTurn('t1');
      fakeService.emit(const CardRevealedReceived(_card));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(revealedCardProvider), _card);
    });

    test(
      'manual dismiss() still clears it (existing, unchanged path)',
      () async {
        await seedCurrentTurn('t1');
        fakeService.emit(const CardRevealedReceived(_card));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(container.read(revealedCardProvider), isNotNull);

        container.read(revealedCardProvider.notifier).dismiss();

        expect(container.read(revealedCardProvider), isNull);
      },
    );

    test(
      'auto-timeout regression: a reveal never manually dismissed is cleared '
      'automatically once game_state shows the round moved to a new turnId — '
      'this is what stopped the overlay from blocking Bench Selection/Final '
      'Lineup forever',
      () async {
        await seedCurrentTurn('t1');
        fakeService.emit(const CardRevealedReceived(_card));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(container.read(revealedCardProvider), isNotNull);

        // The round advanced (e.g. an auto-pick timeout) with no tap ever
        // reaching CardFlipReveal's dismiss handler.
        fakeService.emit(
          GameStateReceived(
            _emptyGameState(
              turnId: 't2',
              phase: 'bench_selection',
              activePlayerId: 'p1',
            ),
            'p1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(container.read(revealedCardProvider), isNull);
      },
    );

    test(
      'a reveal is NOT cleared by a game_state for the SAME turnId (e.g. an '
      'unrelated resync broadcast) — it must survive until the round '
      'actually moves on or is manually dismissed',
      () async {
        await seedCurrentTurn('t1');
        fakeService.emit(const CardRevealedReceived(_card));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(container.read(revealedCardProvider), isNotNull);

        fakeService.emit(
          GameStateReceived(
            _emptyGameState(
              turnId: 't1',
              phase: 'drafting',
              activePlayerId: 'p1',
            ),
            'p1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(container.read(revealedCardProvider), isNotNull);
      },
    );

    test(
      'REGRESSION: the reveal survives its OWN game_state, which always '
      'carries a brand-new turnId — the sealed-dossier reveal that never '
      'appeared',
      () async {
        // Reproduces the exact live sequence. `pickHiddenSlot` mints a fresh
        // turnId when it enters `hidden_pick_reveal`, and the server sends
        // `card_revealed` BEFORE that game_state — so the turnId captured
        // alongside the reveal is necessarily the stale pre-pick one. The
        // stale-guard then fired on the reveal's own state and wiped it in
        // the same event batch, so the flip never rendered: the player saw a
        // dark flash and their card already slotted into the lineup.
        await seedCurrentTurn('t-prepick');

        fakeService.emit(const CardRevealedReceived(_card));
        fakeService.emit(
          GameStateReceived(
            _emptyGameState(
              turnId: 't-reveal', // new id, minted by pickHiddenSlot
              phase: 'hidden_pick_reveal',
              activePlayerId: 'p1',
            ),
            'p1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          container.read(revealedCardProvider),
          _card,
          reason: 'the reveal must survive its own reveal-phase game_state',
        );
      },
    );

    test(
      'after adopting the reveal turnId, the lockout protection still works — '
      'the round moving on clears the overlay',
      () async {
        await seedCurrentTurn('t-prepick');
        fakeService.emit(const CardRevealedReceived(_card));
        fakeService.emit(
          GameStateReceived(
            _emptyGameState(
              turnId: 't-reveal',
              phase: 'hidden_pick_reveal',
              activePlayerId: 'p1',
            ),
            'p1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(container.read(revealedCardProvider), isNotNull);

        // The round genuinely advances (confirm, or the server's fallback).
        fakeService.emit(
          GameStateReceived(
            _emptyGameState(
              turnId: 't-next',
              phase: 'hidden_pick',
              activePlayerId: 'p2',
            ),
            'p1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          container.read(revealedCardProvider),
          isNull,
          reason: 'the original overlay-lockout protection must be intact',
        );
      },
    );
  });
}
