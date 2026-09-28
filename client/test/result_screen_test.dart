import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hidden_eleven/features/admin/services/admin_api.dart'
    as admin_api;
import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/result/result_screen.dart';
import 'package:hidden_eleven/shared/widgets/rank_medallion.dart';

/// Overrides gameProvider's build() directly (never calling super.build(),
/// so no real socket subscription is ever set up) — same subclass-and-
/// override shape ability_draft_screen_test.dart already uses for
/// RoomSocketService.
class _FixedGameNotifier extends GameNotifier {
  _FixedGameNotifier(this._state);
  final GameState _state;

  @override
  GameState? build() => _state;
}

PitchSlot _gkSlot() => const PitchSlot(
  index: 0,
  label: 'GK',
  basePositionType: 'GK',
  cardPlayerName: 'Test GK',
  cardRating: 80,
  cardId: 'card-0',
  cardNaturalPositions: ['GK'],
);

GameState _resultGameState({required int captainBonus}) {
  return GameState(
    sessionId: 's1',
    roomCode: 'RM1',
    formationName: '4-3-3',
    players: const [GamePlayer(id: 'p1', displayName: 'Alice', isHost: true)],
    pitches: {
      'p1': PlayerPitch(playerId: 'p1', slots: [_gkSlot()], filledCount: 1),
    },
    baseTurnOrder: const ['p1'],
    currentRound: 12,
    totalRounds: 11,
    currentTurnOrder: const ['p1'],
    currentTurnIndex: 0,
    currentRoundSlotIndex: null,
    turn: const GameTurn(
      turnId: 't1',
      phase: 'selecting_position',
      activePlayerId: '',
    ),
    status: 'finished',
    isFinished: true,
    result: GameResult(
      reason: 'completed',
      players: [
        PlayerResult(
          playerId: 'p1',
          displayName: 'Alice',
          rank: 1,
          score: 82,
          scoreBreakdown: ScoreBreakdown(
            defAvg: 80,
            midAvg: 0,
            atkAvg: 0,
            linesTotal: 80,
            userChemTotal: 0,
            cardChemTotal: 0,
            lineLeaderBonus: 2,
            captainBonus: captainBonus,
            yellowPenalty: 0,
            redApplied: false,
            finalScore: 82,
          ),
        ),
      ],
    ),
  );
}

GameState _twoPlayerResultGameState() {
  return GameState(
    sessionId: 's1',
    roomCode: 'RM1',
    formationName: '4-3-3',
    players: const [
      GamePlayer(id: 'p1', displayName: 'Alice', isHost: true),
      GamePlayer(id: 'p2', displayName: 'Bob', isHost: false),
    ],
    pitches: {
      'p1': PlayerPitch(playerId: 'p1', slots: [_gkSlot()], filledCount: 1),
      'p2': PlayerPitch(playerId: 'p2', slots: [_gkSlot()], filledCount: 1),
    },
    baseTurnOrder: const ['p1', 'p2'],
    currentRound: 12,
    totalRounds: 11,
    currentTurnOrder: const ['p1', 'p2'],
    currentTurnIndex: 0,
    currentRoundSlotIndex: null,
    turn: const GameTurn(
      turnId: 't1',
      phase: 'selecting_position',
      activePlayerId: '',
    ),
    status: 'finished',
    isFinished: true,
    result: GameResult(
      reason: 'completed',
      players: [
        PlayerResult(playerId: 'p1', displayName: 'Alice', rank: 1, score: 90),
        PlayerResult(playerId: 'p2', displayName: 'Bob', rank: 2, score: 70),
      ],
    ),
  );
}

