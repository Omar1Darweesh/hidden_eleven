import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/result/widgets/points_breakdown_card.dart';

PlayerResult _resultWithBreakdown(ScoreBreakdown? breakdown, {int? score}) {
  return PlayerResult(
    playerId: 'p1',
    displayName: 'Alice',
    rank: 1,
    score: score ?? breakdown?.finalScore.round(),
    scoreBreakdown: breakdown,
  );
}

Future<void> _pump(
  WidgetTester tester,
  PlayerResult result, {
  double width = 400,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: PointsBreakdownCard(result: result),
        ),
      ),
    ),
  );
  // Stage 3 / R4: the Final total counts up once on mount, so these
  // assertions — which are all about the *settled* value — wait for it.
  // The labels and per-line values are never animated and are already
  // present before this settles.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'renders each ScoreBreakdownLine with its label and signed value',
    (tester) async {
      const breakdown = ScoreBreakdown(
        defAvg: 70,
        midAvg: 80,
        atkAvg: 90,
        linesTotal: 240,
        userChemTotal: 5,
        cardChemTotal: 6,
        finalScore: 251,
        scoringConfigVersion: 1,
        lines: [
          ScoreBreakdownLine(
            key: 'def_avg',
            label: 'Defence average',
            amount: 70,
          ),
          ScoreBreakdownLine(
            key: 'mid_avg',
            label: 'Midfield average',
            amount: 80,
          ),
          ScoreBreakdownLine(
            key: 'atk_avg',
            label: 'Attack average',
            amount: 90,
          ),
          ScoreBreakdownLine(
            key: 'user_chem',
            label: 'Challenges completed',
            amount: 5,
            detail: '1 of 5 challenges satisfied',
          ),
          ScoreBreakdownLine(
            key: 'card_chem',
            label: 'Card chemistry',
            amount: 6,
          ),
        ],
      );

      await _pump(tester, _resultWithBreakdown(breakdown));

      expect(find.text('Defence average'), findsOneWidget);
      expect(find.text('+70'), findsOneWidget);
      expect(find.text('Midfield average'), findsOneWidget);
      expect(find.text('+80'), findsOneWidget);
      expect(find.text('Attack average'), findsOneWidget);
      expect(find.text('+90'), findsOneWidget);
      expect(find.text('Challenges completed'), findsOneWidget);
      expect(find.text('+5'), findsOneWidget);
      expect(find.text('1 of 5 challenges satisfied'), findsOneWidget);
      expect(find.text('Card chemistry'), findsOneWidget);
      expect(find.text('+6'), findsOneWidget);
      // Old collapsed line must NOT appear once lines[] is present.
      expect(find.text('Base squad score'), findsNothing);
    },
  );

  testWidgets(
    'a negative amount (penalty) renders as a signed negative number',
    (tester) async {
      const breakdown = ScoreBreakdown(
        defAvg: 70,
        midAvg: 70,
        atkAvg: 70,
        linesTotal: 210,
        userChemTotal: 0,
        cardChemTotal: 0,
        yellowPenalty: 20,
        finalScore: 190,
        scoringConfigVersion: 1,
        lines: [
          ScoreBreakdownLine(
            key: 'def_avg',
            label: 'Defence average',
            amount: 70,
          ),
          ScoreBreakdownLine(
            key: 'yellow_penalty',
            label: 'Yellow card penalty',
            amount: -20,
          ),
        ],
      );

      await _pump(tester, _resultWithBreakdown(breakdown));

      expect(find.text('-20'), findsOneWidget);
    },
  );

  testWidgets('a zero-amount informational line renders as an em dash', (
    tester,
  ) async {
    const breakdown = ScoreBreakdown(
      defAvg: 70,
      midAvg: 70,
      atkAvg: 70,
      linesTotal: 210,
      userChemTotal: 0,
      cardChemTotal: 0,
      redApplied: true,
      finalScore: 210,
      scoringConfigVersion: 1,
      lines: [
        ScoreBreakdownLine(
          key: 'red_applied',
          label: 'Red card applied (chemistry nullified)',
          amount: 0,
        ),
      ],
    );

    await _pump(tester, _resultWithBreakdown(breakdown));

    expect(find.text('—'), findsOneWidget);
  });

  testWidgets(
    'empty lines[] falls back to the collapsed Base squad score line',
    (tester) async {
      const breakdown = ScoreBreakdown(
        defAvg: 70,
        midAvg: 80,
        atkAvg: 90,
        linesTotal: 240,
        userChemTotal: 0,
        cardChemTotal: 0,
        finalScore: 240,
        // lines defaults to const [] — simulates a payload from before Phase A.
      );

      await _pump(tester, _resultWithBreakdown(breakdown));

      expect(find.text('Base squad score'), findsOneWidget);
      // Appears twice: the collapsed line's own value AND the Final total
      // (they're numerically equal here since there are no bonus lines).
      expect(find.text('240'), findsNWidgets(2));
    },
  );

  testWidgets(
    'a null scoreBreakdown still renders via the score-only fallback',
    (tester) async {
      await _pump(tester, _resultWithBreakdown(null, score: 55));

      expect(find.text('Base squad score'), findsOneWidget);
      expect(find.text('55'), findsNWidgets(2));
    },
  );

  testWidgets(
    'a full line set with a long detail string does not overflow at a narrow width',
    (tester) async {
      const breakdown = ScoreBreakdown(
        defAvg: 70,
        midAvg: 80,
        atkAvg: 90,
        linesTotal: 240,
        userChemTotal: 5,
        cardChemTotal: 12,
        lineLeaderBonus: 6,
        captainBonus: 4,
        yellowPenalty: 20,
        redApplied: true,
        finalScore: 337,
        scoringConfigVersion: 1,
        lines: [
          ScoreBreakdownLine(
            key: 'def_avg',
            label: 'Defence average',
            amount: 70,
          ),
          ScoreBreakdownLine(
            key: 'mid_avg',
            label: 'Midfield average',
            amount: 80,
          ),
          ScoreBreakdownLine(
            key: 'atk_avg',
            label: 'Attack average',
            amount: 90,
          ),
          ScoreBreakdownLine(
            key: 'user_chem',
            label: 'Challenges completed',
            amount: 5,
            detail:
                'A genuinely very long explanation of exactly which challenges '
                'were satisfied and why, long enough to wrap onto more than '
                'one line on a narrow phone screen.',
          ),
          ScoreBreakdownLine(
            key: 'card_chem',
            label: 'Card chemistry',
            amount: 12,
          ),
          ScoreBreakdownLine(
            key: 'line_leader',
            label: 'Line Leader bonus',
            amount: 6,
          ),
          ScoreBreakdownLine(key: 'captain', label: 'Captain bonus', amount: 4),
          ScoreBreakdownLine(
            key: 'yellow_penalty',
            label: 'Yellow card penalty',
            amount: -20,
          ),
          ScoreBreakdownLine(
            key: 'red_applied',
            label: 'Red card applied (chemistry nullified)',
            amount: 0,
          ),
        ],
      );

      await _pump(tester, _resultWithBreakdown(breakdown), width: 320);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
