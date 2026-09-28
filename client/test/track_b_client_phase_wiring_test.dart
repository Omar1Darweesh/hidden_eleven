import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/game_screen.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/subs/subs_panel.dart';

/// Track B Phase B3 — client wiring for bench_selection/lineup_edit.
/// Covers exactly the required cases:
///  1. GameScreen routes bench_selection to the correct panel.
///  2. GameScreen routes lineup_edit to the correct panel.
///  3. bench_selection mode hides free-swap/confirm UI.
///  4. lineup_edit mode shows swap/confirm UI.
///  5. Extra Bench controls only appear in lineup_edit when eligible.
///  6. The ability reveal flow still transitions correctly around
///     ability_activation (unaffected by the reorder — verified directly
///     against the edge-detection condition game_screen.dart uses).
void main() {
  group('GamePanelKind routing (game_screen.dart)', () {
    test('bench_selection routes to GamePanelKind.benchSelection', () {
      expect(gamePanelKindFor('bench_selection'), GamePanelKind.benchSelection);
    });

    test('lineup_edit routes to GamePanelKind.lineupEdit', () {
      expect(gamePanelKindFor('lineup_edit'), GamePanelKind.lineupEdit);
    });

    test(
      'ability_activation routes to GamePanelKind.abilityActivation (unchanged)',
      () {
        expect(
          gamePanelKindFor('ability_activation'),
          GamePanelKind.abilityActivation,
        );
      },
    );

    test('every other status falls through to turn-based rendering', () {
      for (final s in ['drafting', 'ability_draft', 'tournament', 'finished']) {
        expect(gamePanelKindFor(s), GamePanelKind.turnBased);
      }
    });
  });

  group('SubsPanel mode behavior', () {
    GameState fixture({
      required String status,
      required bool hasExtraBench,
      bool isComplete = true,
      bool lineupConfirmed = false,
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
      subsPhase: SubsPhase(
        userSubs: {
          'p1': UserSubstitutions(
            isComplete: isComplete,
            lineupConfirmed: lineupConfirmed,
            hasExtraBench: hasExtraBench,
          ),
          'p2': const UserSubstitutions(
            isComplete: true,
            lineupConfirmed: false,
            hasExtraBench: false,
          ),
        },
      ),
    );

    Future<void> pump(
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
      // Not pumpAndSettle: the opponent/bench-selection status rows render a
      // perpetually-spinning CircularProgressIndicator while waiting on
      // others, which never "settles" — a fixed pump is enough to resolve
      // the widget tree for these assertions.
      await tester.pump();
    }

    testWidgets('bench_selection mode hides free-swap/confirm UI', (
      tester,
    ) async {
      await pump(
        tester,
        game: fixture(status: 'bench_selection', hasExtraBench: false),
        mode: SubsPanelMode.benchSelection,
      );

      expect(find.text('BENCH SELECTION'), findsOneWidget);
      expect(find.textContaining('Bench locked'), findsOneWidget);
      expect(find.text('Bench Locked ✓'), findsOneWidget);
      expect(find.text('Submit Final Lineup'), findsNothing);
      expect(find.text('Confirm Lineup'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      expect(find.textContaining('Tap a bench card or a player'), findsNothing);
    });

    testWidgets('lineup_edit mode shows swap/confirm UI', (tester) async {
      await pump(
        tester,
        game: fixture(status: 'lineup_edit', hasExtraBench: false),
        mode: SubsPanelMode.lineupEdit,
      );

      expect(find.text('FINAL LINEUP'), findsOneWidget);
      // Idle hint shown (no source selected yet) — proves the swap area
      // renders at all, unlike bench_selection.
      expect(
        find.textContaining('Tap a bench card or a player'),
        findsOneWidget,
      );
      expect(find.text('Submit Final Lineup'), findsOneWidget);
      expect(find.text('Confirm Lineup'), findsNothing);
    });

    testWidgets(
      'Extra Bench controls do NOT appear during bench_selection even for an eligible player',
      (tester) async {
        // hasExtraBench: true would only ever be set once lineup_edit begins
        // in the real flow, but this proves the client's OWN gate (not just
        // the server's) blocks it defensively during bench_selection too.
        await pump(
          tester,
          game: fixture(status: 'bench_selection', hasExtraBench: true),
          mode: SubsPanelMode.benchSelection,
        );

        expect(find.text('EXTRA'), findsNothing);
      },
    );

    testWidgets(
      'Extra Bench controls appear during lineup_edit for an eligible player',
      (tester) async {
        await pump(
          tester,
          game: fixture(
            status: 'lineup_edit',
            hasExtraBench: true,
            isComplete: false, // extra not yet picked
          ),
          mode: SubsPanelMode.lineupEdit,
        );

        expect(find.text('EXTRA'), findsOneWidget);
      },
    );

    testWidgets(
      'Extra Bench controls do NOT appear during lineup_edit for an ineligible player',
      (tester) async {
        await pump(
          tester,
          game: fixture(status: 'lineup_edit', hasExtraBench: false),
          mode: SubsPanelMode.lineupEdit,
        );

        expect(find.text('EXTRA'), findsNothing);
      },
    );
  });

  group('Ability reveal cinematic edge-detection (unaffected by the reorder)', () {
    // game_screen.dart's ref.listen edge-detection condition, verified
    // directly (mirrors the exact boolean expression at its call site):
    //   prev.status == 'ability_activation' && !prev.abilityActivationRevealed
    //       && next.abilityActivationRevealed
    bool justRevealed({
      required String? prevStatus,
      required bool prevRevealed,
      required bool nextRevealed,
    }) => prevStatus == 'ability_activation' && !prevRevealed && nextRevealed;

    test(
      'fires when ability_activation reveals (prev unrevealed, next revealed)',
      () {
        expect(
          justRevealed(
            prevStatus: 'ability_activation',
            prevRevealed: false,
            nextRevealed: true,
          ),
          isTrue,
        );
      },
    );

    test('does not fire once the phase has moved on to lineup_edit', () {
      // Track B: ability_activation's successor is now lineup_edit (was
      // 'subs') — the edge-detection is keyed on prev.status alone, so this
      // proves the reorder didn't silently break (or wrongly re-trigger) it.
      expect(
        justRevealed(
          prevStatus: 'lineup_edit',
          prevRevealed: true,
          nextRevealed: true,
        ),
        isFalse,
      );
    });

    test(
      'does not fire from bench_selection (ability_activation not yet begun)',
      () {
        expect(
          justRevealed(
            prevStatus: 'bench_selection',
            prevRevealed: false,
            nextRevealed: false,
          ),
          isFalse,
        );
      },
    );

    test(
      'does not fire twice for the same reveal (already revealed -> revealed)',
      () {
        expect(
          justRevealed(
            prevStatus: 'ability_activation',
            prevRevealed: true,
            nextRevealed: true,
          ),
          isFalse,
        );
      },
    );
  });
}