void main() {
  setUp(() {
    ChemistryVars.debugOverrideValues(null);
    // The AppBar's ContextHelpButton fetches AdminApi.getContextHelp() — a
    // fast, deterministic failure keeps this test independent of the
    // sandbox's real network timing (same rationale as abilities_help_test.dart).
    admin_api.debugHttpClient = MockClient(
      (request) async => http.Response('error', 500),
    );
  });

  tearDown(() {
    admin_api.debugHttpClient = null;
  });

  Future<void> pumpResultScreen(
    WidgetTester tester, {
    required int captainBonus,
  }) async {
    final game = _resultGameState(captainBonus: captainBonus);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [gameProvider.overrideWith(() => _FixedGameNotifier(game))],
        child: const MaterialApp(home: ResultScreen(roomCode: 'RM1')),
      ),
    );
    await tester.pumpAndSettle();
    // The squad/chemistry details (line-leaders banner, scoring breakdown)
    // live inside a collapsed-by-default ExpansionTile — expand it.
    await tester.tap(find.text('SQUAD & CHEMISTRY DETAILS'));
    await tester.pumpAndSettle();
  }

  group('line-leaders banner', () {
    testWidgets(
      'shows the resolved bonus amount for a mocked non-default lineLeaderBonus',
      (tester) async {
        ChemistryVars.debugOverrideValues({'lineLeaderBonus': 7});
        await pumpResultScreen(tester, captainBonus: 0);

        expect(find.text('LINE LEADERS  ·  +7 EACH'), findsOneWidget);
        expect(find.text('LINE LEADERS  ·  +2 EACH'), findsNothing);
      },
    );

    testWidgets('falls back to the v1 default before any config is loaded', (
      tester,
    ) async {
      await pumpResultScreen(tester, captainBonus: 0);

      expect(find.text('LINE LEADERS  ·  +2 EACH'), findsOneWidget);
    });
  });

  group('captain wording', () {
    testWidgets(
      'shows ×{captainMultiplier}, resolved to a mocked non-default value, not "doubled"',
      (tester) async {
        ChemistryVars.debugOverrideValues({'captainMultiplier': 3});
        await pumpResultScreen(tester, captainBonus: 4);

        expect(find.text('Captain — ×3 a player’s chemistry'), findsOneWidget);
        expect(
          find.text('Captain — doubled a player’s chemistry'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'falls back to the v1 default (×2) before any config is loaded',
      (tester) async {
        await pumpResultScreen(tester, captainBonus: 4);

        expect(find.text('Captain — ×2 a player’s chemistry'), findsOneWidget);
      },
    );
  });

  testWidgets(
    'a maximal (3-digit) resolved value does not overflow the line-leaders banner at a narrow width',
    (tester) async {
      ChemistryVars.debugOverrideValues({'lineLeaderBonus': 999});
      final game = _resultGameState(captainBonus: 0);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gameProvider.overrideWith(() => _FixedGameNotifier(game)),
          ],
          child: MediaQuery(
            data: const MediaQueryData(size: Size(360, 800)),
            child: const MaterialApp(home: ResultScreen(roomCode: 'RM1')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('SQUAD & CHEMISTRY DETAILS'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('LINE LEADERS  ·  +999 EACH'), findsOneWidget);
    },
  );

  group('Final Standings — rank medallion and current-player visibility', () {
    testWidgets(
      'standings use RankMedallion, never a medal emoji, and mark the local '
      'player with "(you)"',
      (tester) async {
        final game = _twoPlayerResultGameState();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              gameProvider.overrideWith(() => _FixedGameNotifier(game)),
            ],
            child: const MaterialApp(home: ResultScreen(roomCode: 'RM1')),
          ),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ResultScreen)),
        );
        container.read(localPlayerIdProvider.notifier).set('p1');
        await tester.pumpAndSettle();

        expect(find.byType(RankMedallion), findsWidgets);
        expect(find.textContaining('🥇'), findsNothing);
        expect(find.textContaining('🥈'), findsNothing);
        expect(find.textContaining('🥉'), findsNothing);
        expect(find.textContaining('(you)'), findsWidgets);
      },
    );

    testWidgets(
      'the winner hero shows a violet-driven "YOUR RESULT" bar with a '
      'RankMedallion for the local player',
      (tester) async {
        final game = _twoPlayerResultGameState();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              gameProvider.overrideWith(() => _FixedGameNotifier(game)),
            ],
            child: const MaterialApp(home: ResultScreen(roomCode: 'RM1')),
          ),
        );
        // Mirrors the app's own localPlayerId seam (see server_event.dart /
        // SpectatingBanner tests) rather than a widget-tree lookup.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ResultScreen)),
        );
        container.read(localPlayerIdProvider.notifier).set('p2');
        await tester.pumpAndSettle();

        expect(find.text('YOUR RESULT'), findsOneWidget);
        expect(find.byType(RankMedallion), findsWidgets);
        expect(find.textContaining('🥈'), findsNothing);
      },
    );
  });

  group('Phase B — narrow-layout Back to Home position', () {
    testWidgets(
      'at narrow width, Back to Home sits right after Final Standings — '
      'reachable well before the Squad Details section further down',
      (tester) async {
        // MediaQuery placed *above* MaterialApp does not affect it in tests
        // — MaterialApp/WidgetsApp derives its own size from the test
        // binding's view. `tester.view.physicalSize` is the mechanism that
        // actually changes what MediaQuery.sizeOf resolves to app-wide.
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final game = _twoPlayerResultGameState();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              gameProvider.overrideWith(() => _FixedGameNotifier(game)),
            ],
            child: const MaterialApp(home: ResultScreen(roomCode: 'RM1')),
          ),
        );
        await tester.pumpAndSettle();

        final standingsY = tester
            .getTopLeft(find.text('FINAL STANDINGS'))
            .dy;
        final backHomeY = tester.getTopLeft(find.text('Back to Home')).dy;
        final squadDetailsY = tester
            .getTopLeft(find.text('SQUAD & CHEMISTRY DETAILS'))
            .dy;

        expect(backHomeY, greaterThan(standingsY));
        expect(backHomeY, lessThan(squadDetailsY));
      },
    );
  });
}
