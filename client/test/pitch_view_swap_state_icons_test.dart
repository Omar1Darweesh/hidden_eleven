import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/pitch_view.dart';

/// Phase 5: the subs-swap ring recolor (green/amber -> violet/gold) must not
/// leave any state relying on color alone. PitchView already pairs each
/// swap-flow state with a distinct icon on the filled card — this locks that
/// pairing in so a future color tweak can't silently drop it.
void main() {
  PitchSlot filledSlot({
    required int index,
    String basePositionType = 'ST',
    List<String> naturalPositions = const ['ST'],
  }) => PitchSlot(
    index: index,
    label: 'ST',
    basePositionType: basePositionType,
    cardPlayerName: 'Test Player',
    cardRating: 80,
    cardId: 'c$index',
    cardNaturalPositions: naturalPositions,
  );

  Widget harness(PitchView view) =>
      MaterialApp(home: Scaffold(body: SizedBox(width: 400, child: view)));

  testWidgets('the swap source shows a check icon, not just a colored ring', (
    tester,
  ) async {
    final slots = [filledSlot(index: 0)];
    await tester.pumpWidget(
      harness(
        PitchView(
          slots: slots,
          roundSlotIndex: null,
          isInteractiveOwner: false,
          turnPhase: 'selecting_position',
          subsSourceSlotIndex: 0,
          subsSelectionActive: true,
          onSubsSlotTap: (_) {},
        ),
      ),
    );

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets(
    'a valid unselected target shows a swap icon, not just a colored ring',
    (tester) async {
      final slots = [filledSlot(index: 0), filledSlot(index: 1)];
      await tester.pumpWidget(
        harness(
          PitchView(
            slots: slots,
            roundSlotIndex: null,
            isInteractiveOwner: false,
            turnPhase: 'selecting_position',
            subsSourceSlotIndex: 0,
            subsTargetSlotIndices: const {1},
            subsSelectionActive: true,
            onSubsSlotTap: (_) {},
          ),
        ),
      );

      expect(find.byIcon(Icons.swap_horiz_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'a swapped-in sub shows an undo icon, not just a colored ring',
    (tester) async {
      final slots = [filledSlot(index: 0)];
      await tester.pumpWidget(
        harness(
          PitchView(
            slots: slots,
            roundSlotIndex: null,
            isInteractiveOwner: false,
            turnPhase: 'selecting_position',
            subsSwappedSlotIndices: const {0},
            onSubsSlotTap: (_) {},
          ),
        ),
      );

      expect(find.byIcon(Icons.undo_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'an out-of-position (invalid) card shows a warning icon, not just red text',
    (tester) async {
      // Natural positions don't include the slot's own basePositionType, so
      // cardFitsSlot is false.
      final slots = [
        filledSlot(index: 0, basePositionType: 'ST', naturalPositions: ['GK']),
      ];
      await tester.pumpWidget(
        harness(
          PitchView(
            slots: slots,
            roundSlotIndex: null,
            isInteractiveOwner: false,
            turnPhase: 'selecting_position',
            highlightOutOfPosition: true,
            onSubsSlotTap: (_) {},
          ),
        ),
      );

      expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
    },
  );
}
