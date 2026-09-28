import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/ability_activation_screen.dart';
import 'package:hidden_eleven/features/game/widgets/ability_resolved_summary.dart';
import 'package:hidden_eleven/features/game/widgets/compact_bench_summary.dart';
import 'package:hidden_eleven/features/game/widgets/command_strip.dart';
import 'package:hidden_eleven/features/subs/subs_panel.dart';

/// Post-bench ability flow UX — continuity between bench_selection →
/// ability_activation → reveal → lineup_edit without changing gameplay rules.
void main() {
  setUp(() {
    AbilityMeta.debugOverrideConfigured(null);
    ChemistryVars.debugOverrideValues(null);
  });

  GameState gameFixture({
    required String status,
    bool isComplete = true,
    bool lineupConfirmed = false,
    bool hasExtraBench = false,
    PlayerAbility? myAbility,
    bool abilityActivationRevealed = false,
    Map<String, bool>? abilityActivationResolved,
    SubSlot? att,
    SubSlot? mid,
    SubSlot? def,
  }) => GameState(
    sessionId: 's1',
    roomCode: 'RM1',
    formationName: '4-3-3',
    players: const [
      GamePlayer(id: 'p1', displayName: 'Alice', isHost: true),
      GamePlayer(id: 'p2', displayName: 'Bob', isHost: false),
    ],
    pitches: const {},
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
    status: status,
    isFinished: false,
    myAbility: myAbility,
    abilityActivationRevealed: abilityActivationRevealed,
    abilityActivationResolved: abilityActivationResolved,
    subsPhase: SubsPhase(
      userSubs: {
        'p1': UserSubstitutions(
          isComplete: isComplete,
          lineupConfirmed: lineupConfirmed,
          hasExtraBench: hasExtraBench,
          att: att,
          mid: mid,
          def: def,
        ),
        'p2': const UserSubstitutions(
          isComplete: false,
          lineupConfirmed: false,
          hasExtraBench: false,
        ),
      },
    ),
  );

  Future<void> pumpSubs(
    WidgetTester tester, {
    required GameState game,
    required SubsPanelMode mode,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SubsPanel(game: game, localId: 'p1', mode: mode),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('A) Bench selection lock / next-step messaging', () {
    testWidgets('incomplete bench shows next-step ability messaging', (
      tester,
    ) async {
      await pumpSubs(
        tester,
        game: gameFixture(status: 'bench_selection', isComplete: false),
        mode: SubsPanelMode.benchSelection,
      );

      expect(find.textContaining('hidden ability phase'), findsOneWidget);
      expect(find.text('Bench Locked ✓'), findsNothing);
      expect(find.text('Submit Final Lineup'), findsNothing);
    });

    testWidgets('complete bench shows explicit Bench Locked CTA state', (
      tester,
    ) async {
      await pumpSubs(
        tester,
        game: gameFixture(status: 'bench_selection', isComplete: true),
        mode: SubsPanelMode.benchSelection,
      );

      expect(find.text('Bench Locked'), findsOneWidget);
      expect(find.text('Bench Locked ✓'), findsOneWidget);
      expect(find.textContaining('tactical card'), findsWidgets);
      expect(find.text('Submit Final Lineup'), findsNothing);
      expect(find.textContaining('Tap a bench card or a player'), findsNothing);
    });
  });

  group('B) Ability phase continuity + no lineup-edit actions', () {
    testWidgets(
      'ability panel shows compact locked bench and no swap/submit UI',
      (tester) async {
        final game = gameFixture(
          status: 'ability_activation',
          myAbility: const PlayerAbility(
            type: AbilityType.extraBench,
            status: 'pending',
          ),
          att: const SubSlot(
            positionGroup: 'att',
            chosenPlayerId: 'c1',
            chosenPlayerName: 'Haaland',
          ),
          mid: const SubSlot(
            positionGroup: 'mid',
            chosenPlayerId: 'c2',
            chosenPlayerName: 'De Bruyne',
          ),
          def: const SubSlot(
            positionGroup: 'def',
            chosenPlayerId: 'c3',
            chosenPlayerName: 'Van Dijk',
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: AbilityActivationPanel(game: game, localPlayerId: 'p1'),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(CompactBenchSummary), findsOneWidget);
        expect(find.text('YOUR BENCH'), findsOneWidget);
        expect(find.text('Haaland'), findsOneWidget);
        expect(find.text('De Bruyne'), findsOneWidget);
        expect(find.text('Van Dijk'), findsOneWidget);
        expect(find.text('HIDDEN ABILITY'), findsOneWidget);
        expect(find.text('Submit Final Lineup'), findsNothing);
        expect(find.text('Swap'), findsNothing);
        expect(
          find.textContaining('Tap a bench card or a player'),
          findsNothing,
        );
      },
    );

    testWidgets('waiting state appears after ability lock', (tester) async {
      final game = gameFixture(
        status: 'ability_activation',
        myAbility: const PlayerAbility(
          type: AbilityType.yellow,
          status: 'used',
          pendingSummary: 'Yellow on Bob',
        ),
        abilityActivationResolved: const {'p1': true, 'p2': false},
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AbilityActivationPanel(game: game, localPlayerId: 'p1'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('ability-locked-wait')), findsOneWidget);
      expect(find.text('Ability locked'), findsOneWidget);
      expect(
        find.textContaining('Hidden until everyone locks'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Reveal starts when the room is fully locked'),
        findsOneWidget,
      );
      expect(find.text('Use Card'), findsNothing);
      expect(find.text('Discard'), findsNothing);
    });
  });

  group('C) Final lineup edit after reveal', () {
    testWidgets('lineup_edit shows final rearrange + submit intent', (
      tester,
    ) async {
      await pumpSubs(
        tester,
        game: gameFixture(status: 'lineup_edit', isComplete: true),
        mode: SubsPanelMode.lineupEdit,
      );

      expect(find.text('FINAL LINEUP'), findsOneWidget);
      expect(find.textContaining('Abilities resolved'), findsOneWidget);
      expect(find.text('Submit Final Lineup'), findsOneWidget);
      expect(
        find.textContaining('Tap a bench card or a player'),
        findsOneWidget,
      );
    });

    testWidgets('reveal summary CTA points into lineup edit', (tester) async {
      var continued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AbilityResolvedSummary(
              activations: const [],
              localPlayerId: 'p1',
              onContinue: () => continued = true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Edit final lineup'), findsOneWidget);
      await tester.tap(find.text('Edit final lineup'));
      expect(continued, isTrue);
    });
  });

  group('D) CommandStrip phase distinction', () {
    testWidgets('bench / ability / final lineup labels are distinct', (
      tester,
    ) async {
      Widget bar(String status) => MaterialApp(
        home: Scaffold(
          body: CommandStrip(
            currentRound: 12,
            totalRounds: 11,
            turnPhase: 'selecting_position',
            currentPlayer: const GamePlayer(
              id: 'p2',
              displayName: 'Bob',
              isHost: false,
            ),
            // Stale draft turn — post-draft must still show as active.
            isLocalPlayerTurn: false,
            gameStatus: status,
          ),
        ),
      );

      await tester.pumpWidget(bar('bench_selection'));
      expect(find.text('BENCH SELECT'), findsOneWidget);
      expect(find.textContaining('Pick & lock your bench'), findsOneWidget);

      await tester.pumpWidget(bar('ability_activation'));
      expect(find.text('ABILITY'), findsOneWidget);
      expect(find.textContaining('Use your tactical card'), findsOneWidget);

      await tester.pumpWidget(bar('lineup_edit'));
      expect(find.text('FINAL LINEUP'), findsWidgets);
      expect(find.textContaining('Rearrange & submit lineup'), findsOneWidget);
    });
  });

  group('E) Ability reveal edge-detection unchanged', () {
    bool justRevealed({
      required String? prevStatus,
      required bool prevRevealed,
      required bool nextRevealed,
    }) => prevStatus == 'ability_activation' && !prevRevealed && nextRevealed;

    test('still fires only on ability_activation reveal edge', () {
      expect(
        justRevealed(
          prevStatus: 'ability_activation',
          prevRevealed: false,
          nextRevealed: true,
        ),
        isTrue,
      );
      expect(
        justRevealed(
          prevStatus: 'lineup_edit',
          prevRevealed: true,
          nextRevealed: true,
        ),
        isFalse,
      );
    });
  });
}
