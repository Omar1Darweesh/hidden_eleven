import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/features/game/game_screen.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/pitch_view.dart';
import 'package:hidden_eleven/features/subs/sub_swap_selection.dart';

/// Regression for the mobile pitch bug: on a phone the portrait pitch was
/// fitted purely by the (small) available height, collapsing its width to
/// ~130px, at which the 11 position cards overlapped into an unreadable,
/// un-tappable cluster. GamePitchStage now enforces a legibility floor and
/// scrolls vertically instead of shrinking below it.
void main() {
  List<PitchSlot> elevenSlots() {
    const labels = [
      'GK',
      'LB',
      'CB',
      'CB',
      'RB',
      'CM',
      'CM',
      'CAM',
      'LW',
      'ST',
      'RW',
    ];
    return [
      for (var i = 0; i < labels.length; i++)
        PitchSlot(index: i, label: labels[i], basePositionType: labels[i]),
    ];
  }

  GameState draftingGame() => GameState(
    sessionId: 's1',
    roomCode: 'RM1',
    formationName: '4-3-3',
    players: const [GamePlayer(id: 'p1', displayName: 'You', isHost: true)],
    pitches: const {},
    baseTurnOrder: const ['p1'],
    currentRound: 2,
    totalRounds: 11,
    currentTurnOrder: const ['p1'],
    currentTurnIndex: 0,
    currentRoundSlotIndex: null,
    turn: const GameTurn(
      turnId: 't1',
      phase: 'selecting_position',
      activePlayerId: 'p1',
    ),
    status: 'drafting',
    isFinished: false,
  );

  Widget harness({required Size box}) => ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: box.width,
            height: box.height,
            child: GamePitchStage(
              game: draftingGame(),
              orderedIds: const ['p1'],
              localPlayerId: 'p1',
              viewedPlayerId: 'p1',
              viewedSlots: elevenSlots(),
              isMyTurn: true,
              tabIndex: 0,
              subSwap: SubSwapView.none,
              swappedSubSlots: const {},
              onSubsPitchSlotTap: (_) {},
              onTabChanged: (_) {},
              onSlotTap: (_) {},
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'height-starved mobile pitch stays at the legible width floor and scrolls',
    (tester) async {
      // A typical phone body region left for the pitch after the status bar and
      // action sheet: full-ish width, but short height.
      await tester.pumpWidget(harness(box: const Size(343, 250)));
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'must not overflow');

      final pitchSize = tester.getSize(find.byType(PitchView));
      // The whole point: never collapse below the legible floor (300).
      expect(
        pitchSize.width,
        greaterThanOrEqualTo(300.0),
        reason: 'pitch must stay legible, not shrink to fit the short height',
      );
      // Portrait ratio preserved.
      expect(pitchSize.height / pitchSize.width, closeTo(1 / 0.625, 0.02));
      // Too tall for 250px → must be scrollable rather than clipped/squeezed.
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    },
  );

  testWidgets('tall viewport shows the whole pitch without scrolling', (
    tester,
  ) async {
    // Plenty of height — the pitch fits fully and should NOT force a scroll.
    await tester.pumpWidget(harness(box: const Size(343, 620)));
    await tester.pump();

    expect(tester.takeException(), isNull, reason: 'must not overflow');

    final pitchSize = tester.getSize(find.byType(PitchView));
    expect(pitchSize.width, greaterThanOrEqualTo(300.0));
    expect(pitchSize.height, lessThanOrEqualTo(620.0));
    // The ratio must hold here too. This previously could not be trusted: a
    // SizedBox taller than its parent silently resolved to the parent's
    // height, squashing the pitch without raising an overflow error.
    expect(pitchSize.height / pitchSize.width, closeTo(1 / 0.625, 0.02));
    expect(find.byType(SingleChildScrollView), findsNothing);
  });
}
