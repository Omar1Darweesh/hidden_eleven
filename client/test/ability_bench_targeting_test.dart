import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/ability_activation_screen.dart';

GameState _activationGame({
  required PlayerAbility myAbility,
  SubSlot? localMid,
  SubSlot? rivalMid,
}) => GameState(
  sessionId: 's1',
  roomCode: 'RM1',
  formationName: '4-3-3',
  players: const [
    GamePlayer(id: 'p1', displayName: 'Alice', isHost: true),
    GamePlayer(id: 'p2', displayName: 'Bob', isHost: false),
  ],
  pitches: {
    'p1': PlayerPitch(
      playerId: 'p1',
      filledCount: 1,
      slots: [
        const PitchSlot(
          index: 0,
          label: 'ST',
          basePositionType: 'ST',
          cardPlayerName: 'Alice ST',
          cardRating: 80,
          cardId: 'a-st',
          cardNaturalPositions: ['ST'],
        ),
        const PitchSlot(
          index: 1,
          label: 'CM',
          basePositionType: 'CM',
          cardPlayerName: 'Alice CM',
          cardRating: 78,
          cardId: 'a-cm',
          cardNaturalPositions: ['CM'],
        ),
      ],
    ),
    'p2': PlayerPitch(
      playerId: 'p2',
      filledCount: 1,
      slots: [
        const PitchSlot(
          index: 0,
          label: 'ST',
          basePositionType: 'ST',
          cardPlayerName: 'Bob ST',
          cardRating: 81,
          cardId: 'b-st',
          cardNaturalPositions: ['ST'],
        ),
        const PitchSlot(
          index: 1,
          label: 'CM',
          basePositionType: 'CM',
          cardPlayerName: 'Bob CM',
          cardRating: 79,
          cardId: 'b-cm',
          cardNaturalPositions: ['CM'],
        ),
      ],
    ),
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
  status: 'ability_activation',
  isFinished: false,
  myAbility: myAbility,
  abilityActivationResolved: const {'p1': false, 'p2': false},
  subsPhase: SubsPhase(
    userSubs: {
      'p1': UserSubstitutions(
        isComplete: true,
        lineupConfirmed: false,
        mid: localMid,
      ),
      'p2': UserSubstitutions(
        isComplete: true,
        lineupConfirmed: false,
        mid: rivalMid,
      ),
    },
  ),
);

const _midBench = SubSlot(
  positionGroup: 'mid',
  chosenPlayerId: 'bench-cm',
  chosenPlayerName: 'Bench CM',
  chosenPlayerRating: 77,
  chosenPlayerPosition: 'CM',
  benchedPlayerId: 'bench-cm',
  benchedPlayerName: 'Bench CM',
  benchedPlayerRating: 77,
  benchedPlayerPosition: 'CM',
);

void main() {
  setUp(() {
    AbilityMeta.debugOverrideConfigured(null);
    ChemistryVars.debugOverrideValues(null);
  });

  Future<void> pumpPanel(WidgetTester tester, GameState game) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AbilityActivationPanel(game: game, localPlayerId: 'p1'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('captain shows starting XI only — no bench target chips', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      _activationGame(
        myAbility: const PlayerAbility(
          type: AbilityType.captain,
          status: 'pending',
        ),
        localMid: _midBench,
      ),
    );

    // _SectionLabel uppercases its text.
    expect(find.text('YOUR STARTING XI'), findsOneWidget);
    expect(find.text('Alice ST'), findsOneWidget);
    // Picker bench chips use "· bench" subtitle; captain must not offer them.
    expect(find.textContaining('· bench'), findsNothing);
  });

  testWidgets('coach shows own bench chips', (tester) async {
    await pumpPanel(
      tester,
      _activationGame(
        myAbility: const PlayerAbility(
          type: AbilityType.coach,
          status: 'pending',
        ),
        localMid: _midBench,
      ),
    );

    // CompactBenchSummary + coach picker section both title "YOUR BENCH".
    expect(find.text('YOUR BENCH'), findsWidgets);
    expect(find.text('Bench CM'), findsWidgets);
    expect(find.textContaining('· bench'), findsOneWidget);
  });

  testWidgets('red shows rival bench after rival is selected', (tester) async {
    await pumpPanel(
      tester,
      _activationGame(
        myAbility: const PlayerAbility(
          type: AbilityType.red,
          status: 'pending',
        ),
        rivalMid: _midBench,
      ),
    );

    // Rival picker chip + lock-status row both show "Bob".
    await tester.tap(find.text('Bob').first);
    await tester.pump();

    // Apostrophe in section labels is U+2019 (’).
    expect(find.text('BOB\u2019S BENCH'), findsOneWidget);
    expect(find.text('Bench CM'), findsOneWidget);
    expect(find.text('BOB\u2019S STARTING XI'), findsOneWidget);
    expect(find.textContaining('· bench'), findsOneWidget);
  });

  testWidgets('sub includes rival same-position bench options', (tester) async {
    await pumpPanel(
      tester,
      _activationGame(
        myAbility: const PlayerAbility(
          type: AbilityType.sub,
          status: 'pending',
        ),
        rivalMid: _midBench,
      ),
    );

    await tester.tap(find.text('Alice CM'));
    await tester.pump();

    expect(find.textContaining('· bench'), findsOneWidget);
    expect(find.textContaining('Bench CM'), findsOneWidget);
  });
}
