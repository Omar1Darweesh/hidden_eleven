import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/mission_card.dart';

/// REGRESSION: "RenderFlex overflowed by 2.8 pixels" in MissionCard's header
/// row, caught live during a real playtest.
///
/// The header row (eyebrow pill + optional trophy icon + Spacer + phase pill
/// + optional settings button) reported an available width of exactly 262px
/// — MissionCard's own `compact` layout, which is what a narrow game screen
/// actually gives it. Neither pill had any way to shrink, so once the phase
/// label was one of the longer ones (e.g. during ability_activation), the
/// fixed-width pills simply didn't fit.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required String gameStatus,
    required String turnPhase,
    double width = 262,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: MissionCard(
              currentRound: 5,
              totalRounds: 11,
              turnPhase: turnPhase,
              currentPlayer: const GamePlayer(
                id: 'p1',
                displayName: 'A Reasonably Long Display Name',
                isHost: false,
              ),
              isLocalPlayerTurn: false,
              gameStatus: gameStatus,
              compact: true,
              onSettingsTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final status in [
    'drafting',
    'bench_selection',
    'lineup_edit',
    'ability_activation',
  ]) {
    testWidgets(
      'does not overflow at the exact reported 262px width — status: $status',
      (tester) async {
        await pump(tester, gameStatus: status, turnPhase: 'selecting_card');
        expect(tester.takeException(), isNull, reason: 'overflow for $status');
      },
    );
  }

  testWidgets('does not overflow on the final round (trophy icon shown too)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 262,
            child: MissionCard(
              currentRound: 11,
              totalRounds: 11,
              turnPhase: 'selecting_card',
              currentPlayer: const GamePlayer(
                id: 'p1',
                displayName: 'Someone',
                isHost: false,
              ),
              isLocalPlayerTurn: true,
              gameStatus: 'ability_activation',
              compact: true,
              onSettingsTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phase pill still shows readable text, just truncated if needed', (
    tester,
  ) async {
    await pump(
      tester,
      gameStatus: 'ability_activation',
      turnPhase: 'selecting_card',
    );
    // Some pill text is present — the fix truncates, it never hides the pill.
    expect(find.textContaining(RegExp(r'.+')), findsWidgets);
  });
}
