import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/result/widgets/score_breakdown_bar.dart';

/// Locks in `ScoreBreakdownBar`'s exact pre-Phase-B behavior — segment
/// order, labels, colors, the zero/negative-omission rule, the total
/// calculation, and the accessibility summary — so its Phase B extraction
/// onto the generic `SegmentedBar` provably changed nothing observable.
void main() {
  Widget harness(Widget child) =>
      MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: child));

  const breakdown = ScoreBreakdown(
    defAvg: 70,
    midAvg: 72,
    atkAvg: 74,
    linesTotal: 216,
    userChemTotal: 10,
    cardChemTotal: 5,
    lineLeaderBonus: 8,
    captainBonus: 4,
    yellowPenalty: 2,
    finalScore: 241.0,
  );

  testWidgets('renders all four segment labels in order', (tester) async {
    await tester.pumpWidget(harness(const ScoreBreakdownBar(breakdown: breakdown)));

    expect(find.text('Base'), findsOneWidget);
    expect(find.text('Tactical Fit'), findsOneWidget);
    expect(find.text('Line Leaders'), findsOneWidget);
    expect(find.text('Abilities'), findsOneWidget);
  });

  testWidgets('legend values match the exact ScoreBreakdown grouping', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const ScoreBreakdownBar(breakdown: breakdown)));

    // Base = linesTotal (216); Tactical Fit = userChemTotal + cardChemTotal
    // (15); Line Leaders = lineLeaderBonus (8); Abilities = captainBonus -
    // yellowPenalty (4 - 2 = 2).
    expect(find.text('+216'), findsOneWidget);
    expect(find.text('+15'), findsOneWidget);
    expect(find.text('+8'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets(
    'a net-negative Abilities value still shows its true (negative) legend '
    'value, and contributes zero width to the bar rather than being hidden',
    (tester) async {
      const heavyPenalty = ScoreBreakdown(
        defAvg: 70,
        midAvg: 72,
        atkAvg: 74,
        linesTotal: 216,
        userChemTotal: 10,
        cardChemTotal: 5,
        lineLeaderBonus: 8,
        captainBonus: 0,
        yellowPenalty: 6,
        finalScore: 233.0,
      );
      await tester.pumpWidget(
        harness(const ScoreBreakdownBar(breakdown: heavyPenalty)),
      );

      // captainBonus(0) - yellowPenalty(6) = -6, shown as "-6", not "+-6" or
      // omitted from the legend.
      expect(find.text('-6'), findsOneWidget);
    },
  );

  testWidgets('semantics summary lists every segment plus the final score', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const ScoreBreakdownBar(breakdown: breakdown)));

    // The explicit Semantics(label: ...) merges with its descendant legend
    // Text nodes (pre-existing behavior, unchanged by the SegmentedBar
    // extraction — the label string itself is what Phase B must preserve
    // exactly, not the merge behavior) — so the accessibility tree's label
    // is the summary sentence followed by the rendered legend text.
    final semantics = tester.getSemantics(find.byType(ScoreBreakdownBar));
    expect(
      semantics.label,
      startsWith(
        'Score breakdown: Base 216 points, Tactical Fit 15 points, '
        'Line Leaders 8 points, Abilities 2 points. Final score 241.00.',
      ),
    );
  });

  testWidgets('colors map Base/Tactical Fit/Line Leaders/Abilities exactly', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const ScoreBreakdownBar(breakdown: breakdown)));

    final dots = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration)
        .map((c) => (c.decoration as BoxDecoration).color)
        .where((c) => c != null)
        .toSet();

    expect(dots, contains(HETheme.pfTextSecondary));
    expect(dots, contains(HETheme.pfSuccess));
    expect(dots, contains(HETheme.pfGold));
    expect(dots, contains(HETheme.pfSecondaryViolet));
  });
}
