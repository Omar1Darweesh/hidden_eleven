import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/widgets/ability_activation_screen.dart';
import 'package:hidden_eleven/features/game/widgets/ability_resolved_summary.dart';

GameState _activationGameState({
  AbilityType type = AbilityType.yellow,
  List<GamePlayer> players = const [
    GamePlayer(id: 'p1', displayName: 'Alice', isHost: true),
    GamePlayer(id: 'p2', displayName: 'Bob', isHost: false),
  ],
}) => GameState(
  sessionId: 's1',
  roomCode: 'RM1',
  formationName: '4-3-3',
  players: players,
  pitches: const {},
  baseTurnOrder: players.map((p) => p.id).toList(),
  currentRound: 12,
  totalRounds: 11,
  currentTurnOrder: players.map((p) => p.id).toList(),
  currentTurnIndex: 0,
  currentRoundSlotIndex: null,
  turn: const GameTurn(
    turnId: 't1',
    phase: 'selecting_position',
    activePlayerId: '',
  ),
  status: 'ability_activation',
  isFinished: false,
  myAbility: PlayerAbility(type: type, status: 'pending'),
);

void main() {
  setUp(() {
    AbilityMeta.debugOverrideConfigured(null);
    ChemistryVars.debugOverrideValues(null);
  });

  Future<void> pumpPanel(WidgetTester tester, {GameState? game}) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AbilityActivationPanel(
              game: game ?? _activationGameState(),
              localPlayerId: 'p1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'yellow-card instruction shows the resolved penalty for a mocked non-default yellowPenalty',
    (tester) async {
      ChemistryVars.debugOverrideValues({'yellowPenalty': 55});
      await pumpPanel(tester);

      expect(find.text('Pick a rival to dock 55 points.'), findsOneWidget);
      expect(find.text('Pick a rival to dock 20 points.'), findsNothing);
    },
  );

  testWidgets('falls back to the v1 default before any config is loaded', (
    tester,
  ) async {
    await pumpPanel(tester);

    expect(find.text('Pick a rival to dock 20 points.'), findsOneWidget);
  });

  testWidgets(
    'a maximal (3-digit) resolved value does not overflow the activation card',
    (tester) async {
      ChemistryVars.debugOverrideValues({'yellowPenalty': 999});
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                child: AbilityActivationPanel(
                  game: _activationGameState(),
                  localPlayerId: 'p1',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Pick a rival to dock 999 points.'), findsOneWidget);
    },
  );

  group('Protection — self-targeting, nothing to pick', () {
    testWidgets('shows its instruction and no target picker at all', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        game: _activationGameState(type: AbilityType.protect),
      );

      expect(
        find.textContaining('Shields you from every hostile ability'),
        findsOneWidget,
      );
      // No rival grid — protection targets nobody.
      expect(find.text('Rivals'), findsNothing);
      expect(find.text('RIVAL TO DISABLE'), findsNothing);
    });

    testWidgets('Use Card is enabled immediately, with no selection required', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        game: _activationGameState(type: AbilityType.protect),
      );

      final useButton = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Use Card'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(useButton.onPressed, isNotNull);
    });
  });

  group('Freeze — targets a rival, same shape as Yellow', () {
    testWidgets('shows the rival picker and its instruction', (tester) async {
      await pumpPanel(
        tester,
        game: _activationGameState(type: AbilityType.freeze),
      );

      expect(
        find.text('Pick a rival to disable their ability entirely.'),
        findsOneWidget,
      );
      expect(find.text('RIVAL TO DISABLE'), findsOneWidget);
      expect(find.text('Bob'), findsWidgets);
    });

    testWidgets('Use Card stays disabled until a rival is picked', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        game: _activationGameState(type: AbilityType.freeze),
      );

      ElevatedButton useButton() => tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Use Card'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(useButton().onPressed, isNull);

      await tester.tap(find.text('Bob').first);
      await tester.pumpAndSettle();

      expect(useButton().onPressed, isNotNull);
    });

    testWidgets('never offers the caster as their own freeze target', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        game: _activationGameState(type: AbilityType.freeze),
      );

      // The rival ("Bob") appears in the target grid; "Alice" — the local
      // player, who cannot freeze herself — never does.
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsWidgets);
    });
  });

  group('Ability reveal — honest fizzle text for frozen/blocked outcomes', () {
    // Previously recognised only the literal word "fizzled" for the muted/
    // italic "had no effect" treatment. The server's new frozen/blocked
    // outcomes use different wording and were rendered as if they had
    // succeeded — a player would see "Protection — frozen by an opponent"
    // styled exactly like a successful activation.
    Future<Text> summaryTextFor(WidgetTester tester, String summary) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AbilityResolvedSummary(
              activations: [
                AbilityActivation(
                  byPlayerId: 'p2',
                  byName: 'Bob',
                  type: AbilityType.protect,
                  summary: summary,
                ),
              ],
              localPlayerId: 'p1',
              onContinue: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.widget<Text>(find.text(summary));
    }

    testWidgets('a frozen outcome gets the muted/italic "no effect" style', (
      tester,
    ) async {
      final text = await summaryTextFor(
        tester,
        'Protection — frozen by an opponent',
      );
      expect(text.style?.fontStyle, FontStyle.italic);
      expect(text.style?.color, HETheme.pfTextMuted);
    });

    testWidgets(
      'a blocked-by-Protection outcome gets the same "no effect" style',
      (tester) async {
        final text = await summaryTextFor(
          tester,
          'Red Card on J. Stones (Alice) — blocked by Protection',
        );
        expect(text.style?.fontStyle, FontStyle.italic);
        expect(text.style?.color, HETheme.pfTextMuted);
      },
    );

    testWidgets('a genuinely successful activation keeps its normal style', (
      tester,
    ) async {
      final text = await summaryTextFor(tester, 'Captain on Van de Ven');
      expect(text.style?.fontStyle, FontStyle.normal);
      expect(text.style?.color, HETheme.pfTextSecondary);
    });
  });
}
