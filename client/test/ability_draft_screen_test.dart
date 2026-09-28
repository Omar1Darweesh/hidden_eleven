import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hidden_eleven/features/game/models/ability.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/ability_draft_screen.dart';
import 'package:hidden_eleven/features/lobby/models/server_event.dart';
import 'package:hidden_eleven/features/lobby/room_socket_service.dart';

/// Coverage for the connection-gating fix: unlike every other phase,
/// AbilityDraftScreen is a full-screen takeover that bypasses _ActionPanel
/// entirely, so it never inherited _ActionPanel's own "disable actions while
/// reconnecting/disconnected" behavior — a card could be tapped, and a
/// pick_ability sent, into a socket that wasn't confirmed healthy. Verifies
/// the fix at the actual send boundary (a fake RoomSocketService recording
/// every `send()` call) rather than just checking a widget property, so this
/// proves the tap genuinely never reaches the network layer when disconnected.
class _RecordingSocketService extends RoomSocketService {
  final _fakeController = StreamController<ServerEvent>.broadcast();
  final List<String> sentEvents = [];

  @override
  Stream<ServerEvent> get stream => _fakeController.stream;

  @override
  void connect() {}

  @override
  void reconnect() {}

  @override
  void send(String event, [Map<String, dynamic>? data]) {
    sentEvents.add(event);
  }

  void disposeFake() => _fakeController.close();
}

GameTurn _turn() => const GameTurn(
  turnId: 't0',
  phase: 'selecting_position',
  activePlayerId: '',
);

GameState _abilityDraftGameState({
  required String localPlayerId,
  required String? currentPickerId,
  PlayerAbility? myAbility,
}) => GameState(
  sessionId: 's1',
  roomCode: 'RM1',
  formationName: '4-4-2',
  players: const [
    GamePlayer(id: 'p1', displayName: 'Alice', isHost: true, isConnected: true),
    GamePlayer(id: 'p2', displayName: 'Bob', isHost: false, isConnected: true),
  ],
  pitches: const {},
  baseTurnOrder: const ['p1', 'p2'],
  currentRound: 1,
  totalRounds: 11,
  currentTurnOrder: const ['p1', 'p2'],
  currentTurnIndex: 0,
  currentRoundSlotIndex: null,
  turn: _turn(),
  status: 'ability_draft',
  isFinished: false,
  abilityDraft: AbilityDraftState(
    poolCount: 2,
    pickOrder: const ['p1', 'p2'],
    currentPickIndex: 0,
    currentPickerId: currentPickerId,
    cards: const [
      AbilityCardInfo(id: 0, pickedBy: null, type: null),
      AbilityCardInfo(id: 1, pickedBy: null, type: null),
    ],
  ),
  myAbility: myAbility,
);

void main() {
  late _RecordingSocketService fakeService;

  setUp(() {
    fakeService = _RecordingSocketService();
  });

  tearDown(() => fakeService.disposeFake());

  Future<void> pumpScreen(
    WidgetTester tester, {
    required bool connected,
  }) async {
    final game = _abilityDraftGameState(
      localPlayerId: 'p1',
      currentPickerId:
          'p1', // it IS p1's turn — the only case a tap could ever be enabled
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [roomSocketServiceProvider.overrideWithValue(fakeService)],
        child: MaterialApp(
          home: AbilityDraftScreen(
            game: game,
            localPlayerId: 'p1',
            connected: connected,
          ),
        ),
      ),
    );
    // Let the deal-in entrance animation settle so taps land on final layout.
    await tester.pump(const Duration(milliseconds: 900));
  }

  // The pool cards render inside the deck's Wrap — scoping the finder there
  // (rather than find.byType(GestureDetector) unscoped) avoids accidentally
  // hitting unrelated GestureDetectors elsewhere on the screen (e.g. the
  // help button, which sits in its own Align outside the Wrap).
  Finder firstCard() => find
      .descendant(of: find.byType(Wrap), matching: find.byType(GestureDetector))
      .first;

  testWidgets(
    'connected: false — tapping a face-down card during your own turn never sends pick_ability',
    (tester) async {
      await pumpScreen(tester, connected: false);

      await tester.tap(firstCard(), warnIfMissed: false);
      await tester.pump();

      expect(fakeService.sentEvents, isEmpty);
    },
  );

  testWidgets(
    'connected: true — tapping a face-down card during your own turn does send pick_ability',
    (tester) async {
      await pumpScreen(tester, connected: true);

      await tester.tap(firstCard(), warnIfMissed: false);
      await tester.pump();

      expect(fakeService.sentEvents, contains('pick_ability'));
    },
  );

  group('revealed card — description rendering (D3)', () {
    setUp(() {
      AbilityMeta.debugOverrideConfigured(null);
      ChemistryVars.debugOverrideValues(null);
    });

    Future<void> pumpRevealed(WidgetTester tester) async {
      final game = _abilityDraftGameState(
        localPlayerId: 'p1',
        currentPickerId: 'p2', // not p1's turn — reveal card is what's shown
        myAbility: const PlayerAbility(
          type: AbilityType.yellow,
          status: 'pending',
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [roomSocketServiceProvider.overrideWithValue(fakeService)],
          child: MaterialApp(
            home: AbilityDraftScreen(game: game, localPlayerId: 'p1'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));
    }

    testWidgets(
      'shows the server-configured description, resolved through ChemistryVars, not the old hardcoded tagline',
      (tester) async {
        AbilityMeta.debugOverrideConfigured({
          AbilityType.yellow: (
            name: 'Yellow Card',
            description: 'Docks {yellowPenalty} points from a rival.',
            color: const Color(0xFFF2C037),
          ),
        });
        ChemistryVars.debugOverrideValues({'yellowPenalty': 30});

        await pumpRevealed(tester);

        expect(find.text('Docks 30 points from a rival.'), findsOneWidget);
        // The old hardcoded copy must not be the rendered source anymore.
        expect(find.text('Knock 20 points off a rival’s score.'), findsNothing);
      },
    );

    testWidgets(
      'falls back to the built-in description before ensureLoaded() ever resolves',
      (tester) async {
        // No debugOverrideConfigured call — simulates the pre-fetch state.
        await pumpRevealed(tester);

        expect(
          find.text('Knock 20 points off a rival’s score.'),
          findsOneWidget,
        );
      },
    );
  });
}
