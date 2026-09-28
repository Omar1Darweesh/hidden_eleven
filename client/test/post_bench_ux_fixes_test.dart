import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/compact_bench_summary.dart';
import 'package:hidden_eleven/features/game/widgets/command_strip.dart';
import 'package:hidden_eleven/features/game/widgets/pitch_view.dart';
import 'package:hidden_eleven/features/subs/subs_panel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('chemBonusBadgeColor', () {
    // Phase 5: centralized onto HETheme.pf* tokens (was locally-hardcoded
    // hex) — asserting against the token rather than a hex literal so this
    // test doesn't drift from the app's own source of truth.
    test('valid chemistry stays green', () {
      expect(
        chemBonusBadgeColor(outOfPosition: false, captain: false),
        HETheme.pfSuccess,
      );
    });

    test('captain stays gold when in position', () {
      expect(
        chemBonusBadgeColor(outOfPosition: false, captain: true),
        HETheme.pfGold,
      );
    });

    test('out-of-position uses danger red (overrides captain gold)', () {
      expect(
        chemBonusBadgeColor(outOfPosition: true, captain: false),
        HETheme.pfDanger,
      );
      expect(
        chemBonusBadgeColor(outOfPosition: true, captain: true),
        HETheme.pfDanger,
      );
    });
  });

  group('bench / lineup phase icons', () {
    testWidgets('bench_selection PanelHeader uses event_seat icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SubsPanel(
                game: GameState(
                  sessionId: 's1',
                  roomCode: 'RM1',
                  formationName: '4-3-3',
                  players: const [
                    GamePlayer(id: 'p1', displayName: 'A', isHost: true),
                  ],
                  pitches: const {},
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
                  status: 'bench_selection',
                  isFinished: false,
                  subsPhase: const SubsPhase(
                    userSubs: {
                      'p1': UserSubstitutions(
                        isComplete: false,
                        lineupConfirmed: false,
                      ),
                    },
                  ),
                ),
                localId: 'p1',
                mode: SubsPanelMode.benchSelection,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.event_seat_rounded), findsOneWidget);
      expect(
        find.byIcon(Icons.airline_seat_recline_extra_rounded),
        findsNothing,
      );
    });

    testWidgets('CommandStrip uses event_seat for bench_selection', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CommandStrip(
              currentRound: 12,
              totalRounds: 11,
              turnPhase: 'selecting_position',
              currentPlayer: null,
              isLocalPlayerTurn: true,
              gameStatus: 'bench_selection',
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.event_seat_rounded), findsOneWidget);
    });
  });

  group('CompactBenchSummary details tap', () {
    testWidgets('tapping a locked bench chip opens card details (no edit)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompactBenchSummary(
              subs: const UserSubstitutions(
                isComplete: true,
                lineupConfirmed: false,
                att: SubSlot(
                  positionGroup: 'att',
                  chosenPlayerId: 'c1',
                  chosenPlayerName: 'Haaland',
                  chosenPlayerRating: 91,
                  chosenPlayerPosition: 'ST',
                  benchedPlayerId: 'c1',
                  benchedPlayerName: 'Haaland',
                  benchedPlayerRating: 91,
                  benchedPlayerPosition: 'ST',
                  benchedPace: 89,
                  benchedShooting: 91,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Haaland'), findsOneWidget);
      await tester.tap(find.text('Haaland'));
      await tester.pump(); // dialog open (no animation)

      // Shared details modal — name appears in the dialog too.
      expect(find.text('Haaland'), findsWidgets);
      // Informational only: no pick/confirm action from this strip.
      expect(find.text('Pick'), findsNothing);
      expect(find.text('Swap'), findsNothing);
    });

    testWidgets('empty chip is not tappable', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompactBenchSummary(
              subs: UserSubstitutions(isComplete: true, lineupConfirmed: false),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('—').first);
      await tester.pump();
      // No dialog — still just the strip.
      expect(find.text('YOUR BENCH'), findsOneWidget);
    });
  });
}
